#!/usr/bin/env python3
"""300_monthly_aggregate_features.py — Cycle 58CC Phase 1

도훈 mandate: monthly rebalancing task → daily snapshot features X.
매월 첫 영업일 시점에서 monthly aggregate features 30+ build.

Output: outputs/01_data/monthly_features.parquet (~370 rows × 30+ cols)
Target: y_tail_q15 (existing) — endpoint return ≤ rolling 5y q15
"""
import os
import sys
import json
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR = WS / "outputs/01_data"
OUT_PATH = DATA_DIR / "monthly_features.parquet"

# Load all daily data sources
print("[Load] benchmark + features")
bm = pd.read_parquet(PROJECT_ROOT / ".cache/benchmark.parquet")
bm['Date'] = pd.to_datetime(bm['Date'])
bm = bm.sort_values('Date').reset_index(drop=True)

# Targets (existing y_tail_q15)
tg = pd.read_parquet(WS / "outputs/02_targets/targets_long_horizon_observable.parquet")
tg['Date'] = pd.to_datetime(tg['Date'])

# Daily features sources
v5g = pd.read_parquet(DATA_DIR / "feature_panel_v5g_cross_market.parquet")
v5g['Date'] = pd.to_datetime(v5g['Date'])

etf = pd.read_parquet(DATA_DIR / "etf_flow_features.parquet")
etf['Date'] = pd.to_datetime(etf['Date'])

yc = pd.read_parquet(DATA_DIR / "kr_yield_curve_features.parquet")
yc['Date'] = pd.to_datetime(yc['Date'])

inv = pd.read_parquet(DATA_DIR / "investor_breadth_daily.csv".replace(
    '.csv', '.parquet')) if (DATA_DIR / "investor_breadth_daily.parquet").exists() else \
    pd.read_csv(DATA_DIR / "investor_breadth_daily.csv")
inv['Date'] = pd.to_datetime(inv['Date'])

print(f"  bm: {len(bm)} rows, v5g: {len(v5g)} cols, etf: {etf.shape}, yc: {yc.shape}, inv: {inv.shape}")

# Build monthly aggregate features
# Loop: each month start = first business day of month
def first_bd_each_month(dates_series):
    """Return first business day of each month from a date series."""
    df = pd.DataFrame({'Date': dates_series.sort_values().unique()})
    df['Date'] = pd.to_datetime(df['Date'])
    df['ym'] = df['Date'].dt.to_period('M')
    return df.groupby('ym').first().reset_index()['Date'].tolist()

first_bds = first_bd_each_month(bm['Date'])
print(f"\n[Monthly] {len(first_bds)} first business days (1990-2026)")

