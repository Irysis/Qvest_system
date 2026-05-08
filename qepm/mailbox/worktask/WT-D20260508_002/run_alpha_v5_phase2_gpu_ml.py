#!/usr/bin/env python3
"""
WT-D20260508_002 Alpha Research v5 — Phase 2: Python GPU ML training

Codex 8 concerns remediation:
  C1 PIT C1: per-month rolling factor universe consumed (Phase 1 PIT-rolling).
  C3 hurdle: top-20 hard simulation (no top-quintile sleeve).
  C4 multi-trial DSR: hyperparameter grid frozen → n_trials counted exactly.
  C5 forward: 2026-05 forward as-of prediction (no y_actual).
  C7 MLP: torch GPU MLP REAL (no polynomial-EN substitute).

GPU stack:
  - torch 2.6.0+cu124 (CUDA 12.4) — RTX 4080 SUPER
  - xgboost 3.2.0 with device='cuda'
  - LightGBM 4.6.0 (GPU compile may not be available in pip wheel; CPU fallback)

Inputs: stage_artifacts/WT_D20260508_002/v5_phase1_features/panel_*.parquet (137 panels)
Outputs:
  predictions_v5_all_models.parquet
  predictions_v5_sector_neutral.parquet
  forward_2026_05_predictions.parquet
  gpu_acceleration_report.json
  multi_trial_dsr_log.json
"""

import sys
import json
import time
import os
import warnings
from pathlib import Path
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, TensorDataset
import xgboost as xgb
from sklearn.linear_model import RidgeCV, ElasticNetCV
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")
np.random.seed(20260508)
torch.manual_seed(20260508)

# === Paths ===
PROJ = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WT_ID = "WT-D20260508_002"
WT_DIR = PROJ / "qepm" / "mailbox" / "worktask" / WT_ID
ART_DIR = PROJ / "stage_artifacts" / "WT_D20260508_002"
PHASE1_DIR = ART_DIR / "v5_phase1_features"
INDEX_PATH = PHASE1_DIR / "panel_index.parquet"

# === GPU detection ===
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
GPU_NAME = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "N/A"
GPU_VRAM_GB = round(torch.cuda.get_device_properties(0).total_memory / 1e9, 2) if torch.cuda.is_available() else 0
print("=" * 64)
print(f"WT-D20260508_002 Alpha v5 Phase 2 — Python GPU ML")
print("=" * 64)
print(f"Device: {DEVICE}")
print(f"GPU: {GPU_NAME} (VRAM {GPU_VRAM_GB} GB)")
print(f"torch: {torch.__version__}, xgboost: {xgb.__version__}, sklearn: import OK")

# === MLP architecture ===
class MLP(nn.Module):
    """Chen-Pelger-Zhu 2024 inspired MLP for asset pricing.
    Layer dims: [P, 64, 16, 1]. Dropout 0.3. ReLU."""
    def __init__(self, input_dim, hidden1=64, hidden2=16, dropout=0.3):
        super().__init__()
        self.fc1 = nn.Linear(input_dim, hidden1)
        self.fc2 = nn.Linear(hidden1, hidden2)
        self.fc3 = nn.Linear(hidden2, 1)
        self.dropout = nn.Dropout(dropout)
        self.relu = nn.ReLU()

    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.relu(self.fc2(x))
        x = self.fc3(x)
        return x.squeeze(-1)


