#!/usr/bin/env python
# build_panel.py -- assemble wide factor panel keyed on grid sig-date, PIT-correct.
#
# PIT alignment (authoritative, from grid.rds):
#   grid element: sig (decision date, first-of-month) -> forward window realized over ym (= sig month +1),
#                 ret_fwd per Ticker = that forward return. This is the harness's own PIT forward return.
#   Decision at sig uses information through end of the PRIOR month (t-1). factor_db_YYYYMM = month-end snapshot.
#   => factor month for a given sig = (sig_month - 1). e.g. sig=2004-02-01 -> use factor_db_200401 (end of Jan).
#   This guarantees factor Z is strictly known before the forward window opens (C1/C5/C14 clean, expanding, lag+1).
#
# Target = ret_fwd (grid). Features = factor Z_Score (C13-aligned) at factor month (sig-1).
import os, glob, sys
import numpy as np, pandas as pd
import pyarrow.parquet as pq

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT=os.path.join(ROOT,"stage_artifacts/beat_pg2_uncertainty_20260705")
os.makedirs(OUT,exist_ok=True)

FACTORS=[
 "C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m","C04_ESBR","C05_ESCR","C06_TP_Gap","C07_TP_Mom","C16_EPS_Acceleration",
 "V18_AM","V19_Debt_to_Market","V20_SP","V22_FCFF_EV","V24_Residual_Income",
 "AC01_Total_Accruals_CF","AC03_WC_Accruals","AC24_NOA_Growth",
 "XF_DU01_NetMargin","XF_DU02_AssetTurnover","XF_GD01_GrossProfit_Growth","XF_GD02_OpProfit_Growth",
 "D01_IdioVol","D02_Beta","D03_RealVol","D04_Downside_Beta",
 "CR01_Sector_Comovement","CR07_Momentum_Crowding","CR09_Money_Flow_Ratio","CR11_Idiosyncratic_Return",
]

fw=pq.read_table(os.path.join(OUT,"grid_fwd.parquet")).to_pandas()
fw["sig"]=pd.to_datetime(fw["sig"])
fw=fw.dropna(subset=["ret_fwd"]).copy()
# factor month = sig month - 1
fw["fac_ym"]=(fw["sig"]-pd.offsets.MonthBegin(1)).dt.strftime("%Y-%m")
# regime from BASE (regime_state at sig Date). BASE Date == sig (first-of-month).
base=pq.read_table(os.path.join(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
                   columns=["Date","Ticker","score_eff","regime_state"]).to_pandas()
base["Date"]=pd.to_datetime(base["Date"]); base["ym"]=base["Date"].dt.strftime("%Y-%m")
reg=base.groupby("ym")["regime_state"].agg(lambda s: s.mode().iat[0] if len(s.mode()) else "NORMAL")
seff=base[["ym","Ticker","score_eff"]].rename(columns={"ym":"sig_ym"})

fw["sig_ym"]=fw["sig"].dt.strftime("%Y-%m")

files=sorted(glob.glob(os.path.join(ROOT,".cache/factor_db/factor_db_*.parquet")))
fmap={os.path.basename(f)[10:16]:f for f in files}

need_facym=sorted(fw["fac_ym"].unique())
frows=[]
for fym in need_facym:
    key=fym.replace("-","")
    f=fmap.get(key)
    if f is None: continue
    t=pq.read_table(f,columns=["Ticker","Factor_Name","Z_Score"]).to_pandas()
    t=t[t["Factor_Name"].isin(FACTORS)]
    if t.empty: continue
    w=t.pivot_table(index="Ticker",columns="Factor_Name",values="Z_Score",aggfunc="first").reset_index()
    w["fac_ym"]=fym
    frows.append(w)
fac=pd.concat(frows,ignore_index=True)
print("factor rows:",len(fac),file=sys.stderr)

panel=fw.merge(fac,on=["fac_ym","Ticker"],how="inner")
faccols=[c for c in FACTORS if c in panel.columns]
panel[faccols]=panel[faccols].fillna(0.0)
# attach score_eff (base signal at sig month) + regime
panel=panel.merge(seff,on=["sig_ym","Ticker"],how="left")
panel["regime_state"]=panel["sig_ym"].map(reg).fillna("NORMAL")
panel=panel[["sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd","bm"]+faccols].sort_values(["sig","Ticker"]).reset_index(drop=True)
panel.to_parquet(os.path.join(OUT,"panel.parquet"),index=False)

# quick IC sanity: cross-sectional corr of each factor Z with ret_fwd (pooled), to confirm no gross misalignment
ic={}
for c in faccols:
    ic[c]=np.corrcoef(panel[c],panel["ret_fwd"])[0,1]
ics=pd.Series(ic).sort_values()
print("PANEL:",panel.shape,"months:",panel['sig_ym'].nunique(),panel['sig_ym'].min(),panel['sig_ym'].max(),file=sys.stderr)
print("pooled IC (factor vs ret_fwd), extremes:",file=sys.stderr)
print(ics.head(4).to_string(),file=sys.stderr)
print(ics.tail(4).to_string(),file=sys.stderr)
print("FACCOLS="+",".join(faccols))
