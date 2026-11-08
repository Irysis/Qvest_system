"""qw_datakey_master.py — 퀀티 질의서 종목 목록(DATA_Key)의 정본 관리.

왜(2026-11-08 · BUILD_20261108.md §1):
  퀀티 Update_File DB마다 DATA_Key D:E 목록을 사람이 손으로 붙여 왔다. 실측 11-06:
  OHLCVS 3,717 · 나머지 3개 DB 3,668 — 3개 DB에 53종이 없어 위생 표식이 NA(PLAN F7), OHLCVS 에도
  상장 보통주 45종(2026-03-05 이후 신규 상장)이 없어 RAWDATA 에 아예 없다.
  → 종목 목록의 정본을 하나(06_Registry/qw_datakey_master.json)로 두고, 매일 KRX 상장 목록과
    대조해 새 종목을 '끝에만' 붙인다. DB 반영은 ops/qw_datakey_sync.ps1 이 한다.

정본 규칙(기존 OHLCVS 목록의 구성을 실측해 그대로 따른다 — 새 기준을 만들지 않는다):
  KRX 종목기본정보 SECUGRP_NM ∈ {주권, 외국주권, 주식예탁증권} ∧ KIND_STKCERT_TP_NM = 보통주
  ∧ 이름에 '스팩' · '기업인수목적' 없음.
  실측(11-06 KRX 목록 ∩ 기존 목록): 주권 보통주 2,495 · 외국주권 12 · 주식예탁증권 9 · 스팩 0 ·
  우선주 · 종류주권 · 리츠 · 인프라 · 투자회사 0. 스팩이 합병 뒤 이름이 바뀌면 그날 규칙에 들어와 붙는다.
  목록에서는 지우지 않는다(상장폐지 종목도 이력 때문에 남긴다 — 생존 편향 방지 · C6).

사용:
  python qw_datakey_master.py --seed      # 정본이 없을 때 1회: OHLCVS_update DATA_Key 순서 + 3개 DB 전용 종목
  python qw_datakey_master.py --update [--date YYYYMMDD]   # KRX 스냅숏과 대조해 새 종목을 끝에 붙인다
  python qw_datakey_master.py --status
종료 코드: 0 정상(새 종목 0 포함) · 2 그 날짜 KRX 스냅숏 없음 · 1 오류
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

import pyarrow.parquet as pq

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
MASTER = ROOT / "06_Registry" / "qw_datakey_master.json"
KRX = ROOT / ".cache" / "krx"
OHLCVS_BOOK = ROOT / "03_Universe" / "Update_File" / "OHLCVS_update.xlsx"
CONS_TICKERS = ROOT / ".cache" / "consensus" / "ticker_map.parquet"

RULE = {
    "secugrp": ["주권", "외국주권", "주식예탁증권"],
    "kind": ["보통주"],
    "exclude_name_regex": "스팩|기업인수목적",
    "basis": "11-06 KRX 목록과 기존 OHLCVS DATA_Key 3,717 의 교집합 구성 실측(주권 보통주 2,495 · 외국주권 12 · 주식예탁증권 9 · 스팩 0)",
}
_SPAC = re.compile(RULE["exclude_name_regex"])


def _now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


def _norm(code) -> str:
    c = str(code).strip()
    return c if c.startswith("A") else "A" + c


def _write_atomic(path: Path, obj) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, path)


def load_master() -> dict:
    with open(MASTER, encoding="utf-8") as f:
        m = json.load(f)
    codes = [e["code"] for e in m["codes"]]
    if len(codes) != len(set(codes)):
        raise SystemExit("[master] 정본에 중복 코드가 있다 — 손으로 고친 흔적인지 확인할 것")
    return m


def seed() -> int:
    if MASTER.exists():
        print(f"[master] 이미 있음: {MASTER} — seed 생략")
        return 0
    import openpyxl  # 지연 import(--update 경로는 openpyxl 불필요)

    wb = openpyxl.load_workbook(OHLCVS_BOOK, read_only=True, data_only=True)
    try:
        ws = wb["DATA_Key"]
        seen, entries = set(), []
        for r in ws.iter_rows(min_row=2, max_row=10001, min_col=4, max_col=5, values_only=True):
            d, e = r
            if d is None or str(d).strip() == "":
                continue
            c = _norm(d)
            if c in seen:
                raise SystemExit(f"[master] OHLCVS DATA_Key 중복 {c}")
            seen.add(c)
            entries.append({"code": c, "name": e, "source": "seed:OHLCVS_update.DATA_Key", "added_at": _now()})
    finally:
        wb.close()
    n_ohlcvs = len(entries)
    tm = pq.read_table(CONS_TICKERS).to_pydict()
    extra = []
    for t, nm in zip(tm["Ticker"], tm["Name"]):
        c = _norm(t)
        if c not in seen:
            seen.add(c)
            extra.append({"code": c, "name": nm, "source": "seed:3book_only(consensus.ticker_map)", "added_at": _now()})
    entries.extend(sorted(extra, key=lambda e: e["code"]))
    m = {
        "schema": "qw_datakey_master/v1",
        "_note": "퀀티 Update_File DB DATA_Key 의 정본 종목 목록. 순서 = 붙인 순서(앞 순서는 바꾸지 않는다). writer = 02_Infrastructure/data/qw_datakey_master.py 만. DB 반영 = 02_Infrastructure/ops/qw_datakey_sync.ps1",
        "rule": RULE,
        "seeded_at": _now(),
        "seed_counts": {"ohlcvs_datakey": n_ohlcvs, "three_book_only": len(extra)},
        "last_krx_date": None,
        "codes": entries,
        "runs": [],
    }
    _write_atomic(MASTER, m)
    print(f"[master] seed: OHLCVS {n_ohlcvs} + 3개 DB 전용 {len(extra)} = {len(entries)} -> {MASTER}")
    return 0


def _krx_snapshot(date: str | None):
    stk_dir, ksq_dir = KRX / "stk_info", KRX / "ksq_info"
    dates = sorted({p.stem.split("_")[-1] for p in stk_dir.glob("stk_info_*.parquet")} &
                   {p.stem.split("_")[-1] for p in ksq_dir.glob("ksq_info_*.parquet")})
    if date:
        dates = [d for d in dates if d <= date]
    if not dates:
        return None, []
    d = dates[-1]
    rows = []
    for mkt, p in (("KOSPI", stk_dir / f"stk_info_{d}.parquet"), ("KOSDAQ", ksq_dir / f"ksq_info_{d}.parquet")):
        for r in pq.read_table(p).to_pylist():
            r["Market"] = mkt
            rows.append(r)
    return d, rows


def _eligible(r) -> bool:
    return (r.get("SECUGRP_NM") in RULE["secugrp"] and r.get("KIND_STKCERT_TP_NM") in RULE["kind"]
            and not _SPAC.search(str(r.get("ISU_ABBRV") or r.get("ISU_NM") or "")))


def update(date: str | None) -> int:
    m = load_master()
    d, rows = _krx_snapshot(date)
    if d is None or (date and d != date):
        print(f"[master] KRX 스냅숏 없음(요청 {date} · 최신 {d}) — 먼저 data/krx_listing_snapshot.R 실행")
        return 2
    have = {e["code"] for e in m["codes"]}
    elig = [r for r in rows if _eligible(r)]
    # 이미 정본에 있는데 상장일을 모르는 종목(seed 분)은 KRX 상장일로 채운다 — 보충 수급 창(qw_datakey_sync.ps1)의 근거
    by_code = {_norm(r["ISU_SRT_CD"]): r for r in rows}
    n_fill = 0
    for e in m["codes"]:
        r = by_code.get(e["code"])
        if r is not None and not e.get("list_dd"):
            e["list_dd"], e["market"], e["secugrp"] = str(r.get("LIST_DD")), r["Market"], r.get("SECUGRP_NM")
            e["list_dd_source"] = f"krx_base_info:{d}"
            n_fill += 1
    new = sorted((r for r in elig if _norm(r["ISU_SRT_CD"]) not in have), key=lambda r: (str(r.get("LIST_DD")), _norm(r["ISU_SRT_CD"])))
    for r in new:
        m["codes"].append({"code": _norm(r["ISU_SRT_CD"]), "name": r.get("ISU_ABBRV"), "market": r["Market"],
                           "list_dd": str(r.get("LIST_DD")), "secugrp": r.get("SECUGRP_NM"),
                           "source": f"krx_base_info:{d}", "added_at": _now()})
    listed = {_norm(r["ISU_SRT_CD"]) for r in elig}
    m["last_krx_date"] = d
    m["listed_eligible_n"] = len(listed)
    m["runs"] = (m.get("runs") or [])[-49:] + [{"at": _now(), "krx_date": d, "n_new": len(new),
                                                 "new": [_norm(r["ISU_SRT_CD"]) for r in new]}]
    _write_atomic(MASTER, m)
    print(f"[master] KRX {d}: 규칙 해당 상장 {len(listed)} · 정본 {len(have)} → 새 종목 {len(new)} 추가 (정본 {len(m['codes'])}) · 상장일 보충 {n_fill}")
    for r in new[:60]:
        print(f"   + {_norm(r['ISU_SRT_CD'])} {r.get('ISU_ABBRV')} {r['Market']} 상장 {r.get('LIST_DD')}")
    return 0


def status() -> int:
    m = load_master()
    print(json.dumps({"codes": len(m["codes"]), "last_krx_date": m.get("last_krx_date"),
                      "listed_eligible_n": m.get("listed_eligible_n"), "last_run": (m.get("runs") or [None])[-1]},
                     ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--seed", action="store_true")
    g.add_argument("--update", action="store_true")
    g.add_argument("--status", action="store_true")
    ap.add_argument("--date")
    a = ap.parse_args()
    try:
        sys.exit(seed() if a.seed else update(a.date) if a.update else status())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"[master] ERROR: {e}")
        sys.exit(1)
