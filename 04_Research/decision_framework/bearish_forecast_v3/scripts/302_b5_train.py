"""
302_b5_train.py — Phase 5a-2.A B5 NGBoost paper baseline reproduce on KOSPI200

도훈 confirm 2026-05-24:
- B5 paper baseline (returns + RV) on KOSPI200 1-day forward
- ⚠️ paper i.i.d. assumption → purging/embargo 5-fold CV mandatory (CR-V04)
- AMENDMENT E07: paper UCI tabular only → KR equity 첫 적용 (v3)

Spec (paper Algorithm 1 + Section 4):
- 5 built-in distributions: Normal, LogNormal, Laplace, Exponential
- (skewed-t custom: Phase 5a-2.B Stage 2 implement)
- depth ∈ {3, 4, 5, 6}
- n_estimators ∈ {500, 1000, 2000}
- learning_rate ∈ {0.001, 0.01, 0.1}
- Natural gradient default True

Stage 1 baseline: distribution=Normal, depth=4, n_est=500, lr=0.01.

Reference: Duan et al 2020 ICML, arxiv 1910.03225v4

Output:
- 03_models/b5_paper_reproduce/{dist}_{config}/fold_{k}_predictions.parquet
- 04_evaluation/b5_paper_metrics.json
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


METRICS = _load_module("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load_module("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load_module("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
CVMOD = _load_module("walk_forward_cv", str(ROOT / "scripts" / "200_walk_forward_cv.py"))


# ─── NGBoost distribution registry ─────────────────────────────────────────
from ngboost import NGBoost
from ngboost.distns import Normal, LogNormal, Laplace, Exponential
from ngboost.scores import LogScore

NGB_DISTS = {
    'normal': Normal,
    'lognormal': LogNormal,
    'laplace': Laplace,
    'exponential': Exponential,
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
    raise TypeError(f"Object of type {type(obj).__name__} not JSON serializable")


# ─── Data + features ───────────────────────────────────────────────────────
def load_kospi_features(cfg: dict) -> pd.DataFrame:
    """Build KOSPI200 features + target.

    Features (paper baseline):
    - lagged log returns t-1, t-2, t-5, t-10, t-22
    - rolling vol 5d, 22d, 60d
    - rolling mean 5d, 22d, 60d
    - log_return latest
    """
    bm_path = PROJECT_ROOT / cfg['data']['bm_path']
    bm = pd.read_parquet(bm_path)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    bm['log_ret'] = np.log(bm['BM_Close']).diff()

    # Lagged returns
    for lag in [1, 2, 5, 10, 22]:
        bm[f'log_ret_lag_{lag}'] = bm['log_ret'].shift(lag)

    # Rolling vol (realized volatility — uses past info, PIT safe)
    for w in [5, 22, 60]:
        bm[f'rv_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()
        bm[f'mean_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()

    # Forward target — horizon
    horizon_mode = cfg['data'].get('horizon', 'paper')
    h = 1 if horizon_mode == 'paper' else 21
    bm['ret_fwd'] = np.log(bm['BM_Close'].shift(-h) / bm['BM_Close'])

    # Filter to paper window
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    bm = bm[(bm['Date'] >= date_start) & (bm['Date'] <= date_end)].reset_index(drop=True)

    # Drop rows with NaN
    feature_cols = [c for c in bm.columns if c not in ('Date', 'BM_Close', 'BM_Ret', 'ret_fwd')]
    bm = bm.dropna(subset=feature_cols + ['ret_fwd']).reset_index(drop=True)

    # Percent scale
    if cfg['data'].get('percent_scale', True):
        for c in bm.columns:
            if c.startswith(('log_ret', 'rv_', 'mean_', 'ret_fwd')):
                bm[c] = bm[c] * 100.0

    return bm, feature_cols


# ─── Standardization (per CV fold) ─────────────────────────────────────────
def fit_standardize(X_train: np.ndarray) -> dict:
    return {
        'mu': X_train.mean(axis=0),
        'std': X_train.std(axis=0) + 1e-8,
    }


def apply_standardize(X: np.ndarray, stdz: dict) -> np.ndarray:
    return (X - stdz['mu']) / stdz['std']


# ─── Training one config one fold ──────────────────────────────────────────
def train_eval_one_fold(
    X_train: np.ndarray, y_train: np.ndarray,
    X_test: np.ndarray, y_test: np.ndarray,
    dist_name: str, n_est: int, lr: float, max_depth: int,
    seed: int = 0,
) -> dict:
    """Train NGBoost + evaluate on test fold."""
    np.random.seed(seed)
    dist = NGB_DISTS[dist_name]
    # Base learner: shallow tree
    from sklearn.tree import DecisionTreeRegressor
    base = DecisionTreeRegressor(criterion="friedman_mse", max_depth=max_depth, random_state=seed)
    model = NGBoost(
        Dist=dist,
        Score=LogScore,
        Base=base,
        n_estimators=n_est,
        learning_rate=lr,
        natural_gradient=True,
        random_state=seed,
        verbose=False,
    )

    # Internal validation split (last 20% of train) for early stopping
    n_train = len(X_train)
    val_frac = 0.2
    val_n = max(int(n_train * val_frac), 100)
    X_tr_in, X_va = X_train[:-val_n], X_train[-val_n:]
    y_tr_in, y_va = y_train[:-val_n], y_train[-val_n:]
    # Fit with early stopping
    model.fit(X_tr_in, y_tr_in, X_val=X_va, Y_val=y_va, early_stopping_rounds=20)

    # Test predictions
    dist_pred = model.pred_dist(X_test)
    # Extract NLL per obs (use LogScore.score returns per-obs negative log score)
    # NGBoost dist_pred has 'logpdf' method
    log_pdf = dist_pred.logpdf(y_test)
    nll_per = -log_pdf

    # CRPS via empirical sampling (NGBoost has dist samples)
    samples = dist_pred.sample(2000).T  # (N, 2000)
    crps_per = METRICS.crps_empirical_np(samples, y_test)

    # VaR 5% / 1%
    var_05 = np.quantile(samples, 0.05, axis=1)
    var_01 = np.quantile(samples, 0.01, axis=1)

    # PIT
    cdf_vals = (samples <= y_test[:, None]).mean(axis=1)

    return {
        'crps_per_obs': crps_per,
        'nll_per_obs': nll_per,
        'pit_values': cdf_vals,
        'var_05_forecasts': var_05,
        'var_01_forecasts': var_01,
        'y_test': y_test,
        'best_iter': model.best_val_loss_itr if hasattr(model, 'best_val_loss_itr') else n_est,
    }


# ─── Main orchestration ────────────────────────────────────────────────────
def run_b5_baseline(cfg_path: str, dists: list, configs: list, output_dir: str, seed: int = 0):
    """Run B5 NGBoost paper baseline reproduce."""
    with open(cfg_path, 'r') as f:
        cfg = yaml.safe_load(f)
    print("[b5_train] config loaded")

    df, feature_cols = load_kospi_features(cfg)
    horizon = cfg['data'].get('horizon', 'paper')
    pct = cfg['data'].get('percent_scale', True)
    print(f"[b5_train] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")
    print(f"[b5_train] features: {len(feature_cols)} | horizon={horizon} | percent_scale={pct}")

    X = df[feature_cols].values.astype(np.float32)
    y = df['ret_fwd'].values.astype(np.float32)
    dates = df['Date'].values

    # Walk-forward purged CV (Lopez de Prado 2018, CR-V04)
    cv_cfg = cfg.get('walk_forward', {})
    splitter = CVMOD.PurgedWalkForwardCV(
        n_splits=cv_cfg.get('n_splits', 5),
        train_min=cv_cfg.get('train_min', 1008),
        test_size=cv_cfg.get('test_window', 504),
        embargo=cv_cfg.get('embargo', 21),
    )
    sanity = CVMOD.sanity_check_cv(splitter, X)
    print(f"[b5_train] CV sanity: {sanity}")

    os.makedirs(output_dir, exist_ok=True)
    all_results = {}

    for dist_name in dists:
        for config_dict in configs:
            n_est = config_dict['n_est']
            lr = config_dict['lr']
            depth = config_dict['depth']
            tag = f"{dist_name}_n{n_est}_lr{lr}_d{depth}"
            print(f"\n[b5_train] ====== {tag} ======")
            sub_dir = Path(output_dir) / tag
            sub_dir.mkdir(parents=True, exist_ok=True)

            fold_metrics = []
            all_test = []
            for fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
                X_tr, y_tr = X[tr_idx], y[tr_idx]
                X_te, y_te = X[te_idx], y[te_idx]
                dates_te = dates[te_idx]

                stdz = fit_standardize(X_tr)
                X_tr_z = apply_standardize(X_tr, stdz)
                X_te_z = apply_standardize(X_te, stdz)

                try:
                    result = train_eval_one_fold(
                        X_tr_z, y_tr, X_te_z, y_te,
                        dist_name=dist_name, n_est=n_est, lr=lr, max_depth=depth,
                        seed=seed,
                    )
                except Exception as e:
                    print(f"  fold[{fold_idx}] FAILED: {e}")
                    continue

                crps_mean = float(np.mean(result['crps_per_obs']))
                nll_mean = float(np.mean(result['nll_per_obs']))
                var_05_bt = VARBT.var_backtest_full(y_te, result['var_05_forecasts'], alpha=0.05)
                var_01_bt = VARBT.var_backtest_full(y_te, result['var_01_forecasts'], alpha=0.01)
                pit_chi = CALIB.pit_chi_square(result['pit_values'], n_bins=10)

                fold_metrics.append({
                    'fold': fold_idx,
                    'crps_mean': crps_mean,
                    'nll_mean': nll_mean,
                    'n_obs': len(y_te),
                    'best_iter': result['best_iter'],
                    'var_05_kupiec_pass': var_05_bt['kupiec_uc']['pass_at_005'],
                    'var_01_kupiec_pass': var_01_bt['kupiec_uc']['pass_at_005'],
                    'pit_chi_pass': pit_chi['pass_at_005'],
                })

                pred_df = pd.DataFrame({
                    'Date': pd.to_datetime(dates_te),
                    'y_actual': y_te,
                    'crps': result['crps_per_obs'],
                    'nll': result['nll_per_obs'],
                    'pit': result['pit_values'],
                    'var_05': result['var_05_forecasts'],
                    'var_01': result['var_01_forecasts'],
                })
                pred_df.to_parquet(sub_dir / f"fold_{fold_idx:02d}_predictions.parquet")
                all_test.append(pred_df)

                print(f"  fold[{fold_idx}] CRPS={crps_mean:.5f} NLL={nll_mean:.4f} "
                      f"VaR_05={var_05_bt['kupiec_uc']['pass_at_005']} "
                      f"VaR_01={var_01_bt['kupiec_uc']['pass_at_005']} "
                      f"PIT_chi={pit_chi['pass_at_005']} "
                      f"best_iter={result['best_iter']}")

            # Pool across folds
            if all_test:
                full_pred = pd.concat(all_test, ignore_index=True)
                full_pred.to_parquet(sub_dir / "all_predictions.parquet")
                crps_pool = float(full_pred['crps'].mean())
                nll_pool = float(full_pred['nll'].mean())
                var_05_pool = VARBT.var_backtest_full(
                    full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05
                )
                var_01_pool = VARBT.var_backtest_full(
                    full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01
                )
                pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

                all_results[tag] = {
                    'n_test_obs_total': int(len(full_pred)),
                    'crps_pooled': crps_pool,
                    'nll_pooled': nll_pool,
                    'var_05_backtest_pooled': var_05_pool,
                    'var_01_backtest_pooled': var_01_pool,
                    'pit_chi_square_pooled': pit_pool,
                    'fold_metrics': fold_metrics,
                    'config': {
                        'dist': dist_name,
                        'n_estimators': n_est,
                        'learning_rate': lr,
                        'max_depth': depth,
                    },
                }
                print(f"[{tag}] POOLED: CRPS={crps_pool:.5f} NLL={nll_pool:.4f} n={len(full_pred)}")

    metrics_path = Path(output_dir) / "b5_paper_metrics.json"
    with open(metrics_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[b5_train] aggregate metrics saved: {metrics_path}")

    return all_results


# ─── CLI ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b5_search_space.yaml')
    parser.add_argument('--output', type=str, default='03_models/b5_paper_reproduce')
    parser.add_argument('--dists', type=str, default='normal',
                        help='comma-separated: normal,lognormal,laplace,exponential')
    parser.add_argument('--stage', type=str, default='baseline',
                        help='baseline (1 config) or grid (sweep)')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    dists = args.dists.split(',')
    if args.stage == 'baseline':
        configs = [{'n_est': 500, 'lr': 0.01, 'depth': 4}]
    elif args.stage == 'grid':
        configs = []
        for n_est in [500, 1000, 2000]:
            for lr in [0.001, 0.01, 0.1]:
                for depth in [3, 4, 5, 6]:
                    configs.append({'n_est': n_est, 'lr': lr, 'depth': depth})
    else:
        raise ValueError(f"Unknown stage: {args.stage}")

    print(f"[b5_train] CFG: {cfg_path}")
    print(f"[b5_train] OUT: {output_dir}")
    print(f"[b5_train] dists: {dists}  configs: {len(configs)}  seed: {args.seed}")

    run_b5_baseline(
        cfg_path=str(cfg_path),
        dists=dists,
        configs=configs,
        output_dir=str(output_dir),
        seed=args.seed,
    )


if __name__ == "__main__":
    main()
