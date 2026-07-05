# prep_dividend.py — KR dividend-change SIGNALING drift (Lintner) signal construction.
# WT-D20260706_006. R arrow SEGFAULTS on 419MB rawdata -> precompute in Python -> small parquets.
#
# SIGNAL (Lintner signaling / dividend-CHANGE channel — distinct from yield LEVEL):
#   div_paid_{fy}       = total CASH dividends PAID during fiscal year fy (CF statement, DividendsPaid, abs)
#   div_yoy_{fy}        = div_paid_{fy} / div_paid_{fy-1} - 1   (YoY growth in cash dividends paid)
#   div_initiate_{fy}   = 1 if div_paid_{fy}>0 and div_paid_{fy-1}==0 (or missing) else 0  (dividend initiation)
#   Primary signal = div_yoy (continuous, higher=stronger positive signal). Initiation folded in as a
#     separate dummy analysis. We ALSO scale by lagged market cap to normalize (div growth is size-free already,
#     but we test a payout-intensity change variant div_paid/mcap YoY as robustness).
#
# PIT (C1 rolling / C2 no same-day / C4 annual->May lag / C10 liq t-1 / C14 usable<=sig):
#   Annual report for bsns_year fy is filed ~March fy+1. STANDARD KR annual lag = May fy+1 rebalance.
#   -> signal for fiscal year fy becomes USABLE starting sig month 'fy+1'-05, held until next-year 'fy+2'-04.
#   We stamp usable_ym = (fy+1)-05. For each sig month-end eom_t we pick the MOST RECENT usable annual signal.
#   div_yoy needs fy AND fy-1 both present -> first usable YoY ~2017-05 (fy2016 vs fy2015).
#   NO lookahead: usable_ym derived purely from fiscal-year filing calendar, never from returns.
#
# Cap-tier: mega=top-10 by Size(mktcap) each month, mid=11-30, small=31+. Size PIT (month-end observable).
#
# Outputs (consumed by R canonical_screen_bt):
#   div_scores.parquet : Date(sig eom), Ticker, div_yoy, div_initiate, div_payer, payout_yoy, mcap_rank, Size, tier
#   liq_dt.parquet     : Date, Ticker, adv (20d ADV t-1)
#
import pyarrow.parquet as pq
import pyarrow as pa
import numpy as np
import pandas as pd

BASE = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
OUT  = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/dividend_signaling_wt006"

# ---------------- 1. DART annual cash dividends paid ----------------
print("[py] reading DART annual financials (CF DividendsPaid)...")
dp = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/dart/dart_raw_financials.parquet"
dt = pq.read_table(dp, columns=["bsns_year","Ticker","sj_div","account_id","account_nm",
                                "thstrm_amount","fs_div"]).to_pandas()
cf = dt[dt["sj_div"]=="CF"].copy()
paid_ids = ["ifrs-full_DividendsPaid","ifrs_DividendsPaid",
            "ifrs-full_DividendsPaidClassifiedAsFinancingActivities","ifrs_DividendsPaidClassifiedAsFinancingActivities",
            "dart_AnnualDividendsPaid","dart_InterimDividendsPaid"]
paid_nm  = ["배당금지급","배당금의 지급","배당금 지급","배당금의지급","연차배당","현금배당"]
cfd = cf[cf["account_id"].isin(paid_ids) | cf["account_nm"].isin(paid_nm)].copy()
# exclude RECEIVED / stock dividends / hybrid bond / noncontrolling
excl = cfd["account_nm"].str.contains("수취|수익|주식배당|신종자본|비지배", na=False) | \
       cfd["account_id"].str.contains("Received|StockDividends|HybridBond|Noncontrolling", case=False, na=False)
cfd = cfd[~excl].copy()
def num(x):
    try: return abs(float(str(x).replace(",","").strip()))
    except: return np.nan
