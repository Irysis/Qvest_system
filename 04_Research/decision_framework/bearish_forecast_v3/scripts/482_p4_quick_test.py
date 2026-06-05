"""
482_p4_quick_test.py — P4 (22d horizon) quick test

도훈 mandate 2026-05-27: PG2 monthly rebalance와 frequency match.
P3 spec (α=6.68e-4, taus=11, train_min=3024) 그대로 + horizon=22일.

Quick test 결과 좋으면 정식 P4 (features + hparam sweep) 진행.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
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


LQM = _load("a1_lasso_quantile", str(ROOT / "03_models" / "a1_lasso_quantile.py"))
HSK = _load("p1_hansen_skewt", str(ROOT / "03_models" / "p1_hansen_skewt.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))


# P4 spec (h=22 + P3 hyperparams)
P4_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
P4_ALPHA = 6.68e-4    # P3 sweet spot
P4_TRAIN_MIN = 3024   # P3 sweet spot
P4_TEST_WINDOW = 504
P4_HORIZON = 22       # 21 영업일 forward
P4_EMBARGO = 25       # 22+ buffer (h=22 + 3 safety days)
P4_N_SPLITS = 12


def load_data_h22(cfg, horizon=22):
    """Load benchmark + features + h-day forward log return label."""
    bm_path = PROJECT_ROOT / cfg['data']['bm_path']
    df = pd.read_parquet(bm_path)
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.rename(columns={'BM_Close': 'Close'}).sort_values('Date').reset_index(drop=True)
    df['log_ret'] = np.log(df['Close']).diff()

    for lag in [1, 2, 5, 22]:
        df[f'log_ret_lag_{lag}'] = df['log_ret'].shift(lag)
    for w in [5, 22, 60]:
        df[f'rv_{w}d'] = df['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()
        df[f'mean_{w}d'] = df['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()
    eps = 1e-8
    cum_max = df['Close'].cummax()
    df['drawdown'] = (df['Close'] - cum_max) / (cum_max + eps)

    def expanding_z(s, min_periods=60):
        mu = s.expanding(min_periods=min_periods).mean()
        sd = s.expanding(min_periods=min_periods).std() + eps
        return (s - mu) / sd
    df['rv_22d_z'] = expanding_z(df['rv_22d'])
    df['drawdown_z'] = expanding_z(df['drawdown'])

    # h-day forward log return label
    df['ret_fwd'] = np.log(df['Close'].shift(-horizon) / df['Close'])

    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)

    feature_cols = [
        'log_ret_lag_1', 'log_ret_lag_2', 'log_ret_lag_5', 'log_ret_lag_22',
        'rv_5d', 'rv_22d', 'rv_60d', 'mean_5d', 'mean_22d', 'mean_60d',
        'rv_22d_z', 'drawdown_z',
    ]
    df = df.dropna(subset=feature_cols + ['ret_fwd']).reset_index(drop=True)

    if cfg['data'].get('percent_scale', True):
        for c in ['log_ret', 'ret_fwd'] + [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] + \
                 [f'rv_{w}d' for w in [5, 22, 60]] + [f'mean_{w}d' for w in [5, 22, 60]] + ['drawdown']:
            if c in df.columns:
                df[c] = df[c] * 100.0
    return df, feature_cols


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p4_quick_test')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(args.seed)

    df, feature_cols = load_data_h22(cfg, horizon=P4_HORIZON)
    print(f'[P4 quick] data: {len(df)} rows ({df["Date"].min().date()} ~ {df["Date"].max().date()})')
    print(f'[P4 quick] horizon={P4_HORIZON}, embargo={P4_EMBARGO}, train_min={P4_TRAIN_MIN}, α={P4_ALPHA}')

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values

    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=P4_N_SPLITS, train_min=P4_TRAIN_MIN, test_size=P4_TEST_WINDOW, embargo=P4_EMBARGO,
    )
    taus_np = np.array(P4_TAUS)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P4_TAUS, alpha=P4_ALPHA, standardize=True)
        model.fit(X_tr, y_tr, feature_names=feature_cols)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)

        sst = HSK.derive_metrics_per_obs(Q_te, taus_np)
        pit = HSK.pit_per_obs(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['lam'])

        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 500
        for i in range(N):
            u = np.random.uniform(0, 1, n_samples)
            samples = HSK.hansen_quantile(u, sst['mu'][i], sst['sigma'][i], sst['nu'][i], sst['lam'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(n_samples)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(dates_te),
            'y_actual': y_te, 'crps': crps_per, 'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'], 'nu': sst['nu'], 'lam': sst['lam'],
            'var_05': sst['var_05'], 'var_01': sst['var_01'],
            'var_005': sst['var_005'], 'var_001': sst['var_001'],
            'es_05': sst['es_05'],
            'p_minus_5pct': sst['p_minus_5'],
            'p_minus_7pct': sst['p_minus_7'],
            'p_minus_10pct': sst['p_minus_10'],
        })
        pred_df.to_parquet(output_dir / f'fold_{fold_idx:02d}_predictions.parquet')
        all_preds.append(pred_df)

        var_05_bt = VARBT.var_backtest_full(y_te, sst['var_05'], alpha=0.05)
        var_01_bt = VARBT.var_backtest_full(y_te, sst['var_01'], alpha=0.01)
        pit_chi = CALIB.pit_chi_square(pit, n_bins=10)

        fold_metrics.append({
            'fold': fold_idx, 'n_obs': len(y_te),
            'crps_mean': float(crps_per.mean()),
            'var_05_kupiec_p': var_05_bt['kupiec_uc']['p_value'],
            'var_05_kupiec_pass': var_05_bt['kupiec_uc']['pass_at_005'],
            'var_01_kupiec_p': var_01_bt['kupiec_uc']['p_value'],
            'var_01_kupiec_pass': var_01_bt['kupiec_uc']['pass_at_005'],
            'pit_chi_pvalue': pit_chi['p_value'],
            'pit_chi_pass': pit_chi['pass_at_005'],
            'lambda_mean': float(sst['lam'].mean()),
            'nu_mean': float(sst['nu'].mean()),
        })
        print(f"  fold[{fold_idx}] n={N} CRPS={crps_per.mean():.5f} "
              f"VaR_05_p={var_05_bt['kupiec_uc']['p_value']:.4f} "
              f"VaR_01_p={var_01_bt['kupiec_uc']['p_value']:.4f} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"λ̄={sst['lam'].mean():.3f} ν̄={sst['nu'].mean():.2f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(output_dir / 'all_predictions.parquet')
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    y_std = full_pred['y_actual'].std()
    crps_normalized = full_pred['crps'].mean() / y_std

    summary = {
        'method': 'P4 quick test (h=22 with P3 hparams)',
        'spec': {'alpha': P4_ALPHA, 'taus_count': len(P4_TAUS),
                 'train_min': P4_TRAIN_MIN, 'test_window': P4_TEST_WINDOW,
                 'embargo': P4_EMBARGO, 'horizon': P4_HORIZON, 'n_splits': P4_N_SPLITS},
        'n_obs_total': len(full_pred),
        'y_std_pooled': float(y_std),
        'crps_pooled': float(full_pred['crps'].mean()),
        'crps_normalized': float(crps_normalized),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'lambda_mean_pooled': float(full_pred['lam'].mean()),
        'nu_mean_pooled': float(full_pred['nu'].mean()),
        'fold_metrics': fold_metrics,
        'bear_probabilities_summary': {
            'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
            'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
            'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
            'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
        },
    }
    with open(output_dir / 'summary.json', 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)

    print(f'\n=== P4 quick test (h=22) POOLED ===')
    print(f'  n_obs_total = {len(full_pred)}')
    print(f'  y std (22d) = {y_std:.3f}%   (sqrt(22)*1.3% = ~6.1%)')
    print(f'  CRPS = {summary["crps_pooled"]:.5f}')
    print(f'  CRPS normalized (/y_std) = {crps_normalized:.5f}  (P3 h=1: 0.490)')
    print(f'  VaR_05 Kupiec p={var_05_pool["kupiec_uc"]["p_value"]:.4f} pass={var_05_pool["kupiec_uc"]["pass_at_005"]}')
    print(f'  VaR_01 Kupiec p={var_01_pool["kupiec_uc"]["p_value"]:.4f} pass={var_01_pool["kupiec_uc"]["pass_at_005"]}')
    print(f'  PIT chi2 p={pit_pool["p_value"]:.4f} pass={pit_pool["pass_at_005"]}')
    print(f'  λ̄ = {summary["lambda_mean_pooled"]:.4f}  ν̄ = {summary["nu_mean_pooled"]:.2f}')
    print(f'  P(-10%) max = {summary["bear_probabilities_summary"]["p_minus_10pct_max"]*100:.3f}%')


if __name__ == "__main__":
    main()
