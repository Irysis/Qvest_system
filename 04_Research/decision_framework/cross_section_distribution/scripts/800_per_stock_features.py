"""
800_per_stock_features.py — Per-stock features panel (CSDA Phase 1)

도훈 mandate 2026-05-28 (WT-D20260528_001):
- KOSPI200 ∪ KOSDAQ150 ~350 종목 각각 ~30 features × ~6000 day
- 그룹 A 자체 12 + B horizon 6 + C cross-section 3 + D macro 9 = 30
- PIT C1-C15 + bear_date_audit + label_direction validate

Universe: RAWDATA의 K200 == 1 OR KQ150 == 1 (시기별)
Output: long-format parquet (Date × Ticker × 30 features + ret_h_21d_forward)

CLI:
    python 800_per_stock_features.py [--output ...] [--start 2005-01-01]
"""
from __future__ import annotations
import argparse
import sys
import warnings
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa

warnings.filterwarnings('ignore')

PROJECT_ROOT = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')

# Constants
HORIZON = 21
PERCENT_SCALE = True
DATE_START_DEFAULT = "2005-01-03"
EPS = 1e-8

RAWDATA_CACHE = PROJECT_ROOT / ".cache" / "rawdata.parquet"
FRED_PARQUET = PROJECT_ROOT / ".cache" / "fred_macro.parquet"
ECOS_BOND = PROJECT_ROOT / ".cache" / "ecos_bond_rates.parquet"
ECOS_KRWUSD = PROJECT_ROOT / ".cache" / "ecos_krw_usd.parquet"
BM_PARQUET = PROJECT_ROOT / ".cache" / "benchmark.parquet"


def expanding_z(s: pd.Series, min_periods: int = 60) -> pd.Series:
    mu = s.expanding(min_periods=min_periods).mean()
    sd = s.expanding(min_periods=min_periods).std() + EPS
    return (s - mu) / sd


def load_rawdata():
    """Load RAWDATA from cache."""
    if not RAWDATA_CACHE.exists():
        raise FileNotFoundError(f"RAWDATA cache not found: {RAWDATA_CACHE}")
    df = pd.read_parquet(RAWDATA_CACHE)
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values(['Ticker', 'Date']).reset_index(drop=True)
    return df


def load_macro_features():
    """Load FRED + KR macro features (P4 panel과 동일 logic)."""
    # FRED long → wide
    fred = pd.read_parquet(FRED_PARQUET)
    fred['Date'] = pd.to_datetime(fred['Date'])
    series_ids = ['VIXCLS', 'T10Y2Y', 'DGS10', 'NFCI']
    sub = fred[fred['Series_ID'].isin(series_ids)][['Date', 'Series_ID', 'Value']]
    fred_w = sub.pivot(index='Date', columns='Series_ID', values='Value').reset_index()
    fred_w = fred_w.sort_values('Date').reset_index(drop=True)
    fred_w['NFCI'] = fred_w['NFCI'].ffill(limit=7)
    fred_w['vix_lag1'] = fred_w['VIXCLS'].shift(1)
    fred_w['term_spread_lag1'] = fred_w['T10Y2Y'].shift(1)
    fred_w['dgs10_lag1'] = fred_w['DGS10'].shift(1)
    fred_w['nfci_lag1'] = fred_w['NFCI'].shift(1)
    fred_w['vix_60d_z'] = expanding_z(fred_w['vix_lag1'])

    # KR bond
    br = pd.read_parquet(ECOS_BOND)
    br['Date'] = pd.to_datetime(br['Date'])
    kr_series = ['KR_Gov10Y', 'KR_Gov3Y', 'KR_CorpBBB']
    sub = br[br['Series'].isin(kr_series)][['Date', 'Series', 'Value']]
    kr = sub.pivot(index='Date', columns='Series', values='Value').reset_index()
    kr = kr.sort_values('Date').reset_index(drop=True)
    for c in ['KR_Gov10Y', 'KR_Gov3Y', 'KR_CorpBBB']:
        if c in kr.columns:
            kr[c] = kr[c].ffill(limit=7)
    kr['kr_gov10y_lag1'] = kr['KR_Gov10Y'].shift(1)
    kr['kr_term_spread_lag1'] = (kr['KR_Gov10Y'] - kr['KR_Gov3Y']).shift(1)
    kr['kr_credit_spread_lag1'] = (kr['KR_CorpBBB'] - kr['KR_Gov10Y']).shift(1)

    # KRW_USD
    krw = pd.read_parquet(ECOS_KRWUSD)
    krw['Date'] = pd.to_datetime(krw['Date'])
    krw = krw[['Date', 'KRW_USD']].sort_values('Date').reset_index(drop=True)
    krw['KRW_USD'] = krw['KRW_USD'].ffill(limit=7)
    krw_ret = np.log(krw['KRW_USD']).diff()
    krwusd_vol = krw_ret.rolling(60, min_periods=20).std()
    krw['krwusd_vol_60d_z'] = expanding_z(krwusd_vol)

    fred_feats = ['vix_lag1', 'vix_60d_z', 'term_spread_lag1', 'dgs10_lag1', 'nfci_lag1']
    kr_feats = ['kr_gov10y_lag1', 'kr_term_spread_lag1', 'kr_credit_spread_lag1']
    krw_feats = ['krwusd_vol_60d_z']

    macro = fred_w[['Date'] + fred_feats]
    macro = macro.merge(kr[['Date'] + kr_feats], on='Date', how='outer')
    macro = macro.merge(krw[['Date'] + krw_feats], on='Date', how='outer')
    macro = macro.sort_values('Date').reset_index(drop=True)
    macro_cols = fred_feats + kr_feats + krw_feats
    return macro, macro_cols


