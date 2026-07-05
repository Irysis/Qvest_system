#!/usr/bin/env python
# build_uncertainty.py -- PIT expanding-window uncertainty model for forward-1M return.
# Outputs per (sig_date, ticker): pred_mean, pred_var, confidence(=1/pred_var).
# PIT: at sig_date t, training uses only rows whose forward-return window CLOSED strictly
#      before t. Ret_1m at Date d covers (d, d+1M]; realized at d+1M. To predict at t we
#      train on rows with Date <= t - 2 months (their forward window closes by t-1 < t).
# Self-synthesis: none. This produces only confidence scores; portfolio recon/oos done in R.
import os, json, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np, pandas as pd
from dateutil.relativedelta import relativedelta

BASE="C:/Users/99922/OneDrive/Quant_Module_Moltbot/"
OUT=BASE+"stage_artifacts/beat_pg2_uncertainty_20260705/"
os.makedirs(OUT, exist_ok=True)

from ngboost import NGBRegressor
from ngboost.distns import Normal
from sklearn.tree import DecisionTreeRegressor

# ---- load base panel (PIT-built, C13-aligned scores + forward Ret_1m) ----
df=pd.read_parquet(BASE+"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
df['Date']=pd.to_datetime(df['Date'])
FEATS=['score_core_z','score_defense_z','score_eff']
# regime one-hot (regime_state is t-1 macro label already, PIT-safe as used in base)
reg_dum=pd.get_dummies(df['regime_state'],prefix='rg')
REG_COLS=list(reg_dum.columns)
df=pd.concat([df,reg_dum],axis=1)
ALLF=FEATS+REG_COLS
df=df.dropna(subset=FEATS)  # need feature completeness
# training rows also need a realized target
df['has_y']=df['Ret_1m'].notna()

dates=sorted(df['Date'].unique())
# minimum history before first prediction
MIN_TRAIN_MONTHS=48   # 4y warmup
REFIT_EVERY=3         # refit model every 3 months (expanding); reuse between

def winsor(a, lo=0.01, hi=0.99):
    ql,qh=np.nanquantile(a,lo),np.nanquantile(a,hi)
    return np.clip(a,ql,qh)

rows=[]
model=None
last_fit_idx=-999
n_dates=len(dates)
for i,t in enumerate(dates):
    t=pd.Timestamp(t)
    # PIT cutoff: training forward window must close < t  => Date <= t - 2 months
    cutoff=t - relativedelta(months=2)
    tr=df[(df['Date']<=cutoff) & (df['has_y'])]
    n_train_months=tr['Date'].nunique()
    cur=df[df['Date']==t]
    if len(cur)==0: continue
    if n_train_months < MIN_TRAIN_MONTHS or len(tr) < 2000:
        continue  # not enough history yet -> no confidence emitted (skip early period)
    Xtr=tr[ALLF].astype(float).values
    ytr=winsor(tr['Ret_1m'].astype(float).values)
    # refit on schedule (expanding window each refit)
    if (i - last_fit_idx) >= REFIT_EVERY or model is None:
        learner=DecisionTreeRegressor(criterion='squared_error',max_depth=4,min_samples_leaf=200)
        model=NGBRegressor(Dist=Normal, Base=learner, n_estimators=300,
                           learning_rate=0.02, natural_gradient=True,
                           minibatch_frac=0.6, col_sample=0.8, verbose=False,
                           random_state=42)
        model.fit(Xtr,ytr)
        last_fit_idx=i
    Xcur=cur[ALLF].astype(float).values
    dist=model.pred_dist(Xcur)
    mu=dist.loc            # predicted mean
    sd=dist.scale          # predicted std
    var=sd**2
    sub=pd.DataFrame({'Date':t,'Ticker':cur['Ticker'].values,
                      'pred_mean':mu,'pred_var':var,
                      'score_eff':cur['score_eff'].values,
                      'Ret_1m':cur['Ret_1m'].values,
                      'regime_state':cur['regime_state'].values})
    rows.append(sub)
    if i % 20 == 0:
        with open(OUT+"progress.txt","a") as pf:
            pf.write(f"[{i}/{n_dates}] {t.date()} train_m={n_train_months} n_cur={len(cur)} "
                     f"mu~{np.mean(mu):+.4f} sd~{np.mean(sd):.4f}\n")

res=pd.concat(rows,ignore_index=True)
# confidence = inverse predicted variance (higher = more predictable per model)
res['confidence']=1.0/res['pred_var'].clip(lower=1e-6)
res['Date']=pd.to_datetime(res['Date'])
res['sig_date']=res['Date']
out=res[['sig_date','Ticker','pred_mean','pred_var','confidence','score_eff','Ret_1m','regime_state']].copy()
out.to_parquet(OUT+"uncertainty_scores.parquet",index=False)
with open(OUT+"progress.txt","a") as pf:
    pf.write(f"DONE rows={len(out)} dates={out['sig_date'].nunique()}\n")
print("WROTE uncertainty_scores.parquet rows=",len(out),
      "dates=",out['sig_date'].nunique(),
      "range=",out['sig_date'].min().date(),out['sig_date'].max().date(),flush=True)
