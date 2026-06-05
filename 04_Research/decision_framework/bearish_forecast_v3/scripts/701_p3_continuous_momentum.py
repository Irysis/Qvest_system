"""
701_p3_continuous_momentum.py — P3 Continuous Exposure + 200MA Momentum Hybrid 백테스트

도훈 mandate 2026-05-26:
1. Continuous exposure (P3 vol-target + tail-dampen + regime-dampen)
2. P3 + 200MA momentum hybrid

벤치마크: KOSPI Buy-and-Hold
"""
import pandas as pd
import numpy as np
import os
from pathlib import Path

ROOT = Path('.')
ANN = 252
TC_BPS = 15
PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])


def metrics(returns_dec, label):
    nav = np.cumprod(1 + returns_dec)
    ann_ret = (nav[-1] ** (ANN / len(returns_dec)) - 1) * 100
    ann_vol = returns_dec.std() * np.sqrt(ANN) * 100
    sr = returns_dec.mean() / (returns_dec.std() + 1e-12) * np.sqrt(ANN)
    cummax = np.maximum.accumulate(nav)
    dd = (nav - cummax) / cummax
    mdd = abs(dd.min()) * 100
    hit = (returns_dec > 0).mean() * 100
    return {'name': label, 'sr': sr, 'cagr': ann_ret, 'vol': ann_vol, 'mdd': mdd,
            'final_nav': nav[-1], 'hit': hit, 'nav': nav}


def apply_exposure(exposure, r):
    """Apply daily exposure with 15bps tx cost on changes."""
    tc = TC_BPS / 10000
    cost = np.abs(np.diff(exposure, prepend=0)) * tc
    return exposure * r - cost


# ─── Load data ──────────────────────────────────────────────────────────────
df = pd.read_parquet('03_models/p3_trial19/all_predictions.parquet')
df['Date'] = pd.to_datetime(df['Date'])
df = df.sort_values('Date').reset_index(drop=True)
print(f'P3 backtest n={len(df)}  ({df.Date.min().date()} ~ {df.Date.max().date()})')

# KOSPI close (for 200MA)
bm = pd.read_parquet(PROJECT / '.cache' / 'benchmark.parquet')
bm['Date'] = pd.to_datetime(bm['Date'])
bm = bm.sort_values('Date').reset_index(drop=True)
# Need MA200 from 200 days before df start
ma_start = df['Date'].min() - pd.Timedelta(days=300)
bm_sub = bm[bm['Date'] >= ma_start].copy()
bm_sub['MA200'] = bm_sub['BM_Close'].rolling(200, min_periods=200).mean()
bm_sub = bm_sub[['Date', 'BM_Close', 'MA200']]

merged = df.merge(bm_sub, on='Date', how='left')
merged['above_ma200'] = (merged['BM_Close'] > merged['MA200']).astype(int)
print(f'  MA200 valid days: {merged["MA200"].notna().sum()} / {len(merged)}')

r = merged['y_actual'].values / 100  # decimal
sigma = merged['sigma'].values  # %
lam = merged['lam'].values
p10 = merged['p_minus_10pct'].values
p5 = merged['p_minus_5pct'].values
above_ma = merged['above_ma200'].values
n = len(merged)

# ─── Baseline ──────────────────────────────────────────────────────────────
m_baseline = metrics(r, 'KOSPI Buy-and-Hold')

# ─── Strategy 1: 200MA filter only ──────────────────────────────────────────
exp_ma_only = above_ma.astype(float)
r_ma_only = apply_exposure(exp_ma_only, r)
m_ma_only = metrics(r_ma_only, '200MA filter only')

# ─── Strategy 2: P3 Vol-target (basic) ──────────────────────────────────────
target_vol_ann = 0.15
sigma_ann = sigma / 100 * np.sqrt(ANN)
exp_vt = np.clip(target_vol_ann / sigma_ann, 0.0, 1.5)
r_vt = apply_exposure(exp_vt, r)
m_vt = metrics(r_vt, 'P3 Vol-target 15%')

# ─── Strategy 3: P3 Continuous (vol + tail + regime) ────────────────────────
def cont_exposure_p3(sigma, lam, p10, target_vol=0.15):
    vol_exp = np.clip(target_vol / (sigma / 100 * np.sqrt(ANN)), 0.0, 1.5)
    # Tail dampen: P(-10%)=0 → 1, P(-10%)=0.02 → 0
    tail_dampen = np.clip(1.0 - 50 * p10, 0.0, 1.0)
    # Regime dampen: λ=-0.3 → 0, λ=+0.1 → 1 (smooth)
    regime_dampen = np.clip((lam + 0.3) / 0.4, 0.0, 1.0)
    return vol_exp * tail_dampen * regime_dampen

exp_cont = cont_exposure_p3(sigma, lam, p10, target_vol=0.15)
r_cont = apply_exposure(exp_cont, r)
m_cont = metrics(r_cont, 'P3 Continuous (vol+tail+regime)')
print(f'  P3 continuous mean exposure: {exp_cont.mean():.2f}, range [{exp_cont.min():.2f}, {exp_cont.max():.2f}]')

