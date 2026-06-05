"""
471_p1_patch.py — P1 patch v1: Quantile crossing fix + skewed-t fit

도훈 mandate 2026-05-26: P1 (A LASSO Quantile baseline) Path 3 patch
1. var_05 != var_01 (별도 값 도출)
2. PIT improvement (skewed-t distribution shape fit)
3. P(-X%) bear probability 정확 derive

Pipeline:
1. LASSO Quantile fit 11 quantiles τ ∈ {0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99}
2. Each obs: Azzalini-Capitanio skewed-t fit to 11 quantile points
3. Derive distinct var_01, var_05, var_005 + P(-X%) from fitted skewed-t
4. PIT from CDF
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import importlib.util
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
P1FIT = _load("p1_skewed_t_fit", str(ROOT / "03_models" / "p1_skewed_t_fit.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))


P1_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)

KEY_BEAR_DATES = {
    'Lehman_2008-09-15': '2008-09-15',
    'Euro_2011-08-08': '2011-08-08',
    'COVID_2020-02-19': '2020-02-19',
    'COVID_2020-03-13': '2020-03-13',
    '2022_Rate_Hike': '2022-09-26',
    '2024_Yen_Carry': '2024-08-02',
    '2024_Martial_Law': '2024-12-03',
}


def _json_default(obj):
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        return float(obj)
    if isinstance(obj, (np.ndarray,)):
        return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def load_data(cfg):
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
    df['ret_fwd'] = np.log(df['Close'].shift(-1) / df['Close'])

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


def run_p1_patch(cfg_path, output_dir, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df, feature_cols = load_data(cfg)
    print(f"[p1_patch] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")
    print(f"[p1_patch] features: {len(feature_cols)}")

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values

    cv_cfg = cfg.get('walk_forward', {})
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=cv_cfg.get('n_splits', 12),
        train_min=cv_cfg.get('train_min', 1008),
        test_size=cv_cfg.get('test_window', 504),
        embargo=cv_cfg.get('embargo', 21),
    )
    print(f"[p1_patch] CV sanity: {CVMOD.sanity_check_cv(splitter, X)}")

    os.makedirs(output_dir, exist_ok=True)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P1_TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr, feature_names=feature_cols)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)

        print(f"  fold[{fold_idx}] fitting skewed-t to {len(y_te)} obs...")
        sst = P1FIT.derive_metrics_from_skew_t(
            Q_te, np.array(P1_TAUS), n_samples=1000,
            bear_thresholds=(-5.0, -7.0, -10.0),
        )

        pit = P1FIT.pit_from_skew_t(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['xi'])

        pinball_per_tau = {}
        for j, tau in enumerate(P1_TAUS):
            q_t = Q_te[:, j]
            diff = y_te - q_t
            pb = np.where(diff > 0, tau * diff, -(1 - tau) * diff)
            pinball_per_tau[tau] = float(pb.mean())

        # CRPS via skewed-t samples (per-obs)
        sample_grid_size = 500
        crps_per = np.zeros(len(y_te))
        for i in range(len(y_te)):
            u = np.random.uniform(0, 1, sample_grid_size)
            samples = P1FIT.skew_t_quantile(u, sst['mu'][i], sst['sigma'][i], sst['nu'][i], sst['xi'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(sample_grid_size)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(dates_te),
            'y_actual': y_te,
            'crps': crps_per,
            'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'], 'nu': sst['nu'], 'xi': sst['xi'],
            'var_05': sst['var_05'], 'var_01': sst['var_01'], 'var_005': sst['var_005'],
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
        pb_mean = float(np.mean(list(pinball_per_tau.values())))

        fold_metrics.append({
            'fold': fold_idx, 'n_obs': len(y_te),
            'crps_mean': float(crps_per.mean()),
            'pinball_mean': pb_mean,
            'var_05_kupiec': var_05_bt['kupiec_uc']['pass_at_005'],
            'var_01_kupiec': var_01_bt['kupiec_uc']['pass_at_005'],
            'pit_chi_pass': pit_chi['pass_at_005'],
            'pit_chi_pvalue': pit_chi['p_value'],
            'var_05_diff_01_mean_abs': float(np.abs(sst['var_05'] - sst['var_01']).mean()),
        })
        print(f"  fold[{fold_idx}] CRPS={crps_per.mean():.5f} Pinball={pb_mean:.5f} "
              f"VaR_05_kupiec={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kupiec={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"|var_05-var_01|={float(np.abs(sst['var_05'] - sst['var_01']).mean()):.4f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    bear_evals = {}
    for label, dstr in KEY_BEAR_DATES.items():
        td = pd.to_datetime(dstr)
        mask = full_pred['Date'] == td
        if mask.sum() == 0:
            diffs = (full_pred['Date'] - td).abs()
            if diffs.min() <= pd.Timedelta(days=3):
                idx = diffs.idxmin()
                row = full_pred.iloc[idx]
            else:
                bear_evals[label] = {'in_test_set': False}
                continue
        else:
            row = full_pred[mask].iloc[0]
        bear_evals[label] = {
            'in_test_set': True,
            'forecast_date': str(row['Date'].date()),
            'y_actual': float(row['y_actual']),
            'var_05': float(row['var_05']),
            'var_01': float(row['var_01']),
            'p_minus_5pct': float(row['p_minus_5pct']),
            'p_minus_7pct': float(row['p_minus_7pct']),
            'p_minus_10pct': float(row['p_minus_10pct']),
        }

    summary = {
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'fold_metrics': fold_metrics,
        'bear_date_evaluations': bear_evals,
        'bear_probabilities_summary': {
            'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
            'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
            'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
            'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
        },
    }
    with open(Path(output_dir) / "p1_patch_summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n[p1_patch] saved to {output_dir}")
    print(f"\n=== POOLED METRICS ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}")
    print(f"  |var_05 - var_01| avg = {summary['var_05_diff_var_01_mean_abs_pooled']:.4f}")
    print(f"  P(-10%) max = {summary['bear_probabilities_summary']['p_minus_10pct_max']*100:.3f}%")
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p1_patch_v1')
    parser.add_argument('--alpha', type=float, default=0.001)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    print(f"[p1_patch] CFG: {cfg_path}")
    print(f"[p1_patch] OUT: {output_dir}")
    print(f"[p1_patch] alpha_L1: {args.alpha}")
    run_p1_patch(str(cfg_path), str(output_dir), alpha_l1=args.alpha, seed=args.seed)


if __name__ == "__main__":
    main()
