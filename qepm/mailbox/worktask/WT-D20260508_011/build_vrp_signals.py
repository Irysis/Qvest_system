#!/usr/bin/env python
"""
WT-D20260508_011 — KOSPI200 옵션 chain 직접 VRP 4모형 정밀 산출

Models:
  1. BKM 2003 — Bakshi-Kapadia-Madan risk-neutral variance/skewness
  2. Carr-Wu 2009 — Variance swap synthetic (model-free implied variance)
  3. BTZ 2009 — HAR-RV expected RV vs implied
  4. VKOSPI reconstruction — CBOE 1993/2003 methodology

Data:
  - .cache/krx_options/<YYYYMMDD>.parquet (4023 days, 2010-01 ~ 2026-05)
  - .cache/rawdata.parquet BM_Ret (KOSPI200)
  - .cache/ecos_bond_rates.parquet KR_CD91

Output:
  - stage_artifacts/WT_D20260508_011/vrp_signals_monthly.parquet
  - stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet
  - stage_artifacts/WT_D20260508_011/option_chain_summary.parquet
"""

import os
import re
import json
import math
import warnings
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from scipy.stats import norm
from scipy.optimize import brentq

warnings.filterwarnings('ignore')

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
CACHE = f'{ROOT}/.cache/krx_options'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'
os.makedirs(OUT, exist_ok=True)

# ================== Helpers ==================

ISU_PAT = re.compile(r'(?:코스피200|코스피|미니코스피)(?:\s+위클리\([월목]\))?\s*([CP])\s*(\d{6})\s+([\d\.]+)')

def parse_isu_nm(s):
    s2 = s.replace('(정규)', '').replace('(야간)', '').strip()
    m = ISU_PAT.match(s2)
    if m:
        return m.group(1), m.group(2), float(m.group(3))
    return None, None, None

def expiry_date_of_yyyymm(yyyymm):
    """KRX KOSPI200 옵션 만기 = 두번째 목요일 (Settlement on 그 다음 영업일).
    표준 만기 사용 위해 두번째 목요일 사용 (close enough)."""
    y = int(yyyymm[:4]); m = int(yyyymm[4:6])
    d1 = datetime(y, m, 1)
    # 두번째 목요일
    first_thu_offset = (3 - d1.weekday()) % 7  # Thursday = 3
    second_thu = d1 + timedelta(days=first_thu_offset + 7)
    return second_thu

def load_options(date_str):
    fp = f'{CACHE}/{date_str}.parquet'
    if not os.path.exists(fp):
        return None
    df = pd.read_parquet(fp)
    # Standard KOSPI200 options regular session only
    std = df[(df['PROD_NM'] == '코스피200 옵션') & (~df['ISU_NM'].str.contains('야간', na=False))].copy()
    if len(std) == 0:
        return None
    parsed = std['ISU_NM'].apply(parse_isu_nm)
    std['cp'] = parsed.apply(lambda x: x[0])
    std['expiry'] = parsed.apply(lambda x: x[1])
    std['strike'] = parsed.apply(lambda x: x[2])
    std['close'] = pd.to_numeric(std['TDD_CLSPRC'], errors='coerce')
    std['iv'] = pd.to_numeric(std['IMP_VOLT'], errors='coerce') / 100.0
    std['vol'] = pd.to_numeric(std['ACC_TRDVOL'], errors='coerce')
    std['oi'] = pd.to_numeric(std['ACC_OPNINT_QTY'], errors='coerce')
    std = std.dropna(subset=['cp', 'expiry', 'strike']).copy()
    return std

# Black-Scholes for a European option (no dividend)
def bs_call(F, K, T, sig):
    if sig <= 0 or T <= 0:
        return max(F-K, 0)
    d1 = (math.log(F/K) + 0.5*sig*sig*T) / (sig*math.sqrt(T))
    d2 = d1 - sig*math.sqrt(T)
    return F*norm.cdf(d1) - K*norm.cdf(d2)