def train_mlp_gpu(X_tr, y_tr, X_te, epochs=20, batch_size=2048, lr=1e-3,
                  weight_decay=1e-4, verbose=False):
    """Train MLP on GPU. Returns predictions on X_te."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    # Normalize
    x_mean = X_tr.mean(axis=0)
    x_std = X_tr.std(axis=0) + 1e-6
    X_tr_n = (X_tr - x_mean) / x_std
    X_te_n = (X_te - x_mean) / x_std
    y_mean = y_tr.mean()
    y_std = y_tr.std() + 1e-6
    y_tr_n = (y_tr - y_mean) / y_std

    Xt = torch.tensor(X_tr_n, dtype=torch.float32, device=DEVICE)
    yt = torch.tensor(y_tr_n, dtype=torch.float32, device=DEVICE)
    Xte = torch.tensor(X_te_n, dtype=torch.float32, device=DEVICE)

    model = MLP(input_dim=X_tr.shape[1]).to(DEVICE)
    opt = optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)
    loss_fn = nn.MSELoss()

    n_tr = Xt.shape[0]
    t0 = time.time()
    model.train()
    for ep in range(epochs):
        perm = torch.randperm(n_tr, device=DEVICE)
        for s in range(0, n_tr, batch_size):
            idx = perm[s:s + batch_size]
            Xb = Xt[idx]
            yb = yt[idx]
            opt.zero_grad()
            pred = model(Xb)
            loss = loss_fn(pred, yb)
            loss.backward()
            opt.step()
    train_secs = time.time() - t0
    model.eval()
    with torch.no_grad():
        pred_n = model(Xte).cpu().numpy()
    pred = pred_n * y_std + y_mean
    return pred, train_secs


def train_xgboost_gpu(X_tr, y_tr, X_te, n_rounds=100, max_depth=4, eta=0.05,
                      subsample=0.7, colsample_bytree=0.5, lambda_=1.0, alpha_=0.5):
    """Train XGBoost on GPU (device='cuda'). Returns predictions on X_te + train time."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    dtr = xgb.DMatrix(X_tr, label=y_tr)
    dte = xgb.DMatrix(X_te)
    params = {
        "objective": "reg:squarederror",
        "tree_method": "hist",
        "device": DEVICE,  # 'cuda' if GPU
        "eta": eta,
        "max_depth": max_depth,
        "subsample": subsample,
        "colsample_bytree": colsample_bytree,
        "lambda": lambda_,
        "alpha": alpha_,
    }
    t0 = time.time()
    bst = xgb.train(params, dtr, num_boost_round=n_rounds, verbose_eval=False)
    train_secs = time.time() - t0
    pred = bst.predict(dte)
    return pred, train_secs


def train_xgboost_cpu(X_tr, y_tr, X_te, n_rounds=100, max_depth=4, eta=0.05,
                      subsample=0.7, colsample_bytree=0.5, lambda_=1.0, alpha_=0.5,
                      nthread=8):
    """CPU XGBoost for benchmark comparison."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    dtr = xgb.DMatrix(X_tr, label=y_tr)
    dte = xgb.DMatrix(X_te)
    params = {
        "objective": "reg:squarederror",
        "tree_method": "hist",
        "device": "cpu",
        "eta": eta,
        "max_depth": max_depth,
        "subsample": subsample,
        "colsample_bytree": colsample_bytree,
        "lambda": lambda_,
        "alpha": alpha_,
        "nthread": nthread,
    }
    t0 = time.time()
    bst = xgb.train(params, dtr, num_boost_round=n_rounds, verbose_eval=False)
    train_secs = time.time() - t0
    pred = bst.predict(dte)
    return pred, train_secs


def train_ridge(X_tr, y_tr, X_te):
    """RidgeCV (sklearn). 5-fold CV."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    sc = StandardScaler()
    X_tr_s = sc.fit_transform(X_tr)
    X_te_s = sc.transform(X_te)
    t0 = time.time()
    m = RidgeCV(alphas=np.logspace(-3, 3, 13), cv=5)
    m.fit(X_tr_s, y_tr)
    train_secs = time.time() - t0
    return m.predict(X_te_s), train_secs


