"""재계산 뒤 저장된 팩터 DB 점검 — R18(두 줄 합) vs Q16(같은 기간 TotalDebt) 차이 · 예시 종목 · 날짜
(2026-11-10 차입 두 줄 기간 완비 수리 · 저장 무결성 점검 · 리서치 소비 아님)"""
import sys
import pyarrow.parquet as pq

ROOT = r"G:/OneDrive/Quant_Module_Moltbot/.cache/factor_db"
MONTHS = sys.argv[1:] or ["200106", "200512", "201206", "201412", "201906", "202506", "202610", "202611"]
F = ["R18_Book_Leverage", "Q16_Debt_to_Assets", "R17_Market_Leverage", "AC05_NOA"]
for ym in MONTHS:
    t = pq.read_table(f"{ROOT}/factor_db_{ym}.parquet", columns=["Date", "Ticker", "Factor_Name", "Raw_Value"],
                      filters=[("Factor_Name", "in", F)]).to_pandas()
    d = sorted(set(str(x)[:10] for x in t["Date"].unique()))
    w = t.pivot_table(index="Ticker", columns="Factor_Name", values="Raw_Value", aggfunc="first")
    b = w[["R18_Book_Leverage", "Q16_Debt_to_Assets"]].dropna()
    gap = (b["R18_Book_Leverage"] - b["Q16_Debt_to_Assets"]).abs()
    ex = []
    for tk in ("A002290", "A001000"):
        if tk in w.index:
            ex.append(f"{tk} Q16 {w.loc[tk, 'Q16_Debt_to_Assets']:.4f} R18 {w.loc[tk, 'R18_Book_Leverage']:.4f}")
    print(f"[{ym}] Date={d} · R18 vs Q16 둘 다 {len(b):,} · 차이 > 자산 1% {int((gap > 0.01).sum()):,} · > 5% {int((gap > 0.05).sum()):,} · "
          f"같음(1e-12) {int((gap <= 1e-12).sum()):,} · " + " · ".join(ex))
