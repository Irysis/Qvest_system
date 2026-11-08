"""qw_fund_v2_ingest.py — 퀀티 재무 수집 DB(fundamentals_v2 · Peer Analysis) → DB 별 장형 parquet.

왜(2026-11-08 · 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/README.md):
  도훈 '퀀티 중심 재무 적재' 지시로 만든 DB 4개(FundV2_BS · IS · CF · META · 1998Q1~)를 읽는다.
  같은 날 시험에서 퀀티 표준 재무 값은 **정정 뒤 값으로 덮인다**(정정 기업: 자산총계 · 지배자본 35/35,
  4분기 손익 131/140 이 정정 값)는 것이 드러났다 — 벤더는 개정 이력을 주지 않는다. 그래서 적재기가
  직접 남긴다: 값이 바뀌면 revisions 에 (옛 값 · 새 값 · 시각)을 쓰고 그 행의 first_fetched_at 을
  새 시각으로 바꾼다(앞으로의 시점 재현용 의사 빈티지 — 과거 이력의 정정은 되살리지 못한다).

입력: 02_Infrastructure/data/qw_updatefile_registry.json :: fundamentals_v2(items · dbs · dir).
출력(원자적 쓰기 · 출력 폴더 기본 .cache/qw_fund_v2):
  <DB>.parquet       Ticker · Period(YYYYMM) · Item · Value(float) · Text(날짜 YYYYMMDD · 글) ·
                     first_fetched_at · last_fetched_at
                     (갱신용 DB = dbs[].target 이 있으면 부모 <target>.parquet 의 그 DB 창(항목 × 기간)만 교체)
  revisions.parquet  Ticker · Period · Item · Db · old_value · new_value · old_text · new_text ·
                     old_first_fetched_at · detected_at · kind(changed | deleted)   — 누적
  fiscal_month.parquet  Ticker · FiscalMonth · fetched_at (항목 시트 C 열 '결산월')
  _ingest_state.json DB 별 mtime · 시트 B1 스탬프 · (항목|기간) 채움 수
관문(하나라도 걸리면 그 DB 적재 0 · 그 DB 출력 무접촉 — 다른 DB 는 계속):
  G1 리프레시됨 — 모든 항목 시트의 B1 'Last Update' 가 해석되고 생성 템플릿 스탬프가 아니다
  G2 코드 — 등록부 항목이 시트로 전부 있고 · D9 = 등록부 code · A3 = 'Peer Analysis*' · 기간 열이 시트끼리 같다
  G3 채움 — (항목, 기간) 채움 수가 직전 적재의 FILL_RATIO 미만으로 떨어지지 않는다(직전 ≥ FILL_MIN 일 때)
종료: 0 적재 · 2 바뀐 DB 없음 · 3 관문 거부(그 DB 적재 0) · 1 오류
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

FILL_RATIO = 0.5      # G3: 직전 채움의 절반 미만 = 부분 리프레시 의심
FILL_MIN = 50         # G3: 직전 채움이 이보다 작으면 비율 검사 생략(소표본)
TEMPLATE_STAMP = "2026-03-15 11:12:55"   # 03_Universe/Fundamental.xlsx 의 B1 — 생성기가 그대로 복사한다
KEYS = ["Ticker", "Period", "Item"]
CODE_RE = re.compile(r"A[0-9A-Z]{6}")


def now_iso() -> str:
    return dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def atomic_write(path: Path, writer) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp{os.getpid()}")
    writer(tmp)
    os.replace(tmp, path)


def parse_stamp(b1) -> str | None:
    m = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", str(b1 or ""))
    return m.group(1) if m else None


def read_db(path: Path, items: dict):
    """items: sheet -> catalog entry. Returns (sheets, problems); sheets[s] = dict(stamp, periods, codes, vals, fiscal)."""
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    sheets, problems = {}, []
    names = set(wb.sheetnames)
    for s in items:
        if s not in names:
            problems.append(f"G2 시트 없음: {s}")
    for s, it in items.items():
        if s not in names:
            continue
        hdr, codes, vals, fiscal = {}, [], [], []
        np_ = None
        for r_i, row in enumerate(wb[s].iter_rows(min_row=1, max_row=5000, values_only=True), start=1):
            if r_i <= 13:
                hdr[r_i] = row
                if r_i == 10:
                    per = []
                    for v in row[3:]:
                        if v is None or str(v).strip() == "":
                            break
                        per.append(str(int(float(v))))
                    np_ = len(per)
                    hdr["periods"] = per
                continue
            if not row or row[0] is None:
                continue
            code = str(row[0]).strip()
            if not CODE_RE.fullmatch(code):
                continue
            codes.append(code)
            fiscal.append(None if len(row) < 3 or row[2] is None else str(row[2]).strip())
            seg = list(row[3:3 + (np_ or 0)])
            if len(seg) < (np_ or 0):
                seg += [None] * ((np_ or 0) - len(seg))
            vals.append(seg)
        a3 = str((hdr.get(3) or [None])[0] or "")
        r9 = hdr.get(9) or ()
        d9 = str(r9[3] if len(r9) > 3 and r9[3] is not None else "").strip()
        r1 = hdr.get(1) or ()
        stamp = parse_stamp(r1[1] if len(r1) > 1 else None)
        if not a3.startswith("Peer Analysis"):
            problems.append(f"G2 {s}: A3 '{a3}'")
        if d9 != it["code"]:
            problems.append(f"G2 {s}: D9 '{d9}' != 등록부 '{it['code']}'")
        if stamp is None or stamp == TEMPLATE_STAMP:
            problems.append(f"G1 {s}: 리프레시 안 됨(B1 스탬프 {stamp})")
        sheets[s] = {"stamp": stamp, "periods": hdr.get("periods", []), "codes": codes, "vals": vals,
                     "fiscal": fiscal, "kind": it.get("kind", "")}
    wb.close()
    pers = {tuple(sh["periods"]) for sh in sheets.values()}
    if len(pers) > 1:
        problems.append(f"G2 기간 열이 시트마다 다름({len(pers)}종)")
    return sheets, problems


def sheet_long(s: str, sh: dict):
    """한 시트 → 장형 DataFrame(Ticker, Period, Item, Value, Text) · 빈칸 · 'n/a' 제외."""
    import numpy as np
    import pandas as pd
    codes, per = sh["codes"], sh["periods"]
    if not codes or not per:
        return pd.DataFrame(columns=["Ticker", "Period", "Item", "Value", "Text"])
    raw = pd.Series(np.array(sh["vals"], dtype=object).ravel())
    raw = raw.where(~raw.isin(["", "n/a", "N/A"]), None)
    tk = np.repeat(np.array(codes, dtype=object), len(per))
    pr = np.tile(np.array(per, dtype=object), len(codes))
    if sh["kind"] == "text":
        # pd.isna, not 'v is None' (11-08): a text-only column is inferred as pandas 3 str dtype, which turns None
        #   into NaN, and str(NaN) = 'nan' was written for every empty cell (INFO text items = the whole panel).
        txt = raw.map(lambda v: None if pd.isna(v) else str(v).strip())
        df = pd.DataFrame({"Ticker": tk, "Period": pr, "Item": s, "Value": np.nan, "Text": txt})
        return df[df["Text"].notna() & (df["Text"] != "")]
    num = pd.to_numeric(raw, errors="coerce")
    if sh["kind"] == "date":
        txt = num.map(lambda v: None if pd.isna(v) else str(int(v)))
        df = pd.DataFrame({"Ticker": tk, "Period": pr, "Item": s, "Value": np.nan, "Text": txt})
        return df[df["Text"].notna()]
    df = pd.DataFrame({"Ticker": tk, "Period": pr, "Item": s, "Value": num.astype("float64"), "Text": None})
    return df[df["Value"].notna()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT") or str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--registry", default="")
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--db", action="append", default=[])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    import numpy as np
    import pandas as pd
    import pyarrow as pa
    import pyarrow.parquet as pq

    root = Path(a.root)
    reg_path = Path(a.registry) if a.registry else root / "02_Infrastructure/data/qw_updatefile_registry.json"
    out_dir = Path(a.out_dir) if a.out_dir else root / ".cache/qw_fund_v2"
    fv = json.loads(reg_path.read_text(encoding="utf-8")).get("fundamentals_v2")
    if not fv:
        print(f"[fund-v2] 등록부에 fundamentals_v2 없음: {reg_path}")
        return 1
    cat = {it["sheet"]: it for it in fv["items"]}
    state_path = out_dir / "_ingest_state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {"dbs": {}}
    rev_path, fm_path = out_dir / "revisions.parquet", out_dir / "fiscal_month.parquet"
    new_revs, fiscal_new = [], {}
    loaded, refused = 0, []

    for d in fv["dbs"]:
        name = d["name"]
        if a.db and name not in a.db:
            continue
        path = root / fv["dir"] / d["file"]
        if not path.exists():
            print(f"[fund-v2] {name}: 파일 없음(아직 생성 전) — 건너뜀")
            continue
        mtime = dt.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%dT%H:%M:%S")
        prev = state["dbs"].get(name, {})
        if prev.get("mtime") == mtime:
            print(f"[fund-v2] {name}: 변경 없음(mtime {mtime})")
            continue
        src = d if d.get("items") else next((x for x in fv["dbs"] if x["name"] == d.get("items_from")), None)
        if not src or not src.get("items"):
            print(f"[fund-v2] {name}: 항목 목록 없음(items · items_from)"); refused.append(name); continue
        d = dict(d, items=src["items"])
        sheets, problems = read_db(path, {s: cat[s] for s in d["items"]})
        fills = {}
        for s, sh in sheets.items():
            for j, p in enumerate(sh["periods"]):
                fills[f"{s}|{p}"] = sum(1 for r in sh["vals"] if r[j] is not None and str(r[j]).strip() not in ("", "n/a"))
        # 갱신용 DB 의 첫 적재는 자기 이력이 없다 — 부모 DB 의 같은 (항목|기간) 채움으로 G3 를 건다.
        pf = prev.get("fills") or state["dbs"].get(d.get("target") or "", {}).get("fills", {})
        drops = [f"{k} {pf[k]}->{v}" for k, v in fills.items() if pf.get(k, 0) >= FILL_MIN and v < FILL_RATIO * pf[k]]
        if drops:
            problems.append(f"G3 채움 급감 {len(drops)}칸: " + "; ".join(drops[:5]))
        # G1b 빈 시트 = 리프레시 안 됨(11-08 실측: 끊긴 세션이 B1 스탬프만 새로 찍어 G1 을 통과한 빈 시트 35개).
        #   예외 = 등록부 allow_empty · glossary_basis 'gaap'(2006 이전 항목은 최근 창에서 비는 게 정상).
        for s, sh in sheets.items():
            it = cat[s]
            if it.get("allow_empty") or it.get("glossary_basis") == "gaap":
                continue
            if not any(v is not None and str(v).strip() not in ("", "n/a") for r in sh["vals"] for v in r):
                problems.append(f"G1 {s}: 값 0칸(스탬프 {sh['stamp']}) — 리프레시 안 됨")
        if problems:
            print(f"[fund-v2] {name}: 관문 거부 — " + " | ".join(problems[:8]) + (" …" if len(problems) > 8 else ""))
            refused.append(name)
            continue
        fetched = max(sh["stamp"] for sh in sheets.values()).replace(" ", "T")
        new = pd.concat([sheet_long(s, sh) for s, sh in sheets.items()], ignore_index=True)
        first_sheet = d["items"][0]
        for tk, fm in zip(sheets[first_sheet]["codes"], sheets[first_sheet]["fiscal"]):
            if fm:
                fiscal_new[tk] = (fm, fetched)
        # 구조 경고(거부 아님 — 11-08 CF Capex 가 115분기 중 201209 에서 끊긴 부분 수신을 첫 적재 G3 는 못 본다):
        #   W1 일찍 끝남 = 값이 있는 마지막 기간 < 끝에서 두 번째 기간(마지막은 공시 시즌 진행 중일 수 있음)
        #   W2 중간 구멍 = 처음~마지막 사이 채움 < 중앙값 × 0.3 인 기간
        per_all = next(iter(sheets.values()))["periods"]
        cnt = new.groupby(["Item", "Period"]).size()
        for s in sheets:
            if s not in cnt.index.get_level_values(0):
                print(f"  ⚠ W0 {s}: 값 0행"); continue
            row = cnt.loc[s].reindex(per_all).fillna(0)
            nz = row[row > 0]
            med = float(nz.median())
            span = row.loc[nz.index[0]:nz.index[-1]]
            holes = [p for p, v in span.items() if v < 0.3 * med and p != per_all[-1]]   # 마지막 기간 = 공시 시즌 진행 중일 수 있음
            if len(per_all) >= 2 and nz.index[-1] < per_all[-2]:
                print(f"  ⚠ W1 {s}: {nz.index[-1]} 에서 끝남(DB 마지막 {per_all[-1]}) — 부분 수신이면 그 시트만 다시 리프레시")
            if holes:
                print(f"  ⚠ W2 {s}: 중간 구멍 {len(holes)}기간 — " + ",".join(holes[:6]) + (" …" if len(holes) > 6 else ""))
        # 갱신용 DB(최근 N분기 창 · dbs[].target = 부모 DB)는 부모의 parquet 에 그 창만 교체해 넣는다.
        out_path = out_dir / f"{d.get('target') or name}.parquet"
        if out_path.exists():
            old = pq.read_table(out_path).to_pandas()
        else:
            old = pd.DataFrame(columns=["Ticker", "Period", "Item", "Value", "Text", "first_fetched_at", "last_fetched_at"])
        win = {(s, p) for s, sh in sheets.items() for p in sh["periods"]}
        m = old.merge(new, on=KEYS, how="outer", suffixes=("_old", ""), indicator=True)
        in_win = pd.Series([(i, p) in win for i, p in zip(m["Item"], m["Period"])], index=m.index)
        both = m["_merge"] == "both"
        # pandas 3: 읽은 parquet 문자열 = StringDtype(NaN) · 새 값 = object(None) — 둘 다 object 로 맞추고
        # 빈 값을 같은 표지로 바꿔 비교한다('\x00' 표지는 StringDtype 쪽에서 같다고 나오지 않았다 · 11-08 실측).
        def _norm_txt(s):
            return s.astype(object).where(s.notna(), "<NA>")
        same_v = (m["Value_old"].fillna(np.inf) == m["Value"].fillna(np.inf)) & (_norm_txt(m["Text_old"]) == _norm_txt(m["Text"]))
        changed = both & ~same_v
        deleted = (m["_merge"] == "left_only") & in_win
        for kind, mask in (("changed", changed), ("deleted", deleted)):
            if mask.any():
                r = m.loc[mask]
                new_revs.append(pd.DataFrame({
                    "Ticker": r["Ticker"], "Period": r["Period"], "Item": r["Item"], "Db": name,
                    "old_value": r["Value_old"], "new_value": r["Value"] if kind == "changed" else np.nan,
                    "old_text": r["Text_old"], "new_text": r["Text"] if kind == "changed" else None,
                    "old_first_fetched_at": r["first_fetched_at"], "detected_at": fetched, "kind": kind}))
        keep_old = (m["_merge"] == "left_only") & ~in_win
        res = pd.DataFrame({"Ticker": m["Ticker"], "Period": m["Period"], "Item": m["Item"]})
        res["Value"] = np.where(keep_old, m["Value_old"], m["Value"])
        res["Text"] = m["Text_old"].where(keep_old, m["Text"])
        res["first_fetched_at"] = np.where(both & same_v, m["first_fetched_at"],
                                           np.where(keep_old, m["first_fetched_at"], fetched))
        res["last_fetched_at"] = np.where(keep_old, m["last_fetched_at"], fetched)
        res = res.loc[~deleted].sort_values(KEYS, kind="stable").reset_index(drop=True)
        n_new = int((m["_merge"] == "right_only").sum())
        print(f"[fund-v2] {name}: 적재 — 시트 {len(sheets)} · 기간 {len(next(iter(sheets.values()))['periods'])} · "
              f"행 {len(res):,} · 신규 {n_new:,} · 변경 {int(changed.sum()):,} · 삭제 {int(deleted.sum()):,} · 스탬프 {fetched}")
        if not a.dry_run:
            schema = pa.schema([("Ticker", pa.string()), ("Period", pa.string()), ("Item", pa.string()),
                                ("Value", pa.float64()), ("Text", pa.string()),
                                ("first_fetched_at", pa.string()), ("last_fetched_at", pa.string())])
            tbl = pa.Table.from_pandas(res, schema=schema, preserve_index=False)
            atomic_write(out_path, lambda p: pq.write_table(tbl, p))
            state["dbs"][name] = {"mtime": mtime, "fetched_at": fetched, "at": now_iso(),
                                  "stamps": {s: sh["stamp"] for s, sh in sheets.items()}, "fills": fills}
        loaded += 1

    if not a.dry_run and loaded:
        rschema = pa.schema([("Ticker", pa.string()), ("Period", pa.string()), ("Item", pa.string()), ("Db", pa.string()),
                             ("old_value", pa.float64()), ("new_value", pa.float64()), ("old_text", pa.string()),
                             ("new_text", pa.string()), ("old_first_fetched_at", pa.string()),
                             ("detected_at", pa.string()), ("kind", pa.string())])
        if new_revs:
            add = pd.concat(new_revs, ignore_index=True)
            old_r = pq.read_table(rev_path).to_pandas() if rev_path.exists() else add.iloc[0:0]
            allr = pd.concat([old_r, add], ignore_index=True)
            rt = pa.Table.from_pandas(allr, schema=rschema, preserve_index=False)
            atomic_write(rev_path, lambda p: pq.write_table(rt, p))
        elif not rev_path.exists():
            et = pa.Table.from_pylist([], schema=rschema)
            atomic_write(rev_path, lambda p: pq.write_table(et, p))
        if fiscal_new:
            fm_old = pq.read_table(fm_path).to_pandas() if fm_path.exists() else pd.DataFrame(columns=["Ticker", "FiscalMonth", "fetched_at"])
            fm = {r.Ticker: (r.FiscalMonth, r.fetched_at) for r in fm_old.itertuples()}
            fm.update(fiscal_new)
            ft = pa.table({"Ticker": list(fm), "FiscalMonth": [v[0] for v in fm.values()], "fetched_at": [v[1] for v in fm.values()]})
            atomic_write(fm_path, lambda p: pq.write_table(ft, p))
        atomic_write(state_path, lambda p: Path(p).write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8"))
    if a.dry_run:
        print("[fund-v2] dry-run — 쓰기 없음")
    if refused:
        return 3
    return 0 if loaded else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f"[fund-v2] 오류: {e!r}")
        sys.exit(1)
