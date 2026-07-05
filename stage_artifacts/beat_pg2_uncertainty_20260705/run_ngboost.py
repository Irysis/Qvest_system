#!/usr/bin/env python
# run_ngboost.py -- expanding-window NGBoost (Normal) forward-1M return model with per-name uncertainty.
# PIT: at each sig month t, TRAIN on all rows with sig_ym < t (strictly past forward returns already realized),
#      PREDICT rows at sig_ym == t. Expanding window. Factor features are from month t-1 (built into panel).
#      => no future information enters training or prediction. lag+1 preserved (factors are t-1).
# Output per (sig, ticker): pred_mean, pred_var (NGBoost Normal scale^2), confidence=1/pred_var.
# self-synthesis: none -- pure model inference, no return compounding here (that stays in R bridge).
import os, sys, json, warnings
import numpy as np, pandas as pd
import pyarrow.parquet as pq
warnings.filterwarnings("ignore")
from ngboost import NGBRegressor
from ngboost.distns import Normal
from sklearn.tree import DecisionTreeRegressor

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT=os.path.join(ROOT,"stage_artifacts/beat_pg2_uncertainty_20260705")
panel=pq.read_table(os.path.join(OUT,"panel.parquet")).to_pandas()
faccols=[c for c in panel.columns if c not in
         ("sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd","bm")]
yms=sorted(panel["sig_ym"].unique())
BURN="2009-12"   # first prediction month = first ym > burn-in (>=5yr history)
start_idx=next(i for i,m in enumerate(yms) if m> BURN)
REFIT_EVERY=1    # refit each month (expanding). Model is cheap enough with capped trees.

def winsor(a,lo=-0.5,hi=0.5):  # cap extreme forward returns for stable NLL fit (does not touch sign/rank)
    return np.clip(a,lo,hi)

base_learner=DecisionTreeRegressor(criterion="friedman_mse",max_depth=3,min_samples_leaf=200)
preds=[]
model=None
for i in range(start_idx,len(yms)):
    m=yms[i]
    tr=panel[panel["sig_ym"]<m]
    te=panel[panel["sig_ym"]==m]
    if len(tr)<2000 or len(te)==0:
        continue
    Xtr=tr[faccols].values.astype(np.float64); ytr=winsor(tr["ret_fwd"].values.astype(np.float64))
    Xte=te[faccols].values.astype(np.float64)
    if (i==start_idx) or ((i-start_idx)%REFIT_EVERY==0):
        model=NGBRegressor(Dist=Normal,Base=base_learner,n_estimators=200,learning_rate=0.02,
                           minibatch_frac=0.5,natural_gradient=True,verbose=False,random_state=42)
        model.fit(Xtr,ytr)
    dist=model.pred_dist(Xte)
    mu=dist.loc; sigma=dist.scale
    var=sigma**2
    out=te[["sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd"]].copy()
    out["pred_mean"]=mu
    out["pred_var"]=var
    preds.append(out)
    if (i-start_idx)%12==0:
        print(f"[{m}] train={len(tr)} test={len(te)} mu_sd={np.std(mu):.4f} var_med={np.median(var):.5f}",file=sys.stderr)

P=pd.concat(preds,ignore_index=True)
# confidence = inverse predictive variance, cross-sectionally standardized per month for comparability
P["confidence"]=1.0/P["pred_var"]
# cross-sectional rank of confidence within each sig (0..1), robust for sleeve construction
P["conf_pct"]=P.groupby("sig_ym")["confidence"].rank(pct=True)
P["pred_mean_z"]=P.groupby("sig_ym")["pred_mean"].transform(lambda x:(x-x.mean())/(x.std()+1e-9))
P=P[["sig","sig_ym","ym","Ticker","regime_state","score_eff","ret_fwd",
     "pred_mean","pred_var","confidence","conf_pct","pred_mean_z"]]
P.to_parquet(os.path.join(OUT,"uncertainty_scores.parquet"),index=False)
print("SAVED uncertainty_scores:",P.shape,"months",P['sig_ym'].nunique(),P['sig_ym'].min(),P['sig_ym'].max(),file=sys.stderr)
# correlation: pred_mean vs score_eff (should be positively related if model recovers base signal)
sub=P.dropna(subset=["score_eff"])
print("cor(pred_mean, score_eff) pooled:",round(np.corrcoef(sub['pred_mean'],sub['score_eff'])[0,1],4),file=sys.stderr)