# ─── Strategy 4: P3 Continuous (vol+tail only, no λ regime) ─────────────────
def cont_simple(sigma, p10, target_vol=0.15):
    vol_exp = np.clip(target_vol / (sigma / 100 * np.sqrt(ANN)), 0.0, 1.5)
    tail_dampen = np.clip(1.0 - 50 * p10, 0.0, 1.0)
    return vol_exp * tail_dampen

exp_simple = cont_simple(sigma, p10, target_vol=0.15)
r_simple = apply_exposure(exp_simple, r)
m_simple = metrics(r_simple, 'P3 Cont (vol+tail only)')

# ─── Strategy 5: 200MA × P3 vol-target Hybrid ───────────────────────────────
exp_h1 = above_ma.astype(float) * exp_vt
r_h1 = apply_exposure(exp_h1, r)
m_h1 = metrics(r_h1, '200MA × P3 Vol-target')

# ─── Strategy 6: 200MA × P3 Continuous Hybrid ───────────────────────────────
exp_h2 = above_ma.astype(float) * exp_cont
r_h2 = apply_exposure(exp_h2, r)
m_h2 = metrics(r_h2, '200MA × P3 Continuous')

# ─── Strategy 7: 200MA + Tail-hedge only ────────────────────────────────────
# When above MA200: full 100%. When below: 0%. Override: tail-hedge cash when P(-10%) high.
tail_override = np.where(p10 > 0.01, 0.0, 1.0)
exp_h3 = above_ma.astype(float) * tail_override
r_h3 = apply_exposure(exp_h3, r)
m_h3 = metrics(r_h3, '200MA × Tail-hedge P(-10%)')

# ─── Strategy 8: Vol-target × Tail-hedge (no MA) ────────────────────────────
exp_h4 = exp_vt * np.clip(1.0 - 50 * p10, 0.0, 1.0)
r_h4 = apply_exposure(exp_h4, r)
m_h4 = metrics(r_h4, 'Vol-target × Tail-dampen')

# ─── Print table ────────────────────────────────────────────────────────────
print()
print(f"{'Strategy':<35} {'SR':>7} {'CAGR%':>8} {'Vol%':>7} {'MDD%':>7} {'NAV':>7} {'Hit%':>6}")
print('─' * 90)
strategies = [m_baseline, m_ma_only, m_vt, m_cont, m_simple, m_h1, m_h2, m_h3, m_h4]
for m in strategies:
    print(f"{m['name']:<35} {m['sr']:>7.3f} {m['cagr']:>+8.2f} {m['vol']:>7.2f} {m['mdd']:>7.2f} {m['final_nav']:>7.2f} {m['hit']:>6.1f}")

# Improvement vs baseline
print()
print('=== Improvement vs KOSPI Buy-and-Hold ===')
print(f"{'Strategy':<35} {'ΔSR':>8} {'ΔCAGR':>8} {'ΔVol':>8} {'ΔMDD':>9}")
for m in strategies[1:]:
    print(f"{m['name']:<35} {m['sr'] - m_baseline['sr']:>+8.3f} {m['cagr'] - m_baseline['cagr']:>+8.2f} "
          f"{m['vol'] - m_baseline['vol']:>+8.2f} {m['mdd'] - m_baseline['mdd']:>+9.2f}")

# Yearly Sharpe
print()
print('=== Year-by-year SR ===')
merged['Year'] = merged['Date'].dt.year
print(f"{'Year':<6} {'KOSPI':>7} {'200MA':>7} {'VolT':>7} {'Cont':>7} {'MA×VolT':>8} {'MA×Cont':>9} {'MA×Tail':>8}")
strategies_yearly = {
    'KOSPI': r, '200MA': r_ma_only, 'VolT': r_vt, 'Cont': r_cont,
    'MA×VolT': r_h1, 'MA×Cont': r_h2, 'MA×Tail': r_h3
}
for year in sorted(merged['Year'].unique()):
    mask = (merged['Year'].values == year)
    if mask.sum() < 50: continue
    line = f"{year:<6} "
    for label, rr in strategies_yearly.items():
        sr_y = rr[mask].mean() / (rr[mask].std() + 1e-9) * np.sqrt(ANN)
        line += f"{sr_y:>7.3f} " if label != 'MA×VolT' and label != 'MA×Cont' else f"{sr_y:>8.3f} "
    print(line)

# Save NAV
out_dir = ROOT / '03_models' / 'p3_continuous'
out_dir.mkdir(parents=True, exist_ok=True)
nav_df = pd.DataFrame({'Date': merged['Date']})
for label, rr in strategies_yearly.items():
    nav_df[f'nav_{label}'] = np.cumprod(1 + rr)
nav_df.to_parquet(out_dir / 'continuous_backtest.parquet')
print(f'\n[saved] {out_dir / "continuous_backtest.parquet"}')
