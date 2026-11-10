"""차입 두 줄 기간 완비 — 같은 코드 · 재무 표만 정본(old) vs 후보(new) build_factor_db(save = FALSE) 비교
① 바뀐 팩터(달마다 · 합집합) ② R18(두 줄 합 / 자산) vs Q16(같은 기간 TotalDebt / 자산) 차이 > 자산 1% 종목 수 ③ 예시 종목 (2026-11-10)"""
import sys
import numpy as np
import pandas as pd

sp = sys.argv[1]; months = sys.argv[2:]
allchg = {}
for ym in months:
    o = pd.read_parquet(f"{sp}/old_{ym}.parquet"); n = pd.read_parquet(f"{sp}/new_{ym}.parquet")
    m = o.merge(n, on=["Ticker", "Factor_Name"], how="outer", suffixes=("_o", "_n"), indicator=True)
    both = m[m._merge == "both"]
    chg = both[~np.isclose(both.Raw_Value_o, both.Raw_Value_n, rtol=1e-10, atol=1e-12, equal_nan=True)]
    g = pd.DataFrame({"n_old": o.groupby("Factor_Name").size(), "n_new": n.groupby("Factor_Name").size(),
                      "changed": chg.groupby("Factor_Name").size()}).fillna(0).astype(int)
    g = g[(g.changed > 0) | (g.n_old != g.n_new)]
    print(f"== {ym}: 팩터 {o.Factor_Name.nunique()} · 바뀐 팩터 {len(g)}")
    print(g.sort_values("changed", ascending=False).to_string())
    for f in g.index:
        allchg.setdefault(f, []).append(ym)
    for side, d in (("old", o), ("new", n)):
        w = d[d.Factor_Name.isin(["R18_Book_Leverage", "Q16_Debt_to_Assets"])].pivot_table(
            index="Ticker", columns="Factor_Name", values="Raw_Value", aggfunc="first").dropna()
        gap = (w["R18_Book_Leverage"] - w["Q16_Debt_to_Assets"]).abs()
        print(f"   [{side}] R18 vs Q16 둘 다 있는 종목 {len(w):,} · 차이 > 자산 1% {int((gap > 0.01).sum()):,} · > 5% {int((gap > 0.05).sum()):,} · "
              f"같음(1e-12) {int((gap <= 1e-12).sum()):,}")
    for tk in ("A002290", "A001000", "A015760", "A005380", "A051910"):
        r = m[(m.Ticker == tk) & m.Factor_Name.isin(["R18_Book_Leverage", "Q16_Debt_to_Assets", "R17_Market_Leverage", "AC05_NOA"])]
        if len(r):
            print(f"   {tk}: " + " · ".join(f"{f} {a:.4f}→{b:.4f}" for f, a, b in r[["Factor_Name", "Raw_Value_o", "Raw_Value_n"]].itertuples(index=False)))
print("\nUNION", len(allchg), sorted(allchg))
print("ALL3", sorted(f for f, v in allchg.items() if len(v) == len(months)))
