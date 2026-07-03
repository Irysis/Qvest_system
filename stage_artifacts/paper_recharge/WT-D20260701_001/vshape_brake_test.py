#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Quick-test for paper 2606.09025 V-shape crash-brake filter (non-max-cash component).
KR adaptation. PIT-disciplined.

Design:
  - Risky sleeve R = self-built cap-weighted (Size) daily return of K200 union KQ150 universe
    from RAWDATA (immune to corrupted BM_Ret).
  - BrakeScore (paper eq, t-1 lagged):
        BrakeScore_t = VIXCore + lam_r*RatePanic + lam_c*CreditPanic  (+ drawdown/crash-loss)
    VIXCore = a_vix*VIXLevel_z + (1-a_vix)*VIXSpike_z
    -> mapped to cash weight w_cash in [0, maxcash]; risk-on (w_R = 1-w_cash) otherwise.
  - Signal uses ONLY data up to t-1 (shift(1)); standardization is EXPANDING (no full-sample).
  - Net cost on |delta w_R| * 15bps one-way.
  - Compare: (A) brake-gated R vs buy&hold R; (B) brake vs existing `exposure` overlay; (C) brake OR exposure.
  - Metrics: annualized Sharpe, CAGR, MDD, Calmar (standard formulas only; no synthetic compounding of blended legs).
  - Windows: full-ex-2026 (<=2025-12) and <=2025-09 (BM-safe). Self-built proxy so 2026 tail still shown but flagged.

