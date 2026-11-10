"""차입 두 줄(DLC = 유동 차입 + 유동 사채 · DLTT = 장기차입 + 사채) 중 한 줄만 있는 재무상태표 칸 — 없는 줄 = 0 관례가 맞는가
(이자발생부채 M113800 로 대조) · 같은 (종목, 기간) 안 Factor_Date 가 항목마다 같은가 (2026-11-10 · 읽기 전용)"""
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

SRC = r"G:/OneDrive/Quant_Module_Moltbot/.cache/fundamental_v2/fund_v2_quarterly.parquet"
ITEMS = ["CurrentBorr", "CurrentBonds", "LongTermBorr", "Bonds", "InterestBearingDebt", "TotalAssets"]
d = pq.read_table(SRC, columns=["Ticker", "Period", "Item", "Value", "Factor_Date"],
                  filters=[("Item", "in", ITEMS)]).to_pandas()
d["Period"] = d["Period"].astype(str)
print("rows", len(d), d["Item"].value_counts().to_dict())

# Q1 같은 (종목, 기간) 안 날짜가 하나인가
nfd = d.groupby(["Ticker", "Period"])["Factor_Date"].nunique()
print(f"[Q1] (종목, 기간) {len(nfd):,} 중 항목 간 Factor_Date 가 둘 이상인 칸 {int((nfd > 1).sum()):,}")
dup = d.groupby(["Ticker", "Period", "Item"]).size()
print(f"[Q1b] (종목, 기간, 항목) 중복 {int((dup > 1).sum())}")

w = d.pivot_table(index=["Ticker", "Period"], columns="Item", values="Value", aggfunc="first")
def s(cols):
    sub = w[cols]
    return sub.sum(axis=1, min_count=1)
w["DLC"] = s(["CurrentBorr", "CurrentBonds"])
w["DLTT"] = s(["LongTermBorr", "Bonds"])
w["Y"] = w.index.get_level_values("Period").str[:4].astype(int)
bs = w["TotalAssets"].notna()
c_both = w["DLC"].notna() & w["DLTT"].notna()
c_dlc = w["DLC"].notna() & w["DLTT"].isna()
c_dltt = w["DLC"].isna() & w["DLTT"].notna()
c_none = w["DLC"].isna() & w["DLTT"].isna()
print(f"[Q2] 재무상태표 칸 {int(bs.sum()):,}: 두 줄 {int((bs & c_both).sum()):,} · DLC 만 {int((bs & c_dlc).sum()):,} · "
      f"DLTT 만 {int((bs & c_dltt).sum()):,} · 둘 다 없음 {int((bs & c_none).sum()):,}")
print(f"[Q2b] 자산총계 없는데 차입 줄 있음 {int((~bs & ~c_none).sum()):,}")

def cmp(mask, present, label):
    x = w[mask & bs]
    ibd = x["InterestBearingDebt"]
    p = x[present] if isinstance(present, str) else x[present].sum(axis=1)
    has = ibd.notna()
    gap = (ibd - p)[has]
    rel = gap / x["TotalAssets"][has]
    pos = p[has] > 0
    ratio = (ibd[has][pos] / p[has][pos])
    print(f"  {label}: 칸 {len(x):,} · 이자발생부채 있음 {int(has.sum()):,} · "
          f"|이자발생부채 − 있는 줄| ≤ 자산 0.5% {float((rel.abs() <= 0.005).mean()):.3f} · ≤ 2% {float((rel.abs() <= 0.02).mean()):.3f} · "
          f"이자발생부채 > 있는 줄 + 자산 5% {float((rel > 0.05).mean()):.3f} · 비율 중앙 {float(ratio.median()) if len(ratio) else float('nan'):.3f}")
    return x
print("[Q3] 이자발생부채 대 있는 줄(없는 줄 = 0 이 맞으면 두 줄 칸과 같은 분포)")
cmp(c_both, ["DLC", "DLTT"], "두 줄(대조)")
xd = cmp(c_dlc, "DLC", "DLC 만")
xt = cmp(c_dltt, "DLTT", "DLTT 만")
print("[Q4] 한 줄 칸 연도별(DLC 만 / DLTT 만):")
yy = pd.DataFrame({"DLC만": xd.groupby("Y").size(), "DLTT만": xt.groupby("Y").size(),
                   "BS": w[bs].groupby("Y").size()}).fillna(0).astype(int)
print(yy.T.to_string())
# 0 으로 명시된 줄 비율(두 줄 칸 중 하나가 0)
z = w[c_both & bs]
print(f"[Q5] 두 줄 칸 중 DLC = 0 {float((z['DLC'] == 0).mean()):.3f} · DLTT = 0 {float((z['DLTT'] == 0).mean()):.3f}")
