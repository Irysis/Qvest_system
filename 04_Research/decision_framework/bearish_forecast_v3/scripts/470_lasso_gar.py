"""
470_lasso_gar.py — Phase 5c LASSO Quantile GaR training entry

도훈 mandate 2026-05-24: Phase 5c LASSO Quantile + Tier 3 Linear Pool

Reference:
- Adrian-Boyarchenko-Giannone 2019 AER "Vulnerable Growth"
- Koenker-Bassett 1978 Econometrica

Setup:
- Target: KOSPI200 1-day forward log return (paper horizon) or 21d (v3 use)
- Features:
  (1) KR NFCI proxy components (KOSPI realized vol + drawdown + BBVA macro composite + K200 implied skew + US sector dispersion)
  (2) Lagged returns + rolling statistics (from B5 feature set)
- Walk-forward purged CV (Lopez de Prado 2018, embargo 21d)
- Output: per-fold quantile forecasts + pinball loss + VaR backtest

Outputs:
- 03_models/a1_lasso_gar/{config_tag}/fold_{k}_predictions.parquet
- 04_evaluation/a1_lasso_gar_metrics.json
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


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LQM = _load_module("a1_lasso_quantile", str(ROOT / "03_models" / "a1_lasso_quantile.py"))
METRICS = _load_module("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load_module("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load_module("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load_module("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))


def _json_default(obj):
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        return float(obj)
    if isinstance(obj, (np.ndarray,)):
        return obj.tolist()
    raise TypeError(f"Object of type {type(obj).__name__} not JSON serializable")


# ─── Data + feature engineering ────────────────────────────────────────────
def load_kospi_with_alt(cfg: dict) -> pd.DataFrame:
    """Load KOSPI200 daily + KR NFCI proxy components + v2 alt features.

    Features assembled:
    (A) KR NFCI proxy (rv_22d, dd_z, BBVA macro, K200 implied skew, US sector dispersion)
    (B) Lagged returns t-1, t-2, t-5, t-22
    (C) Rolling volatility 5d, 22d, 60d
    (D) Rolling mean 5d, 22d, 60d
    """
    bm_path = PROJECT_ROOT / cfg['data']['bm_path']
    bm = pd.read_parquet(bm_path)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    bm['log_ret'] = np.log(bm['BM_Close']).diff()

    # (B) Lagged returns
    for lag in [1, 2, 5, 22]:
        bm[f'log_ret_lag_{lag}'] = bm['log_ret'].shift(lag)

    # (C) Rolling volatility
    for w in [5, 22, 60]:
        bm[f'rv_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()

    # (D) Rolling mean
    for w in [5, 22, 60]:
        bm[f'mean_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()

    # (A.1) NFCI proxy components (computed inline for PIT safety)
    eps = 1e-8
    cum_max = bm['BM_Close'].cummax()
    bm['drawdown'] = (bm['BM_Close'] - cum_max) / (cum_max + eps)

    # Expanding z-score (PIT-safe)
    def expanding_z(s: pd.Series, min_periods: int = 60) -> pd.Series:
        mu = s.expanding(min_periods=min_periods).mean()
        sd = s.expanding(min_periods=min_periods).std() + eps
        return (s - mu) / sd

    bm['rv_22d_z'] = expanding_z(bm['rv_22d'])
    bm['drawdown_z'] = expanding_z(bm['drawdown'])

    # (A.2) Merge v2 alt features (BBVA + K200 implied + US sector)
    alt_path = PROJECT_ROOT / cfg['data']['alt_features_path']
    if alt_path.exists():
        alt = pd.read_parquet(alt_path)
        alt['Date'] = pd.to_datetime(alt['Date'])
        bm = bm.merge(alt, on='Date', how='left')
    else:
        print(f"[lasso_gar] alt features NOT FOUND at {alt_path} — skip alt data merge")

    # Forward target
    horizon_mode = cfg['data'].get('horizon', 'paper')
    h = 1 if horizon_mode == 'paper' else 21
    bm['ret_fwd'] = np.log(bm['BM_Close'].shift(-h) / bm['BM_Close'])

    # Date filter
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    bm = bm[(bm['Date'] >= date_start) & (bm['Date'] <= date_end)].reset_index(drop=True)

    # Percent scale on returns + RV
    if cfg['data'].get('percent_scale', True):
        for c in bm.columns:
            if c.startswith(('log_ret', 'rv_', 'mean_', 'ret_fwd', 'drawdown')) and not c.endswith('_z'):
                bm[c] = bm[c] * 100.0

    return bm


def build_feature_matrix(df: pd.DataFrame, cfg: dict) -> tuple:
    """Select feature columns according to feature_set config + drop NaN rows."""
    feature_set = cfg.get('feature_set', 'core')
    if feature_set == 'core':
        feature_cols = [
            'log_ret_lag_1', 'log_ret_lag_2', 'log_ret_lag_5', 'log_ret_lag_22',
            'rv_5d', 'rv_22d', 'rv_60d',
            'mean_5d', 'mean_22d', 'mean_60d',
            'rv_22d_z', 'drawdown_z',
        ]
    elif feature_set == 'full':
        feature_cols = [
            'log_ret_lag_1', 'log_ret_lag_2', 'log_ret_lag_5', 'log_ret_lag_22',
            'rv_5d', 'rv_22d', 'rv_60d',
            'mean_5d', 'mean_22d', 'mean_60d',
            'rv_22d_z', 'drawdown_z',
            # v2 alt 8
            'bbva_market_z', 'bbva_sovereign_z', 'bbva_transmission_z', 'bbva_macro_composite',
            'k200_implied_skew_z', 'k200_implied_kurt_z',
            'us_sector_avg_z', 'us_sector_dispersion_z',
        ]
    else:
        raise ValueError(f"Unknown feature_set: {feature_set}")

    # Keep only columns present + drop NaN
    available = [c for c in feature_cols if c in df.columns]
    missing = [c for c in feature_cols if c not in df.columns]
    if missing:
        print(f"[lasso_gar] missing features (dropped): {missing}")
    df_clean = df.dropna(subset=available + ['ret_fwd']).reset_index(drop=True)
    X = df_clean[available].values.astype(np.float64)
    y = df_clean['ret_fwd'].values.astype(np.float64)
    dates = df_clean['Date'].values
    return X, y, dates, available


# ─── Walk-forward training ─────────────────────────────────────────────────
def train_eval_one_fold(
    X_train, y_train, X_test, y_test,
    taus, alpha_l1,
    feature_names,
) -> dict:
    """Fit LassoQuantileGaR on train, evaluate on test."""
    model = LQM.LassoQuantileGaR(taus=taus, alpha=alpha_l1, standardize=True)
    model.fit(X_train, y_train, feature_names=feature_names)

    # Multi-quantile predictions on test
    Q_test = model.predict_all_quantiles(X_test, fix_crossing=True)

    # VaR 5% and 1%
    var_05 = model.predict_var(X_test, alpha=0.05)
    var_01 = model.predict_var(X_test, alpha=0.01)
    es_05 = model.predict_es(X_test, alpha=0.05, n_grid=30)

    # Pinball loss per τ
    pinball_per_tau = {}
    for tau in taus:
        q_t = model.predict_quantile(X_test, tau)
        pinball_per_tau[tau] = float(np.mean(METRICS.pinball_loss(q_t, y_test, tau)))

    # Skewed-t Normal approximation density → CRPS via empirical quantile rank
    # For Phase 5c MVP, use mean Pinball loss as proxy for distributional fit quality.

    # VaR backtest
    var_05_bt = VARBT.var_backtest_full(y_test, var_05, alpha=0.05, es_forecasts=es_05)
    var_01_bt = VARBT.var_backtest_full(y_test, var_01, alpha=0.01)

    # Empirical CDF for PIT (using fitted quantiles + interpolation)
    pit = np.zeros(len(y_test))
    sorted_taus = np.array(sorted(taus))
    for i in range(len(y_test)):
        Q_i = np.sort(Q_test[i])
        rank = np.searchsorted(Q_i, y_test[i])
        if rank == 0:
            pit[i] = 0.0
        elif rank == len(Q_i):
            pit[i] = 1.0
        else:
            # Linear interp between adjacent τ values
            lo_q, hi_q = Q_i[rank - 1], Q_i[rank]
            lo_t, hi_t = sorted_taus[rank - 1], sorted_taus[rank]
            if hi_q > lo_q:
                w = (y_test[i] - lo_q) / (hi_q - lo_q)
                pit[i] = lo_t + w * (hi_t - lo_t)
            else:
                pit[i] = (lo_t + hi_t) / 2

    pit_chi = CALIB.pit_chi_square(pit, n_bins=10)

    # Feature importance per τ
    importance = {tau: model.feature_importance(tau).tolist() for tau in taus}
    n_nonzero = {tau: int(model.n_nonzero_features(tau, threshold=1e-6)) for tau in taus}

    return {
        'var_05_forecasts': var_05,
        'var_01_forecasts': var_01,
        'es_05_forecasts': es_05,
        'pinball_per_tau': pinball_per_tau,
        'pinball_mean': float(np.mean(list(pinball_per_tau.values()))),
        'var_05_backtest': var_05_bt,
        'var_01_backtest': var_01_bt,
        'pit_chi_square': pit_chi,
        'pit_values': pit,
        'n_nonzero_features_per_tau': n_nonzero,
        'feature_importance_per_tau': importance,
    }


def run_lasso_gar(cfg_path: str, alpha_grid: list, feature_set: str, output_dir: str, seed: int = 0):
    """Phase 5c entry: walk-forward LASSO quantile fit + eval."""
    with open(cfg_path, 'r') as f:
        cfg = yaml.safe_load(f)
    cfg['feature_set'] = feature_set
    print("[lasso_gar] config loaded")

    df = load_kospi_with_alt(cfg)
    horizon = cfg['data'].get('horizon', 'paper')
    pct = cfg['data'].get('percent_scale', True)
    print(f"[lasso_gar] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()}) horizon={horizon} percent_scale={pct}")

    X, y, dates, feature_names = build_feature_matrix(df, cfg)
    print(f"[lasso_gar] X={X.shape} y={y.shape} | feature_set={feature_set} ({len(feature_names)} features)")
    print(f"  features: {feature_names}")

    cv_cfg = cfg.get('walk_forward', {})
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=cv_cfg.get('n_splits', 5),
        train_min=cv_cfg.get('train_min', 1008),
        test_size=cv_cfg.get('test_window', 504),
        embargo=cv_cfg.get('embargo', 21),
    )
    sanity = CVMOD.sanity_check_cv(splitter, X)
    print(f"[lasso_gar] CV sanity: {sanity}")

    os.makedirs(output_dir, exist_ok=True)
    taus = LQM.DEFAULT_TAUS

    all_results = {}
    for alpha_l1 in alpha_grid:
        tag = f"alpha_{alpha_l1}"
        print(f"\n[lasso_gar] ====== {tag} ======")
        sub_dir = Path(output_dir) / tag
        sub_dir.mkdir(parents=True, exist_ok=True)

        fold_metrics = []
        all_test_preds = []
        for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
            X_tr, y_tr = X[tr_idx], y[tr_idx]
            X_te, y_te = X[te_idx], y[te_idx]
            dates_te = dates[te_idx]

            try:
                result = train_eval_one_fold(
                    X_tr, y_tr, X_te, y_te,
                    taus=taus, alpha_l1=alpha_l1,
                    feature_names=feature_names,
                )
            except Exception as e:
                print(f"  fold[{fold_idx}] FAILED: {e}")
                continue

            fold_metrics.append({
                'fold': fold_idx,
                'pinball_mean': result['pinball_mean'],
                'pinball_per_tau': result['pinball_per_tau'],
                'n_obs': len(y_te),
                'var_05_kupiec_pass': result['var_05_backtest']['kupiec_uc']['pass_at_005'],
                'var_05_cc_pass': result['var_05_backtest']['christoffersen_cc']['pass_at_005'],
                'var_01_kupiec_pass': result['var_01_backtest']['kupiec_uc']['pass_at_005'],
                'pit_chi_pass': result['pit_chi_square']['pass_at_005'],
                'n_nonzero_05': result['n_nonzero_features_per_tau'][0.05],
                'n_nonzero_50': result['n_nonzero_features_per_tau'][0.50],
            })

            pred_df = pd.DataFrame({
                'Date': pd.to_datetime(dates_te),
                'y_actual': y_te,
                'var_05': result['var_05_forecasts'],
                'var_01': result['var_01_forecasts'],
                'es_05': result['es_05_forecasts'],
                'pit': result['pit_values'],
            })
            pred_df.to_parquet(sub_dir / f"fold_{fold_idx:02d}_predictions.parquet")
            all_test_preds.append(pred_df)

            print(f"  fold[{fold_idx}] Pinball={result['pinball_mean']:.5f} "
                  f"VaR_05_kupiec={result['var_05_backtest']['kupiec_uc']['pass_at_005']} "
                  f"VaR_05_cc={result['var_05_backtest']['christoffersen_cc']['pass_at_005']} "
                  f"PIT_chi={result['pit_chi_square']['pass_at_005']} "
                  f"nz(0.05)={result['n_nonzero_features_per_tau'][0.05]} "
                  f"nz(0.50)={result['n_nonzero_features_per_tau'][0.50]}")

        if all_test_preds:
            full_pred = pd.concat(all_test_preds, ignore_index=True)
            full_pred.to_parquet(sub_dir / "all_predictions.parquet")

            var_05_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                es_forecasts=full_pred['es_05'].values,
            )
            var_01_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01,
            )
            pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

            # Pooled pinball — recompute per τ averaging fold-level
            pinball_pool = {}
            for tau in taus:
                vals = [fm['pinball_per_tau'].get(tau) for fm in fold_metrics if fm.get('pinball_per_tau')]
                pinball_pool[float(tau)] = float(np.mean([v for v in vals if v is not None]))

            all_results[tag] = {
                'config': {
                    'alpha_l1': alpha_l1,
                    'feature_set': feature_set,
                    'n_features': len(feature_names),
                    'feature_names': feature_names,
                    'taus': list(taus),
                },
                'n_test_obs_total': int(len(full_pred)),
                'pinball_pooled': pinball_pool,
                'pinball_pooled_mean': float(np.mean(list(pinball_pool.values()))),
                'var_05_backtest_pooled': var_05_pool,
                'var_01_backtest_pooled': var_01_pool,
                'pit_chi_square_pooled': pit_pool,
                'fold_metrics': fold_metrics,
            }
            print(f"[{tag}] POOLED: Pinball mean={all_results[tag]['pinball_pooled_mean']:.5f} "
                  f"VaR_05 kupiec={var_05_pool['kupiec_uc']['pass_at_005']} "
                  f"cc={var_05_pool['christoffersen_cc']['pass_at_005']} n={len(full_pred)}")

    metrics_path = Path(output_dir) / "a1_lasso_gar_metrics.json"
    with open(metrics_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[lasso_gar] aggregate metrics saved: {metrics_path}")

    # Top configs by pinball mean
    print("\n" + "=" * 64)
    print("TOP configs (by pooled Pinball mean):")
    print("=" * 64)
    valid = [(tag, r) for tag, r in all_results.items() if r.get('pinball_pooled_mean') is not None]
    valid.sort(key=lambda x: x[1]['pinball_pooled_mean'])
    for i, (tag, r) in enumerate(valid[:5]):
        print(f"#{i+1} {tag} | Pinball={r['pinball_pooled_mean']:.5f} | "
              f"VaR_05_kupiec={r['var_05_backtest_pooled']['kupiec_uc']['pass_at_005']} "
              f"VaR_05_cc={r['var_05_backtest_pooled']['christoffersen_cc']['pass_at_005']}")

    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_gar.yaml')
    parser.add_argument('--output', type=str, default='03_models/a1_lasso_gar')
    parser.add_argument('--feature_set', type=str, default='full',
                        help='core (12 features) | full (20 incl v2 alt)')
    parser.add_argument('--alpha_grid', type=str, default='0.0001,0.001,0.01,0.1',
                        help='comma-separated L1 alpha values')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    alpha_grid = [float(a) for a in args.alpha_grid.split(',')]

    print(f"[lasso_gar] CFG: {cfg_path}")
    print(f"[lasso_gar] OUT: {output_dir}")
    print(f"[lasso_gar] feature_set: {args.feature_set} alpha_grid: {alpha_grid}")

    run_lasso_gar(
        cfg_path=str(cfg_path),
        alpha_grid=alpha_grid,
        feature_set=args.feature_set,
        output_dir=str(output_dir),
        seed=args.seed,
    )


if __name__ == "__main__":
    main()
