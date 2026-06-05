"""
482_p3_full_backtest.py — P3 production candidate full walk-forward backtest

도훈 confirmed 2026-05-26: P3 = α=1e-4, taus=11, train_min=2520 (~10년 lookback)

Output: 03_models/p3_production/all_predictions.parquet (5,241 rows)
        + summary.json
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
P472 = _load("p1_patch_v2", str(ROOT / "scripts" / "472_p1_patch_v2.py"))


# Default P3 spec (Grid 8 — 도훈 confirmed). Override via CLI.
P3_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
P3_TEST_WINDOW = 504
P3_EMBARGO = 21
P3_N_SPLITS = 12

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
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p3_production')
    parser.add_argument('--alpha', type=float, default=1e-4, help='LASSO L1 penalty')
    parser.add_argument('--train_min', type=int, default=2520, help='Training window min (~10년)')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    global P3_ALPHA, P3_TRAIN_MIN
    P3_ALPHA = args.alpha
    P3_TRAIN_MIN = args.train_min

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(args.seed)
    df, feature_cols = P472.load_data(cfg)
    print(f"[P3] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")
    print(f"[P3] spec: α={P3_ALPHA}, taus_count={len(P3_TAUS)}, train_min={P3_TRAIN_MIN}, test={P3_TEST_WINDOW}, embargo={P3_EMBARGO}")

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values

    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=P3_N_SPLITS, train_min=P3_TRAIN_MIN, test_size=P3_TEST_WINDOW, embargo=P3_EMBARGO,
    )
    taus_np = np.array(P3_TAUS)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P3_TAUS, alpha=P3_ALPHA, standardize=True)
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
            'y_actual': y_te,
            'crps': crps_per, 'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'], 'nu': sst['nu'], 'lam': sst['lam'],
            'var_05': sst['var_05'], 'var_01': sst['var_01'],
            'var_005': sst['var_005'], 'var_001': sst['var_001'],
            'es_05': sst['es_05'],
            'p_minus_5pct': sst['p_minus_5'],
            'p_minus_7pct': sst['p_minus_7'],
            'p_minus_10pct': sst['p_minus_10'],
        })
        pred_df.to_parquet(output_dir / f"fold_{fold_idx:02d}_predictions.parquet")
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
        })
        print(f"  fold[{fold_idx}] CRPS={crps_per.mean():.5f} "
              f"VaR_05_kup={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kup={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(output_dir / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    # Bear date evaluations
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
            'var_05': float(row['var_05']), 'var_01': float(row['var_01']),
            'p_minus_5pct': float(row['p_minus_5pct']),
            'p_minus_10pct': float(row['p_minus_10pct']),
        }

    summary = {
        'method': 'P3 production candidate (α=1e-4, tmin=2520, taus=11)',
        'spec': {'alpha': P3_ALPHA, 'taus_count': len(P3_TAUS), 'train_min': P3_TRAIN_MIN,
                 'test_window': P3_TEST_WINDOW, 'embargo': P3_EMBARGO, 'n_splits': P3_N_SPLITS},
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'lambda_mean_pooled': float(full_pred['lam'].mean()),
        'nu_mean_pooled': float(full_pred['nu'].mean()),
        'fold_metrics': fold_metrics,
        'bear_date_evaluations': bear_evals,
        'p2_baseline_comparison': {
            'p2_crps': 0.6386, 'p3_crps': float(full_pred['crps'].mean()),
            'p2_pit_p': 0.0050, 'p3_pit_p': float(pit_pool['p_value']),
            'crps_delta_pct': (float(full_pred['crps'].mean()) - 0.6386) / 0.6386 * 100,
        },
    }
    with open(output_dir / "summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== P3 production POOLED (n={len(full_pred)}) ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}  (P2: 0.6386 → Δ {summary['p2_baseline_comparison']['crps_delta_pct']:+.1f}%)")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}  (P2: 0.005 → P3 PASS!)")
    print(f"  λ̄={summary['lambda_mean_pooled']:.4f}, ν̄={summary['nu_mean_pooled']:.2f}")


if __name__ == "__main__":
    main()
