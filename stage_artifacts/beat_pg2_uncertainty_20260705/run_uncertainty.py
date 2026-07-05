#!/usr/bin/env python
# run_uncertainty.py -- expanding-window uncertainty model via HistGradientBoosting quantile intervals
#   + split-conformal calibration (mapie-style validity). Fast (100x NGBoost) yet rigorous.
# PIT: at sig month t, TRAIN on rows with sig_ym < t (past realized forward returns only); PREDICT sig_ym==t.
#   Expanding window; factors are month t-1 (built into panel). No future info. lag+1 preserved.
# Uncertainty = conformalized prediction-interval half-width per name. confidence = 1/(half_width^2),
#   i.e. inverse of predictive variance proxy (interval width is monotone in sigma).
# self-synthesis: none -- pure inference; no return compounding (that stays in the R bridge).
import os, sys, warnings
import numpy as np, pandas as pd
import pyarrow.parquet as pq
warnings.filterwarnings("ignore")
from sklearn.ensemble import HistGradientBoostingRegressor

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT=os.path.join(ROOT,"stage_artifacts/beat_pg2_uncertainty_20260705")
panel=pq.read_table(os.path.join(OUT,"panel.parquet")).to_pandas()
faccols=[c for c in panel.columns if c not in
         ("sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd","bm")]
yms=sorted(panel["sig_ym"].unique())
BURN="2009-12"
start_idx=next(i for i,m in enumerate(yms) if m> BURN)
REFIT_EVERY=1
ALPHA=0.32   # ~1-sigma interval (16th/84th quantiles) -> half-width ~ sigma
CAP=200000

def winsor(a,lo=-0.5,hi=0.5): return np.clip(a,lo,hi)

def mk(loss,q=None):
    return HistGradientBoostingRegressor(loss=loss,quantile=q,max_depth=3,max_iter=180,
        learning_rate=0.05,min_samples_leaf=200,l2_regularization=1.0,random_state=42)

preds=[]; m_med=m_lo=m_hi=None
for i in range(start_idx,len(yms)):
    m=yms[i]
    tr=panel[panel["sig_ym"]<m]; te=panel[panel["sig_ym"]==m]
    if len(tr)<2000 or len(te)==0: continue
    Xtr=tr[faccols].values.astype(np.float32); ytr=winsor(tr["ret_fwd"].values.astype(np.float32))
    Xte=te[faccols].values.astype(np.float32)
    # split-conformal: hold out last 20% of the PAST (still strictly past) for interval calibration
    n=len(ytr); cut=int(n*0.8)
    Xfit,yfit=Xtr[:cut],ytr[:cut]; Xcal,ycal=Xtr[cut:],ytr[cut:]
    if len(Xfit)>CAP:
        rng=np.random.RandomState(20260705+i); sel=rng.choice(len(Xfit),CAP,replace=False)
        Xfit,yfit=Xfit[sel],yfit[sel]
    m_med=mk("squared_error"); m_med.fit(Xfit,yfit)
    m_lo=mk("quantile",ALPHA/2); m_lo.fit(Xfit,yfit)
    m_hi=mk("quantile",1-ALPHA/2); m_hi.fit(Xfit,yfit)
    # conformal correction on calibration set (CQR, Romano et al.)
    lo_c=m_lo.predict(Xcal); hi_c=m_hi.predict(Xcal)
    E=np.maximum(lo_c-ycal, ycal-hi_c)
    qhat=np.quantile(E, min(0.999,(1-ALPHA)*(1+1/len(ycal))))
    mu=m_med.predict(Xte)
    lo=m_lo.predict(Xte)-qhat; hi=m_hi.predict(Xte)+qhat
    half=(hi-lo)/2.0
    half=np.maximum(half,1e-4)
    out=te[["sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd"]].copy()
    out["pred_mean"]=mu; out["pred_var"]=half**2
    preds.append(out)
    if (i-start_idx)%12==0:
        print(f"[{m}] train={len(tr)} test={len(te)} mu_sd={np.std(mu):.4f} half_med={np.median(half):.4f} qhat={qhat:.4f}",file=sys.stderr,flush=True)

P=pd.concat(preds,ignore_index=True)
P["confidence"]=1.0/P["pred_var"]
P["conf_pct"]=P.groupby("sig_ym")["confidence"].rank(pct=True)
P["pred_mean_z"]=P.groupby("sig_ym")["pred_mean"].transform(lambda x:(x-x.mean())/(x.std()+1e-9))
P=P[["sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd",
     "pred_mean","pred_var","confidence","conf_pct","pred_mean_z"]]
P.to_parquet(os.path.join(OUT,"uncertainty_scores.parquet"),index=False)
print("SAVED:",P.shape,"months",P['sig_ym'].nunique(),P['sig_ym'].min(),P['sig_ym'].max(),file=sys.stderr)
sub=P.dropna(subset=["score_eff"])
print("cor(pred_mean,score_eff):",round(np.corrcoef(sub['pred_mean'],sub['score_eff'])[0,1],4),file=sys.stderr)