cfd["div_paid"] = cfd["thstrm_amount"].apply(num)
cfd = cfd[cfd["div_paid"].notna() & (cfd["div_paid"]>0)].copy()
# prefer consolidated (CFS) over separate (OFS); dedup to 1 row per (Ticker,bsns_year)
cfd["fs_pri"] = (cfd["fs_div"]=="CFS").astype(int)
cfd = cfd.sort_values(["Ticker","bsns_year","fs_pri","div_paid"], ascending=[True,True,False,False])
div = cfd.groupby(["Ticker","bsns_year"], as_index=False).first()[["Ticker","bsns_year","div_paid"]]
print(f"[py] annual dividend payer firm-years={len(div)} tickers={div['Ticker'].nunique()} "
      f"years={div['bsns_year'].min()}-{div['bsns_year'].max()}")

# --- build a COMPLETE payer/non-payer panel over the years so we can detect initiation & YoY ---
# universe of tickers that EVER appear in DART financials (payer or not) — but non-payer years have div_paid=0.
# For initiation we need to know prior-year was 0. We take: for each ticker, the min..max year it appears in DART.
allyrs = dt[["Ticker","bsns_year"]].drop_duplicates()
# firm-year exists in DART (filed a report) even if no dividend line
panel = allyrs.merge(div, on=["Ticker","bsns_year"], how="left")
panel["div_paid"] = panel["div_paid"].fillna(0.0)  # filed report but no CF dividend line = paid 0
panel = panel.sort_values(["Ticker","bsns_year"]).reset_index(drop=True)
g = panel.groupby("Ticker", group_keys=False)
panel["div_paid_prev"] = g["div_paid"].shift(1)
panel["prev_exists"]   = g["bsns_year"].shift(1).notna() & (g["bsns_year"].shift(1) == panel["bsns_year"]-1)
# YoY growth: needs prev year present AND prev>0 (can't divide by 0). initiation handled separately.
panel["div_yoy"] = np.where(panel["prev_exists"] & (panel["div_paid_prev"]>0),
                            panel["div_paid"]/panel["div_paid_prev"] - 1.0, np.nan)
# initiation: prev year present, prev==0, this>0
panel["div_initiate"] = np.where(panel["prev_exists"] & (panel["div_paid_prev"]==0) & (panel["div_paid"]>0), 1, 0)
panel["div_payer"] = (panel["div_paid"]>0).astype(int)
# usable ym = (fy+1)-05
panel["usable_ym"] = (panel["bsns_year"]+1).astype(str) + "05"
print(f"[py] panel firm-years={len(panel)}  with_yoy={panel['div_yoy'].notna().sum()}  "
      f"initiations={int(panel['div_initiate'].sum())}")

# ---------------- 2. Monthly panel from rawdata ----------------
print("[py] reading rawdata (Close/Vol/Size + member/bad)...")
t = pq.read_table(f"{BASE}/rawdata.parquet",
    columns=["Date","Ticker","Close","Vol","Size","K200","KQ150",
             "AdminStock","TradingHalt","UnfaithfulDisc"]).to_pandas()
t["Date"] = pd.to_datetime(t["Date"])
t = t[(t["Date"]>="2014-01-01") & (t["Date"]<="2026-06-30")].copy()
t["ym"] = t["Date"].dt.strftime("%Y%m")
t = t.sort_values(["Ticker","Date"]).reset_index(drop=True)
me = t.groupby("ym")["Date"].max().reset_index().rename(columns={"Date":"eom"})
ym2date = me.rename(columns={"eom":"Date"})

# 20d ADV (t-1 PIT)
gr = t.groupby("Ticker", group_keys=False)
t["tv"] = t["Vol"]*t["Close"]
t["adv20_raw"] = gr["tv"].transform(lambda s: s.rolling(20, min_periods=20).mean())
t["adv20"] = t.groupby("Ticker")["adv20_raw"].shift(1)

