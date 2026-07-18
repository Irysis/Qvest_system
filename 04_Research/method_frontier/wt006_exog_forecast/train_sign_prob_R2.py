# WT-006 R2 sign_prob lane — classify P(fwd_ret > that-month 6-family MEDIAN), calibrated GBM.
# theta ∝ calibrated probability (normalized to sum=1 per date).
# Walk-forward expanding, annual refit (~14x), IS-only, family categorical, full exog + momentum features.
# PIT: at decision time t, train on rows date<t with REALIZED fwd_ret (fwd_ret(t-1)=month-t return, known end of month t).
#      Predict theta(t) from features observable end-of-month t -> holds month t+1 (=target fwd_ret(t)).
# Trees handle NA natively; drop only ~86% empty cols. No self-synthesis (probabilities only).
import os, json, numpy as np, pandas as pd
import lightgbm as lgb
from sklearn.calibration import CalibratedClassifierCV

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  = os.path.join(ROOT, "04_Research/method_frontier/wt006_exog_forecast")
W5   = os.path.join(ROOT, "04_Research/method_frontier/wt005_factor_timing")
fams = ["value","quality","momentum","low_vol","size","dividend"]

X = pd.read_parquet(os.path.join(OUT,"wt006_candidate_features.parquet"))
X["date"] = pd.to_datetime(X["date"])

# feature set = full exog + momentum (drop >30% NA cols: BBB_Spread/HY_Spread/HY_Spread_chg3 ~86%)
drop_hi_na = [c for c in X.columns if c not in ("date","family","fwd_ret") and X[c].isna().mean() > 0.30]
feat_base = [c for c in X.columns if c not in ("date","family","fwd_ret")+tuple(drop_hi_na)]
print("dropped high-NA:", drop_hi_na)
print("features (%d):"%len(feat_base), feat_base)

# target: above cross-sectional (6-family) median that month
X = X.sort_values(["date","family"]).reset_index(drop=True)
X["med"] = X.groupby("date")["fwd_ret"].transform("median")
X["y"]   = (X["fwd_ret"] > X["med"]).astype(int)
X["family_code"] = X["family"].astype("category").cat.set_categories(fams).cat.codes
feat_cols = feat_base + ["family_code"]

oos_dates = pd.to_datetime(pd.read_parquet(os.path.join(W5,"theta_transformer_ensemble.parquet"))["date"]).sort_values().unique()
oos_dates = pd.DatetimeIndex(oos_dates)
print("OOS:", oos_dates.min().date(), "..", oos_dates.max().date(), "n=", len(oos_dates))

def lgb_params(seed):
    return dict(objective="binary", n_estimators=150, learning_rate=0.03,
                num_leaves=7, min_child_samples=40, subsample=0.7, subsample_freq=1,
                colsample_bytree=0.7, reg_lambda=5.0, reg_alpha=0.5, max_depth=3,
                random_state=seed, n_jobs=1, verbose=-1)

def run_seed(seed, refit_every=12):
    rng_anchor=None; model=None; n_ref=0; rows=[]
    for t in oos_dates:
        need = (model is None) or (rng_anchor is None) or ((t-rng_anchor).days/30.4 >= refit_every)
        tr = X[X["date"] < t].dropna(subset=["fwd_ret"])
        tr = tr[tr[feat_base].notna().any(axis=1)]
        if len(tr) < 60: continue
        if need:
            base = lgb.LGBMClassifier(**lgb_params(seed))
            # calibrate on training only (sigmoid, 3-fold internal) -> calibrated P(above median)
            m = CalibratedClassifierCV(base, method="sigmoid", cv=3)
            m.fit(tr[feat_cols], tr["y"])
            model=m; rng_anchor=t; n_ref+=1
        te = X[X["date"]==t]
        if len(te)==0: continue
        ph = model.predict_proba(te[feat_cols])[:,1]
        for fam,p in zip(te["family"].values, ph): rows.append((t,fam,float(p)))
    return pd.DataFrame(rows, columns=["date","family","p"]), n_ref

def prob_to_theta(P):
    # theta ∝ calibrated probability, normalized per date (all p>0)
    out=[]
    for d,g in P.groupby("date"):
        p=np.clip(g["p"].values,1e-6,None); w=p/p.sum()
        for fam,wi in zip(g["family"].values,w): out.append((d,fam,wi))
    return pd.DataFrame(out, columns=["date","family","theta"])

seeds=[0,1,2]; probs=[]; nref=0
for s in seeds:
    P,nr=run_seed(s); nref=nr
    prob_to_theta(P).to_parquet(os.path.join(OUT,f"theta_R2_sign_prob_seed{s}.parquet"), index=False)
    probs.append(P.rename(columns={"p":f"p{s}"}).set_index(["date","family"]))
    print(f"[sign_prob seed{s}] refits={nr} oos_mo={P['date'].nunique()}")

M=pd.concat(probs,axis=1); M["p"]=M[[f"p{s}" for s in seeds]].mean(axis=1)
Pens=M.reset_index()[["date","family","p"]]
th=prob_to_theta(Pens)
th.to_parquet(os.path.join(OUT,"theta_R2_sign_prob.parquet"), index=False)
# diagnostic: how spread are the probs / weights
wt=th.groupby("date")["theta"]
print("[ensemble] theta min/mean/max per-date avg:",
      round(wt.min().mean(),3), round(wt.mean().mean(),3), round(wt.max().mean(),3))
print("[sign_prob done] saved theta_R2_sign_prob.parquet  refits/seed=",nref)
