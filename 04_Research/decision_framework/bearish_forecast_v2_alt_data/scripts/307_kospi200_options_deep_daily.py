#!/usr/bin/env python3
"""307_kospi200_options_deep_daily.py — Phase 1.2 KOSPI200 옵션 deep features

학술 anchor:
  - Bates 2008 (JF): implied skew predicts crash
  - Bollerslev-Todorov 2011 (JF): fear index from short OTM options
  - Yan 2011 / Faff-Liu 2014: IV skew predicts crashes
  - Andreou 2025 (JFM): options-implied jump intensity

Raw data: .cache/krx_options/<YYYYMMDD>.parquet
  Columns: BAS_DD, PROD_NM, RGHT_TP_NM (CALL/PUT), ISU_NM, TDD_CLSPRC, IMP_VOLT, ACC_OPNINT_QTY

Daily features (8개, 2010-2026 coverage):
  1. atm_iv_near        : ATM IV of nearest expiry
  2. atm_iv_far         : ATM IV of 2nd-nearest expiry (term structure)
  3. iv_term_slope      : far - near (term structure slope)
  4. iv_skew_put        : OTM put IV / ATM IV (downside skew, Bates 2008)
  5. iv_smile_curvature : (OTM_call IV + OTM_put IV)/2 - ATM IV (Bollerslev 2011)
  6. pcr_oi             : Put OI / Call OI (put-call ratio, fear gauge)
  7. pcr_vol            : Put volume / Call volume (intraday fear)
  8. iv_rolling_z_5y    : ATM near IV expanding rolling z-score (extreme percentile)

PIT: 모두 BAS_DD 기준, monthly aggregate에서 lag1 (전일 종가)로 사용.

Output: outputs/01_data/kospi200_options_deep_daily.parquet
"""
import re
from pathlib import Path
import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
CACHE = PROJECT_ROOT / ".cache/krx_options"
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
BM = PROJECT_ROOT / ".cache/benchmark.parquet"  # KOSPI200 close
OUT = WS / "outputs/01_data/kospi200_options_deep_daily.parquet"

# Load KOSPI200 close for spot reference
bm = pd.read_parquet(BM)
bm['Date'] = pd.to_datetime(bm['Date'])
bm = bm.sort_values('Date').reset_index(drop=True)
spot_lookup = dict(zip(bm['Date'], bm['BM_Close']))
print(f"[Load] KOSPI200 spot: {len(bm)} days, {bm.Date.min().date()} ~ {bm.Date.max().date()}")

# Parse option name for strike + expiry (예: "코스피200 C 201001 185.0 (정규)")
def parse_option_meta(isu_nm):
    """Extract type, expiry_ym (YYYYMM int), strike."""
    if not isinstance(isu_nm, str): return None, None, None
    m = re.match(r'코스피200\s+([CP])\s+(\d{6})\s+([\d.]+)', isu_nm)
    if not m: return None, None, None
    return m.group(1), int(m.group(2)), float(m.group(3))


# Iterate daily files
files = sorted(CACHE.glob("*.parquet"))
files = [f for f in files if f.stem != "_index"]
print(f"[Process] {len(files)} daily files")

