"""
476_b1_multiday.py — B.1 Multi-day forecast: P2 with 5일 / 22일 horizon

도훈 mandate 2026-05-26 B.1: P2 Hansen 모델 horizon 확장.

Horizon options:
- h=1   (기존 P2 baseline, 비교용)
- h=5   (1주)
- h=22  (1개월)

label = log(P_{t+h} / P_t) — h일 누적 log return

walk-forward CV embargo: max(21, h)  ← horizon에 따라 lookahead 방지 강화.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

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


P_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)


def load_data_multiday(cfg, horizon=1):
    """Load benchmark + build features + h-day forward log return label."""
    bm_path = PROJECT_ROOT / cfg['data']['bm_path']
    df = pd.read_parquet(bm_path)
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.rename(columns={'BM_Close': 'Close'})
    df = df.sort_values('Date').reset_index(drop=True)
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

    # h-day forward log return
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


def run(cfg_path, output_dir, horizon=1, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df, feature_cols = load_data_multiday(cfg, horizon=horizon)
    print(f"[B.1 h={horizon}] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values

    cv_cfg = cfg.get('walk_forward', {})
    # embargo: max(21, horizon) — forward leak 방지
    embargo = max(21, horizon)
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=cv_cfg.get('n_splits', 12),
        train_min=cv_cfg.get('train_min', 1008),
        test_size=cv_cfg.get('test_window', 504),
        embargo=embargo,
    )
    print(f"  embargo={embargo}d (horizon={horizon})")

    os.makedirs(output_dir, exist_ok=True)
    taus_np = np.array(P_TAUS)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P_TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr, feature_names=feature_cols)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)

        print(f"  fold[{fold_idx}] Hansen fit to {len(y_te)} obs...")
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
            'y_actual': y_te,
            'crps': crps_per,
            'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'], 'nu': sst['nu'], 'lam': sst['lam'],
            'var_05': sst['var_05'], 'var_01': sst['var_01'],
            'var_005': sst['var_005'], 'var_001': sst['var_001'],
            'es_05': sst['es_05'],
            'p_minus_5pct': sst['p_minus_5'],
            'p_minus_7pct': sst['p_minus_7'],
            'p_minus_10pct': sst['p_minus_10'],
        })
        pred_df.to_parquet(Path(output_dir) / f"fold_{fold_idx:02d}_predictions.parquet")
        all_preds.append(pred_df)

        var_05_bt = VARBT.var_backtest_full(y_te, sst['var_05'], alpha=0.05)
        var_01_bt = VARBT.var_backtest_full(y_te, sst['var_01'], alpha=0.01)
        pit_chi = CALIB.pit_chi_square(pit, n_bins=10)

        fold_metrics.append({
            'fold': fold_idx, 'n_obs': len(y_te),
            'crps_mean': float(crps_per.mean()),
            'var_05_kupiec': var_05_bt['kupiec_uc']['pass_at_005'],
            'var_01_kupiec': var_01_bt['kupiec_uc']['pass_at_005'],
            'pit_chi_pass': pit_chi['pass_at_005'],
            'pit_chi_pvalue': pit_chi['p_value'],
            'lambda_mean': float(sst['lam'].mean()),
            'nu_mean': float(sst['nu'].mean()),
        })
        print(f"  fold[{fold_idx}] CRPS={crps_per.mean():.5f} "
              f"VaR_05_kup={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kup={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"λ̄={sst['lam'].mean():.3f} ν̄={sst['nu'].mean():.2f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    summary = {
        'method': f'B.1 P2 Hansen 1994 (horizon={horizon}d)',
        'horizon': horizon, 'embargo': embargo,
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'y_actual_stats': {
            'mean': float(full_pred['y_actual'].mean()),
            'std': float(full_pred['y_actual'].std()),
            'min': float(full_pred['y_actual'].min()),
            'max': float(full_pred['y_actual'].max()),
        },
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
    with open(Path(output_dir) / "summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== B.1 horizon={horizon}d POOLED ===")
    print(f"  y std (horizon-{horizon}) = {full_pred['y_actual'].std():.3f}%")
    print(f"  CRPS = {summary['crps_pooled']:.5f}")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}")
    print(f"  λ̄ = {summary['lambda_mean_pooled']:.4f}  ν̄ = {summary['nu_mean_pooled']:.2f}")
    print(f"  P(-10%) max = {summary['bear_probabilities_summary']['p_minus_10pct_max']*100:.3f}%")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--horizon', type=int, required=True, choices=[1, 5, 22])
    parser.add_argument('--output', type=str, default=None)
    parser.add_argument('--alpha', type=float, default=0.001)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / (args.output or f"03_models/b1_multiday_h{args.horizon}")
    print(f"[B.1] CFG: {cfg_path}")
    print(f"[B.1] OUT: {output_dir}")
    print(f"[B.1] horizon: {args.horizon}d")
    run(str(cfg_path), str(output_dir), horizon=args.horizon, alpha_l1=args.alpha, seed=args.seed)


if __name__ == "__main__":
    main()
