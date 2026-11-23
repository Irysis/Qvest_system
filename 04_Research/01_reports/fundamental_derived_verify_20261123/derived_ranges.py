import json, sys, numpy as np, pandas as pd, pyarrow.parquet as pq, pyarrow.compute as pc
ROOT="G:/OneDrive/Quant_Module_Moltbot"; OUT=sys.argv[1]
res={}
# 값이 정의상 가져야 할 범위(분모 양수 · 분자 비음수 · 부분 ≤ 전체 · 지시변수)
RULES = {"PiotroskiF": (0, 9, True), "TaxRate": (0, 1, False), "EffectiveTaxRate": (0, 1, False), "ShortDebtShare": (0, 1, False),
         "O_OENEG": (0, 1, True), "O_INTWO": (0, 1, True), "CashToAssets": (0, 1, False), "InventoryToAssets": (0, 1, False),
         "RecvToAssets": (0, 1, False), "TangibleAssetRatio": (0, 1, False), "IntangibleRatio": (0, 1, False),
         "NonCurrentAssetRatio": (0, 1, False), "DebtToAssets": (0, None, False), "LiabToAssets": (0, None, False),
         "CurrentRatio": (0, None, False), "QuickRatio": (0, None, False), "CashRatio": (0, None, False), "TreasuryShareRatio": (0, 1, False),
         "LongTermDebtRatio": (0, None, False), "IBDebtToAssets": (0, None, False), "PayoutRatio": (0, None, False)}
for c in ["PF_ROA","PF_CFO","PF_dROA","PF_Accrual","PF_dLever","PF_dLiquid","PF_EqIssue","PF_dMargin","PF_dTurn"]: RULES[c]=(0,1,True)
for lab, f in (("quarterly", "fundamental_quarterly"), ("annual", "fundamental_annual")):
    t = pq.read_table(f"{ROOT}/.cache/{f}.parquet", columns=["Item", "Value", "Kind", "Ticker"], read_dictionary=["Item", "Kind", "Ticker"])
    t = t.filter(pc.equal(t["Kind"], "derived")).to_pandas()
    g = t.groupby("Item", observed=True).Value
    st = pd.DataFrame({"n": g.size(), "tickers": t.groupby("Item", observed=True).Ticker.nunique(), "p001": g.quantile(0.001), "p01": g.quantile(0.01),
                       "p50": g.median(), "p99": g.quantile(0.99), "p999": g.quantile(0.999), "min": g.min(), "max": g.max()})
    st.to_csv(f"{OUT}/derived_ranges_{lab}.csv")
    viol = {}
    for it, (lo, hi, integer) in RULES.items():
        v = t.Value[t.Item == it]
        if not len(v): viol[it] = "없음"; continue
        bad = ((v < lo - 1e-12) | ((v > hi + 1e-12) if hi is not None else False) | ((np.abs(v - np.round(v)) > 1e-9) if integer else False))
        if bad.sum(): viol[it] = dict(n_bad=int(bad.sum()), n=int(len(v)), min=float(v.min()), max=float(v.max()))
    res[lab] = dict(items=len(st), low_coverage=st[st.tickers < 200].index.tolist(), violations=viol,
                    huge_abs=st[(st["max"].abs() > 1e6) | (st["min"].abs() > 1e6)].index.tolist())
json.dump(res, open(f"{OUT}/derived_ranges_summary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(res, ensure_ascii=False, indent=1))