# Build features per month
monthly_rows = []
for m_start in first_bds:
    # Use data UP TO m_start - 1 day (PIT — month start prediction uses prior data)
    cut = m_start - pd.Timedelta(days=1)
    bm_past = bm[bm['Date'] <= cut].copy()
    if len(bm_past) < 252:  # need at least 1 year history
        continue

    row = {'Date': m_start}

    # ========== Returns / Momentum ==========
    close = bm_past['BM_Close'].values
    p_now = close[-1]
    for n_days, name in [(21, '1m'), (63, '3m'), (126, '6m'), (252, '12m')]:
        if len(close) >= n_days:
            row[f'ret_{name}'] = p_now / close[-n_days] - 1
        else:
            row[f'ret_{name}'] = np.nan

    # ========== Risk / Volatility ==========
    rets = bm_past['BM_Close'].pct_change().dropna().values
    for n_days, name in [(21, '1m'), (63, '3m'), (252, '12m')]:
        if len(rets) >= n_days:
            row[f'realized_vol_{name}'] = rets[-n_days:].std() * np.sqrt(252)
        else:
            row[f'realized_vol_{name}'] = np.nan

    # ========== HAR-RV cascade (Corsi 2009 JFE) ==========
    # Daily / weekly / monthly realized variance cascade
    if len(rets) >= 22:
        rv_1d = rets[-1] ** 2  # latest daily RV
        rv_5d = (rets[-5:] ** 2).mean()  # weekly RV
        rv_22d = (rets[-22:] ** 2).mean()  # monthly RV
        row['har_rv_1d'] = rv_1d
        row['har_rv_5d'] = rv_5d
        row['har_rv_22d'] = rv_22d
        # HAR combined (weighted, normalized)
        row['har_rv_combined'] = (rv_1d + rv_5d + rv_22d) / 3
        # Ratios (regime indicators)
        if rv_22d > 1e-9:
            row['har_rv_1d_to_22d'] = rv_1d / rv_22d  # short-term spike
            row['har_rv_5d_to_22d'] = rv_5d / rv_22d  # weekly vs monthly
        else:
            row['har_rv_1d_to_22d'] = np.nan
            row['har_rv_5d_to_22d'] = np.nan
    else:
        for c in ['har_rv_1d', 'har_rv_5d', 'har_rv_22d', 'har_rv_combined',
                  'har_rv_1d_to_22d', 'har_rv_5d_to_22d']:
            row[c] = np.nan

    # Current drawdown
    if len(close) >= 252:
        recent = close[-252:]
        peak = recent.max()
        row['current_dd_pct'] = p_now / peak - 1
        # DD duration: days since peak
        peak_idx = np.argmax(recent)
        row['dd_duration_days'] = len(recent) - 1 - peak_idx
    else:
        row['current_dd_pct'] = np.nan
        row['dd_duration_days'] = np.nan

    # Max drawdown 12M / 6M
    for n_days, name in [(126, '6m'), (252, '12m')]:
        if len(close) >= n_days:
            window = close[-n_days:]
            cummax = np.maximum.accumulate(window)
            dd = window / cummax - 1
            row[f'max_dd_{name}'] = dd.min()
        else:
            row[f'max_dd_{name}'] = np.nan

    # ========== Macro state at month start ==========
    v5g_past = v5g[v5g['Date'] <= cut]
    if len(v5g_past) > 0:
        last = v5g_past.iloc[-1]
        for col in ['bbva_market_z_lag1', 'bbva_sovereign_z_lag1',
                    'bbva_macro_composite_lag1', 'k200_implied_skew_z_lag1',
                    'k200_implied_kurt_z_lag1',
                    'us_t10y2y_spread_lag1', 'us_initial_claims_4w_avg_lag1',
                    'us_cfnai_lag1', 'us_stlfsi_lag1',
                    'ecos_m2_yoy_lag1', 'ecos_krw_usd_change_5d_lag1',
                    'ecos_base_rate_lag1',
                    'ecos_industrial_production_yoy_lag1',
                    'ecos_cpi_yoy_lag1',
                    'foreign_breadth_ad_ratio_5d_avg_lag1',
                    'nikkei225_return_lag1', 'sp500_overnight_return_lag1',
                    'dxy_change_5d_lag1', 'usdkrw_change_5d_lag1',
                    'hangseng_return_lag1', 'wti_change_5d_lag1',
                    'vix_change_5d_lag1']:
            if col in last.index:
                row[f'm_start_{col}'] = last[col]

    # ========== ETF flow 1M aggregate ==========
    etf_past = etf[etf['Date'] <= cut]
    if len(etf_past) > 21:
        recent_etf = etf_past.tail(21)
        for col in ['etf_inv_lev_z_lag1', 'etf_bond_eq_z_lag1',
                    'etf_k200_vol_z_lag1', 'etf_2xinv_vol_z_lag1']:
            if col in recent_etf.columns:
                row[f'{col}_1m_mean'] = recent_etf[col].mean()

    # ========== Yield curve at month start ==========
    yc_past = yc[yc['Date'] <= cut]
    if len(yc_past) > 0:
        last_yc = yc_past.iloc[-1]
        for col in ['ktb10y_lag1', 'kr_term_premium_lag1', 'kr_steepness_lag1',
                    'kr_credit_spread_lag1', 'kr_curvature_lag1',
                    # Phase 1.3: EBP deep features (Gilchrist-Zakrajsek 2012)
                    'kr_ebp_rolling_z_5y_lag1', 'kr_ebp_rm21_lag1',
                    'kr_ebp_chg21_lag1']:
            if col in last_yc.index:
                row[f'm_start_{col}'] = last_yc[col]
        # 1M change
        yc_1m_ago = yc[yc['Date'] <= (cut - pd.Timedelta(days=21))]
        if len(yc_1m_ago) > 0:
            last_1m = yc_1m_ago.iloc[-1]
            for col in ['ktb10y_lag1', 'kr_term_premium_lag1']:
                if col in last.index and col in last_1m.index:
                    row[f'{col}_1m_chg'] = last_yc[col] - last_1m[col]

    # ========== Investor breadth 1M aggregate ==========
    inv_past = inv[inv['Date'] <= cut]
    if len(inv_past) > 21:
        recent_inv = inv_past.tail(21)
        for col in ['ad_ratio', 'hhi_buy']:
            if col in recent_inv.columns:
                row[f'foreign_{col}_1m_mean'] = recent_inv[col].mean()
                row[f'foreign_{col}_1m_trend'] = (
                    recent_inv[col].iloc[-1] - recent_inv[col].iloc[0]
                )

    # ========== Calendar effects ==========
    row['month'] = m_start.month
    row['is_quarter_end_month'] = int(m_start.month % 3 == 0)
    row['is_year_end_month'] = int(m_start.month == 12)

    monthly_rows.append(row)

