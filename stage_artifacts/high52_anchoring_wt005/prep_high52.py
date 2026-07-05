# prep_high52.py — 52-week-high proximity (George-Hwang 2004) signal construction.
# R arrow SEGFAULTS on 419MB rawdata → precompute in Python, write small monthly parquets.
#
# PIT construction (C1 rolling / C2 no same-day / C10 liq t-1):
#   For each ticker, at sig month-end eom_t:
#     high252_{t-1} = max(High) over the trailing 252 TRADING DAYS ending at t-1 (i.e., days < eom_t)
#     price_{t-1}   = Close at t-1 (the last trading day STRICTLY before eom_t is not needed;
#                     we use eom_t's own Close vs high computed over [t-251 ... t] EXCLUDING nothing?)
#   ★ PIT decision: signal is known AT eom_t (decision date). Close_{eom} and High over the window
#     ending AT eom (inclusive) are all observable at eom close. Forward return is ym_next.
#     This is the standard George-Hwang construction: PRt,j = P_{t,j} / high_{t,j}(52wk) at formation date t.
#     No lookahead: window ends at formation date, return measured next month. (C2 satisfied: we do NOT
#     use same-day forward info; C1: rolling window per date.)
#   To be extra-conservative and match the request's "t-1" phrasing we ALSO build a lag1 variant
#     (price and high both as-of the prior trading day) for the self-adversarial PIT check.
#
# Cap-tier: mega = top-10 by Size (mktcap) each month, mid = 11-30, small = 31+.
#   Size is PIT (month-end observable market cap). rank within eligible universe.
#
# Outputs (consumed by R canonical_screen_bt):
#   high52_scores.parquet : Date(sig eom), Ticker, pr52 (proximity, higher=nearer high), pr52_lag1, mcap_rank, Size, tier
#   liq_dt.parquet        : Date, Ticker, adv (20d ADV t-1)
# Reuses returns_dt/bench_dt/me_uni already built in flow_microstructure_cycle2 (verified same construction).

import pyarrow.parquet as pq
import pyarrow as pa
import numpy as np
import pandas as pd

BASE = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
CYC2 = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/flow_microstructure_cycle2"
OUT  = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/high52_anchoring_wt005"

print("[py] reading rawdata (Close/High/Vol/Size + member/bad flags)...")
t = pq.read_table(f"{BASE}/rawdata.parquet",
    columns=["Date","Ticker","Close","High","Vol","Size","K200","KQ150",
             "AdminStock","TradingHalt","UnfaithfulDisc"])
df = t.to_pandas()
df["Date"] = pd.to_datetime(df["Date"])
# need >=252 trading days lookback before 2004-10 start; go back further
df = df[(df["Date"] >= "2002-01-01") & (df["Date"] <= "2026-06-30")].copy()
df["ym"] = df["Date"].dt.strftime("%Y%m")
df = df.sort_values(["Ticker","Date"]).reset_index(drop=True)
print(f"[py] rawdata rows={len(df)}")

# month-end dates
me = df.groupby("ym")["Date"].max().reset_index().rename(columns={"Date":"eom"})
me = me.sort_values("ym").reset_index(drop=True)
ym2date = me.rename(columns={"eom":"Date"})

# --- 52wk-high proximity: rolling max High over trailing 252 trading days per ticker ---
# window includes the current day (formation date). min_periods=200 to require sufficient history.
g = df.groupby("Ticker", group_keys=False)
df["high252"] = g["High"].transform(lambda s: s.rolling(252, min_periods=200).max())
# lag1 variant: high and price both shifted by 1 trading day (strictly-before-formation)
df["Close_lag1"]   = g["Close"].shift(1)
df["high252_lag1"] = g["high252"].shift(1)
# proximity ratios
df["pr52"]      = df["Close"]      / df["high252"]
df["pr52_lag1"] = df["Close_lag1"] / df["high252_lag1"]

# 20d ADV (t-1 PIT) for liquidity filter
df["tv"] = df["Vol"] * df["Close"]
df["adv20_raw"] = g["tv"].transform(lambda s: s.rolling(20, min_periods=20).mean())
df["adv20"] = df.groupby("Ticker")["adv20_raw"].shift(1)

# month-end snapshot
eom_set = set(me["eom"])
mes = df[df["Date"].isin(eom_set)].copy()
mes["member"] = (mes["K200"]==1) | (mes["KQ150"]==1)
mes["bad"] = ((mes["AdminStock"]==1) | (mes["TradingHalt"]==1) | (mes["UnfaithfulDisc"]==1)).fillna(False)
# eligible universe: member & !bad & adv20>=2e8 (matches canonical) & valid signal & valid Size
elig = mes[(mes["member"]) & (~mes["bad"]) & (mes["adv20"].notna()) & (mes["adv20"]>=2e8)
           & (mes["pr52"].notna()) & (mes["Size"].notna()) & (mes["Size"]>0)].copy()
print(f"[py] eligible month-stock rows={len(elig)} months={elig['ym'].nunique()} median_stocks={elig.groupby('ym').size().median():.0f}")

# cap-tier: rank by Size DESC within each month (1 = largest)
elig["mcap_rank"] = elig.groupby("ym")["Size"].rank(method="first", ascending=False).astype(int)
def tier(r):
    if r <= 10: return "mega"
    if r <= 30: return "mid"
    return "small"
elig["tier"] = elig["mcap_rank"].apply(tier)

scores = elig[["ym","Ticker","pr52","pr52_lag1","mcap_rank","Size","tier"]].merge(ym2date, on="ym")
scores = scores[["Date","Ticker","pr52","pr52_lag1","mcap_rank","Size","tier"]]

# liq_dt (adv at month-end, PIT t-1) — for canonical liq filter (redundant w/ prefilter but pass through)
liq = elig[["ym","Ticker","adv20"]].merge(ym2date, on="ym")[["Date","Ticker","adv20"]].rename(columns={"adv20":"adv"})

def w(dfx, name):
    pq.write_table(pa.Table.from_pandas(dfx.reset_index(drop=True), preserve_index=False), f"{OUT}/{name}")
    print(f"[py] wrote {name}: rows={len(dfx)}")

import os
os.makedirs(OUT, exist_ok=True)
w(scores, "high52_scores.parquet")
w(liq, "liq_dt.parquet")

# quick freshness / distribution sanity
print("[py] score Date range:", scores["Date"].min(), "->", scores["Date"].max())
print("[py] pr52 describe:\n", scores["pr52"].describe())
print("[py] tier counts (month-stock):\n", scores["tier"].value_counts())
print("[py] DONE")
