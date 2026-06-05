"""
474_p1_patch_v3_full.py — P1 patch v3-full: Fernandez-Steel 1998 (L-BFGS-B)

도훈 mandate 2026-05-26 옵션 1: Fernandez-Steel 1998 skewed-t,
L-BFGS-B + CDF-matching (Nelder-Mead + brentq 대비 ~100x faster).

Pipeline:
1. LASSO Quantile fit 11 taus
2. Per-obs FS skewed-t fit via L-BFGS-B (4 params μ, σ, ν, ξ)
3. Distinct VaR_05, VaR_01, VaR_005, VaR_001 from closed-form quantile
4. P(-X%) from closed-form CDF
5. PIT = F_FS(y_actual; μ_t, σ_t, ν_t, ξ_t)
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
FS = _load("p1_fs_skewt_fast", str(ROOT / "03_models" / "p1_fs_skewt_fast.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))
P472 = _load("p1_patch_v2", str(ROOT / "scripts" / "472_p1_patch_v2.py"))


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


def run(cfg_path, output_dir, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df, feature_cols = P472.load_data(cfg)
    print(f"[v3-full] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")

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

    os.makedirs(output_dir, exist_ok=True)
    taus_np = np.array(P1_TAUS)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P1_TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr, feature_names=feature_cols)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)

        print(f"  fold[{fold_idx}] Fernandez-Steel fit to {len(y_te)} obs...")
        sst = FS.derive_metrics_per_obs(Q_te, taus_np)
        pit = FS.pit_per_obs(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['xi'])

        # CRPS via skewed-t samples
        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 500
        for i in range(N):
            u = np.random.uniform(0, 1, n_samples)
            samples = FS.fs_quantile(u, sst['mu'][i], sst['sigma'][i], sst['nu'][i], sst['xi'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(n_samples)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(dates_te),
            'y_actual': y_te,
            'crps': crps_per,
            'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'], 'nu': sst['nu'], 'xi': sst['xi'],
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
            'var_05_diff_01_mean_abs': float(np.abs(sst['var_05'] - sst['var_01']).mean()),
            'xi_mean': float(sst['xi'].mean()),
            'nu_mean': float(sst['nu'].mean()),
        })
        print(f"  fold[{fold_idx}] CRPS={crps_per.mean():.5f} "
              f"VaR_05_kupiec={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kupiec={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"|var_05-var_01|={float(np.abs(sst['var_05']-sst['var_01']).mean()):.4f} "
              f"ξ̄={sst['xi'].mean():.3f} ν̄={sst['nu'].mean():.2f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
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
        'method': 'v3-full Fernandez-Steel 1998 (L-BFGS-B)',
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'xi_mean_pooled': float(full_pred['xi'].mean()),
        'nu_mean_pooled': float(full_pred['nu'].mean()),
        'fold_metrics': fold_metrics,
        'bear_date_evaluations': bear_evals,
        'bear_probabilities_summary': {
            'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
            'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
            'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
            'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
        },
    }
    with open(Path(output_dir) / "p1_patch_v3_full_summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== P1 PATCH v3-FULL (Fernandez-Steel) POOLED ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}")
    print(f"  |var_05 - var_01| avg = {summary['var_05_diff_var_01_mean_abs_pooled']:.4f}")
    print(f"  ξ̄ = {summary['xi_mean_pooled']:.4f}  ν̄ = {summary['nu_mean_pooled']:.2f}")
    print(f"  P(-10%) max = {summary['bear_probabilities_summary']['p_minus_10pct_max']*100:.3f}%")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p1_patch_v3_full')
    parser.add_argument('--alpha', type=float, default=0.001)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    print(f"[v3-full] CFG: {cfg_path}")
    print(f"[v3-full] OUT: {output_dir}")
    run(str(cfg_path), str(output_dir), alpha_l1=args.alpha, seed=args.seed)


if __name__ == "__main__":
    main()
