# WT-006 R2 lane = rank_target.
# Cross-sectional RANK prediction: target = within-month rank of fwd_ret (6 families -> standardized rank).
# Rationale: rank target is robust to factor-return fat tails (avoids magnitude noise that dominates MSE).
# Two model variants measured: (A) LGBMRegressor on standardized rank, (B) LGBMRanker (lambdarank).
# Walk-forward expanding, annual refit. TRAIN-ONLY: fit on months whose fwd_ret is realized (date < t). IS-only.
# Features observable at t only. fwd_ret NEVER used as a feature. theta>=0, sum=1/date via softmax.
import os, json, numpy as np, pandas as pd
import lightgbm as lgb

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  = os.path.join(ROOT, "04_Research/method_frontier/wt006_exog_forecast")
W5   = os.path.join(ROOT, "04_Research/method_frontier/wt005_factor_timing")
fams = ["value","quality","momentum","low_vol","size","dividend"]

X = pd.read_parquet(os.path.join(OUT,"wt006_candidate_features.parquet"))
X["date"] = pd.to_datetime(X["date"])
logic_map = json.load(open(os.path.join(OUT,"logic_map.json")))
# full exogenous feature set + tr_* momentum (as in logic_map union), keep those with <=30% NaN
allf = [f for L in logic_map.values() for f in L]
allf = [f for f in dict.fromkeys(allf) if f in X.columns and X[f].isna().mean() <= 0.30]
print("rank_target features (%d):" % len(allf), allf)

oos_dates = pd.to_datetime(pd.read_parquet(os.path.join(W5,"theta_transformer_ensemble.parquet"))["date"]).sort_values().unique()
oos_dates = pd.DatetimeIndex(oos_dates)
print("OOS:", oos_dates.min().date(), "..", oos_dates.max().date(), "n=", len(oos_dates))

X = X.sort_values(["date","family"]).reset_index(drop=True)
X["family_code"] = X["family"].astype("category").cat.set_categories(fams).cat.codes
feat_cols = allf + ["family_code"]

# cross-sectional standardized rank target within each month (1..6 -> z), computed on realized fwd_ret only
def add_rank_target(df):
    df = df.dropna(subset=["fwd_ret"]).copy()
    # rank within date (ascending: high fwd_ret -> high rank), standardize per month
    df["rk"] = df.groupby("date")["fwd_ret"].rank(method="average")
    g = df.groupby("date")["rk"]
    df["rk_z"] = (df["rk"] - g.transform("mean")) / (g.transform("std") + 1e-9)
    return df

def lgb_reg_params(seed):
    return dict(objective="regression", n_estimators=120, learning_rate=0.03,
                num_leaves=7, min_child_samples=40, subsample=0.7, subsample_freq=1,
                colsample_bytree=0.7, reg_lambda=5.0, reg_alpha=0.5, max_depth=3,
                random_state=seed, n_jobs=1, verbose=-1)

def pred_to_theta(P, beta=2.0):
    out=[]
    for d, g in P.groupby("date"):
        pr = g["pred"].values.astype(float)
        z = (pr - pr.mean())/(pr.std()+1e-9)
        w = np.exp(beta*z); w = w/w.sum()
        for fam, wi in zip(g["family"].values, w): out.append((d, fam, float(wi)))
    return pd.DataFrame(out, columns=["date","family","theta"])

# ---------- Variant A: LGBMRegressor on standardized rank ----------
def run_reg(seed, refit_every=12):
    model=None; anchor=None; nref=0; rows=[]
    for t in oos_dates:
        tr = X[X["date"] < t]
        tr = add_rank_target(tr)
        tr = tr[tr[allf].notna().any(axis=1)]
        if tr["date"].nunique() < 24 or len(tr) < 100: continue
        need = (model is None) or (anchor is None) or ((t - anchor).days/30.4 >= refit_every)
        if need:
            m = lgb.LGBMRegressor(**lgb_reg_params(seed))
            m.fit(tr[feat_cols], tr["rk_z"], categorical_feature=["family_code"])
            model=m; anchor=t; nref+=1
        te = X[X["date"]==t]
        if len(te)==0: continue
        ph = model.predict(te[feat_cols])
        for fam,p in zip(te["family"].values, ph): rows.append((t,fam,float(p)))
    return pd.DataFrame(rows, columns=["date","family","pred"]), nref

# ---------- Variant B: LGBMRanker (lambdarank, native ordinal) ----------
def run_ranker(seed, refit_every=12):
    model=None; anchor=None; nref=0; rows=[]
    for t in oos_dates:
        tr = X[X["date"] < t]
        tr = add_rank_target(tr)
        tr = tr[tr[allf].notna().any(axis=1)]
        if tr["date"].nunique() < 24 or len(tr) < 100: continue
        need = (model is None) or (anchor is None) or ((t - anchor).days/30.4 >= refit_every)
        if need:
            trs = tr.sort_values("date")
            grp = trs.groupby("date").size().values
            # relevance label: integer rank 0..5 within month
            lab = trs.groupby("date")["fwd_ret"].rank(method="first").astype(int) - 1
            m = lgb.LGBMRanker(objective="lambdarank", n_estimators=120, learning_rate=0.03,
                               num_leaves=7, min_child_samples=40, subsample=0.7, subsample_freq=1,
                               colsample_bytree=0.7, reg_lambda=5.0, reg_alpha=0.5, max_depth=3,
                               label_gain=list(range(6)), random_state=seed, n_jobs=1, verbose=-1)
            m.fit(trs[feat_cols], lab.values, group=grp, categorical_feature=["family_code"])
            model=m; anchor=t; nref+=1
        te = X[X["date"]==t]
        if len(te)==0: continue
        ph = model.predict(te[feat_cols])
        for fam,p in zip(te["family"].values, ph): rows.append((t,fam,float(p)))
    return pd.DataFrame(rows, columns=["date","family","pred"]), nref

# Regressor: 3-seed ensemble
seeds=[0,1,2]; regs=[]
for s in seeds:
    P,nr = run_reg(s); regs.append(P.rename(columns={"pred":f"p{s}"}).set_index(["date","family"]))
    print(f"[rank-reg seed{s}] refits={nr} oos_mo={P['date'].nunique()}")
Mr = pd.concat(regs, axis=1); Mr["pred"]=Mr[[f"p{s}" for s in seeds]].mean(axis=1)
Preg = Mr.reset_index()[["date","family","pred"]]
th_reg = pred_to_theta(Preg)
th_reg.to_parquet(os.path.join(OUT,"theta_R2_rank_target.parquet"), index=False)
print("[rank-reg ensemble] saved theta_R2_rank_target.parquet rows=", len(th_reg), "months=", th_reg["date"].nunique())

# Ranker: single (lambdarank is deterministic-ish; save separate for diagnostics)
Prk,nrk = run_ranker(0)
th_rk = pred_to_theta(Prk)
th_rk.to_parquet(os.path.join(OUT,"theta_R2_rank_target_ranker.parquet"), index=False)
print("[rank-ranker] refits=",nrk," saved theta_R2_rank_target_ranker.parquet months=", th_rk["date"].nunique())
