"""
481_p2_optuna_bayesian.py — Optuna Bayesian hyperparameter optimization for P2

도훈 mandate 2026-05-26: 그리드 → Bayesian (Optuna TPE sampler).

Search space:
- log10(alpha_l1) ∈ [-7, -1]  continuous (TPE explores promising region)
- train_min ∈ {1008, 1512, 2016, 2520, 3024}  discrete
- taus density: fixed 11 (그리드 결과로 11이 더 robust)

Objective:
  minimize CRPS_pooled
  subject to Kupiec_05_pass AND Kupiec_01_pass (violation → penalty)

Penalty: if VaR fail → CRPS + 1.0 * (1 - kupiec_p) for each violating level.

50 trials × ~30s = ~25분.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
import time
import warnings
from pathlib import Path

import numpy as np
import optuna
import pandas as pd
import yaml

warnings.filterwarnings('ignore')
optuna.logging.set_verbosity(optuna.logging.WARNING)

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


TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def eval_config(X, y, alpha_l1, train_min, test_window=504, embargo=21, n_splits_max=12, seed=0):
    """Run one config, return metrics dict."""
    np.random.seed(seed)
    n_splits_eff = max(1, min(n_splits_max, (len(X) - train_min) // test_window - 1))
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits_eff, train_min=train_min, test_size=test_window, embargo=embargo,
    )
    taus_np = np.array(TAUS)
    all_preds = []
    for tr_idx, te_idx in splitter.split(X):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        model = LQM.LassoQuantileGaR(taus=TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)
        sst = HSK.derive_metrics_per_obs(Q_te, taus_np)
        pit = HSK.pit_per_obs(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['lam'])
        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 300
        for i in range(N):
            u = np.random.uniform(0, 1, n_samples)
            samples = HSK.hansen_quantile(u, sst['mu'][i], sst['sigma'][i], sst['nu'][i], sst['lam'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(n_samples)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx
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
        'breach_05_pct': float((full['y_actual'] < full['var_05']).mean() * 100),
        'breach_01_pct': float((full['y_actual'] < full['var_01']).mean() * 100),
        'kupiec_05_p': float(var05_bt['kupiec_uc']['p_value']),
        'kupiec_05_pass': bool(var05_bt['kupiec_uc']['pass_at_005']),
        'kupiec_01_p': float(var01_bt['kupiec_uc']['p_value']),
        'kupiec_01_pass': bool(var01_bt['kupiec_uc']['pass_at_005']),
        'pit_chi_p': float(pit_chi['p_value']),
        'pit_chi_pass': bool(pit_chi['pass_at_005']),
        'var_diff_avg': float(np.abs(full['var_05'] - full['var_01']).mean()),
        'n_splits_eff': n_splits_eff,
    }


def objective_factory(X, y):
    """Build optuna objective. Penalize VaR violations."""
    def objective(trial: optuna.Trial):
        log_alpha = trial.suggest_float('log10_alpha', -7.0, -1.0)
        alpha = 10.0 ** log_alpha
        train_min = trial.suggest_categorical('train_min', [1008, 1512, 2016, 2520, 3024])

        try:
            r = eval_config(X, y, alpha, train_min)
        except Exception as e:
            print(f"  trial fail: {e}")
            return 99.0

        # Soft penalty for VaR failure (encourage feasible region)
        penalty = 0.0
        if not r['kupiec_05_pass']:
            penalty += 1.0 * (0.05 - r['kupiec_05_p'])  # bigger penalty when p lower
        if not r['kupiec_01_pass']:
            penalty += 1.0 * (0.05 - r['kupiec_01_p'])

        # Log to trial user attrs for inspection
        for k, v in r.items():
            trial.set_user_attr(k, v)
        trial.set_user_attr('alpha', alpha)
        trial.set_user_attr('penalty', penalty)

        objective_value = r['crps_pooled'] + penalty
        return objective_value
    return objective


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/a1_lasso_full.yaml')
    parser.add_argument('--output', type=str, default='03_models/p2_optuna')
    parser.add_argument('--n_trials', type=int, default=50)
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
    print(f"[optuna] data: {len(df)} rows ({df['Date'].min().date()} ~ {df['Date'].max().date()})")
    print(f"[optuna] features: {len(feature_cols)}")
    print(f"[optuna] n_trials = {args.n_trials}")

    sampler = optuna.samplers.TPESampler(seed=args.seed, n_startup_trials=10)
    storage_path = f"sqlite:///{output_dir}/optuna.db"
    study = optuna.create_study(
        direction='minimize', sampler=sampler,
        study_name='p2_hparam', storage=storage_path, load_if_exists=True,
    )

    t0 = time.time()
    print(f"\n{'trial':<5} {'α':<10} {'tmin':<5} {'CRPS':<8} {'kup5_p':<7} {'kup1_p':<7} {'pit_p':<7} {'obj':<8} {'state':<8}")
    def callback(study, trial):
        a = trial.user_attrs
        elapsed = time.time() - t0
        if 'crps_pooled' not in a:
            print(f"{trial.number:<5} {'(failed)':<10}")
            return
        kup5_flag = '✓' if a['kupiec_05_pass'] else '✗'
        kup1_flag = '✓' if a['kupiec_01_pass'] else '✗'
        print(f"{trial.number:<5} {a['alpha']:<10.2e} {a.get('train_min', '?'):<5} "
              f"{a['crps_pooled']:<8.5f} {a['kupiec_05_p']:.4f}{kup5_flag}  {a['kupiec_01_p']:.4f}{kup1_flag}  "
              f"{a['pit_chi_p']:.4f}  {trial.value:.5f}  {elapsed:.0f}s")

    study.optimize(objective_factory(X, y), n_trials=args.n_trials, callbacks=[callback])

    # Best
    best = study.best_trial
    print(f"\n=== BEST trial #{best.number} (objective={best.value:.5f}) ===")
    print(f"  alpha = {best.user_attrs['alpha']:.2e}")
    print(f"  train_min = {best.user_attrs.get('train_min', '?')}")
    print(f"  CRPS = {best.user_attrs['crps_pooled']:.5f}")
    print(f"  VaR_05 breach = {best.user_attrs['breach_05_pct']:.2f}%, kupiec_p = {best.user_attrs['kupiec_05_p']:.4f}  pass={best.user_attrs['kupiec_05_pass']}")
    print(f"  VaR_01 breach = {best.user_attrs['breach_01_pct']:.2f}%, kupiec_p = {best.user_attrs['kupiec_01_p']:.4f}  pass={best.user_attrs['kupiec_01_pass']}")
    print(f"  PIT chi2 p = {best.user_attrs['pit_chi_p']:.4f}  pass = {best.user_attrs['pit_chi_pass']}")
    print(f"  Δ vs P2 baseline (CRPS 0.6386): {(best.user_attrs['crps_pooled'] - 0.6386) / 0.6386 * 100:+.1f}%")

    # Top 5 feasible (both Kupiec PASS)
    print(f"\n=== TOP 10 Production-ready (both Kupiec PASS) — sorted by CRPS ===")
    feasible = [t for t in study.trials
                if t.user_attrs.get('kupiec_05_pass') and t.user_attrs.get('kupiec_01_pass')]
    feasible_sorted = sorted(feasible, key=lambda t: t.user_attrs['crps_pooled'])
    print(f"{'#':<4} {'α':<10} {'tmin':<5} {'CRPS':<8} {'kup5_p':<7} {'kup1_p':<7} {'pit_p':<7}")
    for t in feasible_sorted[:10]:
        a = t.user_attrs
        print(f"{t.number:<4} {a['alpha']:<10.2e} {a.get('train_min', '?'):<5} "
              f"{a['crps_pooled']:<8.5f} {a['kupiec_05_p']:<7.4f} {a['kupiec_01_p']:<7.4f} {a['pit_chi_p']:<7.4f}")

    # Save full results
    results = []
    for t in study.trials:
        if t.state == optuna.trial.TrialState.COMPLETE:
            results.append({
                'trial': t.number, 'objective': t.value,
                **t.user_attrs,
            })
    out = {
        'best_trial': best.number,
        'best_alpha': best.user_attrs['alpha'],
        'best_train_min': best.user_attrs.get('train_min'),
        'best_crps': best.user_attrs['crps_pooled'],
        'best_kupiec_05_p': best.user_attrs['kupiec_05_p'],
        'best_kupiec_01_p': best.user_attrs['kupiec_01_p'],
        'best_pit_p': best.user_attrs['pit_chi_p'],
        'p2_baseline_crps': 0.6386,
        'improvement_pct': (best.user_attrs['crps_pooled'] - 0.6386) / 0.6386 * 100,
        'n_trials_completed': len(results),
        'n_feasible': len(feasible),
        'top10_feasible': [
            {'trial': t.number, **t.user_attrs} for t in feasible_sorted[:10]
        ],
        'all_results': results,
    }
    with open(output_dir / "optuna_summary.json", 'w') as f:
        json.dump(out, f, indent=2, default=_json_default)
    print(f"\n[saved] {output_dir / 'optuna_summary.json'}")


if __name__ == "__main__":
    main()