def bs_put(F, K, T, sig):
    if sig <= 0 or T <= 0:
        return max(K-F, 0)
    d1 = (math.log(F/K) + 0.5*sig*sig*T) / (sig*math.sqrt(T))
    d2 = d1 - sig*math.sqrt(T)
    return K*norm.cdf(-d2) - F*norm.cdf(-d1)

# ================== Risk-free + spot loader ==================

def load_rf():
    """일별 KR_CD91 무위험금리 (annualized %, 백분율)"""
    rates = pd.read_parquet(f'{ROOT}/.cache/ecos_bond_rates.parquet')
    cd91 = rates[rates['Series'] == 'KR_CD91'][['Date','Value']].copy()
    cd91 = cd91.rename(columns={'Value':'rf_pct'}).sort_values('Date').reset_index(drop=True)
    cd91['Date'] = pd.to_datetime(cd91['Date'])
    return cd91

def load_kospi200():
    """일별 KOSPI200 BM_Ret + level reconstruct"""
    raw = pd.read_parquet(f'{ROOT}/.cache/rawdata.parquet')
    bm = raw[['Date','BM_Ret']].drop_duplicates().sort_values('Date').reset_index(drop=True)
    bm['Date'] = pd.to_datetime(bm['Date'])
    # base level 100 at start
    bm['level'] = (1 + bm['BM_Ret'].fillna(0)).cumprod() * 100
    return bm

# ================== Step 1: per-day option chain summary ==================