daily_rows = []
for ix, fpath in enumerate(files):
    if ix % 200 == 0:
        print(f"  [{ix:>4d}/{len(files)}] {fpath.stem}", flush=True)
    try:
        d = pd.read_parquet(fpath)
    except Exception as e:
        continue
    if len(d) == 0: continue

    # Date parse
    bas_dd = d['BAS_DD'].iloc[0]
    date = pd.to_datetime(bas_dd, format='%Y%m%d')

    # Filter to KOSPI200 (PROD_NM = '코스피200 옵션')
    d = d[d['PROD_NM'].str.startswith('코스피200', na=False)].copy()
    # Keep only regular options (exclude weekly/mini suffixes)
    d = d[d['ISU_NM'].str.contains(r'\(정규\)', na=False, regex=True)].copy()
    if len(d) == 0: continue

    # Parse metadata
    meta = [parse_option_meta(x) for x in d['ISU_NM']]
    d['opt_type'] = [m[0] for m in meta]
    d['expiry_ym'] = [m[1] for m in meta]
    d['strike'] = [m[2] for m in meta]
    d = d.dropna(subset=['opt_type', 'expiry_ym', 'strike'])
    if len(d) == 0: continue

    # Numeric conversion
    for c in ['IMP_VOLT', 'TDD_CLSPRC', 'ACC_OPNINT_QTY', 'ACC_TRDVOL']:
        d[c] = pd.to_numeric(d[c], errors='coerce')

    # Keep liquid only: OI > 0 + IMP_VOLT in reasonable range (5%~200%)
    d = d[(d['ACC_OPNINT_QTY'] > 0) & (d['IMP_VOLT'] > 5) & (d['IMP_VOLT'] < 200)].copy()
    if len(d) < 5: continue

    # Spot
    spot = spot_lookup.get(date)
    if spot is None or np.isnan(spot): continue

    # Find ATM strike (closest to spot)
    d['moneyness'] = d['strike'] / spot - 1.0  # 0 = ATM, +0.05 = 5% OTM call, -0.05 = 5% OTM put

    # Identify expiry buckets (near + far)
    expiry_ym_sorted = sorted(d['expiry_ym'].unique())
    if len(expiry_ym_sorted) < 1: continue
    near_ym = expiry_ym_sorted[0]
    far_ym = expiry_ym_sorted[1] if len(expiry_ym_sorted) > 1 else near_ym

    # ATM IV = avg of CALL+PUT closest strike, per expiry
    def atm_iv_at_expiry(d_sub):
        if len(d_sub) == 0: return np.nan
        ix = d_sub['moneyness'].abs().idxmin()
        atm_strike = d_sub.loc[ix, 'strike']
        atm_options = d_sub[d_sub['strike'] == atm_strike]
        return atm_options['IMP_VOLT'].mean()

    near = d[d['expiry_ym'] == near_ym]
    far = d[d['expiry_ym'] == far_ym]
    atm_near = atm_iv_at_expiry(near)
    atm_far = atm_iv_at_expiry(far)
    iv_term_slope = (atm_far - atm_near) if (not np.isnan(atm_near) and not np.isnan(atm_far)) else np.nan

    # IV skew: OTM put IV / ATM IV (5% OTM put, near expiry)
    puts_near = near[near['opt_type'] == 'P']
    calls_near = near[near['opt_type'] == 'C']
    # 5% OTM put = strike ≈ spot * 0.95 → moneyness ≈ -0.05
    if len(puts_near) > 0:
        ix_p = (puts_near['moneyness'] + 0.05).abs().idxmin()
        otm_put_iv = puts_near.loc[ix_p, 'IMP_VOLT']
    else:
        otm_put_iv = np.nan
    if len(calls_near) > 0:
        ix_c = (calls_near['moneyness'] - 0.05).abs().idxmin()
        otm_call_iv = calls_near.loc[ix_c, 'IMP_VOLT']
    else:
        otm_call_iv = np.nan
    iv_skew_put = (otm_put_iv / atm_near) if (not np.isnan(otm_put_iv) and not np.isnan(atm_near) and atm_near > 0) else np.nan

    # Smile curvature: (OTM call + OTM put)/2 - ATM
    if not (np.isnan(otm_put_iv) or np.isnan(otm_call_iv) or np.isnan(atm_near)):
        iv_smile_curv = (otm_put_iv + otm_call_iv) / 2 - atm_near
    else:
        iv_smile_curv = np.nan

    # Put-Call OI Ratio (all expiries, sum of OI)
    put_oi = d[d['opt_type'] == 'P']['ACC_OPNINT_QTY'].sum()
    call_oi = d[d['opt_type'] == 'C']['ACC_OPNINT_QTY'].sum()
    pcr_oi = (put_oi / call_oi) if call_oi > 0 else np.nan

    # Put-Call Volume Ratio
    put_vol = d[d['opt_type'] == 'P']['ACC_TRDVOL'].sum()
    call_vol = d[d['opt_type'] == 'C']['ACC_TRDVOL'].sum()
    pcr_vol = (put_vol / call_vol) if call_vol > 0 else np.nan

    daily_rows.append({
        'Date': date,
        'atm_iv_near': atm_near,
        'atm_iv_far': atm_far,
        'iv_term_slope': iv_term_slope,
        'iv_skew_put': iv_skew_put,
        'iv_smile_curvature': iv_smile_curv,
        'pcr_oi': pcr_oi,
        'pcr_vol': pcr_vol,
    })

daily = pd.DataFrame(daily_rows)
daily = daily.sort_values('Date').reset_index(drop=True)
print(f"\n[Built] {len(daily)} daily rows × {len(daily.columns)} cols")
print(f"  Date: {daily.Date.min().date()} ~ {daily.Date.max().date()}")

# Compute rolling z-score (5y window, ~1260 days, expanding for PIT)
def expanding_z(x, min_obs=252):
    n = len(x); z = np.full(n, np.nan)
    for i in range(min_obs, n):
        hist = x[:i]
        valid = hist[~np.isnan(hist)]
        if len(valid) < min_obs: continue
        mu = valid.mean(); s = valid.std()
        if s < 1e-6 or np.isnan(x[i]): continue
        z[i] = (x[i] - mu) / s
    return z

daily['iv_rolling_z_5y'] = expanding_z(daily['atm_iv_near'].values)
# lag1 all (PIT — features available at t for prediction at t+1)
for c in ['atm_iv_near', 'atm_iv_far', 'iv_term_slope', 'iv_skew_put',
          'iv_smile_curvature', 'pcr_oi', 'pcr_vol', 'iv_rolling_z_5y']:
    daily[f'{c}_lag1'] = daily[c].shift(1)

# Diagnostic
for c in ['atm_iv_near_lag1', 'iv_term_slope_lag1', 'iv_skew_put_lag1',
          'iv_smile_curvature_lag1', 'pcr_oi_lag1', 'pcr_vol_lag1',
          'iv_rolling_z_5y_lag1']:
    v = daily[c].dropna()
    if len(v) > 0:
        print(f"  {c:<30s} n={len(v)} mean={v.mean():.3f} std={v.std():.3f} range=[{v.min():.3f}, {v.max():.3f}]")

OUT.parent.mkdir(parents=True, exist_ok=True)
daily.to_parquet(OUT, index=False)
print(f"\n[SAVED] {OUT}")
print(f"  {len(daily)} rows × {len(daily.columns)} cols")
