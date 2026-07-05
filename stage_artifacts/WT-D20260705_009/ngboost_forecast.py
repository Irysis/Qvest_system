"""
ngboost_forecast.py — WT-D20260705_009 Alpha Research
Expanding-window walk-forward NGBoost distributional forecast for uncertainty-conditioned selection.

At each rebalance month t:
  - Train NGBoost(Normal) on ALL rows with month < t  (features known at that month, forward return realized).
  - Predict distribution N(mu_hat, sigma_hat) for every in-universe stock at month t.
  - mu_hat = base alpha-hat (mean forecast).  sigma_hat = forecast uncertainty (per-stock predictive SD).

PIT (C1/C7 no look-ahead):
  - Strict expanding window: month t model NEVER sees month>=t. Forward return of training rows is realized
    before t (return at month m is over m->m+1; included in training only if m+1 <= t, i.e. m < t and realized).
    We include training rows with month <= t-2 to guarantee the forward label was fully realized before t.
  - Retrain cadence RETRAIN_EVERY months to keep tractable (still strictly expanding, never future).
  - Features standardized within-month already (factor DB Z, cross-sectional). No cross-month leakage.

Output (stage_artifacts/WT-D20260705_009/):
  forecast_dist.parquet : Date, Ticker, mu_hat, sigma_hat
  (R bridge then measures top-25-by-mu vs top-25-by-(mu/sigma) via canonical_screen_bt.)

Language boundary (python-policy sec4): Python produces per-stock mu/sigma ONLY.
Portfolio construction + PORT_t measurement is done in R (canonical_screen_bt). No portfolio return synthesis here.
"""
import os, sys, json
import numpy as np
import pandas as pd
from pathlib import Path

ROOT = Path(os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
STAGE = ROOT / "stage_artifacts" / "WT-D20260705_009"
PANEL = STAGE / "panel"

RETRAIN_EVERY = int(os.environ.get("NGB_RETRAIN_EVERY", "12"))   # retrain annually (expanding)
MIN_TRAIN_MONTHS = int(os.environ.get("NGB_MIN_TRAIN_MONTHS", "60"))  # need >=5y before first forecast
N_ESTIMATORS = int(os.environ.get("NGB_N_ESTIMATORS", "300"))
LR = float(os.environ.get("NGB_LR", "0.03"))
SEED = int(os.environ.get("NGB_SEED", "0"))

np.random.seed(SEED)

# ---- load panel ----
feat = pd.read_parquet(PANEL / "features_monthly.parquet")
ret  = pd.read_parquet(PANEL / "returns_monthly.parquet")   # Date,Ticker,Ret_1m (forward realized)
feat["Date"] = pd.to_datetime(feat["Date"])
ret["Date"]  = pd.to_datetime(ret["Date"])

feat_cols = [c for c in feat.columns if c not in ("Date", "Ticker")]
print(f"[ngb] features: {len(feat_cols)} cols -> {feat_cols}", flush=True)

# merge features with forward return label (inner: only rows with both features and realized fwd return)
df = feat.merge(ret[["Date", "Ticker", "Ret_1m"]], on=["Date", "Ticker"], how="left")
# fill missing features with 0 (cross-sectional Z; 0 = neutral). Track coverage.
df[feat_cols] = df[feat_cols].astype(float)
n_feat_present = df[feat_cols].notna().sum(axis=1)
df[feat_cols] = df[feat_cols].fillna(0.0)
# require at least 3 non-missing real features to forecast a stock
df["feat_cov"] = n_feat_present

months = np.array(sorted(df["Date"].unique()))
print(f"[ngb] panel months: {len(months)} ({months.min()} .. {months.max()})", flush=True)

from ngboost import NGBRegressor
from ngboost.distns import Normal
from sklearn.tree import DecisionTreeRegressor

def make_model():
    base = DecisionTreeRegressor(criterion="friedman_mse", max_depth=3,
                                 min_samples_leaf=200, random_state=SEED)
    return NGBRegressor(Dist=Normal, Base=base, n_estimators=N_ESTIMATORS,
                        learning_rate=LR, minibatch_frac=0.5, col_sample=0.8,
                        natural_gradient=True, verbose=False, random_state=SEED)

out_rows = []
model = None
last_train_idx = -RETRAIN_EVERY - 1

# forecast months: those with enough history. training rows for month t = month <= t-2 (label realized before t)
forecast_start_i = MIN_TRAIN_MONTHS + 1
for i in range(forecast_start_i, len(months)):
    t = months[i]
    # retrain cadence (expanding, strictly past)
    if (i - last_train_idx) >= RETRAIN_EVERY or model is None:
        # training rows: month <= months[i-2] AND has realized Ret_1m (label). Strictly before t (no leakage).
        train_cutoff = months[i - 2]
        tr = df[(df["Date"] <= train_cutoff) & df["Ret_1m"].notna()]
        Xtr = tr[feat_cols].values
        ytr = tr["Ret_1m"].values.astype(float)
        # winsorize label at 1/99 pct within training set (robustness, PIT-safe: train-only)
        lo, hi = np.percentile(ytr, [1, 99])
        ytr = np.clip(ytr, lo, hi)
        model = make_model()
        model.fit(Xtr, ytr)
        last_train_idx = i
        print(f"[ngb] retrain @ {pd.Timestamp(t).date()}  train_rows={len(tr)}  cutoff={pd.Timestamp(train_cutoff).date()}", flush=True)

    # predict distribution for month t (all in-univ rows with features)
    cur = df[(df["Date"] == t) & (df["feat_cov"] >= 3)]
    if len(cur) == 0:
        continue
    Xt = cur[feat_cols].values
    dist = model.pred_dist(Xt)
    mu = dist.loc            # Normal mean
    sigma = dist.scale       # Normal SD (forecast uncertainty)
    sub = pd.DataFrame({
        "Date": cur["Date"].values,
        "Ticker": cur["Ticker"].values,
        "mu_hat": mu,
        "sigma_hat": sigma,
    })
    out_rows.append(sub)

forecast = pd.concat(out_rows, ignore_index=True)
# sanity: sigma_hat strictly positive
forecast["sigma_hat"] = forecast["sigma_hat"].clip(lower=1e-6)
outp = STAGE / "forecast_dist.parquet"
forecast.to_parquet(outp, index=False)
print(f"[ngb] wrote {outp}  rows={len(forecast)}  months={forecast['Date'].nunique()} "
      f"({forecast['Date'].min()} .. {forecast['Date'].max()})", flush=True)
# quick diagnostics
print(f"[ngb] mu_hat  mean={forecast['mu_hat'].mean():.5f}  sd={forecast['mu_hat'].std():.5f}", flush=True)
print(f"[ngb] sigma_hat  mean={forecast['sigma_hat'].mean():.5f}  sd={forecast['sigma_hat'].std():.5f} "
      f"min={forecast['sigma_hat'].min():.5f} max={forecast['sigma_hat'].max():.5f}", flush=True)
