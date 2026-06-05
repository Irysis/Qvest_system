"""
489_p4_ecdf_extend_oos.py — Extend P4-ECDF OOS predictions to 2026-04

도훈 mandate 2026-05-27: STR_1718 백테스트 2026-05까지 → P4 OOS extension 필요.
- Best #181 spec: α=9.99e-3, train_min=3528, taus_count=15, embargo=35, n_splits=8
- Existing fold 0~2 (test 2015-12 ~ 2022-05) 그대로 유지
- 추가 fold 3 (test 2022-06 ~ 2026-04) 신규 산출
"""
from __future__ import annotations
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

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


# Best #181 spec
ALPHA = 9.99e-3
TRAIN_MIN = 3528
EMBARGO = 35
TAUS_COUNT = 15
TAUS_15 = (0.005, 0.01, 0.025, 0.05, 0.075, 0.10, 0.25, 0.50,
            0.75, 0.90, 0.925, 0.95, 0.975, 0.99, 0.995)


def main():
    feat_path = PROJECT_ROOT / '04_Research/decision_framework/bearish_forecast_v3/outputs/p4_features_panel.parquet'
    df = pd.read_parquet(feat_path)
    meta = json.loads(feat_path.with_suffix('.meta.json').read_text())
    feature_cols = meta['feature_cols']
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values('Date').reset_index(drop=True)
    n = len(df)
    print(f'[ext] features: {n} rows, {len(feature_cols)} cols')
    print(f'[ext] Date range: {df.Date.min().date()} ~ {df.Date.max().date()}')

    # Existing fold structure (Best #181):
    # fold 0: train [0, 3528), test [3528+35, 3528+504+35) = [3563, 4067)
    # fold 1: train [0, 4067), test [4067+35, 4067+504+35) = [4102, 4606)  WAIT
    # Re-check: test_start = train_min + fold * test_size + embargo
    # fold 0: test [3528 + 0*504 + 35, 4067) = [3563, 4067)
    # fold 1: test [3528 + 504 + 35, 4571) = [4067, 4571)
    # fold 2: test [3528 + 1008 + 35, 5075) = [4571, 5075)
    # fold 3: test [3528 + 1512 + 35, 5579) = [5075, 5579)
    # fold 4: test [3528 + 2016 + 35, 6083) = [5579, ...)  but n=5993
    # → fold 4 partial: test_start=5579, test_end=5993 (414 obs)

    # Generate fold 3 + 4 (extend beyond what 487 produced)
    test_size = 504
    folds_new = []
    for fold_idx in [3, 4]:
        test_start = TRAIN_MIN + fold_idx * test_size + EMBARGO
        test_end = min(test_start + test_size, n)
        if test_start >= n:
            break
        train_end = test_start - EMBARGO
        if train_end < TRAIN_MIN:
            continue
        folds_new.append((fold_idx, np.arange(0, train_end), np.arange(test_start, test_end)))
        d0, d1 = df.Date.iloc[test_start], df.Date.iloc[test_end - 1]
        print(f'  fold {fold_idx}: train [{0}:{train_end}] ({df.Date.iloc[0].date()}~{df.Date.iloc[train_end-1].date()})')
        print(f'           test  [{test_start}:{test_end}] ({d0.date()}~{d1.date()}, n={test_end-test_start})')

    X = df[feature_cols].values.astype(np.float64)
    y = df['ret_h_log_pct'].values.astype(np.float64)
    dates = df['Date'].values
    taus_np = np.array(TAUS_15)
    rng = np.random.default_rng(0)
    np.random.seed(0)

    all_preds = []
    for fold_idx, tr_idx, te_idx in folds_new:
        X_tr, y_tr = X[tr_idx], y[tr_idx]
        X_te, y_te = X[te_idx], y[te_idx]
        d_te = dates[te_idx]
        print(f'\n[fold {fold_idx}] fitting LASSO Quantile (train n={len(X_tr)})...')
        model = LQM.LassoQuantileGaR(taus=TAUS_15, alpha=ALPHA, standardize=True)
        model.fit(X_tr, y_tr)
        Q_te = model.predict_all_quantiles(X_te, fix_crossing=True)
        print(f'  deriving ECDF metrics (n={len(X_te)})...')
        m = ECDF.derive_metrics_per_obs(Q_te, taus_np)
        pit = ECDF.ecdf_pit_per_obs(y_te, Q_te, taus_np)
        N = len(y_te)
        crps_per = np.zeros(N)
        print(f'  computing CRPS...')
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
        print(f"  fold[{fold_idx}] {pred_df.Date.min().date()}~{pred_df.Date.max().date()} "
              f"CRPS={crps_per.mean():.4f}")

    new_preds = pd.concat(all_preds, ignore_index=True)

    # Merge with existing
    existing_path = ROOT / "03_models" / "p4_ecdf_final" / "all_predictions.parquet"
    existing = pd.read_parquet(existing_path)
    existing['Date'] = pd.to_datetime(existing['Date'])

    # Append (existing has fold 0,1,2; new has fold 3,4)
    combined = pd.concat([existing, new_preds], ignore_index=True)
    combined = combined.sort_values('Date').reset_index(drop=True)
    print(f'\n[ext] combined: {len(combined)} rows ({combined.Date.min().date()} ~ {combined.Date.max().date()})')
    print(f'  existing folds: {existing.fold.unique().tolist()}')
    print(f'  new folds: {new_preds.fold.unique().tolist()}')

    out_path = ROOT / "03_models" / "p4_ecdf_final" / "all_predictions_extended.parquet"
    combined.to_parquet(out_path)
    print(f'[saved] {out_path}')


if __name__ == '__main__':
    main()