eom_set = set(me["eom"])
mes = t[t["Date"].isin(eom_set)].copy()
mes["member"] = (mes["K200"]==1) | (mes["KQ150"]==1)
mes["bad"] = ((mes["AdminStock"]==1)|(mes["TradingHalt"]==1)|(mes["UnfaithfulDisc"]==1)).fillna(False)
elig = mes[(mes["member"]) & (~mes["bad"]) & (mes["adv20"].notna()) & (mes["adv20"]>=2e8)
           & (mes["Size"].notna()) & (mes["Size"]>0)].copy()
elig["ym_int"] = elig["ym"].astype(int)
print(f"[py] eligible month-stock rows={len(elig)} months={elig['ym'].nunique()}")

# cap-tier
elig["mcap_rank"] = elig.groupby("ym")["Size"].rank(method="first", ascending=False).astype(int)
def tier(r):
    if r<=10: return "mega"
    if r<=30: return "mid"
    return "small"
elig["tier"] = elig["mcap_rank"].apply(tier)

# ---------------- 3. Point-in-time join: most-recent usable annual dividend signal ----------------
# For each (Ticker, sig ym) pick panel row with largest usable_ym <= sig ym.
sig = panel.copy()
sig["usable_ym_int"] = sig["usable_ym"].astype(int)
sig = sig[["Ticker","usable_ym_int","div_yoy","div_initiate","div_payer","div_paid","bsns_year"]].copy()
# asof merge per ticker
elig = elig.sort_values(["Ticker","ym_int"])
sig  = sig.sort_values(["Ticker","usable_ym_int"])
merged = pd.merge_asof(elig, sig, left_on="ym_int", right_on="usable_ym_int",
                       by="Ticker", direction="backward")
# payout-intensity YoY variant: div_paid / Size, but Size is current-month cap (PIT ok as scaling), YoY of ratio.
# Simpler robustness: div_paid scaled by lagged mcap is noisy; primary=div_yoy. keep div_paid for reference.
merged["payout_yield_proxy"] = merged["div_paid"] / (merged["Size"]*1.0)  # div_paid vs current mcap (reference only)

scores = merged.merge(ym2date, on="ym")
scores = scores[["Date","Ticker","div_yoy","div_initiate","div_payer","payout_yield_proxy",
                 "div_paid","bsns_year","mcap_rank","Size","tier"]].copy()
# keep only rows where the firm has a usable annual signal (payer info known)
scores = scores[scores["div_payer"].notna()].copy()

liq = elig[["ym","Ticker","adv20"]].merge(ym2date, on="ym")[["Date","Ticker","adv20"]].rename(columns={"adv20":"adv"})

import os
os.makedirs(OUT, exist_ok=True)
def w(dfx, name):
    pq.write_table(pa.Table.from_pandas(dfx.reset_index(drop=True), preserve_index=False), f"{OUT}/{name}")
    print(f"[py] wrote {name}: rows={len(dfx)}")
w(scores, "div_scores.parquet")
w(liq, "liq_dt.parquet")

# ---------------- sanity / coverage ----------------
print("\n[py] === COVERAGE / FRESHNESS ===")
print("score Date range:", scores["Date"].min(), "->", scores["Date"].max())
sc_yoy = scores[scores["div_yoy"].notna()]
print("rows with div_yoy (usable continuous signal):", len(sc_yoy))
print("months with >=10 payers (yoy):",
      (sc_yoy.groupby(scores.loc[sc_yoy.index,"Date"]).size()>=10).sum())
cov = sc_yoy.groupby("Date").size()
print("payers-with-yoy per month describe:\n", cov.describe())
print("\ntier counts among yoy-signal rows:\n", sc_yoy["tier"].value_counts())
# mega payers per month (key: is there breadth in mega tier?)
mega_yoy = sc_yoy[sc_yoy["tier"]=="mega"]
print("\nMEGA-tier payers-with-yoy per month describe:\n", mega_yoy.groupby("Date").size().describe())
print("[py] DONE")
