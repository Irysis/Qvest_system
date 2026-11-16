"""rawdata_listing_cut.py — RAWDATA 상장 전 행 삭제 (도훈 11-16 결정 RAWDATA-PRELISTING-EXCLUDE-20261116 · pit.md C6)

도훈 원문(11-16): '상장전 이력까지 백테스팅에 활용하지마. 상장종목은 상장된 시점 이후 퀀티와이즈에 찍히는 가격데이터부터 활용하면 되고,
없는 시점은 유니버스에 제외시켜.' · '상장 첫날에는 가격변동폭제한이 커져서 가짜수익이 아니라 진짜 수익일 수 있다' ·
'자꾸 네가 스스로 새롭게 검증하려고 하지마. 퀀티와이즈 데이터가 무조건 맞는거야'

하는 일 — 행 삭제만(값은 바꾸지 않는다 · 상장 첫날 Ret 도 저장값 그대로):
  종목마다 퀀티 시장구분(R100100 일별 · 외부 책 ListingMarket → .cache/qw_ext/listing_market/market_type.parquet)이
  처음 유가증권(KS) · 코스닥(KQ)이 된 날 = 상장일. 그보다 앞선 날짜의 RAWDATA 행을 지운다.
  시장구분 파일 기간 안에 유가증권 · 코스닥이 한 번도 없는 종목은 그 기간의 행을 지운다(장외 · 코넥스만 있던 종목).
  지우지 않는 것: 시장구분 시계열이 아예 없는 종목(요약에 목록) · 아직 상장일이 없는 종목의 시장구분 파일 마지막 날 뒤 행(다음 실행이 본다).
멱등: 두 번째 실행은 0행을 지운다(밤 적재기가 창 행을 다시 붙이면 그 행만 다시 지운다).
쓰기: --apply 와 환경변수 QVEST_LISTING_CUT_LOCKED=1(RAWDATA writer 잠금 또는 밤 리프레시 잠금 아래에서만) — tmp → 교체(재시도).
  지운 행(전 열)과 요약은 .cache/listing_cut/ 에 남긴다(되돌리기 재료). --backup = RAWDATA 통째 사본(첫 수동 실행용).
사용: python rawdata_listing_cut.py [--apply] [--backup] [--label 이름] [--root R] [--rawdata P] [--market P]
종료: 0 정상(지움 · 안 지움) · 2 입력 없음(미변경) · 3 시장구분 파일에 KS · KQ 코드가 없다(표기가 바뀌면 전부를 지울 수 있어 멈춤 · 미변경) · 1 오류
"""
import argparse
import json
import os
import shutil
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

LISTED = ("KS", "KQ")   # 유가증권 · 코스닥 — 결정 RAWDATA-PRELISTING-EXCLUDE-20261116 · 등록부 ListingMarket date_meaning
KST = timezone(timedelta(hours=9))
BIG = np.iinfo(np.int64).max


def log(msg):
    print(f"[listing_cut] {msg}", flush=True)