metric_type = "proxy_overlay" (market-timing proxy on self-built KR cap-w index; NOT book-authoritative)
"""
import numpy as np, pandas as pd
import pyarrow.dataset as ds, pyarrow.parquet as pq
import pyarrow.compute as pc

ROOT = "."
COST_BPS = 15.0 / 1e4  # one-way

# ---------- 1. Build KR cap-weighted market proxy from RAWDATA ----------
print("[1] building KR cap-weighted market proxy (K200 union KQ150)...")
d = ds.dataset(f"{ROOT}/.cache/RAWDATA.parquet")
# filter: in K200 or KQ150 universe; need Date,Ticker,Ret,Size,K200,KQ150
flt = (pc.field("Date") >= pd.Timestamp("2004-12-01"))
tb = d.to_table(columns=["Date","Ticker","Ret","Size","K200","KQ150"], filter=flt)
df = tb.to_pandas()
df["Date"] = pd.to_datetime(df["Date"])
# universe membership: K200==1 or KQ150==1 (flags are 1.0/NaN)
df["in_univ"] = ((df["K200"].fillna(0) > 0) | (df["KQ150"].fillna(0) > 0))
df = df[df["in_univ"] & df["Ret"].notna() & df["Size"].notna() & (df["Size"] > 0)].copy()
# winsorize daily returns lightly to avoid bad ticks dominating (±50%)
df["Ret"] = df["Ret"].clip(-0.5, 0.5)
# cap-weight within day by lagged Size? Size is same-day market cap; for index proxy use t-1 weights.
# Build prev-day Size weight per ticker to avoid same-day weighting circularity.
df = df.sort_values(["Ticker","Date"])
df["Size_lag"] = df.groupby("Ticker")["Size"].shift(1)
df = df[df["Size_lag"].notna() & (df["Size_lag"] > 0)]
def capw(g):
    w = g["Size_lag"] / g["Size_lag"].sum()
    return (w * g["Ret"]).sum()
mkt = df.groupby("Date").apply(capw)
mkt.name = "R"
mkt = mkt.sort_index()
# also EW for cross-check
ew = df.groupby("Date")["Ret"].mean(); ew.name="R_ew"
print(f"    proxy days: {len(mkt)}  range {mkt.index.min().date()}..{mkt.index.max().date()}")
print(f"    ann mean cap-w R: {mkt.mean()*252:.3%}  ann vol: {mkt.std()*np.sqrt(252):.3%}")

# ---------- 2. Macro state panel (VIX, credit) ----------
print("[2] loading macro state (VIX, HY_Spread, BBB_Spread, StL_Fin_Stress)...")
mw = pq.read_table(f"{ROOT}/.cache/fred_macro_wide.parquet",
                   columns=["Date","VIX","HY_Spread","BBB_Spread","StL_Fin_Stress","US_10Y_Yield"]).to_pandas()
mw["Date"] = pd.to_datetime(mw["Date"]); mw = mw.sort_values("Date").set_index("Date")
# align to trading days, forward-fill (macro is daily-ish but may have gaps); ffill is PIT-safe (last known)
panel = pd.DataFrame(index=mkt.index)
for c in mw.columns:
    panel[c] = mw[c].reindex(panel.index, method="ffill")
panel["R"] = mkt
# regime exposure (existing overlay output)
rg = pq.read_table(f"{ROOT}/.cache/regime_daily_v2.parquet", columns=["Date","exposure","VIX_z_smooth"]).to_pandas()
rg["Date"]=pd.to_datetime(rg["Date"]); rg=rg.sort_values("Date").set_index("Date")
panel["exposure"] = rg["exposure"].reindex(panel.index, method="ffill")
panel = panel.dropna(subset=["R"])

# ---------- 3. V-shape BrakeScore (PIT: all features shift(1)) ----------
print("[3] constructing V-shape BrakeScore (expanding-standardized, t-1 lagged)...")
def expanding_z(s, minp=252):
    mu = s.expanding(min_periods=minp).mean()
    sd = s.expanding(min_periods=minp).std()
    return ((s - mu) / sd).clip(-5, 5)

p = panel.copy()
# VIX core: level z + spike (5d change) z
p["vix_lvl_z"]   = expanding_z(p["VIX"])
p["vix_spike"]   = p["VIX"] - p["VIX"].rolling(5).mean()
p["vix_spike_z"] = expanding_z(p["vix_spike"])
a_vix = 0.5
p["VIXCore"] = a_vix*p["vix_lvl_z"] + (1-a_vix)*p["vix_spike_z"]
# credit panic: HY spread level z + 21d change z (use BBB if HY missing early)
hy = p["HY_Spread"].fillna(p["BBB_Spread"])
p["credit_z"]    = expanding_z(hy)
p["credit_chg"]  = hy - hy.shift(21)
p["credit_chg_z"]= expanding_z(p["credit_chg"])
p["CreditPanic"] = 0.5*p["credit_z"] + 0.5*p["credit_chg_z"]
# rate panic (rate spike): 21d change in 10Y
p["rate_chg"]    = p["US_10Y_Yield"] - p["US_10Y_Yield"].shift(21)
p["RatePanic"]   = expanding_z(p["rate_chg"]).clip(lower=0)  # only upside rate shocks
# drawdown of R (own sleeve) — running peak, lagged
nav = (1+p["R"].fillna(0)).cumprod()
p["dd"] = nav/nav.cummax() - 1.0   # <=0
p["dd_depth"] = (-p["dd"]).clip(0, 1)   # positive depth
# 10d crash loss
p["crash10"] = (-(nav/nav.shift(10)-1)).clip(lower=0)

lam_r, lam_c, lam_dd, lam_crash = 0.5, 0.7, 1.5, 3.0
p["BrakeScore_raw"] = (p["VIXCore"]
                       + lam_r*p["RatePanic"]
                       + lam_c*p["CreditPanic"].clip(lower=0)
                       + lam_dd*expanding_z(p["dd_depth"]).clip(lower=0)
                       + lam_crash*expanding_z(p["crash10"]).clip(lower=0))
# CRITICAL PIT: shift signal by 1 day -> decide today's weight from yesterday's info
p["BrakeScore"] = p["BrakeScore_raw"].shift(1)

# map BrakeScore -> cash weight via softplus-ish squashing into [0, maxcash]
MAXCASH = 1.0
THRESH  = 1.0   # brake activates above ~1 sd composite stress
def brake_to_cash(b, thresh=THRESH, slope=0.8, maxc=MAXCASH):
    x = (b - thresh)
    w = 1.0/(1.0+np.exp(-slope*x))   # logistic
    # zero out below threshold region softly
    w = np.where(b < thresh*0.5, 0.0, w)
    return np.clip(w, 0, maxc)
p["w_cash_brake"] = brake_to_cash(p["BrakeScore"])
p["w_cash_brake"] = p["w_cash_brake"].fillna(0.0)
p["wR_brake"] = 1.0 - p["w_cash_brake"]

# existing overlay exposure (already an OUT signal in [0,1]); lag 1 for fair PIT
p["wR_exposure"] = p["exposure"].shift(1).fillna(1.0).clip(0,1)
# combined (max-cash analogue but min-exposure = take MORE protective): w = min(brake, exposure)
p["wR_combo"] = np.minimum(p["wR_brake"], p["wR_exposure"])

# ---------- 4. Strategy returns (cash leg = 0 for conservatism; KR call rate small) ----------
# net of cost on |delta wR|*COST. Cash earns ~0 (no risk-free series merged; conservative => understates cash benefit)
def strat_ret(wR, R):
    wR = wR.ffill().fillna(1.0)
    gross = wR * R
    dcost = wR.diff().abs().fillna(0.0) * COST_BPS
    return gross - dcost

p["ret_bh"]    = p["R"]                       # buy & hold risky proxy
p["ret_brake"] = strat_ret(p["wR_brake"], p["R"])
p["ret_expo"]  = strat_ret(p["wR_exposure"], p["R"])
p["ret_combo"] = strat_ret(p["wR_combo"], p["R"])

# ---------- 5. Metrics (standard only) ----------
def metrics(r):
    r = r.dropna()
    n = len(r)
    ann = r.mean()*252
    vol = r.std()*np.sqrt(252)
    shp = ann/vol if vol>0 else np.nan
    nav = (1+r).cumprod()
    cagr = nav.iloc[-1]**(252/n) - 1
    mdd  = (nav/nav.cummax()-1).min()
    calmar = cagr/abs(mdd) if mdd<0 else np.nan
    # downside (Sortino)
    dn = r[r<0].std()*np.sqrt(252)
    sortino = ann/dn if dn>0 else np.nan
    return dict(n=n, Sharpe=shp, Sortino=sortino, CAGR=cagr, MDD=mdd, Calmar=calmar, AvgCash=np.nan)

def report(window_name, mask):
    sub = p.loc[mask]
    print(f"\n===== WINDOW: {window_name}  ({sub.index.min().date()}..{sub.index.max().date()}, {mask.sum()}d) =====")
    rows = []
    for nm, col, wcol in [("Buy&Hold R","ret_bh",None),
                          ("V-shape brake","ret_brake","wR_brake"),
                          ("Existing exposure","ret_expo","wR_exposure"),
                          ("min(brake,exposure)","ret_combo","wR_combo")]:
        m = metrics(sub[col])
        if wcol: m["AvgCash"] = float((1-sub[wcol].reindex(sub.index)).clip(0,1).mean())
        m["strategy"]=nm
        rows.append(m)
    rep = pd.DataFrame(rows).set_index("strategy")[["n","Sharpe","Sortino","CAGR","MDD","Calmar","AvgCash"]]
    with pd.option_context('display.float_format', lambda x: f"{x:,.4f}"):
        print(rep.to_string())
    return rep

# active turnover diag
print(f"\n[brake activity] days w_cash_brake>0.1: {(p['w_cash_brake']>0.1).sum()}  "
      f">0.5: {(p['w_cash_brake']>0.5).sum()}  mean cash: {p['w_cash_brake'].mean():.3f}")

full   = (p.index <= pd.Timestamp("2025-12-31"))
safe   = (p.index <= pd.Timestamp("2025-09-30"))
incl26 = (p.index <= pd.Timestamp("2026-06-30"))
r1 = report("FULL ex-2026 (<=2025-12)", full)
r2 = report("BM-SAFE (<=2025-09)", safe)
r3 = report("INCL-2026 (proxy self-built, 2026 OK)", incl26)

# crisis-window MDD check: did brake reduce drawdown in 2008 / 2020 / 2022?
print("\n===== crisis sub-window MDD (buy&hold vs brake vs combo) =====")
for lab,a,b in [("2008 GFC","2008-01-01","2009-06-30"),
                ("2020 COVID","2020-01-01","2020-12-31"),
                ("2022 bear","2022-01-01","2022-12-31"),
                ("2025-2026 (BM-corrupt tail)","2025-01-01","2026-06-30")]:
    m=(p.index>=pd.Timestamp(a))&(p.index<=pd.Timestamp(b))
    if m.sum()<20: continue
    for col in ["ret_bh","ret_brake","ret_combo"]:
        nav=(1+p.loc[m,col]).cumprod(); dd=(nav/nav.cummax()-1).min()
        print(f"  {lab:28s} {col:11s} MDD={dd:.3%}")

print("\nDONE.")