def daily_summary(date_str, rf_df, spot_df):
    """단일 날짜 — front-month 옵션 chain을 받아 BKM moments + Carr-Wu IV² + VKOSPI 재구축.
    Spot은 Put-Call parity (PCP)로 추출 (option chain self-contained)."""
    df = load_options(date_str)
    if df is None:
        return None

    date_dt = datetime.strptime(date_str, '%Y%m%d')

    # Risk-free rate (daily fwd-fill — 2026-03-17 이후 정지: 마지막 값 hold)
    rf_match = rf_df[rf_df['Date'] <= date_dt]
    if len(rf_match) == 0:
        return None
    rf = rf_match.iloc[-1]['rf_pct'] / 100.0  # decimal

    # Front-month (closest expiry > today)
    df['expiry_dt'] = df['expiry'].apply(expiry_date_of_yyyymm)
    df = df[df['expiry_dt'] > date_dt]
    if len(df) == 0:
        return None

    # 30-day target: pick front + next month, blend (CBOE VIX style)
    df['days_to_expiry'] = (df['expiry_dt'] - date_dt).dt.days

    # filter: only options with valid CLOSE + meaningful liquidity
    # KRX uses 0.01 floor (DOTM noise); literature uses OI > 0 OR VOL > 0
    # Carr-Wu 2009 / BKM 2003 / CBOE VIX: filter by bid-ask validity + ATM band
    # We use: close > 0.02 (above floor) AND (OI > 0 OR VOL > 0), strike in ATM band ±50%
    df['valid_close'] = df['close'].notna() & (df['close'] > 0.02) & ((df['oi'] > 0) | (df['vol'] > 0))

    # Choose front (T1 < 30d if exists, else closest to 30d) and next (T2 > 30d)
    expiries = sorted(df['expiry'].unique(), key=lambda x: df[df['expiry']==x]['days_to_expiry'].iloc[0])

    # Use first two expiries by default
    if len(expiries) < 1:
        return None
    T1_exp = expiries[0]
    T1_days = df[df['expiry']==T1_exp]['days_to_expiry'].iloc[0]

    # Next month if exists
    if len(expiries) >= 2:
        T2_exp = expiries[1]
        T2_days = df[df['expiry']==T2_exp]['days_to_expiry'].iloc[0]
    else:
        T2_exp = T1_exp
        T2_days = T1_days

    T1 = T1_days / 365.0
    T2 = T2_days / 365.0

    # ----- Spot via Put-Call Parity (option chain self-contained) -----
    # For T1 (front month): S = K + (C-P)*e^(rT) at ATM K (min |C-P|)
    def pcp_spot(exp_str, T):
        sub_pcp = df[(df['expiry']==exp_str) & df['close'].notna() & (df['close'] > 0.01)].copy()
        pivot = sub_pcp.pivot_table(index='strike', columns='cp', values='close', aggfunc='first').dropna()
        if len(pivot) < 1:
            return None, None
        pivot['CmP'] = pivot['C'] - pivot['P']
        atm = pivot['CmP'].abs().idxmin()
        cmp_v = pivot.loc[atm, 'CmP']
        spot_est = atm + cmp_v * math.exp(rf * T)
        return spot_est, atm

    spot1, K_atm1 = pcp_spot(T1_exp, T1)
    if spot1 is None:
        return None
    spot2, K_atm2 = pcp_spot(T2_exp, T2) if T2_exp != T1_exp else (spot1, K_atm1)
    if spot2 is None:
        spot2 = spot1
    # Use spot1 as the canonical reference
    spot = spot1

    # Forward F = S * e^(rT) (no dividends — KOSPI200 dividend yield ~1.5% small impl bias)
    F1 = spot1 * math.exp(rf * T1)
    F2 = spot2 * math.exp(rf * T2)

    out = {'date': date_dt, 'spot': spot, 'rf': rf,
           'T1_days': T1_days, 'T2_days': T2_days,
           'K_atm1': K_atm1, 'K_atm2': K_atm2}

    # Process each expiry: compute model-free implied variance + BKM moments
    for tag, exp, T, F in [('T1', T1_exp, T1, F1), ('T2', T2_exp, T2, F2)]:
        sub = df[(df['expiry']==exp) & df['valid_close']].copy()
        # ATM is closest to F
        if len(sub) < 3:
            for k in ['mfiv', 'mfiv_sqrt', 'iv_atm', 'bkm_var', 'bkm_skew', 'n_strikes']:
                out[f'{tag}_{k}'] = np.nan
            continue

        # Determine ATM strike (closest to F)
        atm_idx = (sub['strike'] - F).abs().idxmin()
        K_atm = sub.loc[atm_idx, 'strike']

        # ATM IV (use call closest to ATM, KRX IMP_VOLT decimal already)
        atm_call = sub[(sub['cp']=='C') & (sub['strike']==K_atm)]
        atm_put = sub[(sub['cp']=='P') & (sub['strike']==K_atm)]
        iv_atm_vals = []
        if len(atm_call) > 0:
            iv_atm_vals.append(atm_call['iv'].iloc[0])
        if len(atm_put) > 0:
            iv_atm_vals.append(atm_put['iv'].iloc[0])
        iv_atm = np.nanmean(iv_atm_vals) if iv_atm_vals else np.nan

        # OTM only — restrict to ATM band ±33% (literature: Bondarenko 2014, Carr-Wu 2009)
        # to avoid DOTM 0.01 floor numerical contamination
        K_low = F * 0.67
        K_high = F * 1.50
        otm_call = sub[(sub['cp']=='C') & (sub['strike']>=F) & (sub['strike']<=K_high)].sort_values('strike').reset_index(drop=True)
        otm_put = sub[(sub['cp']=='P') & (sub['strike']<=F) & (sub['strike']>=K_low)].sort_values('strike', ascending=False).reset_index(drop=True)

        # Combine into single OTM panel by strike
        otm = pd.concat([
            otm_put[['strike','close']].assign(cp='P'),
            otm_call[['strike','close']].assign(cp='C')
        ]).sort_values('strike').drop_duplicates('strike').reset_index(drop=True)

        if len(otm) < 5:
            for k in ['mfiv', 'mfiv_sqrt', 'iv_atm', 'bkm_var', 'bkm_skew', 'n_strikes']:
                out[f'{tag}_{k}'] = np.nan
            continue

        # ----- Carr-Wu / CBOE-VIX style MFIV -----
        # MFIV = (2/T) * sum_i (ΔK_i / K_i^2) * e^(rT) * Q(K_i) - (1/T)(F/K_atm - 1)^2
        # Q(K_i) = OTM option price at K_i
        K = otm['strike'].values
        Q = otm['close'].values
        # ΔK using midpoint diff
        dK = np.zeros_like(K)
        if len(K) > 1:
            dK[1:-1] = (K[2:] - K[:-2]) / 2.0
            dK[0] = K[1] - K[0]
            dK[-1] = K[-1] - K[-2]
        else:
            dK[0] = 1.0
        contrib = (dK / (K**2)) * Q
        mfiv = (2.0 / T) * math.exp(rf * T) * np.sum(contrib) - (1.0 / T) * ((F / K_atm) - 1.0)**2
        # mfiv is in (vol²) units
        if mfiv < 0:
            mfiv = np.nan
        mfiv_sqrt = math.sqrt(mfiv) if not np.isnan(mfiv) else np.nan

        # ----- BKM 2003 moments (V, W, X) -----
        # BKM 2003 RFS Theorem 1:
        # V(t,τ) = ∫_S^∞ [2(1-ln(K/S))/K²] C(K) dK + ∫_0^S [2(1+ln(S/K))/K²] P(K) dK
        # W(t,τ) = ∫_S^∞ [(6 ln(K/S) - 3 ln²(K/S))/K²] C(K) dK
        #          - ∫_0^S [(6 ln(S/K) + 3 ln²(S/K))/K²] P(K) dK
        # X(t,τ) = ∫_S^∞ [(12 ln²(K/S) - 4 ln³(K/S))/K²] C(K) dK
        #          + ∫_0^S [(12 ln²(S/K) + 4 ln³(S/K))/K²] P(K) dK
        # μ = e^(rτ) - 1 - V/2 - W/6 - X/24
        # bkm var = V - μ² (in τ units, so divide by T to annualize)
        # bkm skew = (W - 3μV + 2μ³) / (V - μ²)^1.5  (NEGATIVE for normal index puts skew)
        S = F  # forward
        # Vector kernels: separate sign for K>S vs K<S
        is_call_side = (K >= S)  # True for OTM call domain (K>=S)
        ln_KS_pos = np.where(is_call_side, np.log(K/S), 0.0)  # ln(K/S) for calls
        ln_SK_pos = np.where(~is_call_side, np.log(S/K), 0.0)  # ln(S/K) for puts (>0)

        V_kernel = np.where(is_call_side,
                            (2.0/K**2) * (1.0 - ln_KS_pos),
                            (2.0/K**2) * (1.0 + ln_SK_pos))

        W_kernel = np.where(is_call_side,
                            (1.0/K**2) * (6.0*ln_KS_pos - 3.0*ln_KS_pos**2),
                            -(1.0/K**2) * (6.0*ln_SK_pos + 3.0*ln_SK_pos**2))

        X_kernel = np.where(is_call_side,
                            (1.0/K**2) * (12.0*ln_KS_pos**2 - 4.0*ln_KS_pos**3),
                            (1.0/K**2) * (12.0*ln_SK_pos**2 + 4.0*ln_SK_pos**3))

        V = math.exp(rf*T) * np.sum(V_kernel * Q * dK)
        W = math.exp(rf*T) * np.sum(W_kernel * Q * dK)
        X = math.exp(rf*T) * np.sum(X_kernel * Q * dK)

        # μ following BKM
        mu = math.exp(rf*T) - 1.0 - V/2.0 - W/6.0 - X/24.0
        bkm_var_T = V - mu**2
        bkm_var = bkm_var_T / T if bkm_var_T > 0 else np.nan

        denom = (V - mu**2)
        if denom > 1e-10:
            bkm_skew = (W - 3*mu*V + 2*mu**3) / (denom**1.5)
        else:
            bkm_skew = np.nan

        out[f'{tag}_mfiv'] = mfiv  # variance unit (annualized)
        out[f'{tag}_mfiv_sqrt'] = mfiv_sqrt
        out[f'{tag}_iv_atm'] = iv_atm
        out[f'{tag}_bkm_var'] = bkm_var
        out[f'{tag}_bkm_skew'] = bkm_skew
        out[f'{tag}_n_strikes'] = len(otm)

    # ----- VKOSPI 30-day blend (CBOE VIX style) -----
    # VKOSPI = sqrt(((T1·σ²(T1)·(NT2-30)/(NT2-NT1)) + (T2·σ²(T2)·(30-NT1)/(NT2-NT1)))·(365/30)) ·100
    if (not np.isnan(out.get('T1_mfiv', np.nan))) and (not np.isnan(out.get('T2_mfiv', np.nan))) and out['T2_days'] > out['T1_days']:
        sig1 = out['T1_mfiv']  # variance per year
        sig2 = out['T2_mfiv']
        N1 = out['T1_days']
        N2 = out['T2_days']
        if 30 >= N1 and 30 <= N2:
            w1 = (N2 - 30) / (N2 - N1)
            w2 = (30 - N1) / (N2 - N1)
        elif 30 < N1:
            # 30d before front — extrapolate (use T1 only)
            w1 = 1.0; w2 = 0.0
        else:
            # 30d after back — extrapolate using T2
            w1 = 0.0; w2 = 1.0
        if w1 + w2 > 0:
            blend_var = (T1 * sig1 * w1 + T2 * sig2 * w2) * (365.0 / 30.0)
            out['vkospi'] = 100.0 * math.sqrt(max(blend_var, 0))
        else:
            out['vkospi'] = np.nan
    else:
        out['vkospi'] = np.nan

    # ATM IV blended (linear in T to 30d)
    if (not np.isnan(out.get('T1_iv_atm', np.nan))) and (not np.isnan(out.get('T2_iv_atm', np.nan))) and out['T2_days'] > out['T1_days']:
        if out['T1_days'] <= 30 <= out['T2_days']:
            w1 = (out['T2_days'] - 30) / (out['T2_days'] - out['T1_days'])
            w2 = 1 - w1
            out['atm_iv_30d'] = w1*out['T1_iv_atm'] + w2*out['T2_iv_atm']
        elif out['T1_days'] > 30:
            out['atm_iv_30d'] = out['T1_iv_atm']
        else:
            out['atm_iv_30d'] = out['T2_iv_atm']
    else:
        out['atm_iv_30d'] = out.get('T1_iv_atm', np.nan)

    # Front-month BKM blend (use T1 if both exist)
    out['bkm_var_30d'] = out.get('T1_bkm_var', np.nan)
    out['bkm_skew_30d'] = out.get('T1_bkm_skew', np.nan)

    return out