monthly = pd.DataFrame(monthly_rows)
print(f"\n[Built] {len(monthly)} monthly rows × {len(monthly.columns)} columns")
print(f"Date range: {monthly['Date'].min().date()} ~ {monthly['Date'].max().date()}")
print(f"Columns: {list(monthly.columns)}")

# Merge with y_tail_q15 (현재 target retain)
tg_m = tg[['Date', 'y_tail_q15']].copy()
tg_m['Date'] = pd.to_datetime(tg_m['Date'])
monthly = monthly.merge(tg_m, on='Date', how='left')

# Add new label: y_dd_8pct (drawdown-based)
bm['ret_h21'] = bm['BM_Close'].pct_change(21).shift(-21)  # forward 21d return endpoint
# Forward max drawdown in 21d
def fwd_dd(s, h=21):
    n = len(s); out = np.full(n, np.nan)
    for i in range(n - h):
        win = s.iloc[i:i+h+1].values
        out[i] = win.min() / s.iloc[i] - 1
    return out
bm['fwd_dd_21'] = fwd_dd(bm['BM_Close'], 21)
bm['y_dd_8pct'] = (bm['fwd_dd_21'] <= -0.08).astype(float)
bm.loc[bm['fwd_dd_21'].isna(), 'y_dd_8pct'] = np.nan
bm_subset = bm[['Date', 'fwd_dd_21', 'y_dd_8pct']]
monthly = monthly.merge(bm_subset, on='Date', how='left')

# Save
monthly.to_parquet(OUT_PATH, index=False)
print(f"\n[SAVED] {OUT_PATH}")
print(f"  {len(monthly)} rows × {len(monthly.columns)} cols")
print(f"  y_tail_q15 positive: {int(monthly['y_tail_q15'].sum())} / {monthly['y_tail_q15'].notna().sum()}")
print(f"  y_dd_8pct  positive: {int(monthly['y_dd_8pct'].sum())} / {monthly['y_dd_8pct'].notna().sum()}")
print(f"\nFirst 3 rows:")
print(monthly.head(3))
print(f"\nLast 3 rows:")
print(monthly.tail(3))
