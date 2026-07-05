#!/usr/bin/env python
# make_sleeves.py -- build confidence-based sleeve caches in eval_lag1.R format (Date,Ticker,score).
# The eval_lag1.R harness blends a sleeve z-score into BASE(score_eff) and tests book-marginal dIR/paired-t/oos_v2.
# Sleeve Date must be the sig-date (first-of-month) so that after harness lag+1 shift the sleeve enters the
# BASE month strictly from a prior signal (PIT-clean). uncertainty_scores.sig is already the sig-date.
#
# Variants (each a hypothesis for the oos lever):
#   UNCms   : pred_mean_z gated by confidence percentile (down-weight low-conf names). score = pred_mean_z * conf_pct
#   UNCgate : score_eff proxy replaced by BASE later; here sleeve = sign of pred_mean where high-conf, else 0
#             implemented as conf_pct itself (a pure "trust weight" the blend can tilt toward predictable names)
#   UNCmean : raw pred_mean_z (no gating) -- control: does the ML mean alone add over score_eff?
#   CONFONLY: confidence percentile as a standalone tilt (predictability weight, no direction)
import os
import numpy as np, pandas as pd
import pyarrow.parquet as pq

OUT="C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/beat_pg2_uncertainty_20260705"
SC="C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
P=pq.read_table(os.path.join(OUT,"uncertainty_scores.parquet")).to_pandas()
P["Date"]=pd.to_datetime(P["sig"])

def save(df,code):
    d=df[["Date","Ticker","score"]].dropna(subset=["score"]).copy()
    d.to_parquet(os.path.join(SC,f"cache_{code}.parquet"),index=False)
    print(f"cache_{code}: {len(d)} rows, dates {d['Date'].min().date()}..{d['Date'].max().date()}")

# UNCms: confidence-gated predicted mean. conf_pct in [0,1]; center to [-.5,.5] emphasis then multiply.
P["score"]=P["pred_mean_z"]*P["conf_pct"]; save(P,"UNCms")
# UNCmean: raw predicted-mean z (control)
P["score"]=P["pred_mean_z"]; save(P,"UNCmean")
# CONFONLY: pure predictability/trust weight
P["score"]=P["conf_pct"]; save(P,"CONFONLY")
# UNCsharp: sharper gating -- only top-confidence names carry the mean signal (quadratic conf)
P["score"]=P["pred_mean_z"]*(P["conf_pct"]**2); save(P,"UNCsharp")
print("DONE sleeves")