# ================== Step 2: full daily run ==================

def main():
    print('Loading risk-free rate + KOSPI200 spot...')
    rf_df = load_rf()
    spot_df = load_kospi200()
    print(f'  rf range: {rf_df["Date"].min()} ~ {rf_df["Date"].max()} (n={len(rf_df)})')
    print(f'  spot range: {spot_df["Date"].min()} ~ {spot_df["Date"].max()} (n={len(spot_df)})')

    files = sorted(os.listdir(CACHE))
    print(f'\nProcessing {len(files)} option chain days...')

    rows = []
    skipped = 0
    for i, fn in enumerate(files):
        date_str = fn.replace('.parquet', '')
        try:
            r = daily_summary(date_str, rf_df, spot_df)
            if r is not None:
                rows.append(r)
            else:
                skipped += 1
        except Exception as e:
            skipped += 1
            if skipped <= 5:
                print(f'  skipped {date_str}: {e}')
        if (i+1) % 500 == 0:
            print(f'  processed {i+1}/{len(files)}, skipped {skipped}')

    print(f'\nTotal rows: {len(rows)}, skipped: {skipped}')

    daily = pd.DataFrame(rows).sort_values('date').reset_index(drop=True)
    daily.to_parquet(f'{OUT}/option_chain_summary.parquet', index=False)
    print(f'Saved option_chain_summary: {daily.shape} → {OUT}/option_chain_summary.parquet')

    # ================== Step 3: BTZ HAR-RV realized variance ==================
    print('\nComputing realized variance (HAR-RV)...')
    spot_df['daily_ret'] = spot_df['BM_Ret'].fillna(0)
    spot_df['daily_var'] = spot_df['daily_ret']**2
    # 22-day rolling RV (annualized)
    spot_df['rv_22d_annual'] = spot_df['daily_var'].rolling(22).sum() * (252.0/22.0)
    # HAR-RV components
    spot_df['rv_d_annual'] = spot_df['daily_var'].rolling(1).sum() * 252.0
    spot_df['rv_w_annual'] = spot_df['daily_var'].rolling(5).sum() * (252.0/5.0)
    spot_df['rv_m_annual'] = spot_df['daily_var'].rolling(22).sum() * (252.0/22.0)
    # forecast next-month RV with HAR (in-sample, but we use rolling forward)

    # Daily merge
    daily2 = daily.merge(spot_df[['Date','rv_22d_annual','rv_d_annual','rv_w_annual','rv_m_annual','level']],
                          left_on='date', right_on='Date', how='left')

    # ================== Step 4: VRP definitions ==================
    # VRP_CW = MFIV (model-free implied) - RV(realized over past 22d)
    # VRP_BKM = BKM_var - RV
    # VRP_VKOSPI = (VKOSPI/100)² - RV (squared decimal)
    # VRP_BTZ = BKM_var - HAR-forecast-RV (we use trailing rv_22d as proxy in-sample)

    daily2['vrp_cw'] = daily2['T1_mfiv'] - daily2['rv_22d_annual']
    daily2['vrp_bkm'] = daily2['bkm_var_30d'] - daily2['rv_22d_annual']
    daily2['vrp_vkospi'] = (daily2['vkospi']/100.0)**2 - daily2['rv_22d_annual']
    daily2['vrp_atm'] = daily2['atm_iv_30d']**2 - daily2['rv_22d_annual']

    # BTZ HAR forecast — fit one model with full sample (in-sample baseline) — for production we use rolling.
    # For this stage just baseline (no forecast — use trailing 22d as predictor of next 22d, well-known proxy)
    daily2['vrp_btz'] = daily2['bkm_var_30d'] - daily2['rv_22d_annual']  # same as bkm but kept separate for future HAR refinement

    # Save daily
    daily2.to_parquet(f'{OUT}/vkospi_reconstruction.parquet', index=False)
    print(f'Saved vkospi_reconstruction: {daily2.shape}')

    # ================== Step 5: Monthly aggregate (sig_date = month-end) ==================
    print('\nAggregating to monthly...')
    daily2['ym'] = daily2['date'].dt.to_period('M')

    def last_valid(s):
        v = s.dropna()
        return v.iloc[-1] if len(v) > 0 else np.nan

    monthly = daily2.groupby('ym').agg({
        'date': 'max',
        'vkospi': last_valid,
        'atm_iv_30d': last_valid,
        'bkm_var_30d': last_valid,
        'bkm_skew_30d': last_valid,
        'T1_mfiv': last_valid,
        'rv_22d_annual': last_valid,
        'vrp_cw': last_valid,
        'vrp_bkm': last_valid,
        'vrp_vkospi': last_valid,
        'vrp_atm': last_valid,
        'vrp_btz': last_valid,
        'level': last_valid,
        'spot': last_valid
    }).reset_index()
    monthly = monthly.rename(columns={'date':'sig_date'})
    monthly = monthly.sort_values('sig_date').reset_index(drop=True)

    monthly.to_parquet(f'{OUT}/vrp_signals_monthly.parquet', index=False)
    print(f'Saved vrp_signals_monthly: {monthly.shape}')

    print('\nMonthly VRP summary:')
    for c in ['vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm','bkm_skew_30d']:
        s = monthly[c].dropna()
        print(f'  {c}: n={len(s)}, mean={s.mean():.5f}, std={s.std():.5f}, min={s.min():.5f}, max={s.max():.5f}')

    # Cross-VRP correlation
    print('\nVRP cross-correlation:')
    print(monthly[['vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm']].corr().round(3))

if __name__ == '__main__':
    main()
