"""DLTT 만 있는 칸(유동 차입 · 유동 사채 줄 없음)은 어떤 회사인가 — 유동 · 비유동 구분 없는 재무상태표(금융업 서식)인가
· 업종 · 유동부채 줄 유무 · 이자발생부채 차이 (2026-11-10 · 읽기 전용)"""
import pandas as pd
import pyarrow.parquet as pq

ROOT = r"G:/OneDrive/Quant_Module_Moltbot"
SRC = ROOT + "/.cache/fundamental_v2/fund_v2_quarterly.parquet"
ITEMS = ["CurrentBorr", "CurrentBonds", "LongTermBorr", "Bonds", "InterestBearingDebt", "TotalAssets",
         "CurrentLiab", "CurrentAssets", "TotalLiab"]
d = pq.read_table(SRC, columns=["Ticker", "Period", "Item", "Value"], filters=[("Item", "in", ITEMS)]).to_pandas()
d["Period"] = d["Period"].astype(str)
w = d.pivot_table(index=["Ticker", "Period"], columns="Item", values="Value", aggfunc="first")
w["DLC"] = w[["CurrentBorr", "CurrentBonds"]].sum(axis=1, min_count=1)
w["DLTT"] = w[["LongTermBorr", "Bonds"]].sum(axis=1, min_count=1)
bs = w["TotalAssets"].notna()
grp = pd.Series("none", index=w.index)
grp[w["DLC"].notna() & w["DLTT"].notna()] = "both"
grp[w["DLC"].notna() & w["DLTT"].isna()] = "DLC_only"
grp[w["DLC"].isna() & w["DLTT"].notna()] = "DLTT_only"
w["grp"] = grp
w = w[bs]
print("[유동부채 줄 있음 비율 · 유동자산 줄 있음 비율] 묶음별")
print(w.groupby("grp").agg(n=("TotalAssets", "size"),
                           has_CL=("CurrentLiab", lambda s: s.notna().mean()),
                           has_CA=("CurrentAssets", lambda s: s.notna().mean()),
                           has_IBD=("InterestBearingDebt", lambda s: s.notna().mean())).to_string())
# 업종: RAWDATA 최신 Sector
raw = pq.read_table(ROOT + "/.cache/RAWDATA.parquet", columns=["Date", "Ticker", "Sector"]).to_pandas() \
    if __import__("os").path.exists(ROOT + "/.cache/RAWDATA.parquet") else None
if raw is not None:
    sec = raw.dropna(subset=["Sector"]).sort_values("Date").groupby("Ticker")["Sector"].last()
    x = w.reset_index()
    x["Ticker6"] = x["Ticker"].str.replace("^A", "", regex=True)
    sec.index = sec.index.astype(str).str.replace("^A", "", regex=True)
    x["Sector"] = x["Ticker6"].map(sec)
    for g in ["DLTT_only", "none", "DLC_only"]:
        vc = x[x["grp"] == g]["Sector"].value_counts(dropna=False)
        print(f"[업종 상위 · {g}] " + " · ".join(f"{k} {v}" for k, v in vc.head(8).items()))
# DLTT 만 칸 중 유동부채 줄이 있는 칸(= 유동 · 비유동 구분 서식인데 유동 차입이 빠진 칸)의 이자발생부채 차이
y = w[(w["grp"] == "DLTT_only")]
for has_cl, sub in y.groupby(y["CurrentLiab"].notna()):
    rel = (sub["InterestBearingDebt"] - sub["DLTT"]) / sub["TotalAssets"]
    print(f"[DLTT 만 · 유동부채 줄 {'있음' if has_cl else '없음'}] 칸 {len(sub):,} · 차이 ≤ 자산 2% {float((rel.abs() <= 0.02).mean()):.3f} · "
          f"차이 중앙 {float(rel.median()):.3f}(자산 대비) · 종목 {sub.index.get_level_values('Ticker').nunique()}")
print(y.reset_index().groupby("Ticker").size().sort_values(ascending=False).head(12).to_string())
