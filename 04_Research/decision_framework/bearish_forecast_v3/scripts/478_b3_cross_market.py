"""
478_b3_cross_market.py — B.3 Cross-market features (PIT-safe)

도훈 mandate 2026-05-26 B.3: P2 + cross-market features.

Cross-market features (lag 1 day for PIT compliance):
- KRW_USD: 1-day return + 5-day return (FX shock)
- VIX: level + 5-day change (US implied vol)
- Term_Spread (10Y-2Y): level (yield curve)
- HY_Spread: level (credit spread)
- StL_Fin_Stress: level (financial stress)

Total: 12 base + 7 cross-market = 19 features.

PIT: all cross-market data lagged by 1 day relative to KOSPI prediction.
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


P_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def load_cross_market_features(df_dates):
    """Build cross-market feature panel for given KOSPI dates (lag=1 for PIT)."""
    fred = pd.read_parquet(PROJECT_ROOT / ".cache" / "fred_macro.parquet")
    fred['Date'] = pd.to_datetime(fred['Date'])

    # HY_Spread, BBB_Spread는 2023+만 있어서 제외 (long history 부재)
    series_to_load = ['KRW_USD', 'VIX', 'Term_Spread', 'StL_Fin_Stress']
    wide = {}
    for s in series_to_load:
        sub = fred[fred['Series'] == s][['Date', 'Value']].copy()
        sub = sub.rename(columns={'Value': s})
        if len(sub) == 0:
            wide[s] = None
            continue
        sub = sub.drop_duplicates('Date').sort_values('Date')
        wide[s] = sub

    # Build a daily DataFrame with lag-1 values
    out = pd.DataFrame({'Date': df_dates})
    out['Date'] = pd.to_datetime(out['Date'])

    for s, sub in wide.items():
        if sub is None:
            out[f'{s}_lag1'] = np.nan
            continue
        # forward fill to daily then lag 1
        all_dates = pd.date_range(sub['Date'].min(), sub['Date'].max(), freq='D')
        full = pd.DataFrame({'Date': all_dates}).merge(sub, on='Date', how='left').ffill()
        full[f'{s}_lag1'] = full[s].shift(1)  # lag 1 day for PIT
        out = out.merge(full[['Date', f'{s}_lag1']], on='Date', how='left')

    # Derived features
    out['KRW_USD_ret1_lag1'] = out['KRW_USD_lag1'].pct_change(1)
    out['KRW_USD_ret5_lag1'] = out['KRW_USD_lag1'].pct_change(5)
    out['VIX_chg5_lag1'] = out['VIX_lag1'].diff(5)

    return out


def load_data_with_cross_market(cfg):
    """Base 12 features + 7 cross-market lag-1 features."""
    df_base, base_features = P472.load_data(cfg)
    cm_df = load_cross_market_features(df_base['Date'].values)
    cm_features = [
        'KRW_USD_lag1', 'KRW_USD_ret1_lag1', 'KRW_USD_ret5_lag1',
        'VIX_lag1', 'VIX_chg5_lag1',
        'Term_Spread_lag1', 'StL_Fin_Stress_lag1',
    ]
    merged = df_base.merge(cm_df[['Date'] + cm_features], on='Date', how='left')
    n_before = len(merged)
    merged = merged.dropna(subset=cm_features).reset_index(drop=True)
    n_after = len(merged)
    print(f"  cross-market features merged: dropped {n_before - n_after} rows (cm NaN)")
    return merged, base_features, cm_features


def run(cfg_path, output_dir, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df, base_features, cm_features = load_data_with_cross_market(cfg)
    all_features = base_features + cm_features
    print(f"[B.3 cross-market] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")
    print(f"  features: {len(base_features)} base + {len(cm_features)} cross-market = {len(all_features)} total")

    X = df[all_features].values.astype(np.float64)
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
    taus_np = np.array(P_TAUS)
    all_preds = []
    fold_metrics = []

    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        dates_te = dates[te_idx]

        model = LQM.LassoQuantileGaR(taus=P_TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr, feature_names=all_features)
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
              f"PIT_p={pit_chi['p_value']:.4f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    summary = {
        'method': 'B.3 P2 Hansen + 8 cross-market features (lag 1, PIT-safe)',
        'features_total': len(all_features),
        'cm_features': cm_features,
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'lambda_mean_pooled': float(full_pred['lam'].mean()),
        'nu_mean_pooled': float(full_pred['nu'].mean()),
        'fold_metrics': fold_metrics,
    }
    with open(Path(output_dir) / "summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== B.3 (P2 + cross-market) POOLED ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}  (P2: 0.63863)")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}  (P2: 0.0050)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/b3_cross_market')
    parser.add_argument('--alpha', type=float, default=0.001)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    print(f"[B.3] CFG: {cfg_path}")
    print(f"[B.3] OUT: {output_dir}")
    run(str(cfg_path), str(output_dir), alpha_l1=args.alpha, seed=args.seed)


if __name__ == "__main__":
    main()
