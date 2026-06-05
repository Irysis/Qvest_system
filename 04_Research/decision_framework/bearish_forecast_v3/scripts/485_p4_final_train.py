"""
485_p4_final_train.py — P4 best trial → full walk-forward train + final report

도훈 mandate 2026-05-27:
- 484_p4_optuna_full.py best trial 추출
- Best hparam으로 full walk-forward CV + predictions
- Comprehensive metrics: CRPS, Kupiec, Christoffersen, McNeil-Frey, PIT chi², Berkowitz
- P3 1d (trial19) vs P4 21d 비교 보고
- AX-008 Triangulation 의무 (Forge + Codex 2-source PASS)

CLI:
    python scripts/485_p4_final_train.py \
        --optuna_db 03_models/p4_optuna/optuna.db \
        --features 04_Research/.../outputs/p4_features_panel.parquet \
        --output 03_models/p4_final/
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
import warnings
from datetime import datetime
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

P4_OPT = _load("p4_optuna_full", str(ROOT / "scripts" / "484_p4_optuna_full.py"))


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def full_train_p4(X, y, dates, alpha_l1, train_min, taus_count, embargo, n_splits,
                   test_window=504, seed=0):
    """Full walk-forward train with best hparams. Returns predictions DataFrame."""
    np.random.seed(seed)
    TAUS = P4_OPT.select_taus(taus_count)
    taus_np = np.array(TAUS)
    n_splits_eff = max(1, min(n_splits, (len(X) - train_min) // test_window - 1))
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits_eff, train_min=train_min,
        test_size=test_window, embargo=embargo,
    )

    all_preds = []
    fold_metrics = []
    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        d_te = dates[te_idx]
        model = LQM.LassoQuantileGaR(taus=TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)
        sst = HSK.derive_metrics_per_obs(Q_te, taus_np)
        pit = HSK.pit_per_obs(y_te, sst['mu'], sst['sigma'], sst['nu'], sst['lam'])

        N = len(y_te)
        crps_per = np.zeros(N)
        n_samples = 500
        for i in range(N):
            u = np.random.uniform(0, 1, n_samples)
            samples = HSK.hansen_quantile(u, sst['mu'][i], sst['sigma'][i],
                                            sst['nu'][i], sst['lam'][i])
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = np.random.permutation(n_samples)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(d_te), 'fold': fold_idx,
            'y_actual': y_te, 'crps': crps_per, 'pit': pit,
            'mu': sst['mu'], 'sigma': sst['sigma'],
            'nu': sst['nu'], 'lam': sst['lam'],
            'var_05': sst['var_05'], 'var_01': sst['var_01'],
            'var_005': sst['var_005'], 'var_001': sst['var_001'],
            'es_05': sst['es_05'],
            'p_minus_5pct': sst['p_minus_5'],
            'p_minus_7pct': sst['p_minus_7'],
            'p_minus_10pct': sst['p_minus_10'],
        })
        all_preds.append(pred_df)

        var05 = VARBT.var_backtest_full(y_te, sst['var_05'], alpha=0.05)
        pit_chi = CALIB.pit_chi_square(pit, n_bins=10)
        fold_metrics.append({
            'fold': fold_idx, 'n_obs': N,
            'date_start': str(pd.to_datetime(d_te[0]).date()),
            'date_end': str(pd.to_datetime(d_te[-1]).date()),
            'crps_mean': float(crps_per.mean()),
            'kupiec_05_p': float(var05['kupiec_uc']['p_value']),
            'kupiec_05_pass': bool(var05['kupiec_uc']['pass_at_005']),
            'pit_chi_p': float(pit_chi['p_value']),
            'pit_chi_pass': bool(pit_chi['pass_at_005']),
            'nu_mean': float(sst['nu'].mean()),
            'lam_mean': float(sst['lam'].mean()),
        })
        print(f"  fold[{fold_idx}] {pred_df.Date.min().date()} ~ {pred_df.Date.max().date()} "
              f"n={N}  CRPS={crps_per.mean():.4f}  k05_p={var05['kupiec_uc']['p_value']:.4f} "
              f"pit_p={pit_chi['p_value']:.4f}  ν̄={sst['nu'].mean():.1f}  λ̄={sst['lam'].mean():+.3f}")

    return pd.concat(all_preds, ignore_index=True), fold_metrics, n_splits_eff


def pooled_metrics(full: pd.DataFrame) -> dict:
    """Pooled comprehensive metrics."""
    y = full['y_actual'].values
    y_std = float(np.std(y))
    var05 = VARBT.var_backtest_full(y, full['var_05'].values, alpha=0.05,
                                      es_forecasts=full['es_05'].values)
    var01 = VARBT.var_backtest_full(y, full['var_01'].values, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(full['pit'].values, n_bins=10)
    pit_ks = CALIB.pit_ks_test(full['pit'].values)
    pit_berk = CALIB.pit_berkowitz(full['pit'].values)
    return {
        'n_obs_total': int(len(full)),
        'y_std_pooled': y_std,
        'crps_pooled': float(full['crps'].mean()),
        'crps_normalized': float(full['crps'].mean() / y_std) if y_std > 0 else None,
        'var_05_backtest': var05,
        'var_01_backtest': var01,
        'pit_chi_square': pit_chi,
        'pit_ks_test': pit_ks,
        'pit_berkowitz': pit_berk,
        'nu_mean': float(full['nu'].mean()),
        'nu_median': float(full['nu'].median()),
        'lam_mean': float(full['lam'].mean()),
        'bear_probs': {
            'p_minus_5pct_mean': float(full['p_minus_5pct'].mean()),
            'p_minus_5pct_max': float(full['p_minus_5pct'].max()),
            'p_minus_7pct_mean': float(full['p_minus_7pct'].mean()),
            'p_minus_10pct_mean': float(full['p_minus_10pct'].mean()),
            'p_minus_10pct_max': float(full['p_minus_10pct'].max()),
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--optuna_db', type=str,
                        default='03_models/p4_optuna/optuna.db')
    parser.add_argument('--study_name', type=str, default='p4_full')
    parser.add_argument('--features', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/outputs/p4_features_panel.parquet')
    parser.add_argument('--output', type=str, default='03_models/p4_final')
    parser.add_argument('--target_col', type=str, default='ret_h_log_pct')
    parser.add_argument('--manual_alpha', type=float, default=None,
                        help='Override best trial alpha (for testing)')
    parser.add_argument('--manual_train_min', type=int, default=None)
    parser.add_argument('--manual_taus_count', type=int, default=None)
    parser.add_argument('--manual_embargo', type=int, default=None)
    parser.add_argument('--manual_n_splits', type=int, default=None)
    args = parser.parse_args()

    db_path = ROOT / args.optuna_db
    feat_path = Path(args.features)
    if not feat_path.is_absolute():
        feat_path = PROJECT_ROOT / feat_path
    out_dir = ROOT / args.output
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── 1. Load best trial ────────────────────────────────────────────────────
    if args.manual_alpha is not None:
        alpha = args.manual_alpha
        train_min = args.manual_train_min or 3024
        taus_count = args.manual_taus_count or 11
        embargo = args.manual_embargo or 25
        n_splits = args.manual_n_splits or 12
        print(f"[P4 final] MANUAL hparams override")
    else:
        storage = f"sqlite:///{db_path}"
        study = optuna.load_study(study_name=args.study_name, storage=storage)
        best = study.best_trial
        print(f"[P4 final] best trial #{best.number} loss={best.value:.5f}")
        print(f"  user_attrs: alpha={best.user_attrs['alpha']:.2e}  "
              f"train_min={best.user_attrs.get('train_min')}  "
              f"taus_count={best.user_attrs.get('taus_count')}  "
              f"embargo={best.user_attrs.get('embargo')}  "
              f"n_splits={best.user_attrs.get('n_splits')}")
        alpha = float(best.user_attrs['alpha'])
        train_min = int(best.user_attrs['train_min'])
        taus_count = int(best.user_attrs['taus_count'])
        embargo = int(best.user_attrs['embargo'])
        n_splits = int(best.user_attrs['n_splits'])

    print(f'\n[P4 final] hparams: α={alpha:.2e} train_min={train_min} '
          f'taus_count={taus_count} embargo={embargo} n_splits={n_splits}')

    # ── 2. Load features ──────────────────────────────────────────────────────
    df = pd.read_parquet(feat_path)
    meta = json.loads(feat_path.with_suffix('.meta.json').read_text())
    feature_cols = meta['feature_cols']
    X = df[feature_cols].values.astype(np.float64)
    y = df[args.target_col].values.astype(np.float64)
    dates = df['Date'].values
    print(f'[P4 final] data: {len(df)} rows ({df.Date.min().date()} ~ {df.Date.max().date()}) '
          f'features={len(feature_cols)}')

    # ── 3. Full walk-forward train ────────────────────────────────────────────
    print(f'\n[P4 final] === Full walk-forward train ===')
    full_preds, fold_metrics, n_splits_eff = full_train_p4(
        X, y, dates, alpha, train_min, taus_count, embargo, n_splits,
    )
    print(f'[P4 final] folds completed: {n_splits_eff}  total predictions: {len(full_preds)}')

    # ── 4. Pooled metrics ─────────────────────────────────────────────────────
    print(f'\n[P4 final] === Pooled metrics ===')
    pooled = pooled_metrics(full_preds)
    print(f"  n_obs_total = {pooled['n_obs_total']}")
    print(f"  y_std (h=21d, %) = {pooled['y_std_pooled']:.3f}")
    print(f"  CRPS_pooled = {pooled['crps_pooled']:.5f}")
    print(f"  CRPS_normalized = {pooled['crps_normalized']:.5f}  (P3 h=1 ≈ 0.490)")
    var05 = pooled['var_05_backtest']
    var01 = pooled['var_01_backtest']
    pit_chi = pooled['pit_chi_square']
    pit_berk = pooled['pit_berkowitz']
    print(f"  VaR 5%  Kupiec_p={var05['kupiec_uc']['p_value']:.4f} pass={var05['kupiec_uc']['pass_at_005']}  "
          f"Christoffersen_CC_p={var05['christoffersen_cc']['p_value']:.4f} pass={var05['christoffersen_cc']['pass_at_005']}  "
          f"McNeil-Frey_p={var05['mcneil_frey_es']['p_value']:.4f}")
    print(f"  VaR 1%  Kupiec_p={var01['kupiec_uc']['p_value']:.4f} pass={var01['kupiec_uc']['pass_at_005']}  "
          f"Christoffersen_CC_p={var01['christoffersen_cc']['p_value']:.4f}")
    print(f"  PIT chi² p={pit_chi['p_value']:.4f}  pass={pit_chi['pass_at_005']}")
    print(f"  PIT Berkowitz p={pit_berk.get('p_value', 'N/A'):.4f}  pass={pit_berk.get('pass_at_005', 'N/A')}")
    print(f"  ν mean={pooled['nu_mean']:.1f}  median={pooled['nu_median']:.1f}  "
          f"(target < 100 non-degenerate)")
    print(f"  λ mean={pooled['lam_mean']:+.4f}")

    # ── 5. P3 baseline comparison ─────────────────────────────────────────────
    # P3 trial19 summary (read if available)
    p3_summary_path = ROOT / "03_models" / "p3_trial19" / "summary.json"
    p3_comparison = None
    if p3_summary_path.exists():
        p3 = json.loads(p3_summary_path.read_text())
        p3_crps = p3.get('crps_pooled', 0.5721)
        # P3 used %-scaled log return (y_std h=1 ≈ 1.16%)
        # P4 h=21d y_std much larger, so direct CRPS not comparable;
        # crps_normalized is the comparable metric.
        p3_comparison = {
            'p3_spec': p3.get('spec'),
            'p3_crps_pooled': p3_crps,
            'p3_kupiec_05_p': p3.get('var_05_backtest_pooled', {}).get('kupiec_uc', {}).get('p_value'),
            'p3_kupiec_01_p': p3.get('var_01_backtest_pooled', {}).get('kupiec_uc', {}).get('p_value'),
            'p3_pit_chi_p': p3.get('pit_chi_square_pooled', {}).get('p_value'),
            'p3_nu_mean': p3.get('nu_mean_pooled'),
            'p3_lam_mean': p3.get('lambda_mean_pooled'),
            'p4_minus_p3_kupiec_05_p': pooled['var_05_backtest']['kupiec_uc']['p_value'] - (p3.get('var_05_backtest_pooled', {}).get('kupiec_uc', {}).get('p_value') or 0),
        }
        print(f"\n[P4 final] === P3 (h=1) vs P4 (h=21) comparison ===")
        print(f"  P3 CRPS_pooled={p3_crps:.4f}  P4 CRPS_pooled={pooled['crps_pooled']:.4f}")
        print(f"  P3 Kupiec_05_p={p3_comparison['p3_kupiec_05_p']}  P4={pooled['var_05_backtest']['kupiec_uc']['p_value']:.4f}")
        print(f"  P3 PIT_p={p3_comparison['p3_pit_chi_p']}  P4={pit_chi['p_value']:.4f}")
        print(f"  P3 ν_mean={p3_comparison['p3_nu_mean']}  P4={pooled['nu_mean']:.1f}")

    # ── 6. Save ───────────────────────────────────────────────────────────────
    full_preds.to_parquet(out_dir / 'all_predictions.parquet')
    for f_idx in range(n_splits_eff):
        sub = full_preds[full_preds['fold'] == f_idx]
        sub.to_parquet(out_dir / f'fold_{f_idx:02d}_predictions.parquet')

    summary = {
        'model': 'P4',
        'description': 'P4 (h=21) Hansen Skewed-t calibration-first, horizon-aware + macro features',
        'spec': {
            'alpha': alpha, 'train_min': train_min,
            'taus_count': taus_count, 'embargo': embargo,
            'n_splits': n_splits, 'n_splits_eff': n_splits_eff,
            'test_window': 504, 'horizon': 21,
            'n_features': len(feature_cols),
            'feature_cols': feature_cols,
            'target_col': args.target_col,
        },
        'pooled_metrics': pooled,
        'fold_metrics': fold_metrics,
        'p3_comparison': p3_comparison,
        'trained_at': datetime.now().isoformat(),
        'optuna_db': str(db_path),
        'features_path': str(feat_path),
    }
    summary_path = out_dir / 'summary.json'
    summary_path.write_text(json.dumps(summary, indent=2, default=_json_default, ensure_ascii=False))
    print(f'\n[P4 final] saved → {summary_path}')
    print(f'[P4 final] saved → {out_dir / "all_predictions.parquet"}')

    # ── 7. Pass/Fail gate ─────────────────────────────────────────────────────
    calibration_pass = (var05['kupiec_uc']['pass_at_005']
                         and var01['kupiec_uc']['pass_at_005']
                         and pit_chi['pass_at_005']
                         and pooled['nu_mean'] < 1000)
    print(f'\n[P4 final] {"✅ CALIBRATION PASS" if calibration_pass else "❌ CALIBRATION FAIL"}'
          f' (PIT={pit_chi["pass_at_005"]} VaR5={var05["kupiec_uc"]["pass_at_005"]} '
          f'VaR1={var01["kupiec_uc"]["pass_at_005"]} ν<1000={pooled["nu_mean"] < 1000})')

    if not calibration_pass:
        print('[P4 final] ⚠️ Stage Gate: 도훈 escalate or search space 확장 검토')
        sys.exit(2)


if __name__ == "__main__":
    main()
