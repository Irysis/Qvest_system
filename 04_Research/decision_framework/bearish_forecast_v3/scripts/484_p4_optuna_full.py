"""
484_p4_optuna_full.py — P4 (h=21) Heavy Optuna 200 trials sweep

도훈 mandate 2026-05-27:
- Calibration-first composite loss (PIT/VaR PASS + ν non-degenerate)
- Search space 5D: α / train_min / taus_count / embargo / n_splits
- Heavy budget 200 trials (TPE n_startup=20)
- Features: 483_p4_features_horizon.py output (27 features, ret_h_log_pct label)

Composite loss:
  loss = crps_normalized
       + 2.0 * max(0, 0.05 - kupiec_05_p)
       + 2.0 * max(0, 0.05 - kupiec_01_p)
       + 1.5 * max(0, 0.05 - pit_chi_p)
       + 0.5 * (1 if nu_mean > 100 else 0)

CLI:
    python scripts/484_p4_optuna_full.py \
        --features 04_Research/.../outputs/p4_features_panel.parquet \
        --output 03_models/p4_optuna/ \
        --n_trials 200
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


# 11 taus default. Optuna trial can choose 7/11/15.
TAUS_7  = (0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
TAUS_11 = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
TAUS_15 = (0.005, 0.01, 0.025, 0.05, 0.075, 0.10, 0.25, 0.50,
            0.75, 0.90, 0.925, 0.95, 0.975, 0.99, 0.995)


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def select_taus(taus_count: int):
    if taus_count == 7: return TAUS_7
    if taus_count == 11: return TAUS_11
    if taus_count == 15: return TAUS_15
    raise ValueError(f"unsupported taus_count={taus_count}")


def eval_p4(X, y, alpha_l1, train_min, taus_count, embargo, n_splits, test_window=504, seed=0):
    """Run one P4 config, return calibration-focused metrics."""
    np.random.seed(seed)
    TAUS = select_taus(taus_count)
    taus_np = np.array(TAUS)
    n_splits_eff = max(1, min(n_splits, (len(X) - train_min) // test_window - 1))
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits_eff, train_min=train_min,
        test_size=test_window, embargo=embargo,
    )
    all_preds = []
    nu_list, lam_list = [], []
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
            'nu': sst['nu'], 'lam': sst['lam'],
        }))
        nu_list.append(float(sst['nu'].mean()))
        lam_list.append(float(sst['lam'].mean()))
    full = pd.concat(all_preds, ignore_index=True)
    var05_bt = VARBT.var_backtest_full(full['y_actual'].values, full['var_05'].values, alpha=0.05,
                                        es_forecasts=full['es_05'].values)
    var01_bt = VARBT.var_backtest_full(full['y_actual'].values, full['var_01'].values, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(full['pit'].values, n_bins=10)
    y_std = float(full['y_actual'].std())
    return {
        'crps_pooled': float(full['crps'].mean()),
        'crps_normalized': float(full['crps'].mean() / y_std) if y_std > 0 else 99.0,
        'y_std_pooled': y_std,
        'kupiec_05_p': float(var05_bt['kupiec_uc']['p_value']),
        'kupiec_05_pass': bool(var05_bt['kupiec_uc']['pass_at_005']),
        'kupiec_01_p': float(var01_bt['kupiec_uc']['p_value']),
        'kupiec_01_pass': bool(var01_bt['kupiec_uc']['pass_at_005']),
        'pit_chi_p': float(pit_chi['p_value']),
        'pit_chi_pass': bool(pit_chi['pass_at_005']),
        'nu_mean': float(full['nu'].mean()),
        'lam_mean': float(full['lam'].mean()),
        'n_obs_total': int(len(full)),
        'n_splits_eff': n_splits_eff,
    }


def composite_loss(m: dict) -> tuple[float, float]:
    """Calibration-first composite. Returns (loss, penalty_breakdown_sum)."""
    base = m['crps_normalized']
    p_k05 = 2.0 * max(0.0, 0.05 - m['kupiec_05_p'])
    p_k01 = 2.0 * max(0.0, 0.05 - m['kupiec_01_p'])
    p_pit = 1.5 * max(0.0, 0.05 - m['pit_chi_p'])
    p_nu = 0.5 if m['nu_mean'] > 100 else 0.0
    penalty = p_k05 + p_k01 + p_pit + p_nu
    return base + penalty, penalty


def objective_factory(X, y):
    def objective(trial: optuna.Trial):
        log_alpha = trial.suggest_float('log10_alpha', -5.0, -2.0)
        alpha = 10.0 ** log_alpha
        train_min = trial.suggest_categorical('train_min', [2520, 3024, 3528, 4032])
        taus_count = trial.suggest_categorical('taus_count', [7, 11, 15])
        embargo = trial.suggest_categorical('embargo', [25, 30, 35])
        n_splits = trial.suggest_categorical('n_splits', [8, 10, 12])

        try:
            m = eval_p4(X, y, alpha, train_min, taus_count, embargo, n_splits)
        except Exception as e:
            print(f"  trial #{trial.number} fail: {e}")
            return 99.0

        loss, penalty = composite_loss(m)
        for k, v in m.items():
            trial.set_user_attr(k, v)
        trial.set_user_attr('alpha', alpha)
        trial.set_user_attr('train_min', train_min)
        trial.set_user_attr('taus_count', taus_count)
        trial.set_user_attr('embargo', embargo)
        trial.set_user_attr('n_splits', n_splits)
        trial.set_user_attr('penalty', penalty)
        return loss
    return objective


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--features', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/outputs/p4_features_panel.parquet')
    parser.add_argument('--output', type=str, default='03_models/p4_optuna')
    parser.add_argument('--n_trials', type=int, default=200)
    parser.add_argument('--target_col', type=str, default='ret_h_log_pct',
                        help='Training target column (default ret_h_log_pct = log return * 100)')
    parser.add_argument('--seed', type=int, default=0)
    parser.add_argument('--study_name', type=str, default='p4_full')
    args = parser.parse_args()

    feat_path = Path(args.features)
    if not feat_path.is_absolute():
        feat_path = PROJECT_ROOT / feat_path
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f'[P4 optuna] features: {feat_path}')
    df = pd.read_parquet(feat_path)
    meta_path = feat_path.with_suffix('.meta.json')
    meta = json.loads(meta_path.read_text())
    feature_cols = meta['feature_cols']
    print(f'[P4 optuna] data: {len(df)} rows ({df.Date.min().date()} ~ {df.Date.max().date()})')
    print(f'[P4 optuna] features: {len(feature_cols)}')
    print(f'[P4 optuna] target: {args.target_col}')
    print(f'[P4 optuna] n_trials: {args.n_trials}')

    X = df[feature_cols].values.astype(np.float64)
    y = df[args.target_col].values.astype(np.float64)

    sampler = optuna.samplers.TPESampler(seed=args.seed, n_startup_trials=20)
    pruner = optuna.pruners.MedianPruner(n_startup_trials=10)
    storage_path = f"sqlite:///{output_dir}/optuna.db"
    study = optuna.create_study(
        direction='minimize', sampler=sampler, pruner=pruner,
        study_name=args.study_name, storage=storage_path, load_if_exists=True,
    )

    t0 = time.time()
    header = f"{'trial':<5} {'α':<10} {'tmin':<5} {'τ':<3} {'emb':<4} {'nspl':<5} " \
             f"{'crps_n':<7} {'k05_p':<7} {'k01_p':<7} {'pit_p':<7} {'ν̄':<10} {'loss':<7} {'pen':<5} {'t':<5}"
    print(f"\n{header}")
    print('─' * len(header))

    def callback(study, trial):
        a = trial.user_attrs
        elapsed = time.time() - t0
        if 'crps_normalized' not in a:
            print(f"{trial.number:<5} (failed)")
            return
        k05_f = '✓' if a['kupiec_05_pass'] else '✗'
        k01_f = '✓' if a['kupiec_01_pass'] else '✗'
        pit_f = '✓' if a['pit_chi_pass'] else '✗'
        nu_f = '·' if a['nu_mean'] <= 100 else '!'
        print(f"{trial.number:<5} {a['alpha']:<10.2e} {a.get('train_min', '?'):<5} "
              f"{a.get('taus_count', '?'):<3} {a.get('embargo', '?'):<4} {a.get('n_splits', '?'):<5} "
              f"{a['crps_normalized']:<7.4f} {a['kupiec_05_p']:.4f}{k05_f} {a['kupiec_01_p']:.4f}{k01_f} "
              f"{a['pit_chi_p']:.4f}{pit_f} {a['nu_mean']:<10.1f}{nu_f} {trial.value:<7.4f} "
              f"{a['penalty']:<5.3f} {elapsed:.0f}s")

    study.optimize(objective_factory(X, y), n_trials=args.n_trials, callbacks=[callback])

    # ── Best ──────────────────────────────────────────────────────────────
    best = study.best_trial
    print(f"\n=== BEST trial #{best.number} (loss={best.value:.5f}) ===")
    a = best.user_attrs
    print(f"  alpha = {a['alpha']:.2e}")
    print(f"  train_min = {a.get('train_min')}  taus_count = {a.get('taus_count')}  "
          f"embargo = {a.get('embargo')}  n_splits = {a.get('n_splits')}")
    print(f"  CRPS_normalized = {a['crps_normalized']:.5f}  (P3 1d baseline ≈ 0.490)")
    print(f"  Kupiec_05 p = {a['kupiec_05_p']:.4f}  pass={a['kupiec_05_pass']}")
    print(f"  Kupiec_01 p = {a['kupiec_01_p']:.4f}  pass={a['kupiec_01_pass']}")
    print(f"  PIT_chi p = {a['pit_chi_p']:.4f}  pass={a['pit_chi_pass']}")
    print(f"  ν_mean = {a['nu_mean']:.2f}  (P3 1d ≈ 45,477; target < 100 non-degenerate)")
    print(f"  λ_mean = {a['lam_mean']:+.4f}")

    # ── Top feasible (PIT + 2 Kupiec all PASS + ν < 100) ────────────────────
    feasible = [t for t in study.trials
                if t.user_attrs.get('kupiec_05_pass')
                and t.user_attrs.get('kupiec_01_pass')
                and t.user_attrs.get('pit_chi_pass')
                and t.user_attrs.get('nu_mean', 1e9) < 100]
    feasible_sorted = sorted(feasible, key=lambda t: t.user_attrs['crps_normalized'])
    print(f"\n=== TOP 10 fully-calibrated (PIT+VaR PASS + ν<100, sorted by crps_normalized) ===")
    print(f"  feasible count = {len(feasible)} / {len(study.trials)}")
    for t in feasible_sorted[:10]:
        a = t.user_attrs
        print(f"  #{t.number:<3} α={a['alpha']:.2e}  tmin={a.get('train_min')}  τ={a.get('taus_count')}  "
              f"emb={a.get('embargo')}  nspl={a.get('n_splits')}  "
              f"crps_n={a['crps_normalized']:.4f}  k05={a['kupiec_05_p']:.3f}  k01={a['kupiec_01_p']:.3f}  "
              f"pit={a['pit_chi_p']:.3f}  ν̄={a['nu_mean']:.1f}")

    # ── Save full results ─────────────────────────────────────────────────
    results = []
    for t in study.trials:
        if t.state == optuna.trial.TrialState.COMPLETE:
            results.append({
                'trial': t.number, 'objective': t.value,
                **t.user_attrs,
            })
    out = {
        'study_name': args.study_name,
        'n_trials_total': len(study.trials),
        'n_trials_completed': len(results),
        'n_feasible_full_calibrated': len(feasible),
        'best_trial': best.number,
        'best_loss': float(best.value),
        'best_params': dict(best.params),
        'best_alpha': float(best.user_attrs['alpha']),
        'best_metrics': {k: v for k, v in best.user_attrs.items()
                         if k not in ('alpha', 'penalty')},
        'top10_feasible': [
            {'trial': t.number, 'alpha': t.user_attrs['alpha'],
             **{k: t.user_attrs[k] for k in
                ['train_min', 'taus_count', 'embargo', 'n_splits',
                 'crps_normalized', 'kupiec_05_p', 'kupiec_01_p', 'pit_chi_p',
                 'nu_mean', 'lam_mean'] if k in t.user_attrs}}
            for t in feasible_sorted[:10]
        ],
        'all_results': results,
    }
    with open(output_dir / "optuna_summary.json", 'w') as f:
        json.dump(out, f, indent=2, default=_json_default)
    print(f"\n[saved] {output_dir / 'optuna_summary.json'}")
    print(f"[saved] {output_dir / 'optuna.db'} (SQLite study)")


if __name__ == "__main__":
    main()
