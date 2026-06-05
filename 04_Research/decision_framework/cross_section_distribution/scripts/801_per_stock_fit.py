"""
801_per_stock_fit.py — CSDA Phase 2: Per-stock LASSO Quantile + ECDF + Hansen ensemble

도훈 mandate 2026-05-28 (WT-D20260528_001 Phase 2):
- 813 stocks × Best #181 spec (P4-ECDF derived)
- α=9.99e-3, train_min=3528, taus_count=15, embargo=35
- ECDF derive (primary) + Hansen Skew-t fit (secondary, ensemble)
- 종목별 시점별 forecast: μ/σ/λ/ν/VaR5/ES5/P(-5%/-10%)

Output: per_stock_forecasts.parquet (Date × Ticker × forecast metrics)

CLI:
    python 801_per_stock_fit.py [--n_stocks 10 (smoke)] [--n_jobs 8]
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
import warnings
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

warnings.filterwarnings('ignore')

PROJECT_ROOT = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
PHASE1_OUTPUT = PROJECT_ROOT / "04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet"
P3_DIR = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v3"


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LQM = _load("a1_lasso_quantile", P3_DIR / "03_models" / "a1_lasso_quantile.py")
ECDF = _load("p4_ecdf", P3_DIR / "03_models" / "p4_ecdf.py")
HSK = _load("p1_hansen_skewt", P3_DIR / "03_models" / "p1_hansen_skewt.py")


# Best #181 spec from P4-ECDF Optuna
ALPHA = 9.99e-3
TRAIN_MIN_STOCK = 1008  # 1년 reduced (개별 종목 history 짧음, 14y 대신 4y)
EMBARGO = 35
TAUS_15 = (0.005, 0.01, 0.025, 0.05, 0.075, 0.10, 0.25, 0.50,
            0.75, 0.90, 0.925, 0.95, 0.975, 0.99, 0.995)

FEATURE_COLS = [
    'log_ret_lag_1', 'log_ret_lag_2', 'log_ret_lag_5', 'log_ret_lag_22',
    'rv_5d', 'rv_22d', 'rv_60d', 'mean_5d', 'mean_22d', 'mean_60d',
    'rv_22d_z', 'drawdown_z',
    'rv_120d', 'rv_252d', 'mean_120d', 'mean_252d',
    'momentum_22_60_slope', 'drawdown_60d',
    'relative_strength_60d', 'sector_beta_120d', 'peer_corr_60d',
    'vix_lag1', 'vix_60d_z', 'term_spread_lag1', 'dgs10_lag1', 'nfci_lag1',
    'kr_gov10y_lag1', 'kr_term_spread_lag1', 'kr_credit_spread_lag1', 'krwusd_vol_60d_z',
]


def fit_one_stock(ticker_data: tuple) -> pd.DataFrame | None:
    """Fit one stock with walk-forward LASSO Quantile + ECDF.

    Returns DataFrame of (Date, Ticker, forecast metrics) for each prediction sig_date.
    """
    ticker, df = ticker_data
    df = df.sort_values('Date').reset_index(drop=True)

    # Drop NA features
    df_valid = df.dropna(subset=FEATURE_COLS + ['ret_h_21d_forward']).reset_index(drop=True)
    if len(df_valid) < TRAIN_MIN_STOCK + 100:
        return None  # insufficient history

    X = df_valid[FEATURE_COLS].values.astype(np.float64)
    y = df_valid['ret_h_21d_forward'].values.astype(np.float64)
    dates = df_valid['Date'].values
    taus_np = np.array(TAUS_15)

    # Sig-date sample: monthly anchor — last business day of each month
    df_valid['ym'] = pd.to_datetime(df_valid['Date']).dt.to_period('M')
    monthly_last = df_valid.groupby('ym').tail(1).reset_index(drop=True)
    # Each monthly anchor predicts next month's distribution (21d forward)

    predictions = []
    np.random.seed(0)

    for idx, anchor_row in monthly_last.iterrows():
        anchor_date = anchor_row['Date']
        anchor_pos = df_valid[df_valid['Date'] == anchor_date].index[0]

        # Train: [0, anchor_pos - embargo]
        train_end = anchor_pos - EMBARGO
        if train_end < TRAIN_MIN_STOCK:
            continue  # insufficient train history

        X_tr = X[:train_end]
        y_tr = y[:train_end]
        x_pred = X[anchor_pos:anchor_pos+1]

        try:
            model = LQM.LassoQuantileGaR(taus=TAUS_15, alpha=ALPHA, standardize=True)
            model.fit(X_tr, y_tr)
            Q_pred = model.predict_all_quantiles(x_pred, fix_crossing=True)
            # ECDF metrics
            ecdf_m = ECDF.derive_metrics_per_obs(Q_pred, taus_np)
            # Hansen fit (per-obs)
            hsk_m = HSK.derive_metrics_per_obs(Q_pred, taus_np)

            # Ensemble: average ECDF + Hansen for μ, σ, λ, ν (where both available)
            mu_ens = 0.5 * (ecdf_m['mu'][0] + hsk_m['mu'][0])
            sigma_ens = 0.5 * (ecdf_m['sigma'][0] + hsk_m['sigma'][0])
            lam_ens = 0.5 * (ecdf_m['lam'][0] + hsk_m['lam'][0])
            # ν: ECDF proxy + Hansen actual → take Hansen (analytical)
            nu_ens = hsk_m['nu'][0]

            predictions.append({
                'Date': anchor_date,
                'Ticker': ticker,
                # Ensemble (primary)
                'mu': mu_ens, 'sigma': sigma_ens, 'lam': lam_ens, 'nu': nu_ens,
                # ECDF (primary metrics)
                'var_05': ecdf_m['var_05'][0], 'var_01': ecdf_m['var_01'][0],
                'es_05': ecdf_m['es_05'][0],
                'p_minus_5pct': ecdf_m['p_minus_5'][0],
                'p_minus_7pct': ecdf_m['p_minus_7'][0],
                'p_minus_10pct': ecdf_m['p_minus_10'][0],
                # Hansen secondary
                'hsk_mu': hsk_m['mu'][0],
                'hsk_sigma': hsk_m['sigma'][0],
                'hsk_lam': hsk_m['lam'][0],
                'hsk_nu': hsk_m['nu'][0],
                # ECDF secondary
                'ecdf_mu': ecdf_m['mu'][0],
                'ecdf_sigma': ecdf_m['sigma'][0],
                'ecdf_lam': ecdf_m['lam'][0],
                # Realized (for sanity, NaN at future dates)
                'y_actual': anchor_row['ret_h_21d_forward'],
            })
        except Exception as e:
            # Skip failed sig_dates
            continue

    if not predictions:
        return None
    return pd.DataFrame(predictions)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--n_stocks', type=int, default=None,
                        help='Smoke test: limit to N stocks. None = all')
    parser.add_argument('--n_jobs', type=int, default=8, help='Parallel workers')
    parser.add_argument('--output', type=str,
                        default='04_Research/decision_framework/cross_section_distribution/outputs/per_stock_forecasts.parquet')
    args = parser.parse_args()

    print(f'[CSDA Phase 2] Loading features panel...')
    panel = pd.read_parquet(PHASE1_OUTPUT)
    panel['Date'] = pd.to_datetime(panel['Date'])
    print(f'  Panel: {len(panel):,} rows, {panel.Ticker.nunique()} tickers')

    # Group by Ticker
    grouped = list(panel.groupby('Ticker', sort=False))
    if args.n_stocks:
        grouped = grouped[:args.n_stocks]
        print(f'  SMOKE TEST: {len(grouped)} stocks only')
    print(f'  Total stocks to fit: {len(grouped)}')

    t0 = datetime.now()
    all_predictions = []
    n_done = 0
    n_skipped = 0

    if args.n_jobs > 1:
        with ProcessPoolExecutor(max_workers=args.n_jobs) as executor:
            futures = {executor.submit(fit_one_stock, td): td[0] for td in grouped}
            for fut in as_completed(futures):
                ticker = futures[fut]
                try:
                    result = fut.result()
                except Exception as e:
                    print(f'  [{ticker}] FAILED: {e}')
                    n_skipped += 1
                    continue
                if result is not None and len(result) > 0:
                    all_predictions.append(result)
                else:
                    n_skipped += 1
                n_done += 1
                if n_done % 50 == 0:
                    elapsed = (datetime.now() - t0).total_seconds()
                    rate = n_done / elapsed
                    eta = (len(grouped) - n_done) / rate if rate > 0 else float('inf')
                    print(f'  [{n_done}/{len(grouped)}] rate={rate:.1f}/s ETA={eta/60:.1f}min, skipped={n_skipped}')
    else:
        for td in grouped:
            ticker = td[0]
            result = fit_one_stock(td)
            if result is not None and len(result) > 0:
                all_predictions.append(result)
            else:
                n_skipped += 1
            n_done += 1
            if n_done % 20 == 0:
                print(f'  [{n_done}/{len(grouped)}] skipped={n_skipped}')

    elapsed = (datetime.now() - t0).total_seconds()
    print(f'\n[CSDA Phase 2] Done. {n_done} stocks processed, {n_skipped} skipped in {elapsed/60:.1f}min')

    if not all_predictions:
        print('[CSDA Phase 2] NO predictions generated!')
        return

    df_pred = pd.concat(all_predictions, ignore_index=True)
    df_pred = df_pred.sort_values(['Date', 'Ticker']).reset_index(drop=True)
    print(f'  Total predictions: {len(df_pred):,} (Date × Ticker)')
    print(f'  Date range: {df_pred.Date.min().date()} ~ {df_pred.Date.max().date()}')
    print(f'  Tickers: {df_pred.Ticker.nunique()}')

    out_path = PROJECT_ROOT / args.output
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df_pred.to_parquet(out_path)
    print(f'  Saved → {out_path}')

    # Meta
    meta = {
        'wt_id': 'WT-D20260528_001',
        'phase': 'CSDA Phase 2',
        'spec': {
            'alpha': ALPHA, 'train_min_stock': TRAIN_MIN_STOCK,
            'embargo': EMBARGO, 'taus_count': len(TAUS_15),
            'n_features': len(FEATURE_COLS),
        },
        'n_predictions': len(df_pred),
        'n_tickers': int(df_pred.Ticker.nunique()),
        'date_start': str(df_pred.Date.min().date()),
        'date_end': str(df_pred.Date.max().date()),
        'n_stocks_processed': n_done,
        'n_stocks_skipped': n_skipped,
        'elapsed_min': elapsed / 60,
        'built_at': datetime.now().isoformat(),
    }
    meta_path = out_path.with_suffix('.meta.json')
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(f'  Meta → {meta_path}')


if __name__ == '__main__':
    main()
