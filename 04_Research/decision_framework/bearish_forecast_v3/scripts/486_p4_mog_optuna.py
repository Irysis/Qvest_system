"""
486_p4_mog_optuna.py — P4-MoG (Mixture Gaussian 22d) Optuna sweep

도훈 mandate 2026-05-27:
- Hansen Skewed-t 22d 구조적 실패 (0/200 PASS) → Paradigm shift to MoG
- 2-3 component Gaussian Mixture
- Calibration-first composite loss (PIT/VaR PASS)
- Features panel: 483 output (27 features) 그대로 재활용

Search space:
- n_components ∈ {2, 3}
- log10_alpha ∈ [-5, -2]
- train_min ∈ {2520, 3024, 3528, 4032}
- taus_count ∈ {7, 11, 15}
- embargo ∈ {25, 30, 35}
- n_splits ∈ {8, 10, 12}

Composite loss (no ν penalty — MoG는 ν 없음):
    loss = crps_normalized
         + 2.0 * max(0, 0.05 - kupiec_05_p)
         + 2.0 * max(0, 0.05 - kupiec_01_p)
         + 1.5 * max(0, 0.05 - pit_chi_p)

CLI:
    python scripts/486_p4_mog_optuna.py --n_trials 100 --study_name p4_mog \
        --output 03_models/p4_mog_optuna
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
MOG = _load("p4_mog", str(ROOT / "03_models" / "p4_mog.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))


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


def eval_p4_mog(X, y, alpha_l1, train_min, taus_count, embargo, n_splits,
                 n_components=2, test_window=504, seed=0):
    """P4-MoG one config eval."""
    np.random.seed(seed)
    rng = np.random.default_rng(seed)
    TAUS = select_taus(taus_count)
    taus_np = np.array(TAUS)
    n_splits_eff = max(1, min(n_splits, (len(X) - train_min) // test_window - 1))
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits_eff, train_min=train_min,
        test_size=test_window, embargo=embargo,
    )
    all_preds = []
    for tr_idx, te_idx in splitter.split(X):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        model = LQM.LassoQuantileGaR(taus=TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)
        sst = MOG.derive_metrics_per_obs(Q_te, taus_np, n_components=n_components)
        # PIT via fitted MoG params (n_components=2 only for now)
        if n_components == 2:
            pit = MOG.pit_per_obs(y_te, sst, n_components=2)
        else:
            # 3-comp PIT not implemented — fallback to empirical CDF from quantile interp
            pit = np.array([float(np.interp(y_te[i], Q_te[i], taus_np)) for i in range(len(y_te))])
            pit = np.clip(pit, 0.001, 0.999)
        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 300
        # CRPS via sampling from MoG
        for i in range(N):
            if n_components == 2:
                samples = MOG.sample_from_mog2(sst['pi'][i],
                                                sst['mu1'][i], sst['sigma1'][i],
                                                sst['mu2'][i], sst['sigma2'][i],
                                                n_samples=n_samples, rng=rng)
            else:
                # Fallback: sample by interp from quantiles
                u = rng.uniform(0.001, 0.999, n_samples)
                samples = np.interp(u, taus_np, Q_te[i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = rng.permutation(n_samples)
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
        'n_obs_total': int(len(full)),
        'n_splits_eff': n_splits_eff,
    }


def composite_loss_mog(m: dict) -> tuple[float, float]:
    base = m['crps_normalized']
    p_k05 = 2.0 * max(0.0, 0.05 - m['kupiec_05_p'])
    p_k01 = 2.0 * max(0.0, 0.05 - m['kupiec_01_p'])
    p_pit = 1.5 * max(0.0, 0.05 - m['pit_chi_p'])
    penalty = p_k05 + p_k01 + p_pit
    return base + penalty, penalty


def objective_factory(X, y):
    def objective(trial: optuna.Trial):
        n_components = trial.suggest_categorical('n_components', [2, 3])
        log_alpha = trial.suggest_float('log10_alpha', -5.0, -2.0)
        alpha = 10.0 ** log_alpha
        train_min = trial.suggest_categorical('train_min', [2520, 3024, 3528, 4032])
        taus_count = trial.suggest_categorical('taus_count', [7, 11, 15])
        embargo = trial.suggest_categorical('embargo', [25, 30, 35])
        n_splits = trial.suggest_categorical('n_splits', [8, 10, 12])

        try:
            m = eval_p4_mog(X, y, alpha, train_min, taus_count, embargo, n_splits,
                              n_components=n_components)
        except Exception as e:
            print(f"  trial #{trial.number} fail: {e}")
            return 99.0

        loss, penalty = composite_loss_mog(m)
        for k, v in m.items():
            trial.set_user_attr(k, v)
        trial.set_user_attr('alpha', alpha)
        trial.set_user_attr('n_components', n_components)
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
    parser.add_argument('--output', type=str, default='03_models/p4_mog_optuna')
    parser.add_argument('--n_trials', type=int, default=100)
    parser.add_argument('--target_col', type=str, default='ret_h_log_pct')
    parser.add_argument('--seed', type=int, default=0)
    parser.add_argument('--study_name', type=str, default='p4_mog')
    args = parser.parse_args()

    feat_path = Path(args.features)
    if not feat_path.is_absolute():
        feat_path = PROJECT_ROOT / feat_path
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f'[P4-MoG optuna] features: {feat_path}')
    df = pd.read_parquet(feat_path)
    meta = json.loads(feat_path.with_suffix('.meta.json').read_text())
    feature_cols = meta['feature_cols']
    print(f'[P4-MoG optuna] data: {len(df)} rows ({df.Date.min().date()} ~ {df.Date.max().date()})')
    print(f'[P4-MoG optuna] features: {len(feature_cols)}  target: {args.target_col}')
    print(f'[P4-MoG optuna] n_trials: {args.n_trials}')

    X = df[feature_cols].values.astype(np.float64)
    y = df[args.target_col].values.astype(np.float64)

    sampler = optuna.samplers.TPESampler(seed=args.seed, n_startup_trials=15)
    pruner = optuna.pruners.MedianPruner(n_startup_trials=10)
    storage_path = f"sqlite:///{output_dir}/optuna.db"
    study = optuna.create_study(
        direction='minimize', sampler=sampler, pruner=pruner,
        study_name=args.study_name, storage=storage_path, load_if_exists=True,
    )

    t0 = time.time()
    header = f"{'trial':<5} {'nc':<3} {'α':<10} {'tmin':<5} {'τ':<3} {'emb':<4} {'nspl':<5} " \
             f"{'crps_n':<7} {'k05_p':<7} {'k01_p':<7} {'pit_p':<7} {'loss':<7} {'t':<5}"
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
        print(f"{trial.number:<5} {a['n_components']:<3} {a['alpha']:<10.2e} {a['train_min']:<5} "
              f"{a['taus_count']:<3} {a['embargo']:<4} {a['n_splits']:<5} "
              f"{a['crps_normalized']:<7.4f} {a['kupiec_05_p']:.4f}{k05_f} {a['kupiec_01_p']:.4f}{k01_f} "
              f"{a['pit_chi_p']:.4f}{pit_f} {trial.value:<7.4f} {elapsed:.0f}s")

    study.optimize(objective_factory(X, y), n_trials=args.n_trials, callbacks=[callback])

    # ── Best ──────────────────────────────────────────────────────────────
    best = study.best_trial
    print(f"\n=== BEST trial #{best.number} (loss={best.value:.5f}) ===")
    a = best.user_attrs
    print(f"  n_components={a['n_components']}  alpha={a['alpha']:.2e}")
    print(f"  train_min={a['train_min']}  taus={a['taus_count']}  embargo={a['embargo']}  n_splits={a['n_splits']}")
    print(f"  CRPS_normalized={a['crps_normalized']:.5f}  (Hansen P4 best 0.559)")
    print(f"  Kupiec_05 p={a['kupiec_05_p']:.4f}  pass={a['kupiec_05_pass']}")
    print(f"  Kupiec_01 p={a['kupiec_01_p']:.4f}  pass={a['kupiec_01_pass']}")
    print(f"  PIT chi² p={a['pit_chi_p']:.4f}  pass={a['pit_chi_pass']}")

    # Feasible (all 3 PASS)
    feasible = [t for t in study.trials
                if t.user_attrs.get('kupiec_05_pass')
                and t.user_attrs.get('kupiec_01_pass')
                and t.user_attrs.get('pit_chi_pass')]
    feasible_sorted = sorted(feasible, key=lambda t: t.user_attrs['crps_normalized'])
    print(f"\n=== TOP 10 fully-calibrated (PIT+VaR PASS) ===")
    print(f"  feasible count = {len(feasible)} / {len(study.trials)}")
    for t in feasible_sorted[:10]:
        a = t.user_attrs
        print(f"  #{t.number:<3} nc={a['n_components']} α={a['alpha']:.2e} tmin={a['train_min']} τ={a['taus_count']} "
              f"emb={a['embargo']} nspl={a['n_splits']} crps_n={a['crps_normalized']:.4f} "
              f"k05={a['kupiec_05_p']:.3f} k01={a['kupiec_01_p']:.3f} pit={a['pit_chi_p']:.3f}")

    # Save
    results = []
    for t in study.trials:
        if t.state == optuna.trial.TrialState.COMPLETE:
            results.append({'trial': t.number, 'objective': t.value, **t.user_attrs})
    out = {
        'study_name': args.study_name,
        'paradigm': 'Mixture Gaussian 2-3 component',
        'n_trials_total': len(study.trials),
        'n_feasible': len(feasible),
        'best_trial': best.number,
        'best_loss': float(best.value),
        'best_params': dict(best.params),
        'best_alpha': float(best.user_attrs['alpha']),
        'best_metrics': {k: v for k, v in best.user_attrs.items() if k not in ('alpha', 'penalty')},
        'top10_feasible': [
            {'trial': t.number, **{k: t.user_attrs[k] for k in
                ['n_components', 'alpha', 'train_min', 'taus_count', 'embargo', 'n_splits',
                 'crps_normalized', 'kupiec_05_p', 'kupiec_01_p', 'pit_chi_p'] if k in t.user_attrs}}
            for t in feasible_sorted[:10]
        ],
        'all_results': results,
    }
    with open(output_dir / "optuna_summary.json", 'w') as f:
        json.dump(out, f, indent=2, default=_json_default)
    print(f"\n[saved] {output_dir / 'optuna_summary.json'}")
    print(f"[saved] {output_dir / 'optuna.db'}")


if __name__ == "__main__":
    main()
