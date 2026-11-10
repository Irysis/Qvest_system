"""R18 · Q16 재도출(모듈과 독립 · 재무 표에서 직접): 신호일 기준 항목마다 Factor_Date 최신 행 → R18 = −(단기 + 장기)/자산 · Q16 = −TotalDebt/자산
— 정본(old) · 후보(new) 표 각각 · 팩터 대조(diff_align.py)의 모듈 산출과 맞춰 본다 (2026-11-10 · 읽기 전용)
사용: python r18_rederive.py <정본 merged.parquet> <후보 merged.parquet> <신호일 YYYY-MM-DD> [모듈 산출 old.parquet new.parquet]"""
import sys
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

canon, cand, sig = sys.argv[1], sys.argv[2], pd.Timestamp(sys.argv[3])
mods = sys.argv[4:6] if len(sys.argv) >= 6 else None
ITEMS = ["ShortTermBorr", "LongTermBorr", "TotalDebt", "TotalAssets"]


def derive(path):
    d = pq.read_table(path, columns=["Ticker", "Item", "Period", "Value", "Factor_Date"],
                      filters=[("Item", "in", ITEMS)]).to_pandas()
    d["Factor_Date"] = pd.to_datetime(d["Factor_Date"])
    d = d[d["Factor_Date"] <= sig].sort_values("Factor_Date").groupby(["Ticker", "Item"]).tail(1)
    w = d.pivot(index="Ticker", columns="Item", values="Value")
    p = d.pivot(index="Ticker", columns="Item", values="Period")
    s, l, ta = w.get("ShortTermBorr"), w.get("LongTermBorr"), w.get("TotalAssets")
    td_lines = np.where(s.isna() & l.isna(), np.nan, s.fillna(0) + l.fillna(0))
    has_lines = s.notna() & l.notna()
    out = pd.DataFrame({"R18": np.where(ta > 0, -td_lines / ta, np.nan), "Q16": np.where(ta > 0, -w["TotalDebt"] / ta, np.nan),
                        "lines_same_period": (p["ShortTermBorr"] == p["LongTermBorr"]).where(has_lines),
                        "P_lines": p["ShortTermBorr"], "P_td": p["TotalDebt"], "P_ta": p["TotalAssets"]}, index=w.index)
    return out


for label, path in (("old", canon), ("new", cand)):
    o = derive(path)
    b = o.dropna(subset=["R18", "Q16"])
    gap = (b["R18"] - b["Q16"]).abs()
    print(f"[{label}] {sig.date()} R18 · Q16 둘 다 {len(b):,} · 차이 > 자산 1% {int((gap > 0.01).sum()):,} · > 5% {int((gap > 0.05).sum()):,} · "
          f"두 줄 최신 행 같은 기간 {int(o['lines_same_period'].sum()):,} / 두 줄 있는 종목 {int(o['lines_same_period'].notna().sum()):,}")
    if label == "new" and (gap > 0.01).any():
        print("   남은 차이(두 줄 기간 대 TotalDebt 기간 대 자산 기간):")
        print(b[gap > 0.01][["R18", "Q16", "P_lines", "P_td", "P_ta"]].to_string())
    if mods:
        m = pd.read_parquet(mods[0] if label == "old" else mods[1])
        r = m[m["Factor_Name"] == "R18_Book_Leverage"].set_index("Ticker")["Raw_Value"]
        j = o.join(r.rename("mod"), how="inner").dropna(subset=["R18", "mod"])
        print(f"   모듈 R18 대 재도출: 맞춘 종목 {len(j):,} · 값 같음(1e-9) {int((j['R18'] - j['mod']).abs().le(1e-9).sum()):,}")
