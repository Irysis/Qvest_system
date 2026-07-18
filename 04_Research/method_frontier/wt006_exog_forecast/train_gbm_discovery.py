# WT-D20260718_006 — GBM (lightgbm) direct E[r_factor,t+1] forecasting for interaction discovery.
# Walk-forward expanding refit(12mo), family as categorical (native interaction discovery),
# regularized (shallow, min_child, L2). 3 seeds -> ensemble. Gain importance = ML combo discovery.
# TRAIN-ONLY: model fit on months < t. No standardization needed (trees). IS-only.
import os, json, numpy as np, pandas as pd
import lightgbm as lgb
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  = os.path.join(ROOT, "04_Research/method_frontier/wt006_exog_forecast")
W5   = os.path.join(ROOT, "04_Research/method_frontier/wt005_factor_timing")
fams = ["value","quality","momentum","low_vol","size","dividend"]

X = pd.read_parquet(os.path.join(OUT,"wt006_candidate_features.parquet"))
X["date"] = pd.to_datetime(X["date"])
logic_map = json.load(open(os.path.join(OUT,"logic_map.json")))
allf = [f for L in logic_map.values() for f in L]
allf = [f for f in dict.fromkeys(allf) if f in X.columns and X[f].isna().mean() <= 0.30]
print("GBM features (%d):" % len(allf), allf)

oos_dates = pd.to_datetime(pd.read_parquet(os.path.join(W5,"theta_transformer_ensemble.parquet"))["date"]).sort_values().unique()
oos_dates = pd.DatetimeIndex(oos_dates)
print("OOS:", oos_dates.min().date(), "..", oos_dates.max().date(), "n=", len(oos_dates))

X = X.sort_values(["family","date"]).reset_index(drop=True)
X["family_code"] = X["family"].astype("category").cat.set_categories(fams).cat.codes
feat_cols = allf + ["family_code"]

def lgb_params(seed):
    return dict(objective="regression", n_estimators=120, learning_rate=0.03,
                num_leaves=7, min_child_samples=40, subsample=0.7, subsample_freq=1,
                colsample_bytree=0.7, reg_lambda=5.0, reg_alpha=0.5, max_depth=3,
                random_state=seed, n_jobs=1, verbose=-1)

def run_seed(seed, refit_every=12):
    rng_anchor = None; model=None; gains=np.zeros(len(feat_cols)); n_ref=0
    rows=[]
    for t in oos_dates:
        need_refit = (model is None) or (rng_anchor is None) or ((t - rng_anchor).days/30.4 >= refit_every)
        tr = X[X["date"] < t].dropna(subset=["fwd_ret"])
        tr = tr[tr[allf].notna().any(axis=1)]
        if len(tr) < 60: continue
        if need_refit:
            m = lgb.LGBMRegressor(**lgb_params(seed))
            m.fit(tr[feat_cols], tr["fwd_ret"], categorical_feature=["family_code"])
            model = m; rng_anchor = t; n_ref += 1
            gains += np.array(m.booster_.feature_importance(importance_type="gain"))
        te = X[X["date"] == t]
        if len(te)==0: continue
        ph = model.predict(te[feat_cols])
        for fam, p in zip(te["family"].values, ph):
            rows.append((t, fam, float(p)))
    P = pd.DataFrame(rows, columns=["date","family","pred"])
    return P, n_ref, gains

def pred_to_theta(P, beta=2.0):
    out=[]
    for d, g in P.groupby("date"):
        pr = g["pred"].values; z = (pr - pr.mean())/(pr.std()+1e-9)
        w = np.exp(beta*z); w = w/w.sum()
        for fam, wi in zip(g["family"].values, w): out.append((d, fam, wi))
    return pd.DataFrame(out, columns=["date","family","theta"])

seeds=[0,1,2]; preds=[]; gains_tot=np.zeros(len(feat_cols)); nref=0
for s in seeds:
    P, nr, g = run_seed(s); nref=nr; gains_tot+=g
    th = pred_to_theta(P)
    th.to_parquet(os.path.join(OUT, f"theta_GBM_seed{s}.parquet"), index=False)
    preds.append(P.rename(columns={"pred":f"pred{s}"}).set_index(["date","family"]))
    print(f"[GBM seed{s}] refits={nr} oos_mo={P['date'].nunique()}")

M = pd.concat(preds, axis=1)
M["pred"] = M[[f"pred{s}" for s in seeds]].mean(axis=1)
Pens = M.reset_index()[["date","family","pred"]]
pred_to_theta(Pens).to_parquet(os.path.join(OUT,"theta_GBM_ensemble.parquet"), index=False)

gi = sorted(zip(feat_cols, (gains_tot/max(nref*len(seeds),1)).tolist()), key=lambda x:-x[1])
json.dump({"refits_per_seed":nref, "seeds":seeds,
           "gain_importance":[{"feature":f,"gain":round(v,1)} for f,v in gi]},
          open(os.path.join(OUT,"gbm_gain_importance.json"),"w"), indent=2)
print("[GBM done] top gain:", [f for f,_ in gi[:8]])
