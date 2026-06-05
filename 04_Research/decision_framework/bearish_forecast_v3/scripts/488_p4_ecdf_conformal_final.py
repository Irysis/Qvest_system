"""
488_p4_ecdf_conformal_final.py — P4-ECDF Best #181 + Conformal Wrap final train

도훈 mandate 2026-05-27 (P4-ECDF Stage 3 + Conformal):
- P4-ECDF Optuna best trial (#181 from 487 sweep) 추출
- Full walk-forward train (12 folds) + raw ECDF predictions
- Conformal Wrap: ACI (Gibbs-Candes 2021) on VaR_05, VaR_01
  - γ ∈ {0.005, 0.01, 0.05, 0.10} sweep
- Calibration 재검정 (Kupiec / Christoffersen / McNeil-Frey / PIT)
- AX-008 Triangulation: PIT/Kupiec PASS 시 admit, FAIL 시 차단

CLI:
    python scripts/488_p4_ecdf_conformal_final.py \
        --optuna_db 03_models/p4_ecdf_optuna/optuna.db \
        --features 04_Research/.../outputs/p4_features_panel.parquet \
        --output 03_models/p4_ecdf_final/
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
ECDF = _load("p4_ecdf", str(ROOT / "03_models" / "p4_ecdf.py"))
F1 = _load("f1_conformal", str(ROOT / "03_models" / "f1_conformal.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))
P487 = _load("p4_ecdf_optuna", str(ROOT / "scripts" / "487_p4_ecdf_optuna.py"))


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def full_train_p4_ecdf(X, y, dates, alpha_l1, train_min, taus_count, embargo, n_splits,
                         test_window=504, seed=0):
    """Full walk-forward train with P4-ECDF best hparams. Returns predictions DF."""
    np.random.seed(seed)
    rng = np.random.default_rng(seed)
    TAUS = P487.select_taus(taus_count)
    taus_np = np.array(TAUS)
    n_splits_eff = max(1, min(n_splits, (len(X) - train_min) // test_window - 1))
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=n_splits_eff, train_min=train_min,
        test_size=test_window, embargo=embargo,
    )
    all_preds = []
    for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        d_te = dates[te_idx]
        model = LQM.LassoQuantileGaR(taus=TAUS, alpha=alpha_l1, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)
        m = ECDF.derive_metrics_per_obs(Q_te, taus_np)
        pit = ECDF.ecdf_pit_per_obs(y_te, Q_te, taus_np)

        # CRPS via sampling
        N = len(y_te)
        crps_per = np.zeros(N)
        for i in range(N):
            samples = ECDF.sample_from_ecdf(Q_te[i], taus_np, n_samples=300, rng=rng)
            abs_xy = np.abs(samples - y_te[i]).mean()
            perm = rng.permutation(300)
            abs_xx = np.abs(samples - samples[perm]).mean()
            crps_per[i] = abs_xy - 0.5 * abs_xx

        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(d_te), 'fold': fold_idx,
            'y_actual': y_te, 'crps': crps_per, 'pit': pit,
            'mu': m['mu'], 'sigma': m['sigma'], 'lam': m['lam'], 'nu': m['nu'],
            'var_05': m['var_05'], 'var_01': m['var_01'],
            'var_005': m['var_005'], 'var_001': m['var_001'],
            'es_05': m['es_05'],
            'p_minus_5pct': m['p_minus_5'],
            'p_minus_7pct': m['p_minus_7'],
            'p_minus_10pct': m['p_minus_10'],
        })
        all_preds.append(pred_df)
        print(f'  fold[{fold_idx}] {pred_df.Date.min().date()}~{pred_df.Date.max().date()} '
              f'n={N} CRPS={crps_per.mean():.4f}')

    return pd.concat(all_preds, ignore_index=True), n_splits_eff


def apply_aci_to_quantile(y_series, q_series, alpha_target, gamma=0.01, warmup=126):
    """Apply ACI on a single VaR quantile series.

    For VaR (lower-tail quantile), use a one-sided ACI variant:
    - score_t = max(0, q_pred_t - y_t)  (positive if breached)
    - ACI updates offset so that breach rate ≈ α_target.

    Implementation: maintain offset_t. q_adjusted_t = q_pred_t - offset_t (more negative).
    """
    n = len(y_series)
    q_adjusted = np.zeros(n)
    offset_t = 0.0
    alpha_t = alpha_target
    score_hist = []
    err_hist = []
    alpha_hist = [alpha_t]

    for t in range(n):
        # Adjusted quantile (subtract offset → push VaR more negative if offset > 0)
        q_adj = q_series[t] - offset_t
        q_adjusted[t] = q_adj

        if t < warmup:
            # collect calibration scores (signed: positive if not breached, negative if breached)
            score_t = q_series[t] - y_series[t]  # >0 if y < q (not breached) WAIT — let me redefine
            # Actually for VaR (q is e.g., -2.5%), breach means y < q
            # Use one-sided CQR-like: score = q_pred - y if y > q_pred (covered above), else negative
            # Simpler: track empirical breach and adjust offset directly via ACI dual
            score_hist.append(y_series[t] - q_series[t])  # >0 if y > q (not breached)
            continue

        # Observe breach
        err_t = 1 if y_series[t] < q_adj else 0
        err_hist.append(err_t)

        # ACI dual update: target = alpha_target
        alpha_t = alpha_t + gamma * (alpha_target - err_t)
        alpha_t = float(np.clip(alpha_t, 1e-6, 1 - 1e-6))
        alpha_hist.append(alpha_t)

        # Recompute offset as (1-α_t)-quantile of score history (= y - q)
        # If err_t=1 (breach), α_t decreases → offset should increase (push VaR more negative)
        score_hist.append(y_series[t] - q_series[t])
        # offset = -quantile(scores, α_t)
        # i.e., we want q_adj such that P(y < q_adj) ≈ α_t
        # historical breach: y < q_adj ⟺ (y - q) < -offset_t
        sorted_scores = np.sort(np.array(score_hist))
        rank = int(np.ceil((len(sorted_scores) + 1) * alpha_t))
        rank = max(1, min(rank, len(sorted_scores)))
        threshold = sorted_scores[rank - 1]
        # offset = -threshold (so q_adj = q + threshold)
        offset_t = -threshold

    return q_adjusted, alpha_hist, err_hist


def evaluate_conformal(full, alpha_target, gamma_sweep=(0.005, 0.01, 0.05, 0.10),
                       block_sweep=(126, 252, 504),
                       warmup=126):
    """Apply ACI (γ sweep) + EnbPI (block sweep) on VaR_α quantile."""
    y = full['y_actual'].values
    q_label = 'var_05' if abs(alpha_target - 0.05) < 1e-6 else 'var_01'
    q_raw = full[q_label].values

    bt_raw = VARBT.var_backtest_full(y, q_raw, alpha=alpha_target)
    out = {
        'alpha_target': alpha_target,
        'q_label': q_label,
        'raw': {
            'breach_rate': float((y < q_raw).mean()),
            'kupiec_p': float(bt_raw['kupiec_uc']['p_value']),
            'kupiec_pass': bool(bt_raw['kupiec_uc']['pass_at_005']),
            'cc_p': float(bt_raw['christoffersen_cc']['p_value']) if 'christoffersen_cc' in bt_raw else None,
        },
        'aci_sweep': {},
        'enbpi_sweep': {},
    }

    # ACI sweep
    for gamma in gamma_sweep:
        q_adj, alpha_hist, err_hist = apply_aci_to_quantile(y, q_raw, alpha_target, gamma=gamma, warmup=warmup)
        y_post = y[warmup:]
        q_post = q_adj[warmup:]
        bt_adj = VARBT.var_backtest_full(y_post, q_post, alpha=alpha_target)
        out['aci_sweep'][f'gamma_{gamma}'] = {
            'breach_rate': float((y_post < q_post).mean()),
            'kupiec_p': float(bt_adj['kupiec_uc']['p_value']),
            'kupiec_pass': bool(bt_adj['kupiec_uc']['pass_at_005']),
            'cc_p': float(bt_adj['christoffersen_cc']['p_value']) if 'christoffersen_cc' in bt_adj else None,
            'long_run_coverage': float(1 - np.mean(err_hist)) if err_hist else None,
            'mean_alpha': float(np.mean(alpha_hist)),
        }

    # EnbPI sweep (block-residual)
    for block in block_sweep:
        result = F1.enbpi_one_sided_var(y, q_raw, alpha=alpha_target, block_size=block, warmup=warmup)
        q_enbpi = result['q_enbpi']
        y_post = y[warmup:]
        q_post = q_enbpi[warmup:]
        bt_adj = VARBT.var_backtest_full(y_post, q_post, alpha=alpha_target)
        out['enbpi_sweep'][f'block_{block}'] = {
            'breach_rate': result['final_breach_rate'],
            'kupiec_p': float(bt_adj['kupiec_uc']['p_value']),
            'kupiec_pass': bool(bt_adj['kupiec_uc']['pass_at_005']),
            'cc_p': float(bt_adj['christoffersen_cc']['p_value']) if 'christoffersen_cc' in bt_adj else None,
            'q_adjusted_first': float(q_enbpi[warmup]) if len(q_enbpi) > warmup else None,
            'q_adjusted_last': float(q_enbpi[-1]),
        }
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--optuna_db', type=str,
                        default='03_models/p4_ecdf_optuna/optuna.db')
    parser.add_argument('--study_name', type=str, default='p4_ecdf')
    parser.add_argument('--features', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/outputs/p4_features_panel.parquet')
    parser.add_argument('--output', type=str, default='03_models/p4_ecdf_final')
    parser.add_argument('--target_col', type=str, default='ret_h_log_pct')
    args = parser.parse_args()

    db_path = ROOT / args.optuna_db
    feat_path = Path(args.features)
    if not feat_path.is_absolute():
        feat_path = PROJECT_ROOT / feat_path
    out_dir = ROOT / args.output
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── 1. Load best trial ──
    storage = f"sqlite:///{db_path}"
    study = optuna.load_study(study_name=args.study_name, storage=storage)
    best = study.best_trial
    a = best.user_attrs
    alpha = float(a['alpha'])
    train_min = int(a['train_min'])
    taus_count = int(a['taus_count'])
    embargo = int(a['embargo'])
    n_splits = int(a['n_splits'])
    print(f"[P4-ECDF final] best trial #{best.number} loss={best.value:.4f}")
    print(f"  α={alpha:.2e}  tmin={train_min}  τ={taus_count}  emb={embargo}  nspl={n_splits}")

    # ── 2. Load features ──
    df = pd.read_parquet(feat_path)
    meta = json.loads(feat_path.with_suffix('.meta.json').read_text())
    feature_cols = meta['feature_cols']
    X = df[feature_cols].values.astype(np.float64)
    y = df[args.target_col].values.astype(np.float64)
    dates = df['Date'].values
    print(f'[P4-ECDF final] data: {len(df)} rows, {len(feature_cols)} features')

    # ── 3. Full WF train ──
    print(f'\n[P4-ECDF final] === Full walk-forward train ===')
    full, n_splits_eff = full_train_p4_ecdf(X, y, dates, alpha, train_min, taus_count,
                                              embargo, n_splits)

    # ── 4. Raw pooled metrics ──
    y_arr = full['y_actual'].values
    y_std = float(np.std(y_arr))
    crps_pooled = float(full['crps'].mean())
    crps_n = crps_pooled / y_std if y_std > 0 else None
    var05_raw = VARBT.var_backtest_full(y_arr, full['var_05'].values, alpha=0.05,
                                          es_forecasts=full['es_05'].values)
    var01_raw = VARBT.var_backtest_full(y_arr, full['var_01'].values, alpha=0.01)
    pit_chi_raw = CALIB.pit_chi_square(full['pit'].values, n_bins=10)
    pit_berk_raw = CALIB.pit_berkowitz(full['pit'].values)

    print(f'\n[RAW (no conformal)] CRPS_n={crps_n:.4f}')
    print(f'  VaR_05 Kupiec_p={var05_raw["kupiec_uc"]["p_value"]:.4f} pass={var05_raw["kupiec_uc"]["pass_at_005"]}')
    print(f'  VaR_01 Kupiec_p={var01_raw["kupiec_uc"]["p_value"]:.4f} pass={var01_raw["kupiec_uc"]["pass_at_005"]}')
    print(f'  PIT chi²={pit_chi_raw["p_value"]:.4f} pass={pit_chi_raw["pass_at_005"]}')

    # ── 5. Conformal Wrap (ACI sweep on VaR_05, VaR_01) ──
    print(f'\n[P4-ECDF final] === Conformal Wrap (ACI sweep) ===')
    aci_05 = evaluate_conformal(full, alpha_target=0.05)
    aci_01 = evaluate_conformal(full, alpha_target=0.01)

    print(f'\n[ACI on VaR_05]:')
    for k, v in aci_05['aci_sweep'].items():
        print(f"  {k}: breach={v['breach_rate']:.4f} kupiec_p={v['kupiec_p']:.4f} pass={v['kupiec_pass']}  long_cov={v['long_run_coverage']}")
    print(f'\n[ACI on VaR_01]:')
    for k, v in aci_01['aci_sweep'].items():
        print(f"  {k}: breach={v['breach_rate']:.4f} kupiec_p={v['kupiec_p']:.4f} pass={v['kupiec_pass']}  long_cov={v['long_run_coverage']}")

    # ── 6. Best ACI selection (highest Kupiec p AND PASS) ──
    best_aci_05 = max(aci_05['aci_sweep'].items(),
                       key=lambda kv: (kv[1]['kupiec_pass'], kv[1]['kupiec_p']))
    best_aci_01 = max(aci_01['aci_sweep'].items(),
                       key=lambda kv: (kv[1]['kupiec_pass'], kv[1]['kupiec_p']))
    print(f"\n[BEST ACI VaR_05] {best_aci_05[0]}: Kupiec_p={best_aci_05[1]['kupiec_p']:.4f} pass={best_aci_05[1]['kupiec_pass']}")
    print(f"[BEST ACI VaR_01] {best_aci_01[0]}: Kupiec_p={best_aci_01[1]['kupiec_p']:.4f} pass={best_aci_01[1]['kupiec_pass']}")

    # ── 7. Save ──
    full.to_parquet(out_dir / 'all_predictions.parquet')
    summary = {
        'model': 'P4-ECDF + Conformal Wrap',
        'spec': {
            'alpha': alpha, 'train_min': train_min, 'taus_count': taus_count,
            'embargo': embargo, 'n_splits': n_splits, 'n_splits_eff': n_splits_eff,
            'best_trial': best.number, 'best_loss': float(best.value),
        },
        'raw_metrics': {
            'crps_pooled': crps_pooled,
            'crps_normalized': crps_n,
            'var_05': {'kupiec_p': var05_raw['kupiec_uc']['p_value'],
                       'kupiec_pass': var05_raw['kupiec_uc']['pass_at_005'],
                       'breach_rate': float((y_arr < full['var_05'].values).mean())},
            'var_01': {'kupiec_p': var01_raw['kupiec_uc']['p_value'],
                       'kupiec_pass': var01_raw['kupiec_uc']['pass_at_005']},
            'pit_chi': pit_chi_raw,
            'pit_berkowitz': pit_berk_raw,
        },
        'aci_05': aci_05,
        'aci_01': aci_01,
        'best_aci': {
            'var_05': {'gamma': best_aci_05[0], **best_aci_05[1]},
            'var_01': {'gamma': best_aci_01[0], **best_aci_01[1]},
        },
        'trained_at': datetime.now().isoformat(),
    }
    (out_dir / 'summary.json').write_text(json.dumps(summary, indent=2, default=_json_default,
                                                       ensure_ascii=False))
    print(f"\n[saved] {out_dir / 'summary.json'}")
    print(f"[saved] {out_dir / 'all_predictions.parquet'}")

    # ── 8. AX-008 calibration gate ──
    aci_pass = (best_aci_05[1]['kupiec_pass'] and best_aci_01[1]['kupiec_pass'])
    if aci_pass:
        print(f"\n[P4-ECDF final] ✅ Conformal Wrap → VaR calibration PASS")
    else:
        print(f"\n[P4-ECDF final] ❌ Even after Conformal Wrap, VaR calibration FAIL")
        print(f"  도훈 escalate: paradigm shift 또는 P4 폐기 검토")


if __name__ == "__main__":
    main()
