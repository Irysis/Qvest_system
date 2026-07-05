# prep_monthly.py — Python preprocessor (R arrow segfaults on 419MB rawdata).
# Produces small monthly tables the R canonical_screen_bt engine consumes:
#   returns_dt.parquet : Date(sig month-end), Ticker, Ret_1m (FORWARD 1m realized)
#   bench_dt.parquet   : Date(sig month-end), BM_Ret (FORWARD 1m benchmark)
#   me_uni.parquet     : ym, Date(eom), Ticker, Size  (eligible universe, t-1 ADV>=2e8, member, no bad-flag)
#   mret.parquet       : ym, Ticker, mret  (monthly compounded asset return, for reversal signal)
# Construction MATCHES prior flow_stage_a_engine.R exactly (verified logic):
#   universe = (K200|KQ150) & !bad & adv20>=2e8, adv20 = shift(frollmean(Vol*Close,20),1) per Ticker (t-1 PIT C10)
#   mret = prod(1+Ret)-1 per (Ticker,ym), require ndays>=5
#   forward: sig month ym -> returns of ym_next
import pyarrow.parquet as pq
import pyarrow.compute as pc
import numpy as np
import pandas as pd

BASE = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
OUT  = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/flow_microstructure_cycle2"

print("[py] reading rawdata...")
t = pq.read_table(f"{BASE}/rawdata.parquet",
    columns=["Date","Ticker","Close","Vol","Ret","Size","K200","KQ150",
             "AdminStock","TradingHalt","UnfaithfulDisc"])
df = t.to_pandas()
df["Date"] = pd.to_datetime(df["Date"])
df = df[(df["Date"] >= "2004-10-01") & (df["Date"] <= "2026-06-30")].copy()
df["ym"] = df["Date"].dt.strftime("%Y%m")
df = df.sort_values(["Ticker","Date"])
print(f"[py] rawdata rows={len(df)}")

# month-end dates
me = df.groupby("ym")["Date"].max().reset_index().rename(columns={"Date":"eom"})
me = me.sort_values("ym").reset_index(drop=True)
ym_sorted = me["ym"].tolist()
next_map = pd.DataFrame({"ym": ym_sorted[:-1], "ym_next": ym_sorted[1:]})
ym2date = me.rename(columns={"eom":"Date"})

# monthly compounded asset return
df["one_plus"] = 1.0 + df["Ret"].fillna(np.nan)
g = df.dropna(subset=["Ret"]).groupby(["Ticker","ym"])
mret = g["Ret"].apply(lambda r: np.prod(1.0+r.values)-1.0).reset_index(name="mret")
ndays = g.size().reset_index(name="ndays")
mret = mret.merge(ndays, on=["Ticker","ym"])
mret = mret[mret["ndays"] >= 5][["ym","Ticker","mret"]]
print(f"[py] mret rows={len(mret)}")

# 20d ADV (t-1 PIT): per Ticker, frollmean(Vol*Close,20) then shift 1
df["tv"] = df["Vol"] * df["Close"]
df["adv20_raw"] = df.groupby("Ticker")["tv"].transform(lambda s: s.rolling(20, min_periods=20).mean())
df["adv20"] = df.groupby("Ticker")["adv20_raw"].shift(1)

# month-end state
eom_set = set(me["eom"])
mes = df[df["Date"].isin(eom_set)].copy()
mes["member"] = (mes["K200"]==1) | (mes["KQ150"]==1)
mes["bad"] = (mes["AdminStock"]==1) | (mes["TradingHalt"]==1) | (mes["UnfaithfulDisc"]==1)
mes["bad"] = mes["bad"].fillna(False)
uni = mes[(mes["member"]) & (~mes["bad"]) & (mes["adv20"].notna()) & (mes["adv20"]>=2e8)][["ym","Ticker","Size"]].copy()
print(f"[py] universe rows={len(uni)} months={uni['ym'].nunique()} median_stocks={uni.groupby('ym').size().median():.0f}")

# forward returns aligned to sig month-end Date
fwd = next_map.merge(mret.rename(columns={"ym":"ym_next"}), on="ym_next")[["ym","Ticker","mret"]]
fwd = fwd.rename(columns={"mret":"Ret_1m"})
returns_dt = fwd.merge(ym2date, on="ym")[["Date","Ticker","Ret_1m"]]

# benchmark monthly forward
bm = pq.read_table(f"{BASE}/benchmark.parquet").to_pandas()
bm["Date"] = pd.to_datetime(bm["Date"])
bm = bm[bm["Date"]>="2004-12-01"].copy()
bm["ym"] = bm["Date"].dt.strftime("%Y%m")
bmret = bm.dropna(subset=["BM_Ret"]).groupby("ym")["BM_Ret"].apply(lambda r: np.prod(1.0+r.values)-1.0).reset_index(name="bm_mret")
bench_fwd = next_map.merge(bmret.rename(columns={"ym":"ym_next"}), on="ym_next")
bench_dt = bench_fwd[["ym","bm_mret"]].merge(ym2date, on="ym")[["Date","bm_mret"]].rename(columns={"bm_mret":"BM_Ret"})

# write
import pyarrow as pa
def w(dfx, name):
    pq.write_table(pa.Table.from_pandas(dfx.reset_index(drop=True), preserve_index=False), f"{OUT}/{name}")
    print(f"[py] wrote {name}: rows={len(dfx)}")
w(returns_dt, "returns_dt.parquet")
w(bench_dt, "bench_dt.parquet")
w(uni.merge(ym2date, on="ym")[["ym","Date","Ticker","Size"]], "me_uni.parquet")
w(mret, "mret.parquet")
print("[py] DONE")