def compute_stock_features(stock_df: pd.DataFrame, horizon: int = HORIZON) -> pd.DataFrame:
    """Per-stock feature computation. Assumes stock_df sorted by Date.

    Returns DataFrame with all features + ret_h_21d_forward.
    Universe (K200 / KQ150) flag retained for filtering later.
    """
    s = stock_df.copy().reset_index(drop=True)
    n = len(s)
    if n < 100:
        return None  # too short, skip

    # log return
    s['log_ret'] = np.log(s['Close']).diff()

    # Group A — base 12
    for lag in [1, 2, 5, 22]:
        s[f'log_ret_lag_{lag}'] = s['log_ret'].shift(lag)
    for w in [5, 22, 60]:
        s[f'rv_{w}d'] = s['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()
        s[f'mean_{w}d'] = s['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()
    # drawdown
    cum_max = s['Close'].cummax()
    s['drawdown'] = (s['Close'] - cum_max) / (cum_max + EPS)
    s['rv_22d_z'] = expanding_z(s['rv_22d'])
    s['drawdown_z'] = expanding_z(s['drawdown'])

    # Group B — horizon-aware 6
    for w in [120, 252]:
        s[f'rv_{w}d'] = s['log_ret'].rolling(w, min_periods=max(20, w // 4)).std()
        s[f'mean_{w}d'] = s['log_ret'].rolling(w, min_periods=max(20, w // 4)).mean()
    s['momentum_22_60_slope'] = (s['mean_22d'] - s['mean_60d']) / (s['rv_22d'] + EPS)
    rolling_max_60 = s['Close'].rolling(60, min_periods=20).max()
    s['drawdown_60d'] = (s['Close'] - rolling_max_60) / (rolling_max_60 + EPS)

    # Group C — cross-section 3 (computed externally after merge with BM/sector)
    # placeholder set elsewhere

    # forward 21d log return (label) - simple return for audit compat
    s['ret_h_21d_forward'] = s['Close'].shift(-horizon) / s['Close'] - 1.0

    return s


def add_cross_section_features(panel: pd.DataFrame, bm: pd.DataFrame) -> pd.DataFrame:
    """Add cross-section features: relative_strength, sector_beta, peer_corr.

    Args:
        panel: long-format DataFrame with Date, Ticker, log_ret, Sector, Close
        bm: benchmark daily series (Date, BM_Close, BM_log_ret)
    """
    bm = bm.copy()
    bm['BM_log_ret'] = np.log(bm['BM_Close']).diff()
    bm['BM_60d_ret'] = bm['BM_log_ret'].rolling(60, min_periods=20).sum()

    # merge BM for each row
    panel = panel.merge(bm[['Date', 'BM_log_ret', 'BM_60d_ret']], on='Date', how='left')

    # relative_strength_60d (stock 60d log ret - BM 60d)
    panel['stock_60d_ret'] = panel.groupby('Ticker')['log_ret'].rolling(60, min_periods=20).sum().reset_index(0, drop=True)
    panel['relative_strength_60d'] = panel['stock_60d_ret'] - panel['BM_60d_ret']

    # sector_beta_120d: cov(stock, BM) / var(BM) rolling 120d per stock
    def rolling_beta(group):
        # group sorted by Date
        x = group['log_ret'].values
        y = group['BM_log_ret'].values
        n = len(x)
        beta = np.full(n, np.nan)
        for i in range(120, n):
            window_x = x[i-120:i]
            window_y = y[i-120:i]
            mask = ~(np.isnan(window_x) | np.isnan(window_y))
            if mask.sum() >= 60:
                cov = np.cov(window_x[mask], window_y[mask])[0, 1]
                var = np.var(window_y[mask])
                if var > 0:
                    beta[i] = cov / var
        return beta

    panel = panel.sort_values(['Ticker', 'Date']).reset_index(drop=True)
    betas = []
    for ticker, grp in panel.groupby('Ticker', sort=False):
        b = rolling_beta(grp)
        betas.append(b)
    panel['sector_beta_120d'] = np.concatenate(betas)

    # peer_corr_60d — placeholder: sector-mean log_ret correlation (simplified)
    # Compute per-sector mean log_ret per Date, then corr stock vs sector mean (rolling 60d)
    panel['sector_log_ret_mean'] = panel.groupby(['Date', 'Sector'])['log_ret'].transform('mean')

    def rolling_corr(group):
        x = group['log_ret'].values
        y = group['sector_log_ret_mean'].values
        n = len(x)
        corr = np.full(n, np.nan)
        for i in range(60, n):
            window_x = x[i-60:i]
            window_y = y[i-60:i]
            mask = ~(np.isnan(window_x) | np.isnan(window_y))
            if mask.sum() >= 30:
                if np.std(window_x[mask]) > 0 and np.std(window_y[mask]) > 0:
                    corr[i] = np.corrcoef(window_x[mask], window_y[mask])[0, 1]
        return corr

    corrs = []
    for ticker, grp in panel.groupby('Ticker', sort=False):
        c = rolling_corr(grp)
        corrs.append(c)
    panel['peer_corr_60d'] = np.concatenate(corrs)
    return panel


def build_per_stock_panel(date_start: str = DATE_START_DEFAULT,
                            date_end: str | None = None) -> tuple[pd.DataFrame, list[str]]:
    """Main panel builder."""
    print('[CSDA Phase 1] Loading RAWDATA...')
    raw = load_rawdata()
    print(f'  RAWDATA: {len(raw):,} rows × {len(raw.columns)} cols, {raw.Ticker.nunique()} tickers')

    # Date filter
    date_start_dt = pd.to_datetime(date_start)
    if date_end:
        date_end_dt = pd.to_datetime(date_end)
    else:
        date_end_dt = raw['Date'].max()
    raw = raw[(raw['Date'] >= date_start_dt) & (raw['Date'] <= date_end_dt)].reset_index(drop=True)

    # Universe: K200 == 1 OR KQ150 == 1 (시기별)
    raw['in_universe'] = (raw['K200'] == 1) | (raw['KQ150'] == 1)
    universe_tickers = raw[raw['in_universe']]['Ticker'].unique()
    print(f'  Universe (KOSPI200 ∪ KOSDAQ150, any 시기): {len(universe_tickers)} tickers')

    # Filter to universe stocks
    raw_uni = raw[raw['Ticker'].isin(universe_tickers)].copy()
    # Keep only rows where in_universe == True (시기별 membership)
    raw_uni = raw_uni[raw_uni['in_universe']].reset_index(drop=True)
    yrs = (raw_uni.Date.max() - raw_uni.Date.min()).days // 365
    print(f'  Filtered RAWDATA: {len(raw_uni):,} rows ({raw_uni.Ticker.nunique()} tickers, {yrs}y range)')

    # Per-stock features
    print('[CSDA Phase 1] Computing per-stock features (Group A + B)...')
    all_features = []
    n_skipped = 0
    for ticker in raw_uni['Ticker'].unique():
        sub = raw_uni[raw_uni['Ticker'] == ticker].sort_values('Date')
        feats = compute_stock_features(sub)
        if feats is not None:
            all_features.append(feats)
        else:
            n_skipped += 1
    print(f'  Processed: {len(all_features)} tickers (skipped {n_skipped} short-history)')

    panel = pd.concat(all_features, ignore_index=True)
    print(f'  Panel: {len(panel):,} rows × {len(panel.columns)} cols')

    # Cross-section features (Group C)
    print('[CSDA Phase 1] Adding cross-section features (Group C)...')
    bm = pd.read_parquet(BM_PARQUET)
    bm['Date'] = pd.to_datetime(bm['Date'])
    panel = add_cross_section_features(panel, bm)
    print(f'  Cross-section features added.')

    # Merge macro features (Group D)
    print('[CSDA Phase 1] Merging macro features (Group D)...')
    macro, macro_cols = load_macro_features()
    panel = panel.merge(macro, on='Date', how='left')
    print(f'  Macro features added: {macro_cols}')

    # Feature column list
    feature_cols = (
        # Group A — base 12
        [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] +
        [f'rv_{w}d' for w in [5, 22, 60]] +
        [f'mean_{w}d' for w in [5, 22, 60]] +
        ['rv_22d_z', 'drawdown_z'] +
        # Group B — horizon 6
        ['rv_120d', 'rv_252d', 'mean_120d', 'mean_252d',
         'momentum_22_60_slope', 'drawdown_60d'] +
        # Group C — cross-section 3
        ['relative_strength_60d', 'sector_beta_120d', 'peer_corr_60d'] +
        # Group D — macro 9
        macro_cols
    )
    assert len(feature_cols) == 30, f"feature count mismatch: {len(feature_cols)}"

    # Percent scale
    if PERCENT_SCALE:
        pct_cols = ['log_ret', 'ret_h_21d_forward'] + \
                   [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] + \
                   [f'rv_{w}d' for w in [5, 22, 60, 120, 252]] + \
                   [f'mean_{w}d' for w in [5, 22, 60, 120, 252]] + \
                   ['drawdown', 'drawdown_60d', 'relative_strength_60d']
        for c in pct_cols:
            if c in panel.columns:
                panel[c] = panel[c] * 100.0

    return panel, feature_cols


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str,
                        default='04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet')
    parser.add_argument('--date_start', type=str, default=DATE_START_DEFAULT)
    parser.add_argument('--date_end', type=str, default=None)
    args = parser.parse_args()

    panel, feature_cols = build_per_stock_panel(
        date_start=args.date_start,
        date_end=args.date_end,
    )

    out_path = Path(args.output)
    if not out_path.is_absolute():
        out_path = PROJECT_ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Drop rows with all features NA (early history insufficient)
    before = len(panel)
    panel = panel.dropna(subset=['rv_252d']).reset_index(drop=True)  # require at least 252d history
    after = len(panel)
    print(f'\n[CSDA Phase 1] Dropped {before - after:,} rows (< 252d history, {(before-after)/before*100:.1f}%)')

    # Save
    panel.to_parquet(out_path)
    print(f'[CSDA Phase 1] Saved → {out_path}')
    print(f'  Final panel: {len(panel):,} rows × {len(panel.columns)} cols')
    print(f'  Date range: {panel.Date.min().date()} ~ {panel.Date.max().date()}')
    print(f'  Tickers: {panel.Ticker.nunique()}')

    # Save metadata
    meta_path = out_path.with_suffix('.meta.json')
    import json
    meta = {
        'horizon': HORIZON,
        'date_start': args.date_start,
        'date_end': str(panel.Date.max().date()),
        'n_rows': len(panel),
        'n_tickers': int(panel.Ticker.nunique()),
        'n_features': len(feature_cols),
        'feature_cols': feature_cols,
        'built_at': datetime.now().isoformat(),
        'wt_id': 'WT-D20260528_001',
        'phase': 'CSDA Phase 1',
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(f'  Meta → {meta_path}')

    # NA ratio per feature
    print('\n[CSDA Phase 1] NA ratio per feature:')
    print(panel[feature_cols].isna().mean().sort_values(ascending=False).round(3).to_string())

    # Per-ticker stats
    print('\n[CSDA Phase 1] Top 10 tickers by row count:')
    print(panel.groupby('Ticker').size().sort_values(ascending=False).head(10).to_string())
    print('\nBottom 10 tickers by row count:')
    print(panel.groupby('Ticker').size().sort_values().head(10).to_string())


if __name__ == '__main__':
    main()
