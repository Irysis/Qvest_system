"""
479_c1_neural_levy.py — C.1 Neural Lévy SDE training + walk-forward CV

도훈 mandate 2026-05-26 C.1: Wang-Rachev 2025 Neural Lévy SDE jump-diffusion.

Approach:
- Per walk-forward fold: train NeuralLevySDE(12 features → μ, σ, λ, μ_J, σ_J)
- Loss: NLL of truncated compound Poisson + Gaussian (K_max=3)
- Inference: sample 2000 paths → empirical CRPS/VaR/PIT

Expected: jump 명시적 모델링 → 블랙스완 일부 잡기 가능. P2 한계 보완.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import sys
import time
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import yaml

warnings.filterwarnings('ignore')

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


NL = _load("c2_neural_levy", str(ROOT / "03_models" / "c2_neural_levy.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))
P472 = _load("p1_patch_v2", str(ROOT / "scripts" / "472_p1_patch_v2.py"))


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def train_one_fold(X_tr, y_tr, X_val, y_val, device, hidden_dim=64, head_dim=32,
                   lr=1e-3, batch_size=256, max_epochs=200, patience=20, weight_decay=1e-5):
    """Train NeuralLevySDE on one fold with early stopping on val NLL."""
    input_size = X_tr.shape[1]
    model = NL.NeuralLevySDE(input_size=input_size, sequence_length=1, horizon=1,
                              hidden_dim=hidden_dim, head_dim=head_dim).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)

    X_tr_t = torch.from_numpy(X_tr).float().to(device)
    y_tr_t = torch.from_numpy(y_tr).float().to(device)
    X_val_t = torch.from_numpy(X_val).float().to(device)
    y_val_t = torch.from_numpy(y_val).float().to(device)

    n_train = len(X_tr_t)
    best_val = float('inf'); best_state = None; bad = 0
    for epoch in range(max_epochs):
        model.train()
        perm = torch.randperm(n_train)
        for start in range(0, n_train, batch_size):
            idx = perm[start:start + batch_size]
            params = model(X_tr_t[idx])
            loss = NL.neural_levy_nll(params, y_tr_t[idx])
            opt.zero_grad(); loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()

        model.eval()
        with torch.no_grad():
            val_params = model(X_val_t)
            val_nll = NL.neural_levy_nll(val_params, y_val_t).item()
        if val_nll < best_val - 1e-5:
            best_val = val_nll
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
            if bad >= patience:
                break
    if best_state is not None:
        model.load_state_dict(best_state)
    return model, best_val, epoch + 1


def infer_one_fold(model, X_te, device, n_samples=2000):
    """Sample-based inference: μ, σ, λ, μ_J, σ_J → CRPS/VaR/P(-X%)/PIT."""
    model.eval()
    with torch.no_grad():
        params = model(torch.from_numpy(X_te).float().to(device))
        samples = NL.neural_levy_sample(params, n_samples=n_samples)  # (B, S)
    samples_np = samples.cpu().numpy()
    params_np = tuple(p.detach().cpu().numpy() for p in params)
    return params_np, samples_np


def compute_metrics_from_samples(samples, y_actual):
    """Compute CRPS, VaR, P(-X%), PIT from empirical samples."""
    N, S = samples.shape
    # CRPS via empirical formula
    crps_per = np.zeros(N)
    abs_xy = np.abs(samples - y_actual[:, None]).mean(axis=1)
    # E|X-X'| via random pairs
    perm_idx = np.random.randint(0, S, size=(N, S))
    abs_xx = np.abs(samples - samples[np.arange(N)[:, None], perm_idx]).mean(axis=1)
    crps_per = abs_xy - 0.5 * abs_xx

    # VaR
    var_05 = np.quantile(samples, 0.05, axis=1)
    var_01 = np.quantile(samples, 0.01, axis=1)
    var_005 = np.quantile(samples, 0.005, axis=1)
    var_001 = np.quantile(samples, 0.001, axis=1)

    # ES (mean below VaR_05)
    es_05 = np.zeros(N)
    for i in range(N):
        below = samples[i] < var_05[i]
        es_05[i] = samples[i][below].mean() if below.any() else var_05[i]

    # P(y < threshold)
    p_5 = (samples < -5.0).mean(axis=1)
    p_7 = (samples < -7.0).mean(axis=1)
    p_10 = (samples < -10.0).mean(axis=1)

    # PIT = empirical CDF at y_actual
    pit = (samples <= y_actual[:, None]).mean(axis=1)

    return {
        'crps': crps_per, 'var_05': var_05, 'var_01': var_01,
        'var_005': var_005, 'var_001': var_001, 'es_05': es_05,
        'p_minus_5': p_5, 'p_minus_7': p_7, 'p_minus_10': p_10,
        'pit': pit,
    }


def run(cfg_path, output_dir, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed); torch.manual_seed(seed)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[C.1] device: {device}")

    df, feature_cols = P472.load_data(cfg)
    print(f"[C.1] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")
    print(f"[C.1] features: {len(feature_cols)}")

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values

    # Standardize features (NN stability)
    cv_cfg = cfg.get('walk_forward', {})
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=cv_cfg.get('n_splits', 12),
        train_min=cv_cfg.get('train_min', 1008),
        test_size=cv_cfg.get('test_window', 504),
        embargo=cv_cfg.get('embargo', 21),
    )

    os.makedirs(output_dir, exist_ok=True)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        # 80/20 train/val split inside training set
        n_tr = len(tr_idx)
        n_val = max(int(n_tr * 0.2), 100)
        tr_split = tr_idx[:n_tr - n_val]
        val_split = tr_idx[n_tr - n_val:]

        # Standardize using training set stats
        mu_X = X[tr_split].mean(axis=0); std_X = X[tr_split].std(axis=0) + 1e-8
        X_tr = (X[tr_split] - mu_X) / std_X
        X_val = (X[val_split] - mu_X) / std_X
        X_te = (X[te_idx] - mu_X) / std_X
        y_tr = y[tr_split]; y_val = y[val_split]; y_te = y[te_idx]
        dates_te = dates[te_idx]

        t0 = time.time()
        model, best_val_nll, epochs = train_one_fold(
            X_tr.astype(np.float32), y_tr.astype(np.float32),
            X_val.astype(np.float32), y_val.astype(np.float32),
            device=device, max_epochs=150, patience=15,
        )
        train_time = time.time() - t0

        params_np, samples = infer_one_fold(model, X_te.astype(np.float32), device)
        metrics = compute_metrics_from_samples(samples, y_te)

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(dates_te),
            'y_actual': y_te,
            'crps': metrics['crps'], 'pit': metrics['pit'],
            'mu': params_np[0], 'sigma': params_np[1], 'lam_int': params_np[2],
            'mu_jump': params_np[3], 'sigma_jump': params_np[4],
            'var_05': metrics['var_05'], 'var_01': metrics['var_01'],
            'var_005': metrics['var_005'], 'var_001': metrics['var_001'],
            'es_05': metrics['es_05'],
            'p_minus_5pct': metrics['p_minus_5'],
            'p_minus_7pct': metrics['p_minus_7'],
            'p_minus_10pct': metrics['p_minus_10'],
        })
        pred_df.to_parquet(Path(output_dir) / f"fold_{fold_idx:02d}_predictions.parquet")
        all_preds.append(pred_df)

        var_05_bt = VARBT.var_backtest_full(y_te, metrics['var_05'], alpha=0.05)
        var_01_bt = VARBT.var_backtest_full(y_te, metrics['var_01'], alpha=0.01)
        pit_chi = CALIB.pit_chi_square(metrics['pit'], n_bins=10)

        fold_metrics.append({
            'fold': fold_idx, 'n_obs': len(y_te),
            'epochs': epochs, 'val_nll': best_val_nll, 'train_time_sec': train_time,
            'crps_mean': float(metrics['crps'].mean()),
            'var_05_kupiec': var_05_bt['kupiec_uc']['pass_at_005'],
            'var_01_kupiec': var_01_bt['kupiec_uc']['pass_at_005'],
            'pit_chi_pvalue': pit_chi['p_value'],
            'pit_chi_pass': pit_chi['pass_at_005'],
            'lambda_mean_test': float(params_np[2].mean()),
            'mu_jump_mean_test': float(params_np[3].mean()),
            'sigma_jump_mean_test': float(params_np[4].mean()),
        })
        print(f"  fold[{fold_idx}] epochs={epochs} val_nll={best_val_nll:.4f} CRPS={metrics['crps'].mean():.5f} "
              f"VaR_05_kup={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kup={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"λ̄_jump={params_np[2].mean():.3f} μ̄_J={params_np[3].mean():+.3f} σ̄_J={params_np[4].mean():.3f} "
              f"({train_time:.1f}s)")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    summary = {
        'method': 'C.1 Neural Lévy SDE (Wang-Rachev 2025, compound Poisson + Gaussian)',
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'lambda_jump_pooled': float(full_pred['lam_int'].mean()),
        'mu_jump_pooled': float(full_pred['mu_jump'].mean()),
        'sigma_jump_pooled': float(full_pred['sigma_jump'].mean()),
        'fold_metrics': fold_metrics,
        'bear_probabilities_summary': {
            'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
            'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
            'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
            'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
        },
    }
    with open(Path(output_dir) / "summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== C.1 (Neural Lévy SDE) POOLED ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}  (P2: 0.63863)")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}  (P2: 0.0050)")
    print(f"  λ̄_jump={summary['lambda_jump_pooled']:.4f}  μ̄_J={summary['mu_jump_pooled']:+.3f}  σ̄_J={summary['sigma_jump_pooled']:.3f}")
    print(f"  P(-10%) max = {summary['bear_probabilities_summary']['p_minus_10pct_max']*100:.3f}%")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/c1_neural_levy')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    print(f"[C.1] CFG: {cfg_path}")
    print(f"[C.1] OUT: {output_dir}")
    run(str(cfg_path), str(output_dir), seed=args.seed)


if __name__ == "__main__":
    main()
