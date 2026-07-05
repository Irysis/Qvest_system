#!/usr/bin/env python
# diagnose.py -- heterogeneity test: is post-2017 decay heterogeneous across names?
# If high-confidence (low predictive variance) names retain predictability while low-confidence do not,
# then confidence-gating can concentrate on the predictable subset -> oos lever plausible.
# If accuracy is flat across confidence buckets -> decay is uniform -> lever dead (honest null).
import os, json, sys
import numpy as np, pandas as pd
import pyarrow.parquet as pq
from scipy.stats import spearmanr

OUT="C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/beat_pg2_uncertainty_20260705"
P=pq.read_table(os.path.join(OUT,"uncertainty_scores.parquet")).to_pandas()
P["year"]=P["sig_ym"].str[:4].astype(int)

def month_metrics(df):
    # per-month: rank-IC of pred_mean vs realized ret_fwd; directional hit (sign agreement vs cross-sec median)
    out=[]
    for sig,g in df.groupby("sig_ym"):
        if len(g)<20: continue
        ic=spearmanr(g["pred_mean"],g["ret_fwd"]).correlation
        # hit: does top-half by pred_mean outperform bottom-half realized?
        med=g["pred_mean"].median()
        top=g.loc[g["pred_mean"]>=med,"ret_fwd"].mean()
        bot=g.loc[g["pred_mean"]<med,"ret_fwd"].mean()
        out.append((sig,ic,top-bot,len(g)))
    return pd.DataFrame(out,columns=["sig_ym","ic","ls_spread","n"])

def conf_bucket_accuracy(df,label):
    # within each month, split names into confidence terciles; measure realized predictability per tercile.
    res={}
    for q,name in [((0.0,0.33),"low_conf"),((0.33,0.66),"mid_conf"),((0.66,1.01),"high_conf")]:
        rows=[]
        for sig,g in df.groupby("sig_ym"):
            if len(g)<30: continue
            sub=g[(g["conf_pct"]>=q[0])&(g["conf_pct"]<q[1])]
            if len(sub)<8: continue
            ic=spearmanr(sub["pred_mean"],sub["ret_fwd"]).correlation
            # directional accuracy of the SIGN of pred_mean vs sign of demeaned realized
            rd=sub["ret_fwd"]-g["ret_fwd"].mean()
            hit=np.mean(np.sign(sub["pred_mean"]-sub["pred_mean"].mean())==np.sign(rd))
            rows.append((ic,hit))
        r=pd.DataFrame(rows,columns=["ic","hit"])
        res[name]={"mean_ic":float(r["ic"].mean()),"mean_hit":float(r["hit"].mean()),"n_months":int(len(r))}
    return res

diag={}
for lab,mask in [("full",P["year"]>=2010),("pre2017",(P["year"]>=2010)&(P["year"]<2017)),("post2017",P["year"]>=2017)]:
    d=P[mask]
    mm=month_metrics(d)
    diag[lab]={
      "mean_monthly_ic":float(mm["ic"].mean()),
      "ic_t":float(mm["ic"].mean()/ (mm["ic"].std()/np.sqrt(len(mm)))) if len(mm)>1 else None,
      "mean_ls_spread":float(mm["ls_spread"].mean()),
      "n_months":int(len(mm)),
      "conf_buckets":conf_bucket_accuracy(d,lab),
    }

# KEY heterogeneity statistic: in post2017, high_conf mean_ic minus low_conf mean_ic.
post=diag["post2017"]["conf_buckets"]
het_ic_gap=post["high_conf"]["mean_ic"]-post["low_conf"]["mean_ic"]
het_hit_gap=post["high_conf"]["mean_hit"]-post["low_conf"]["mean_hit"]

# Also: does confidence predict per-name realized accuracy directly (post2017)?
# per name pooled: correlation between conf_pct and |pred error|^-1 proxy -> use monthly regression of squared error on conf.
d17=P[P["year"]>=2017].copy()
d17["sq_err"]=(d17["ret_fwd"]-d17["pred_mean"])**2
# demean sq_err within month, regress on conf_pct within month, average slope
slopes=[]
for sig,g in d17.groupby("sig_ym"):
    if len(g)<30: continue
    x=g["conf_pct"].values; y=g["sq_err"].values
    x=x-x.mean(); y=y-y.mean()
    if x.std()==0: continue
    slopes.append(np.sum(x*y)/np.sum(x*x))
conf_err_slope=float(np.mean(slopes))  # negative => higher confidence -> lower realized error (informative)

diag["heterogeneity"]={
  "post2017_high_minus_low_conf_ic": float(het_ic_gap),
  "post2017_high_minus_low_conf_hit": float(het_hit_gap),
  "post2017_conf_vs_sqerr_slope": conf_err_slope,
  "interpretation_rule":"het_ic_gap>0.02 AND conf_err_slope<0 => heterogeneous(confidence informative); else uniform",
  "verdict":"HETEROGENEOUS" if (het_ic_gap>0.02 and conf_err_slope<0) else "UNIFORM_OR_WEAK",
}
diag["_meta"]={"n_total":int(len(P)),"sig_range":[P['sig_ym'].min(),P['sig_ym'].max()]}
with open(os.path.join(OUT,"unc_diag.json"),"w") as f:
    json.dump(diag,f,indent=2)
print(json.dumps(diag["heterogeneity"],indent=2))
print("post2017 conf buckets:",json.dumps(post,indent=2))
print("full/pre/post monthly IC:",{k:round(diag[k]["mean_monthly_ic"],4) for k in ["full","pre2017","post2017"]})
