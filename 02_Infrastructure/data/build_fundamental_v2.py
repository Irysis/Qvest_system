"""build_fundamental_v2.py — 퀀티 메인 · DART 정정 검사 · 실제 공시일 → 재무 v2 분기 표.

왜(2026-11-08 도훈 결정 '위 방식대로 가자' · 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/README.md §6):
  퀀티 재무 값은 정정 뒤 값으로 덮여 있다(정정 기업-연도는 다음 해 보고서로 알게 되는 숫자). DART 연간 원장은 그해
  보고서 숫자(최신 기재정정본)다. 그래서 퀀티를 메인으로 쓰되, DART 가 있는 기업-연도는 정의가 같은 항목으로 대조해
  다르면 '정정 의심'으로 보고 그해 퀀티 값을 다음 해 사업보고서가 나온 뒤에만 쓰게 한다. 날짜는 고정 규칙(분기말+45일 ·
  익년 3/31) 대신 실제 공시일(퀀티 M123955 · DART 접수번호 앞 8자리)을 쓰고, 그날 다음 거래일부터 쓴다.

입력(읽기 전용): .cache/qw_fund_v2/FundV2_{BS,IS,CF,GAAP,META,INFO}.parquet · fiscal_month.parquet ·
  .cache/fundamental_dart.parquet(연간 대조값) · .cache/dart/dart_raw_financials.parquet(접수번호) ·
  .cache/RAWDATA.parquet(거래일 달력).
출력(원자적 쓰기 · 기본 .cache/fundamental_v2/):
  fund_v2_quarterly.parquet  Ticker · Period · Period_Date · Item · Value · Avail_Date(그 값이 공개된 날) ·
                             Factor_Date(Avail_Date 다음 거래일 = 쓸 수 있는 첫날) · Avail_Basis · Check · Db
  fund_v2_annual_check.parquet  Ticker · FY · Item · QW_Value · DART_Value · Rel_Diff · DART_Date · Same
  fund_v2_build_report.json  행 수 · 검사 결과 · 날짜 근거 분포
Avail_Basis: qw_report(퀀티 공시일) · dart_rcept(DART 접수일이 더 늦음) · rule(공시일 없음 → 고정 규칙) ·
  restated_next_fy(정정 의심 → 다음 회계연도 사업보고서 공시일)
Check: agree · restated · no_dart(2015~ 12월 결산인데 DART 대조값 없음 — 원장 없음 또는 겹치는 항목 없음) · pre2015(DART API 이전) ·
  non_dec_fy(12월 결산 아님 — DART 연도 대응 미확인이라 검사 안 함)
★주의(PIT): restated 행을 늦게 쓰는 것은 값의 미래참조를 막지만, '늦게 들어온다'는 사실 자체가 나중에 정정될 회사라는
  정보를 담는다. 이 표를 쓰는 쪽은 Check · Avail_Basis 를 표본 거르기(결측 제외 · 유니버스)에 쓰지 말 것. 연간 병합은
  그 칸에 DART 당시 보고서 값을 DART 접수일로 쓰므로 이 문제가 없다(값이 비지 않음).
종료: 0 성공 · 1 오류 · 3 입력 없음
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

TOL = 0.005  # 같은 값으로 보는 상대 차이(11-08 대조와 같은 기준)
# 정정 검사 항목: DART 와 정의가 같은 것만(11-08 실측 2015~ 12월 결산 · 0.5% 일치율 0.91~0.99).
#   매출채권 · 매입채무 · 단기차입금 · 이자비용 · 이자수익 · 감가상각비는 정의가 달라(0.07~0.40) 뺐다.
#   자본금은 일치율 0.99 이지만 차이 92칸 중 88칸이 20% 넘게 벌어진다(정정 크기가 아니라 자료 차이) — 뺐다(11-09).
CHECK_STOCK = {"TotalAssets": "TotalAssets", "TotalLiab": "TotalLiab", "TotalEquity": "TotalEquity",
               "CurrentAssets": "CurrentAssets", "CurrentLiab": "CurrentLiab", "CashAndEquiv": "CashAndEquiv",
               "PPE": "TangibleAssets"}
CHECK_FLOW = {"Revenue": "Revenue", "GrossProfit": "GrossProfit", "OperatingProfit": "OperatingProfit",
              "PretaxIncome": "PretaxIncome", "NetIncome": "NetIncome", "OperatingCF": "OperatingCF"}
NUM_DBS = ["FundV2_BS", "FundV2_IS", "FundV2_CF", "FundV2_GAAP"]
# META · INFO 에서 보고서와 함께 공개되는 수치 항목(잠정치 · 날짜 · 글 항목은 넣지 않는다)
EXTRA_ITEMS = {"FundV2_META": ["SharesCommonAdj", "SharesPrefAdj", "BuybackShares", "TreasuryShares", "CashDivTotal",
                               "CashDivCommon", "AdjDPS"],
               "FundV2_INFO": ["EPSParentAdj", "SharesCommonAvgAdj", "SharesCommonOutAdj", "AdjDPSInterim",
                               "AdjDPSFinal", "Employees"]}


def atomic_write_table(table: pa.Table, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp{os.getpid()}")
    pq.write_table(table, tmp, compression="zstd")
    os.replace(tmp, path)


def period_end(p: np.ndarray) -> np.ndarray:
    """YYYYMM int array -> month-end datetime64[D]."""
    y, m = p // 100, p % 100
    first_next = (pd.to_datetime(pd.DataFrame({"year": y, "month": m, "day": 1})) + pd.offsets.MonthBegin(1))
    return (first_next - pd.Timedelta(days=1)).values.astype("datetime64[D]")


def rule_date(p: np.ndarray, fy_month: np.ndarray) -> np.ndarray:
    """고정 규칙: 회계연도 말 분기 = 분기말 + 3개월 말일(12월 결산 = 익년 3/31), 그 밖 = 분기말 + 45일."""
    pe = period_end(p)
    is_fye = (p % 100) == fy_month
    y, m = p // 100, p % 100
    m3 = m + 3
    y3 = y + (m3 - 1) // 12
    m3 = (m3 - 1) % 12 + 1
    fye = period_end(y3 * 100 + m3)
    return np.where(is_fye, fye, pe + np.timedelta64(45, "D"))


def next_trading_day(d: np.ndarray, cal: np.ndarray) -> np.ndarray:
    """첫 거래일 > d. 달력 밖(달력 시작 전 · 미래)은 d + 1일."""
    idx = np.searchsorted(cal, d, side="right")
    out = d + np.timedelta64(1, "D")
    ok = (idx < len(cal)) & (d >= cal[0])
    out[ok] = cal[idx[ok]]
    return out


def load_long(path: Path, items=None) -> pd.DataFrame:
    t = pq.read_table(path, columns=["Ticker", "Period", "Item", "Value"])
    if items is not None:
        t = t.filter(pc.is_in(t["Item"], value_set=pa.array(items)))
    t = t.filter(pc.is_valid(t["Value"]))
    d = t.to_pandas()
    d = d[d["Value"].notna() & d["Period"].astype(str).str.fullmatch(r"\d{6}")]
    d["Period"] = d["Period"].astype(np.int32)
    for c in ("Ticker", "Item"):
        d[c] = d[c].astype("category")
    return d


def build(a) -> int:
    root = Path(a.root)
    v2 = Path(a.v2_dir) if a.v2_dir else root / ".cache/qw_fund_v2"
    out = Path(a.out_dir) if a.out_dir else root / ".cache/fundamental_v2"
    dart_p = Path(a.dart) if a.dart else root / ".cache/fundamental_dart.parquet"
    raw_p = Path(a.dart_raw) if a.dart_raw else root / ".cache/dart/dart_raw_financials.parquet"
    cal_p = Path(a.rawdata) if a.rawdata else root / ".cache/RAWDATA.parquet"
    need = [v2 / f"{d}.parquet" for d in NUM_DBS + ["FundV2_META"]] + [v2 / "fiscal_month.parquet", dart_p, raw_p, cal_p]
    miss = [str(p) for p in need if not p.exists()]
    if miss:
        print("[fund-v2-build] 입력 없음: " + " | ".join(miss))
        return 3
    tol = a.tol

    # ---- 1. 수치 행 --------------------------------------------------------------------------------
    parts = []
    for db in NUM_DBS:
        d = load_long(v2 / f"{db}.parquet")
        d["Db"] = db
        parts.append(d)
    for db, items in EXTRA_ITEMS.items():
        if (v2 / f"{db}.parquet").exists():
            d = load_long(v2 / f"{db}.parquet", items)
            d["Db"] = db
            parts.append(d)
    rows = pd.concat(parts, ignore_index=True)
    for c in ("Ticker", "Item", "Db"):
        rows[c] = rows[c].astype("category")
    print(f"[fund-v2-build] 수치 행 {len(rows):,} · 종목 {rows['Ticker'].nunique():,} · 항목 {rows['Item'].nunique()}")

    # ---- 2. (종목, 기간) 날짜 표 --------------------------------------------------------------------
    fm = pd.read_parquet(v2 / "fiscal_month.parquet")[["Ticker", "FiscalMonth"]]
    fm["FiscalMonth"] = pd.to_numeric(fm["FiscalMonth"], errors="coerce").fillna(12).astype(np.int32)
    keys = rows[["Ticker", "Period"]].drop_duplicates().copy()
    keys["Ticker"] = keys["Ticker"].astype(str)
    keys = keys.merge(fm, on="Ticker", how="left")
    keys["FiscalMonth"] = keys["FiscalMonth"].fillna(12).astype(np.int32)
    p = keys["Period"].to_numpy(np.int64)
    keys["Period_Date"] = period_end(p)
    keys["Rule_Date"] = rule_date(p, keys["FiscalMonth"].to_numpy(np.int64))
    meta = pq.read_table(v2 / "FundV2_META.parquet", columns=["Ticker", "Period", "Item", "Text"])
    meta = meta.filter(pc.equal(meta["Item"], "ReportDate")).to_pandas()
    meta = meta[meta["Text"].astype(str).str.fullmatch(r"\d{8}")]
    meta["QW_Date"] = pd.to_datetime(meta["Text"], format="%Y%m%d", errors="coerce").values.astype("datetime64[D]")
    meta["Period"] = meta["Period"].astype(np.int32)
    keys = keys.merge(meta[["Ticker", "Period", "QW_Date"]], on=["Ticker", "Period"], how="left")
    # 공시일이 분기말 이전이면(자료 오류) 쓰지 않는다
    bad = keys["QW_Date"].notna() & (keys["QW_Date"] <= keys["Period_Date"])
    keys.loc[bad, "QW_Date"] = pd.NaT
    raw = pq.read_table(raw_p, columns=["Ticker", "bsns_year", "rcept_no"]).to_pandas().dropna()
    raw = raw[raw["rcept_no"].astype(str).str.match(r"\d{8}")]
    raw["DART_Date"] = pd.to_datetime(raw["rcept_no"].astype(str).str[:8], format="%Y%m%d", errors="coerce")
    raw = raw.groupby(["Ticker", "bsns_year"], as_index=False)["DART_Date"].max()
    raw["Period"] = (raw["bsns_year"] * 100 + 12).astype(np.int32)
    keys = keys.merge(raw[["Ticker", "Period", "DART_Date"]], on=["Ticker", "Period"], how="left")
    dec = keys["FiscalMonth"] == 12
    keys.loc[~dec, "DART_Date"] = pd.NaT  # 12월 결산만 DART 연도와 대응시킨다
    qd = keys["QW_Date"].to_numpy("datetime64[D]")
    rd = keys["Rule_Date"].to_numpy("datetime64[D]")
    dd = keys["DART_Date"].to_numpy("datetime64[D]")
    base = np.where(np.isnat(qd), rd, qd)
    basis = np.where(np.isnat(qd), "rule", "qw_report").astype(object)
    later = ~np.isnat(dd) & (dd > base)
    base = np.where(later, dd, base)
    basis[later] = "dart_rcept"
    keys["Avail_Date"] = base
    keys["Avail_Basis"] = basis
    # 침묵 실패 방지: 공시일 해석이 통째로 깨지면 모든 행이 조용히 고정 규칙으로 간다(11-09 실측 qw_report 82%)
    share_qw = float((basis != "rule").mean()) if len(basis) else 0.0
    if share_qw < 0.5:
        print(f"[fund-v2-build] ⚠ 공시일 근거 비율 {share_qw:.1%} — ReportDate(M123955) 해석 확인 필요(고정 규칙으로 대체된 행이 과반)")

    # ---- 3. DART 정정 검사(12월 결산 · 2015~ · 연간) --------------------------------------------------
    dec_t = set(fm.loc[fm["FiscalMonth"] == 12, "Ticker"])
    st = rows[rows["Item"].isin(list(CHECK_STOCK)) & (rows["Period"] % 100 == 12) & (rows["Period"] // 100 >= 2015)]
    st = st.assign(FY=st["Period"] // 100)[["Ticker", "FY", "Item", "Value"]]
    fl = rows[rows["Item"].isin(list(CHECK_FLOW)) & (rows["Period"] // 100 >= 2015)]
    fl = fl.assign(FY=fl["Period"] // 100).groupby(["Ticker", "Item", "FY"], observed=True)["Value"].agg(["sum", "count"]).reset_index()
    fl = fl[fl["count"] == 4].rename(columns={"sum": "Value"})[["Ticker", "FY", "Item", "Value"]]
    qa = pd.concat([st, fl], ignore_index=True)
    qa["Ticker"] = qa["Ticker"].astype(str)
    qa["Item"] = qa["Item"].astype(str)
    qa = qa[qa["Ticker"].isin(dec_t)]
    dmap = {**CHECK_STOCK, **CHECK_FLOW}
    have = set(pq.ParquetFile(dart_p).schema_arrow.names)
    dart = pd.read_parquet(dart_p, columns=["Ticker", "bsns_year"] + sorted(set(dmap.values()) & have))
    dl = dart.melt(id_vars=["Ticker", "bsns_year"], var_name="DItem", value_name="DART_Value").dropna()
    inv = {v: k for k, v in dmap.items()}
    dl["Item"] = dl["DItem"].map(inv)
    dl = dl.rename(columns={"bsns_year": "FY"})[["Ticker", "FY", "Item", "DART_Value"]]
    chk = qa.merge(dl, on=["Ticker", "FY", "Item"], how="inner").rename(columns={"Value": "QW_Value"})
    chk["Rel_Diff"] = np.abs(chk["QW_Value"] - chk["DART_Value"]) / np.maximum(np.abs(chk["DART_Value"]), 1.0)
    chk["Same"] = chk["Rel_Diff"] <= tol
    chk = chk.merge(raw.rename(columns={"bsns_year": "FY"})[["Ticker", "FY", "DART_Date"]], on=["Ticker", "FY"], how="left")
    cy = chk.groupby(["Ticker", "FY"], as_index=False).agg(n_items=("Same", "size"), n_diff=("Same", lambda s: int((~s).sum())))
    restated = set(map(tuple, cy.loc[cy["n_diff"] > 0, ["Ticker", "FY"]].to_numpy()))
    checked = set(map(tuple, cy[["Ticker", "FY"]].to_numpy()))
    print(f"[fund-v2-build] 정정 검사 기업-연도 {len(checked):,} · 정정 의심 {len(restated):,} ({len(restated) / max(len(checked), 1):.1%})")

    # 정정 의심 → 그 회계연도 모든 분기의 공개일 = 다음 회계연도 사업보고서 공개일
    keys["FY"] = (keys["Period"] // 100).astype(np.int32)
    fye = keys[(keys["Period"] % 100) == keys["FiscalMonth"]][["Ticker", "FY", "Avail_Date"]].rename(columns={"Avail_Date": "FYE_Avail"})
    nxt = fye.assign(FY=fye["FY"] - 1).rename(columns={"FYE_Avail": "Next_FYE_Avail"})
    keys = keys.merge(nxt, on=["Ticker", "FY"], how="left")
    # 다음 해 보고서 행이 아직 없으면(가장 최근 연도) 고정 규칙으로 다음 회계연도 말 + 3개월
    miss_n = keys["Next_FYE_Avail"].isna()
    if miss_n.any():
        fyp = ((keys.loc[miss_n, "FY"] + 1) * 100 + keys.loc[miss_n, "FiscalMonth"]).to_numpy(np.int64)
        keys.loc[miss_n, "Next_FYE_Avail"] = rule_date(fyp, keys.loc[miss_n, "FiscalMonth"].to_numpy(np.int64))
    is_rs = pd.Series([(t, f) in restated for t, f in zip(keys["Ticker"], keys["FY"])], index=keys.index)
    keys.loc[is_rs, "Avail_Date"] = np.maximum(keys.loc[is_rs, "Avail_Date"].to_numpy("datetime64[D]"),
                                                keys.loc[is_rs, "Next_FYE_Avail"].to_numpy("datetime64[D]"))
    keys.loc[is_rs, "Avail_Basis"] = "restated_next_fy"
    is_ck = pd.Series([(t, f) in checked for t, f in zip(keys["Ticker"], keys["FY"])], index=keys.index)
    keys["Check"] = np.select(
        [is_rs, is_ck, keys["FiscalMonth"] != 12, keys["FY"] < 2015],
        ["restated", "agree", "non_dec_fy", "pre2015"], default="no_dart")

    # ---- 4. 다음 거래일 = Factor_Date ------------------------------------------------------------------
    cal = pc.unique(pq.read_table(cal_p, columns=["Date"])["Date"]).to_numpy(zero_copy_only=False).astype("datetime64[D]")
    cal = np.sort(cal)
    keys["Factor_Date"] = next_trading_day(keys["Avail_Date"].to_numpy("datetime64[D]"), cal)

    # ---- 5. 붙이기 · 쓰기 ------------------------------------------------------------------------------------
    rows["Ticker"] = rows["Ticker"].astype(str)
    k = keys[["Ticker", "Period", "Period_Date", "Avail_Date", "Factor_Date", "Avail_Basis", "Check"]]
    res = rows.merge(k, on=["Ticker", "Period"], how="left")
    if res["Factor_Date"].isna().any():
        print(f"[fund-v2-build] 오류: 날짜 없는 행 {int(res['Factor_Date'].isna().sum())}")
        return 1
    res["Period"] = res["Period"].astype(str)
    tbl = pa.Table.from_pandas(res[["Ticker", "Period", "Period_Date", "Item", "Value", "Avail_Date", "Factor_Date",
                                    "Avail_Basis", "Check", "Db"]], preserve_index=False)
    tbl = tbl.cast(pa.schema([("Ticker", pa.string()), ("Period", pa.string()), ("Period_Date", pa.date32()),
                              ("Item", pa.string()), ("Value", pa.float64()), ("Avail_Date", pa.date32()),
                              ("Factor_Date", pa.date32()), ("Avail_Basis", pa.string()), ("Check", pa.string()),
                              ("Db", pa.string())]))
    atomic_write_table(tbl, out / "fund_v2_quarterly.parquet")
    ck = pa.Table.from_pandas(chk[["Ticker", "FY", "Item", "QW_Value", "DART_Value", "Rel_Diff", "DART_Date", "Same"]],
                              preserve_index=False)
    atomic_write_table(ck, out / "fund_v2_annual_check.parquet")
    rep = {
        "schema": "fund_v2_build_report/v1", "built_at": dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "tol": tol, "rows": int(len(res)), "tickers": int(res["Ticker"].nunique()), "items": int(res["Item"].nunique()),
        "check_items": sorted(dmap), "company_years_checked": len(checked), "company_years_restated": len(restated),
        "restated_by_fy": {int(f): int(n) for f, n in pd.Series([f for _, f in restated]).value_counts().sort_index().items()},
        "checked_by_fy": {int(f): int(n) for f, n in pd.Series([f for _, f in checked]).value_counts().sort_index().items()},
        "item_diff_rate": {i: round(float(1 - g["Same"].mean()), 4) for i, g in chk.groupby("Item")},
        "avail_basis_rows": {str(b): int(n) for b, n in res["Avail_Basis"].value_counts().items()},
        "check_rows": {str(b): int(n) for b, n in res["Check"].value_counts().items()},
    }
    (out / "fund_v2_build_report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[fund-v2-build] 저장 {out / 'fund_v2_quarterly.parquet'} · 행 {len(res):,}")
    print("  날짜 근거:", rep["avail_basis_rows"])
    print("  검사:", rep["check_rows"])
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT") or str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--v2-dir", default="")
    ap.add_argument("--dart", default="")
    ap.add_argument("--dart-raw", default="")
    ap.add_argument("--rawdata", default="")
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--tol", type=float, default=TOL)
    try:
        return build(ap.parse_args())
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        print(f"[fund-v2-build] 오류: {e!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