def days(col):
    """date32 열 → 정수 일(1970-01-01 기준)."""
    return pc.cast(col, pa.int32()).to_numpy(zero_copy_only=False).astype(np.int64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT", "."))
    ap.add_argument("--rawdata")
    ap.add_argument("--market")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--backup", action="store_true")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    root = Path(a.root.replace("\\", "/"))
    raw_p = Path(a.rawdata) if a.rawdata else root / ".cache" / "RAWDATA.parquet"
    mkt_p = Path(a.market) if a.market else root / ".cache" / "qw_ext" / "listing_market" / "market_type.parquet"
    out_d = root / ".cache" / "listing_cut"
    mode = "APPLY" if a.apply else "DRY-RUN"
    if a.apply and os.environ.get("QVEST_LISTING_CUT_LOCKED") != "1":
        log("APPLY 거부 — writer 잠금 밖이다(QVEST_LISTING_CUT_LOCKED=1 없음 · 측정 러너가 읽는 것은 배리어다)")
        return 1
    for p in (raw_p, mkt_p):
        if not p.exists():
            log(f"입력 없음: {p} — 미변경")
            return 2

    # ── 종목별 상장일 = 시장구분이 처음 KS · KQ 인 날 ──
    m = pq.read_table(mkt_p, columns=["Date", "Ticker", "Value"])
    mval = pc.utf8_trim_whitespace(m["Value"])
    nb = pc.and_(pc.is_valid(mval), pc.not_equal(mval, ""))      # 빈 칸은 관측이 아니다 — 빈칸뿐인 종목 = 시계열 없음(안 지움)
    m, mval = m.filter(nb), mval.filter(nb)
    codes = sorted(set(pc.unique(mval).to_pylist()))
    if any(c not in codes for c in LISTED):
        log(f"멈춤 — 시장구분 코드 {codes} 에 {list(LISTED)} 가 없다(표기 변경?) — 미변경")
        return 3
    m_last = int(days(m["Date"]).max())
    lm = m.filter(pc.is_in(mval, value_set=pa.array(LISTED)))
    first = lm.group_by("Ticker").aggregate([("Date", "min")])
    first_day = dict(zip(first["Ticker"].to_pylist(), days(first["Date_min"]).tolist()))
    series = set(pc.unique(m["Ticker"]).to_pylist())

    # ── RAWDATA 키(판정은 키만 · 전 열은 지울 행이 있을 때만 읽는다) ──
    t = pq.read_table(raw_p, columns=["Date", "Ticker"])
    n0 = t.num_rows
    rd = days(t["Date"])
    tenc = t["Ticker"].combine_chunks().dictionary_encode()
    names = tenc.dictionary.to_pylist()
    rc = tenc.indices.to_numpy(zero_copy_only=False).astype(np.int64)
    cut_until = np.full(len(names), -BIG, dtype=np.int64)        # 이 날 '앞'(엄격)은 지운다
    for i, c in enumerate(names):
        if c in first_day:
            cut_until[i] = first_day[c]
        elif c in series:
            cut_until[i] = m_last + 1                            # 기간 안에 상장일 없음 → 파일 마지막 날까지 지운다
    drop = rd < cut_until[rc]
    no_series = sorted(c for c in names if c not in series)
    tick_drop = np.unique(rc[drop])
    keep_tk = np.unique(rc[~drop])
    summ = dict(
        mode=mode, label=a.label, at=datetime.now(KST).isoformat(timespec="seconds"), decision="RAWDATA-PRELISTING-EXCLUDE-20261116",
        rawdata=str(raw_p), rows_before=int(n0), rows_dropped=int(drop.sum()), rows_after=int(n0 - drop.sum()),
        tickers_with_drops=int(len(tick_drop)), tickers_fully_dropped=int(len(np.setdiff1d(tick_drop, keep_tk))),
        market_file=str(mkt_p), market_codes=codes, market_last_date=str(np.datetime64("1970-01-01", "D") + np.timedelta64(m_last, "D")),
        tickers_no_series=len(no_series), no_series_tickers=no_series,
    )
    log(f"{mode} · RAWDATA {n0:,}행 → 지울 상장 전 행 {summ['rows_dropped']:,}(종목 {summ['tickers_with_drops']:,} · 전부 지워지는 종목 {summ['tickers_fully_dropped']:,})"
        f" · 시장구분 없는 종목 {len(no_series):,}(안 지움) · 시장구분 마지막 날 {summ['market_last_date']}")
    out_d.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(KST).strftime("%Y%m%d_%H%M%S")
    tag = f"{stamp}{('_' + a.label) if a.label else ''}_{'apply' if a.apply else 'dryrun'}"

    summ["applied"] = False
    if a.apply and drop.any():
        if a.backup:
            bak = raw_p.parent / f"rawdata_pre_listing_cut_{stamp[:8]}.parquet"
            if not bak.exists():
                tmpb = bak.with_name("." + bak.name + ".tmp")
                shutil.copyfile(raw_p, tmpb)
                os.replace(tmpb, bak)
                log(f"백업: {bak.name}")
            else:
                log(f"백업 있음(재사용): {bak.name}")
        full = pq.read_table(raw_p)
        if full.num_rows != n0 or not full.select(["Date", "Ticker"]).equals(t):
            log("전 열을 다시 읽는 사이 RAWDATA 가 바뀌었다 — 미변경(잠금 확인 뒤 다시)")
            return 1
        pq.write_table(full.filter(pa.array(drop)), out_d / f"dropped_{tag}.parquet")     # 되돌리기 재료
        keep_t = full.filter(pa.array(~drop)).replace_schema_metadata(full.schema.metadata)
        tmp = raw_p.with_name(f".{raw_p.name}.listingcut.{os.getpid()}")
        pq.write_table(keep_t, tmp, compression="snappy")
        if pq.ParquetFile(tmp).metadata.num_rows != keep_t.num_rows:
            tmp.unlink(missing_ok=True)
            log("tmp 쓰기 확인 실패 — 정본 미갱신")
            return 1
        tries = int(os.environ.get("QVEST_LISTING_CUT_TRIES", "30"))
        wait_s = float(os.environ.get("QVEST_LISTING_CUT_WAIT_S", "20"))
        for k in range(1, tries + 1):
            try:
                os.replace(tmp, raw_p)
                break
            except PermissionError:
                log(f"교체 실패({k}/{tries}) — 다른 프로세스가 파일을 잡고 있다 · {wait_s:.0f}초 뒤 재시도")
                time.sleep(wait_s)
        else:
            tmp.unlink(missing_ok=True)
            log("교체 실패 — 정본 미갱신(재시도 필요)")
            return 1
        summ["applied"] = True
        log(f"APPLY 완료 — {keep_t.num_rows:,}행 · 지운 행 = {out_d.name}/dropped_{tag}.parquet")
    elif a.apply:
        log("지울 행 없음 — 미변경")
    summ["summary_path"] = (out_d / f"summary_{tag}.json").as_posix()
    (out_d / f"summary_{tag}.json").write_text(json.dumps(summ, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"LISTING_CUT mode={mode} dropped={summ['rows_dropped']} tickers={summ['tickers_with_drops']} no_series={summ['tickers_no_series']}"
          f" applied={int(summ['applied'])}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