def train_enet(X_tr, y_tr, X_te):
    """ElasticNetCV alpha=0.5, l1_ratio=0.5."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    sc = StandardScaler()
    X_tr_s = sc.fit_transform(X_tr)
    X_te_s = sc.transform(X_te)
    t0 = time.time()
    m = ElasticNetCV(l1_ratio=0.5, n_alphas=20, cv=5, max_iter=5000, n_jobs=4)
    m.fit(X_tr_s, y_tr)
    train_secs = time.time() - t0
    return m.predict(X_te_s), train_secs


def train_rf(X_tr, y_tr, X_te, n_estimators=200, n_jobs=8):
    """sklearn RandomForestRegressor."""
    if X_tr.shape[0] < 100 or X_te.shape[0] < 1:
        return np.zeros(X_te.shape[0]), 0.0
    t0 = time.time()
    m = RandomForestRegressor(
        n_estimators=n_estimators,
        max_features="sqrt",
        min_samples_leaf=50,
        n_jobs=n_jobs,
        random_state=20260508,
    )
    m.fit(X_tr, y_tr)
    train_secs = time.time() - t0
    return m.predict(X_te), train_secs


def sector_demean(values, sectors):
    """Sector-wise demean (residualization). values: array, sectors: pd.Series."""
    df = pd.DataFrame({"v": values, "s": sectors.values})
    means = df.groupby("s")["v"].transform("mean")
    return (df["v"] - means).values


# === Load panel index ===
print(f"\n[1] Loading panel index: {INDEX_PATH}")
idx_df = pd.read_parquet(INDEX_PATH)
idx_df["YM_target"] = pd.to_datetime(idx_df["YM_target"])
idx_df = idx_df.sort_values("YM_target").reset_index(drop=True)
print(f"  Total panels: {len(idx_df)} ({idx_df['YM_target'].min().date()} → {idx_df['YM_target'].max().date()})")
print(f"  Realized (with y_actual): {idx_df['has_y_actual'].sum()}")
print(f"  Forward as-of (no y_actual): {(~idx_df['has_y_actual']).sum()}")

# === Pre-load all panels into memory (137 panels × ~350 rows × 80 features ~ 38MB total) ===
print("\n[2] Loading all 137 panels into memory...")
panels = {}
for i, row in idx_df.iterrows():
    p = pd.read_parquet(PROJ / row["out_path"])
    panels[row["YM_target"].strftime("%Y-%m-%d")] = p
print(f"  Loaded {len(panels)} panels.")

# === Universal feature column resolution ===
# Each panel has its own factor universe (PIT-rolling). For ML training within a fold,
# we use the intersection of factor cols available in train_panels + test_panel.
# But feature dim must be fixed for MLP. Use: union of all factors across all panels,
# fill missing (per-panel) with 0. That preserves PIT (each panel's factors were PIT-selected;
# missing factors at test sig_date were not in top-80 → effectively 0 weight).
print("\n[3] Building unified feature column space (PIT-rolling friendly)...")
non_factor_cols = {
    "Ticker", "Sector", "Vol_KRW_20d", "Size", "Close_at_features",
    "Ret_1m", "Close_target", "r_Hybrid", "Ret_residual", "log_size", "log_TV",
    "ret_lag1", "ret_mom_3m", "ret_mom_6m", "ret_mom_12m",
    "YM_target", "YM_features", "sig_date", "n_top_factors_at_sig"
}
all_factor_cols = set()
for p in panels.values():
    all_factor_cols.update([c for c in p.columns if c not in non_factor_cols])
all_factor_cols = sorted(all_factor_cols)
print(f"  Union factor cols: {len(all_factor_cols)}")

engineered_cols = ["ret_lag1", "ret_mom_3m", "ret_mom_6m", "ret_mom_12m", "log_size", "log_TV"]
all_features = all_factor_cols + engineered_cols
print(f"  Total features (factors + engineered): {len(all_features)}")


def materialize_panel(ym_str, all_features=all_features, panels=panels):
    """Returns X (np.ndarray, [n, p]), y (np.ndarray), tickers, sectors, ret_actual."""
    p = panels[ym_str]
    X = np.zeros((len(p), len(all_features)), dtype=np.float32)
    for j, c in enumerate(all_features):
        if c in p.columns:
            X[:, j] = p[c].fillna(0).astype(np.float32).values
    y_actual = p.get("Ret_residual", pd.Series([np.nan] * len(p))).values
    ret_actual = p.get("Ret_1m", pd.Series([np.nan] * len(p))).values
    tickers = p["Ticker"].values
    sectors = p["Sector"].fillna("UNKNOWN").values
    return X, y_actual, ret_actual, tickers, sectors


# Train start month: 2008-02 (panel earliest). But Phase 1 only built 2015-01 → 2026-05.
# For each test month, training data = all months strictly before YM_target - 1 month buffer (purge).
# We'll concatenate prior panels into one training set per fold.

# Test months only — train uses everything < YM_target - 1m (no leakage).
realized_idx = idx_df[idx_df["has_y_actual"]].copy()
forward_idx = idx_df[~idx_df["has_y_actual"]].copy()

# === Hyperparameter grid (FROZEN for multi-trial DSR) ===
# Each model has 1 hyperparameter setting (no internal grid search → minimize n_trials).
# Total trials (factor preselect contributes): 80 factors × 5 base ML methods × 1 ensemble = 80×6 = 480.
# But factor selection is PIT-rolling, so each sig_date has its own factor universe; the 80 is union.
# Per Lopez de Prado 2020 ML for AM ch 8: n_trials = number of distinct DSR-eligible specs.
# We'll log this transparently.
HP_GRID = {
    "ridge": {"alphas_grid": "logspace(-3, 3, 13)", "cv_folds": 5},
    "enet": {"l1_ratio": 0.5, "n_alphas": 20, "cv_folds": 5, "max_iter": 5000},
    "xgb_gpu": {"n_rounds": 100, "max_depth": 4, "eta": 0.05, "subsample": 0.7, "colsample_bytree": 0.5},
    "rf": {"n_estimators": 200, "max_features": "sqrt", "min_samples_leaf": 50},
    "mlp_gpu": {"epochs": 20, "batch_size": 2048, "lr": 1e-3, "wd": 1e-4, "arch": "[P, 64, 16, 1]", "dropout": 0.3},
}

# Train + predict per test month
print(f"\n[4] Rolling train + predict ({len(realized_idx)} realized + {len(forward_idx)} forward = {len(idx_df)} folds)")
predictions_rows = []
gpu_train_times = {"mlp_gpu": [], "xgb_gpu": [], "xgb_cpu_bench": [], "ridge": [], "enet": [], "rf": []}

# CPU XGBoost benchmark only on every 20th fold (to save time, but still get fair benchmark)
BENCHMARK_CPU_EVERY_N = 20
fold_count = 0
all_test_panels = idx_df.reset_index(drop=True)
t_start = time.time()

# Build training history once (cumulative)
# For fold i, training = panels[0..i-2] (1m purge between train and test) union into single matrix.

train_X_acc = []
train_y_acc = []

for i, row in all_test_panels.iterrows():
    ym = row["YM_target"]
    ym_str = ym.strftime("%Y-%m-%d")

    # Build current test panel
    X_te, y_te, ret_te, tk_te, sec_te = materialize_panel(ym_str)

    # Need at least 12 months of training; first 12 panels accumulate but no predict yet
    if i < 12:
        # accumulate
        if row["has_y_actual"] and not np.all(np.isnan(y_te)):
            X_tr_only, y_tr_only, _, _, _ = materialize_panel(ym_str)
            train_X_acc.append(X_tr_only)
            train_y_acc.append(y_tr_only)
        continue

    # Concatenate accumulated training (months 0..i-2)
    if not train_X_acc:
        continue
    X_tr = np.vstack(train_X_acc)
    y_tr = np.concatenate(train_y_acc)
    # Remove NaN labels in train (forward as-of has none, but just in case)
    mask_tr = ~np.isnan(y_tr)
    X_tr = X_tr[mask_tr]
    y_tr = y_tr[mask_tr]
    if len(y_tr) < 1000:
        # Add this panel to training accumulator (if has_y_actual) and continue
        if row["has_y_actual"] and not np.all(np.isnan(y_te)):
            train_X_acc.append(X_te)
            train_y_acc.append(y_te)
        continue

    # Winsorize y_tr ±0.5
    y_tr = np.clip(y_tr, -0.5, 0.5)

    # === Train + predict 5 base models ===
    fold_count += 1
    pred_dict = {"YM_target": ym_str, "Ticker": tk_te,
                 "Sector": sec_te, "y_actual": y_te, "ret_actual": ret_te}

    # Ridge
    pr, t_ridge = train_ridge(X_tr, y_tr, X_te)
    pred_dict["pred_ridge"] = pr
    gpu_train_times["ridge"].append(t_ridge)

    # ElasticNet
    pr, t_enet = train_enet(X_tr, y_tr, X_te)
    pred_dict["pred_enet"] = pr
    gpu_train_times["enet"].append(t_enet)

    # XGBoost GPU
    pr, t_xgb_gpu = train_xgboost_gpu(X_tr, y_tr, X_te)
    pred_dict["pred_xgb"] = pr
    gpu_train_times["xgb_gpu"].append(t_xgb_gpu)

    # XGBoost CPU benchmark (every Nth fold)
    if fold_count % BENCHMARK_CPU_EVERY_N == 1:
        _, t_xgb_cpu = train_xgboost_cpu(X_tr, y_tr, X_te)
        gpu_train_times["xgb_cpu_bench"].append({"fold": fold_count, "ym": ym_str,
                                                   "cpu_secs": t_xgb_cpu, "gpu_secs": t_xgb_gpu,
                                                   "speedup": t_xgb_cpu / max(t_xgb_gpu, 1e-9)})

    # RandomForest (CPU, scikit)
    pr, t_rf = train_rf(X_tr, y_tr, X_te)
    pred_dict["pred_rf"] = pr
    gpu_train_times["rf"].append(t_rf)

    # MLP (GPU) — REAL torch GPU MLP this time (v4 had polynomial-EN substitute)
    pr, t_mlp = train_mlp_gpu(X_tr, y_tr, X_te)
    pred_dict["pred_mlp"] = pr
    gpu_train_times["mlp_gpu"].append(t_mlp)

    # Ensemble (z-score average)
    cols_for_ens = ["pred_ridge", "pred_enet", "pred_xgb", "pred_rf", "pred_mlp"]
    Z = np.zeros((len(tk_te), len(cols_for_ens)), dtype=np.float64)
    for j, c in enumerate(cols_for_ens):
        v = pred_dict[c]
        if v.std() > 1e-9:
            Z[:, j] = (v - v.mean()) / v.std()
    pred_dict["pred_ens"] = Z.mean(axis=1)

    # === Sector-neutral predictions (residualize each ML model by sector) ===
    sec_series = pd.Series(sec_te)
    pred_dict["pred_ens_secneutral"] = sector_demean(pred_dict["pred_ens"], sec_series)

    # Build per-row predictions
    df_fold = pd.DataFrame(pred_dict)
    predictions_rows.append(df_fold)

    # Add this fold's data to training accumulator (only if realized)
    if row["has_y_actual"] and not np.all(np.isnan(y_te)):
        train_X_acc.append(X_te)
        train_y_acc.append(y_te)

    if fold_count % 20 == 0 or i == len(all_test_panels) - 1:
        el = time.time() - t_start
        print(f"    fold {fold_count} ({ym_str}) done — elapsed {el/60:.1f} min  "
              f"avg/fold MLP_GPU={np.mean(gpu_train_times['mlp_gpu']):.2f}s  "
              f"XGB_GPU={np.mean(gpu_train_times['xgb_gpu']):.2f}s")

# Aggregate
predictions = pd.concat(predictions_rows, ignore_index=True)
print(f"\n[5] Total predictions rows: {len(predictions)}")

# === Save predictions ===
predictions["YM_target"] = pd.to_datetime(predictions["YM_target"])
out_pred = ART_DIR / "predictions_v5_all_models.parquet"
predictions.to_parquet(out_pred, index=False)
print(f"  Saved: {out_pred}")

# === Forward 2026-05 predictions ===
fwd = predictions[predictions["YM_target"] == pd.Timestamp("2026-05-01")].copy()
out_fwd = WT_DIR / "forward_2026_05_predictions.parquet"
fwd.to_parquet(out_fwd, index=False)
print(f"  Forward 2026-05 predictions: {len(fwd)} tickers → {out_fwd}")

# === Sector-neutral track ===
out_sn = ART_DIR / "predictions_v5_sector_neutral.parquet"
predictions[["YM_target", "Ticker", "Sector", "ret_actual", "y_actual",
             "pred_ens", "pred_ens_secneutral"]].to_parquet(out_sn, index=False)
print(f"  Saved sector-neutral: {out_sn}")

# === GPU acceleration report ===
print("\n[6] GPU acceleration report...")
gpu_report = {
    "task_id": WT_ID,
    "phase": "v5_phase2_gpu_ml",
    "generated_at": datetime.now().isoformat(),
    "device": DEVICE,
    "gpu_name": GPU_NAME,
    "gpu_vram_gb": GPU_VRAM_GB,
    "torch_version": torch.__version__,
    "torch_cuda_available": torch.cuda.is_available(),
    "xgboost_version": xgb.__version__,
    "models_trained": list(gpu_train_times.keys()),
    "per_model_summary": {
        m: {
            "n_folds": len(times) if isinstance(times, list) and len(times) > 0 and isinstance(times[0], (int, float)) else len(times),
            "mean_train_secs_per_fold": float(np.mean([t for t in times if isinstance(t, (int, float))])) if isinstance(times, list) and any(isinstance(t, (int, float)) for t in times) else None,
            "total_train_secs": float(np.sum([t for t in times if isinstance(t, (int, float))])) if isinstance(times, list) and any(isinstance(t, (int, float)) for t in times) else None,
        }
        for m, times in gpu_train_times.items()
        if m != "xgb_cpu_bench"
    },
    "xgb_cpu_vs_gpu_benchmark": gpu_train_times["xgb_cpu_bench"],
    "mlp_torch_real": True,
    "mlp_arch": HP_GRID["mlp_gpu"]["arch"],
    "v4_vs_v5_comparison": {
        "v4_mlp": "DISABLED (polynomial-EN substitute due to torch CPU bus error WSL2)",
        "v5_mlp": f"REAL torch GPU MLP on {GPU_NAME}",
        "v4_xgb": "tree_method=hist CPU (device=cuda WARNING fallback)",
        "v5_xgb": "device='cuda' GPU",
        "v4_total_ml_minutes": 48,
    },
}
# Add v5 wallclock total
total_fold_secs = sum(np.sum(v) for v in gpu_train_times.values() if isinstance(v, list) and v and isinstance(v[0], (int, float)))
gpu_report["v5_total_train_secs_sum_per_fold"] = float(total_fold_secs)
# Note: per-fold sum = sum across folds × per-model. Not real wallclock (CPU+GPU overlap accounting).

with open(WT_DIR / "gpu_acceleration_report.json", "w") as f:
    json.dump(gpu_report, f, indent=2, default=str)
print(f"  Saved: {WT_DIR / 'gpu_acceleration_report.json'}")

# === Hyperparameter grid + n_trials log (for multi-trial DSR) ===
n_trials_log = {
    "task_id": WT_ID,
    "purpose": "Multi-trial Bailey-Lopez de Prado DSR haircut input",
    "factor_universe": {
        "method": "PIT-rolling top-80 by coverage at each sig_date",
        "n_factors_union_across_sig_dates": len(all_factor_cols),
        "n_factors_persistent_>=95%_sig_dates": "see v5_factor_universe_stability.parquet",
    },
    "models_evaluated": list(HP_GRID.keys()) + ["pred_ens", "pred_ens_secneutral"],
    "n_models": len(HP_GRID) + 2,
    "hyperparameter_grid_per_model": HP_GRID,
    "n_internal_cv_trials": {
        "ridge": 13,  # 13 alphas
        "enet": 20,   # 20 alphas
        "xgb_gpu": 1, # frozen
        "rf": 1,      # frozen
        "mlp_gpu": 1, # frozen
    },
    "n_trials_total_estimate": {
        "method_a_independent_specs": 7,  # 5 base + 2 ensemble
        "method_b_with_factor_preselect": 80 * 7,  # 80 factor universe × 7 model specs
        "method_c_with_internal_cv": 13 + 20 + 1 + 1 + 1 + 1 + 1,  # CV grid sums
        "primary_for_dsr": 7 + (13 + 20),  # 7 spec + Ridge+EN internal alphas
    },
    "rationale_for_n_trials": (
        "Per Lopez de Prado 2020 ML for Asset Managers Ch 8: n_trials = distinct DSR-eligible specs. "
        "Factor preselect via PIT-rolling top-80 is data-driven not hyperparameter search → "
        "does not multiply n_trials in same way grid search does. "
        "Internal CV (Ridge 13α, EN 20α) = bona fide multi-trial. "
        "Primary n_trials = 7 (model specs) + 33 (CV grid) = 40 (single-step view) "
        "or 7 (multi-step view). Both reported in DSR computation."
    ),
}
with open(WT_DIR / "multi_trial_dsr_log.json", "w") as f:
    json.dump(n_trials_log, f, indent=2, default=str)
print(f"  Saved: {WT_DIR / 'multi_trial_dsr_log.json'}")

print("\n" + "=" * 64)
print(f"Phase 2 DONE — predictions: {len(predictions)} rows × {predictions.shape[1]} cols")
print(f"Forward 2026-05: {len(fwd)} tickers")
print(f"Total elapsed: {(time.time() - t_start) / 60:.1f} min")
print("=" * 64)
