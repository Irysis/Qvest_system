"""
480_p2_hparam_sweep.py — P2 hyperparameter sweep

도훈 mandate 2026-05-26: P2 baseline CRPS=0.6386 대비 개선 가능한 hyperparam 탐색.

Sweep dimensions:
1. alpha_l1 (LASSO L1 penalty): {1e-5, 1e-4, 5e-4, 1e-3, 5e-3, 1e-2, 5e-2}
2. taus density: 11 (default) vs 21 (dense)
3. train_min: 1008 (default) vs 1512 vs 2520

Total combos: 7 × 2 × 3 = 42 (각 ~30s) → ~20 min full sweep.

Output: 03_models/p2_hparam_sweep/sweep_summary.json
"""
from __future__ import annotations
import argparse
import importlib.util
import itertools
import json
import os
import sys
import time
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


TAUS_11 = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
TAUS_21 = (0.005, 0.01, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20, 0.25, 0.40,
           0.50, 0.60, 0.75, 0.80, 0.85, 0.90, 0.925, 0.95, 0.975, 0.99, 0.995)


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def run_one_config(X, y, dates, taus, alpha_l1, n_splits, train_min, test_window, embargo, seed):
    """Run one hyperparam config, return pooled metrics."""
    np.random.seed(seed)
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits, train_min=train_min, test_size=test_window, embargo=embargo,
    )
    taus_np = np.array(taus)
    all_preds = []
    fold_crps = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]

        model = LQM.LassoQuantileGaR(taus=taus, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)

        sst = HSK.derive_metrics_per_obs(Q_te, taus_np)
        pit = HSK.pit_per_obs(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['lam'])

        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 300  # reduced for sweep speed
        for i in range(N):
            u = np.random.uniform(0, 1, n_samples)
            samples = HSK.hansen_quantile(u, sst['mu'][i], sst['sigma'][i], sst['nu'][i], sst['lam'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(n_samples)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx
        fold_crps.append(crps_per.mean())

        all_preds.append(pd.DataFrame({
            'y_actual': y_te, 'crps': crps_per, 'pit': pit,
            'var_05': sst['var_05'], 'var_01': sst['var_01'], 'es_05': sst['es_05'],
        }))

    full = pd.concat(all_preds, ignore_index=True)
    var05_bt = VARBT.var_backtest_full(full['y_actual'].values, full['var_05'].values, alpha=0.05,
                                        es_forecasts=full['es_05'].values)
    var01_bt = VARBT.var_backtest_full(full['y_actual'].values, full['var_01'].values, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(full['pit'].values, n_bins=10)

    return {
        'crps_pooled': float(full['crps'].mean()),
        'crps_fold_std': float(np.std(fold_crps)),
        'breach_05_pct': float((full['y_actual'] < full['var_05']).mean() * 100),
        'breach_01_pct': float((full['y_actual'] < full['var_01']).mean() * 100),
        'kupiec_05_p': float(var05_bt['kupiec_uc']['p_value']),
        'kupiec_05_pass': bool(var05_bt['kupiec_uc']['pass_at_005']),
        'kupiec_01_p': float(var01_bt['kupiec_uc']['p_value']),
        'kupiec_01_pass': bool(var01_bt['kupiec_uc']['pass_at_005']),
        'pit_chi_p': float(pit_chi['p_value']),
        'pit_chi_pass': bool(pit_chi['pass_at_005']),
        'var_diff_avg': float(np.abs(full['var_05'] - full['var_01']).mean()),
        'n_test': len(full),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p2_hparam_sweep')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)

    df, feature_cols = P472.load_data(cfg)
    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    dates = df['Date'].values
    print(f"[sweep] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")

    # Sweep space
    alpha_list = [1e-5, 1e-4, 5e-4, 1e-3, 5e-3, 1e-2, 5e-2]
    taus_list = [('11', TAUS_11), ('21', TAUS_21)]
    train_min_list = [1008, 1512, 2520]

    cv_default = cfg.get('walk_forward', {})
    n_splits = cv_default.get('n_splits', 12)
    test_window = cv_default.get('test_window', 504)
    embargo = cv_default.get('embargo', 21)

    results = []
    combos = list(itertools.product(alpha_list, taus_list, train_min_list))
    print(f"[sweep] total combos: {len(combos)}")
    print(f"\n{'#':<4} {'α':<8} {'τ':<4} {'tmin':<5} {'CRPS':<8} {'breach5':<8} {'breach1':<8} {'kup5p':<8} {'kup1p':<8} {'pit_p':<8} {'time':<6}")

    for i, (alpha, (tau_name, taus), tmin) in enumerate(combos):
        if tmin >= len(X) - 100:
            continue
        try:
            n_splits_eff = max(1, min(n_splits, (len(X) - tmin) // test_window - 1))
            t0 = time.time()
            r = run_one_config(X, y, dates, taus, alpha, n_splits_eff, tmin, test_window, embargo, args.seed)
            r.update({'alpha': alpha, 'taus_name': tau_name, 'taus_count': len(taus),
                      'train_min': tmin, 'n_splits_eff': n_splits_eff, 'time_sec': time.time() - t0})
            results.append(r)
            print(f"{i:<4} {alpha:<8.0e} {tau_name:<4} {tmin:<5} "
                  f"{r['crps_pooled']:<8.5f} {r['breach_05_pct']:<8.2f} {r['breach_01_pct']:<8.2f} "
                  f"{r['kupiec_05_p']:<8.4f} {r['kupiec_01_p']:<8.4f} {r['pit_chi_p']:<8.4f} {r['time_sec']:<6.1f}")
        except Exception as e:
            print(f"{i:<4} {alpha:<8.0e} {tau_name:<4} {tmin:<5}  FAIL: {e}")
            continue

    # Sort by CRPS
    results_sorted = sorted(results, key=lambda r: r['crps_pooled'])
    print(f"\n=== TOP 10 by CRPS ===")
    print(f"{'rank':<4} {'α':<8} {'τ':<4} {'tmin':<5} {'CRPS':<8} {'kup5p':<8} {'kup1p':<8} {'pit_p':<8}")
    for rk, r in enumerate(results_sorted[:10], 1):
        print(f"{rk:<4} {r['alpha']:<8.0e} {r['taus_name']:<4} {r['train_min']:<5} "
              f"{r['crps_pooled']:<8.5f} {r['kupiec_05_p']:<8.4f} {r['kupiec_01_p']:<8.4f} {r['pit_chi_p']:<8.4f}")

    # Production-grade subset: VaR 둘 다 PASS + PIT 가능한 가장 높은 p
    prod = [r for r in results if r['kupiec_05_pass'] and r['kupiec_01_pass']]
    prod_sorted = sorted(prod, key=lambda r: (r['pit_chi_p'], -r['crps_pooled']), reverse=True)
    print(f"\n=== Production-ready (VaR 둘 다 PASS), sorted by PIT_p desc → CRPS asc ===")
    for r in prod_sorted[:10]:
        print(f"  α={r['alpha']:.0e}  τ={r['taus_name']}  tmin={r['train_min']}  "
              f"CRPS={r['crps_pooled']:.5f}  kup5_p={r['kupiec_05_p']:.4f} kup1_p={r['kupiec_01_p']:.4f} pit_p={r['pit_chi_p']:.4f}")

    # Save
    out = {
        'sweep_dim': {'alpha': alpha_list,
                      'taus': [t[0] for t in taus_list],
                      'train_min': train_min_list},
        'p2_baseline': {'alpha': 1e-3, 'taus': '11', 'train_min': 1008,
                        'crps': 0.6386, 'kupiec_05_p': 0.9469, 'kupiec_01_p': 0.8261, 'pit_p': 0.0050},
        'all_results': results,
        'top10_by_crps': results_sorted[:10],
        'top10_production_ready': prod_sorted[:10],
    }
    with open(output_dir / "sweep_summary.json", 'w') as f:
        json.dump(out, f, indent=2, default=_json_default)
    print(f"\n[saved] {output_dir / 'sweep_summary.json'}")


if __name__ == "__main__":
    main()
