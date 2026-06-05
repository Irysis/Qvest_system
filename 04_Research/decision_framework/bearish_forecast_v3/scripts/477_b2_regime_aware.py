"""
477_b2_regime_aware.py — B.2 Regime-aware Hansen (Markov 2-state hybrid)

도훈 mandate 2026-05-26 B.2: P2 + Markov regime probability as 13th feature.

Approach (parsimonious):
1. Per walk-forward fold, fit Markov 2-state on training log returns
2. Compute regime_prob_high_vol for entire fold range (train + test)
3. Add as 13th feature to LASSO Quantile
4. Hansen fit identical to P2
5. Evaluate vs P2 baseline

If improvement marginal/none → try full separate-per-state mixture in B.2.2.
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


def fit_markov_2state(y_train):
    """Fit Markov 2-state regression on log returns. Return regime probabilities for [0..T-1].

    Returns: (regime_high_vol_prob, regime_means, regime_stds, fit_result_or_None)
    """
    from statsmodels.tsa.regime_switching.markov_regression import MarkovRegression
    model = MarkovRegression(y_train, k_regimes=2, switching_variance=True, trend='c')
    try:
        res = model.fit(disp=False, maxiter=200)
    except Exception:
        # fallback: try different starting params
        try:
            res = model.fit(disp=False, search_reps=3, maxiter=300)
        except Exception:
            # ultimate fallback: equal probs
            T = len(y_train)
            return np.full(T, 0.5), [0.0, 0.0], [1.0, 1.0], None

    smoothed = np.asarray(res.smoothed_marginal_probabilities)
    if smoothed.ndim != 2:
        T = len(y_train)
        return np.full(T, 0.5), [0.0, 0.0], [1.0, 1.0], None

    # Identify "high vol" regime as the one with higher variance
    try:
        param_names = list(res.model.param_names)
        # variances: 'sigma2[0]', 'sigma2[1]'
        sigma2_0 = None; sigma2_1 = None; const_0 = None; const_1 = None
        for i, p in enumerate(param_names):
            if p == 'sigma2[0]': sigma2_0 = res.params[i]
            elif p == 'sigma2[1]': sigma2_1 = res.params[i]
            elif p == 'const[0]': const_0 = res.params[i]
            elif p == 'const[1]': const_1 = res.params[i]
        if sigma2_0 is None or sigma2_1 is None:
            high_vol_idx = 0
        else:
            high_vol_idx = 1 if sigma2_1 > sigma2_0 else 0
        regime_means = [const_0 or 0.0, const_1 or 0.0]
        regime_stds = [float(np.sqrt(sigma2_0 or 1.0)), float(np.sqrt(sigma2_1 or 1.0))]
    except Exception:
        high_vol_idx = 0
        regime_means = [0.0, 0.0]
        regime_stds = [1.0, 1.0]

    regime_high_vol_prob = smoothed[:, high_vol_idx]
    return regime_high_vol_prob, regime_means, regime_stds, res


def predict_regime_oos(res, T_extra):
    """One-step-ahead regime probability for OOS test set.

    Use last filtered prob × transition matrix^k.
    """
    try:
        filtered = np.asarray(res.filtered_marginal_probabilities)
        # transition matrix
        trans = res.regime_transition
        if trans.ndim == 3:
            P = trans[:, :, 0]  # time-invariant case
        else:
            P = trans
        last_prob = filtered[-1, :]  # (2,)
        # iterate k-step ahead
        out = np.zeros((T_extra, 2))
        prob = last_prob.copy()
        for k in range(T_extra):
            prob = P.T @ prob  # forward one step
            out[k, :] = prob
        return out
    except Exception:
        return np.full((T_extra, 2), 0.5)


def run(cfg_path, output_dir, alpha_l1=0.001, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df, feature_cols = P472.load_data(cfg)
    print(f"[B.2 regime] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_fwd'].values.astype(np.float64)
    log_ret_series = df['log_ret'].values.astype(np.float64)
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

        # ─── Fit Markov 2-state on training log returns ─────────────────
        print(f"  fold[{fold_idx}] fitting Markov 2-state (n={len(tr_idx)})...")
        try:
            regime_high_vol_train, regime_means, regime_stds, res = fit_markov_2state(log_ret_series[tr_idx])
            if res is None:
                regime_high_vol_test = np.full(len(te_idx), 0.5)
                markov_ok = False
            else:
                regime_oos = predict_regime_oos(res, len(te_idx))
                # Determine which column corresponds to high vol
                try:
                    param_names = list(res.model.param_names)
                    sigma2_idx = {}
                    for i, p in enumerate(param_names):
                        if p.startswith('sigma2['):
                            idx = int(p[7:-1])
                            sigma2_idx[idx] = float(res.params[i])
                    if sigma2_idx:
                        high_vol_idx = max(sigma2_idx, key=lambda k: sigma2_idx[k])
                    else:
                        high_vol_idx = 0
                except Exception:
                    high_vol_idx = 0
                regime_high_vol_test = regime_oos[:, high_vol_idx]
                markov_ok = True
        except Exception as e:
            print(f"    [WARN] Markov fit failed: {e}. Using 0.5 fallback.")
            regime_high_vol_train = np.full(len(tr_idx), 0.5)
            regime_high_vol_test = np.full(len(te_idx), 0.5)
            regime_means = [0.0, 0.0]; regime_stds = [1.0, 1.0]
            markov_ok = False

        # ─── Augment features ───────────────────────────────────────────
        X_tr_aug = np.column_stack([X_tr, regime_high_vol_train])
        X_te_aug = np.column_stack([X_te, regime_high_vol_test])
        feat_aug = feature_cols + ['regime_high_vol_prob']

        # ─── LASSO Quantile fit ─────────────────────────────────────────
        model = LQM.LassoQuantileGaR(taus=P_TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr_aug, y_tr, feature_names=feat_aug)
        Q_te = model.predict_all_quantiles(X_te_aug, fix_crossing=True)

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
            'regime_high_vol_prob': regime_high_vol_test,
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
            'markov_ok': markov_ok,
            'regime_means': regime_means,
            'regime_stds': regime_stds,
            'regime_high_vol_mean_test': float(regime_high_vol_test.mean()),
        })
        print(f"  fold[{fold_idx}] CRPS={crps_per.mean():.5f} "
              f"VaR_05_kup={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_01_kup={var_01_bt['kupiec_uc']['pass_at_005']} "
              f"PIT_p={pit_chi['p_value']:.4f} "
              f"regime_high_vol_avg={regime_high_vol_test.mean():.3f}")

    full_pred = pd.concat(all_preds, ignore_index=True)
    full_pred.to_parquet(Path(output_dir) / "all_predictions.parquet")
    var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
                                          es_forecasts=full_pred['es_05'].values)
    var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
    pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

    summary = {
        'method': 'B.2 P2 Hansen + Markov 2-state regime probability (13 features)',
        'n_obs_total': len(full_pred),
        'crps_pooled': float(full_pred['crps'].mean()),
        'var_05_backtest_pooled': var_05_pool,
        'var_01_backtest_pooled': var_01_pool,
        'pit_chi_square_pooled': pit_pool,
        'var_05_diff_var_01_mean_abs_pooled': float(np.abs(full_pred['var_05'] - full_pred['var_01']).mean()),
        'lambda_mean_pooled': float(full_pred['lam'].mean()),
        'nu_mean_pooled': float(full_pred['nu'].mean()),
        'regime_high_vol_mean_pooled': float(full_pred['regime_high_vol_prob'].mean()),
        'fold_metrics': fold_metrics,
    }
    with open(Path(output_dir) / "summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    print(f"\n=== B.2 (P2 + Markov regime) POOLED ===")
    print(f"  CRPS = {summary['crps_pooled']:.5f}  (P2 baseline: 0.63863)")
    print(f"  VaR_05 Kupiec p={var_05_pool['kupiec_uc']['p_value']:.4f} pass={var_05_pool['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_01 Kupiec p={var_01_pool['kupiec_uc']['p_value']:.4f} pass={var_01_pool['kupiec_uc']['pass_at_005']}")
    print(f"  PIT chi2 p={pit_pool['p_value']:.4f} pass={pit_pool['pass_at_005']}  (P2: 0.0050)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/b2_regime_aware')
    parser.add_argument('--alpha', type=float, default=0.001)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    print(f"[B.2] CFG: {cfg_path}")
    print(f"[B.2] OUT: {output_dir}")
    run(str(cfg_path), str(output_dir), alpha_l1=args.alpha, seed=args.seed)


if __name__ == "__main__":
    main()
