"""
706_str1716_13y_charts.py — STR_1716 13년 P3 era isolated 시각화

도훈 mandate 2026-05-26: 2013년부터 (P3 era only) 백테스팅 시각화.

Period: 2013-05-02 ~ 2026-04-01 (n=156 monthly, 13년)
Comparison: STR_1715 baseline vs STR_1716 (P3 overlay)
"""
import pandas as pd
import numpy as np
import os
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.dates as mdates

for f in ['NanumGothic', 'Malgun Gothic', 'AppleGothic', 'NanumBarunGothic', 'DejaVu Sans']:
    if any(font.name == f for font in fm.fontManager.ttflist):
        plt.rcParams['font.family'] = f
        break
plt.rcParams['axes.unicode_minus'] = False

PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])
OUT_DIR = PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/charts_13y'
OUT_DIR.mkdir(parents=True, exist_ok=True)

ANN = 12

# ─── Load + filter to P3 era (2013-05+) ─────────────────────────────────────
str1715 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
str1716 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/03_period_returns.csv')
str1715['Date'] = pd.to_datetime(str1715['date'])
str1716['Date'] = pd.to_datetime(str1716['date'])
mask = str1716['Date'] >= pd.Timestamp('2013-05-01')
s1715 = str1715[mask].copy().sort_values('Date').reset_index(drop=True)
s1716 = str1716[mask].copy().sort_values('Date').reset_index(drop=True)

# Benchmark
try:
    bm = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/05_benchmark_returns.csv')
    bm['Date'] = pd.to_datetime(bm['date'])
    bm_col = next((c for c in bm.columns if 'ret' in c.lower() and 'bench' in c.lower()), bm.columns[2])
    bm_ret_full = bm.set_index('Date')[bm_col]
    bm_ret = bm_ret_full[bm_ret_full.index >= pd.Timestamp('2013-05-01')].values
    has_bm = True
except Exception:
    has_bm = False

p3 = pd.read_parquet(PROJECT / '04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet')
p3['Date'] = pd.to_datetime(p3['Date'])

dates = s1716['Date']
ret_1715 = s1715['ret_net'].values
ret_1716 = s1716['ret_net'].values
cash_w = s1716['cash_weight'].values * 100

nav_1715 = np.cumprod(1 + ret_1715)
nav_1716 = np.cumprod(1 + ret_1716)
if has_bm and len(bm_ret) == len(ret_1716):
    nav_bm = np.cumprod(1 + bm_ret)

def dd(nav):
    cm = np.maximum.accumulate(nav); return (nav - cm) / cm
dd_1715 = dd(nav_1715)
dd_1716 = dd(nav_1716)

# Aggregate P3 monthly
p3_monthly = []
for d in dates:
    past = p3[p3.Date < d]
    if len(past) > 0:
        p3_monthly.append(past.iloc[-1])
    else:
        p3_monthly.append(None)
p3_df = pd.DataFrame([{'Date': d,
                       'sigma': r['sigma'] if r is not None else np.nan,
                       'lam': r['lam'] if r is not None else np.nan,
                       'p10': r['p_minus_10pct'] if r is not None else np.nan}
                      for d, r in zip(dates, p3_monthly)])

# ─── Chart 1: NAV equity curve (13년, log) ──────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 6))
ax.semilogy(dates, nav_1715, label=f'STR_1715 baseline (NAV {nav_1715[-1]:.2f}x)', color='#34495e', lw=1.8)
ax.semilogy(dates, nav_1716, label=f'STR_1716 P3 overlay (NAV {nav_1716[-1]:.2f}x)', color='#e74c3c', lw=1.8)
if has_bm and len(bm_ret) == len(ret_1716):
    ax.semilogy(dates, nav_bm, label=f'KOSPI 200 benchmark (NAV {nav_bm[-1]:.2f}x)', color='#3498db', lw=1.3, alpha=0.7)
ax.set_title('NAV — 13년 P3 era (2013-05 ~ 2026-04)', fontsize=13, weight='bold')
ax.set_ylabel('NAV (log)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, which='both')
ax.xaxis.set_major_locator(mdates.YearLocator(1))
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '01_nav_13y.png', dpi=110); plt.close(fig)

# ─── Chart 2: Drawdown (13년) ──────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 5))
ax.fill_between(dates, dd_1715*100, 0, color='#34495e', alpha=0.4, label=f'STR_1715 (MDD {abs(dd_1715.min())*100:.1f}%)')
ax.fill_between(dates, dd_1716*100, 0, color='#e74c3c', alpha=0.5, label=f'STR_1716 (MDD {abs(dd_1716.min())*100:.1f}%)')
ax.set_title('Drawdown — 13년 P3 era (MDD 28.99% → 13.41% / -54%)', fontsize=13, weight='bold')
ax.set_ylabel('Drawdown (%)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='lower left', fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '02_drawdown_13y.png', dpi=110); plt.close(fig)

# ─── Chart 3: Rolling 12m Sharpe (13년) ────────────────────────────────────
def rsr(r, w=12):
    rs = pd.Series(r).rolling(w)
    return rs.mean() / (rs.std() + 1e-9) * np.sqrt(12)

fig, ax = plt.subplots(figsize=(13, 5))
ax.plot(dates, rsr(ret_1715), color='#34495e', lw=1.5, label='STR_1715 12m SR')
ax.plot(dates, rsr(ret_1716), color='#e74c3c', lw=1.5, label='STR_1716 12m SR')
ax.axhline(0, color='gray', ls='--', alpha=0.5)
ax.axhline(1.0, color='green', ls=':', alpha=0.5, label='SR=1.0')
ax.set_title('12-month Rolling Sharpe — 13년', fontsize=13, weight='bold')
ax.set_ylabel('Rolling SR', fontsize=11)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '03_rolling_sharpe_13y.png', dpi=110); plt.close(fig)

# ─── Chart 4: Cash overlay + P3 signals timeline ───────────────────────────
fig, axes = plt.subplots(3, 1, figsize=(13, 9), sharex=True)
axes[0].fill_between(dates, cash_w, 0, color='#3498db', alpha=0.6)
axes[0].set_ylabel('Cash %', fontsize=11)
axes[0].axhline(60, color='red', ls=':', alpha=0.5, label='cap 60%')
axes[0].set_title('STR_1716 cash overlay (13년 P3 era)', fontsize=12, weight='bold')
axes[0].legend(fontsize=9); axes[0].grid(alpha=0.3)

axes[1].plot(p3_df['Date'], p3_df['sigma'], color='#27ae60', lw=1.5)
axes[1].set_ylabel('sigma (daily %)', fontsize=11)
axes[1].axhline(1.3, color='gray', ls=':', alpha=0.5, label='보통 (1.3%)')
axes[1].grid(alpha=0.3); axes[1].legend(fontsize=9)

axes[2].plot(p3_df['Date'], p3_df['lam'], color='#c0392b', lw=1.5)
axes[2].set_ylabel('lambda (bear bias)', fontsize=11); axes[2].set_xlabel('Date', fontsize=10)
axes[2].axhline(0, color='gray', ls='--', alpha=0.5)
axes[2].axhline(-0.15, color='red', ls=':', alpha=0.5, label='trigger -0.15')
axes[2].grid(alpha=0.3); axes[2].legend(fontsize=9)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '04_cash_overlay_p3signals_13y.png', dpi=110); plt.close(fig)

# ─── Chart 5: Yearly returns (2013-2026) ──────────────────────────────────
s1715['Year'] = s1715['Date'].dt.year
s1716['Year'] = s1716['Date'].dt.year
y1715 = s1715.groupby('Year')['ret_net'].apply(lambda x: (1 + x).prod() - 1) * 100
y1716 = s1716.groupby('Year')['ret_net'].apply(lambda x: (1 + x).prod() - 1) * 100

fig, ax = plt.subplots(figsize=(13, 6))
years = y1715.index.values
x = np.arange(len(years))
w = 0.4
ax.bar(x - w/2, y1715.values, w, label='STR_1715', color='#34495e')
ax.bar(x + w/2, y1716.values, w, label='STR_1716', color='#e74c3c')
ax.set_xticks(x); ax.set_xticklabels(years.astype(str), rotation=45)
ax.axhline(0, color='black', lw=0.5)
ax.set_ylabel('Annual return (%)', fontsize=11)
ax.set_title('연도별 returns (13년 P3 era)', fontsize=13, weight='bold')
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, axis='y')

# Mark key events
for i, year in enumerate(years):
    if year == 2018: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '美中\n무역', ha='center', fontsize=7, color='red')
    if year == 2020: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, 'COVID\n+10pp', ha='center', fontsize=7, color='red', weight='bold')
    if year == 2022: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '금리\n+7pp', ha='center', fontsize=7, color='red', weight='bold')
    if year == 2024: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '계엄', ha='center', fontsize=7, color='red')
fig.tight_layout()
fig.savefig(OUT_DIR / '05_yearly_returns_13y.png', dpi=110); plt.close(fig)

# ─── Chart 6: Crisis protection (2020 COVID, 2022 bear, 2024 정치) ──────────
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
for ax, (year, title) in zip(axes, [(2020, '2020 COVID'), (2022, '2022 Bear (금리)'), (2024, '2024 계엄')]):
    mask_y = s1716['Date'].dt.year == year
    d_y = s1716[mask_y]['Date']
    r1715_y = ret_1715[mask_y]
    r1716_y = ret_1716[mask_y]
    nav1715_y = np.cumprod(1 + r1715_y) * 100
    nav1716_y = np.cumprod(1 + r1716_y) * 100
    ax.plot(d_y, nav1715_y, color='#34495e', lw=1.8, label=f'STR_1715 ({nav1715_y[-1]-100:+.1f}%)')
    ax.plot(d_y, nav1716_y, color='#e74c3c', lw=1.8, label=f'STR_1716 ({nav1716_y[-1]-100:+.1f}%)')
    ax.set_title(title, fontsize=11, weight='bold')
    ax.set_ylabel('NAV (start=100)'); ax.legend(fontsize=8); ax.grid(alpha=0.3)
    ax.tick_params(axis='x', rotation=45)
fig.suptitle('Crisis Year zoom — STR_1716 P3 protection', fontsize=13, weight='bold', y=1.02)
fig.tight_layout()
fig.savefig(OUT_DIR / '06_crisis_zoom.png', dpi=110); plt.close(fig)

# ─── Chart 7: Risk-adjusted metrics bar (13년) ─────────────────────────────
def m(r):
    nav = np.cumprod(1 + r); cm = np.maximum.accumulate(nav); d = (nav - cm) / cm
    return {
        'Sharpe': r.mean() / (r.std() + 1e-9) * np.sqrt(12),
        'Sortino': r.mean() / (r[r < 0].std() + 1e-9) * np.sqrt(12),
        'Calmar': (nav[-1] ** (12/len(r)) - 1) / max(abs(d.min()), 1e-9),
        'CAGR%': (nav[-1] ** (12/len(r)) - 1) * 100,
        'MDD%': abs(d.min()) * 100,
        'Vol%': r.std() * np.sqrt(12) * 100,
    }
m_1715 = m(ret_1715); m_1716 = m(ret_1716)

labels = ['Sharpe', 'Sortino', 'Calmar', 'CAGR%', 'MDD%', 'Vol%']
v1715 = [m_1715[l] for l in labels]
v1716 = [m_1716[l] for l in labels]

fig, ax = plt.subplots(figsize=(13, 6))
x = np.arange(len(labels))
ax.bar(x - 0.2, v1715, 0.4, label='STR_1715 (baseline)', color='#34495e')
ax.bar(x + 0.2, v1716, 0.4, label='STR_1716 (P3 overlay)', color='#e74c3c')
ax.set_xticks(x); ax.set_xticklabels(labels)
ax.set_title('Risk-adjusted metrics — 13년 P3 era', fontsize=13, weight='bold')
ax.legend(loc='upper right', fontsize=10); ax.grid(alpha=0.3, axis='y')
for i, (a, b) in enumerate(zip(v1715, v1716)):
    ax.text(i - 0.2, a + (max(v1715+v1716))*0.015, f'{a:.2f}', ha='center', fontsize=9)
    ax.text(i + 0.2, b + (max(v1715+v1716))*0.015, f'{b:.2f}', ha='center', fontsize=9)
fig.tight_layout()
fig.savefig(OUT_DIR / '07_metrics_13y.png', dpi=110); plt.close(fig)

# ─── Chart 8: Monthly returns distribution (histogram) ─────────────────────
fig, ax = plt.subplots(figsize=(13, 5))
ax.hist(ret_1715 * 100, bins=30, alpha=0.6, color='#34495e', label='STR_1715', density=True)
ax.hist(ret_1716 * 100, bins=30, alpha=0.6, color='#e74c3c', label='STR_1716', density=True)
ax.axvline(0, color='black', lw=0.5)
ax.axvline(np.mean(ret_1715)*100, color='#34495e', ls='--', alpha=0.7, label=f'STR_1715 mean ({np.mean(ret_1715)*100:+.2f}%)')
ax.axvline(np.mean(ret_1716)*100, color='#e74c3c', ls='--', alpha=0.7, label=f'STR_1716 mean ({np.mean(ret_1716)*100:+.2f}%)')
ax.set_xlabel('Monthly return (%)', fontsize=11)
ax.set_ylabel('Density', fontsize=11)
ax.set_title('Monthly returns distribution — 13년', fontsize=13, weight='bold')
ax.legend(fontsize=9); ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(OUT_DIR / '08_returns_histogram_13y.png', dpi=110); plt.close(fig)

# ─── Chart 9: Outperformance heatmap (yearly Δret) ─────────────────────────
month_perf = pd.DataFrame({
    'Year': s1716['Date'].dt.year,
    'Month': s1716['Date'].dt.month,
    'd_ret': (ret_1716 - ret_1715) * 100,
})
pivot = month_perf.pivot_table(index='Year', columns='Month', values='d_ret')

fig, ax = plt.subplots(figsize=(14, 6))
import matplotlib.colors as mcolors
norm = mcolors.TwoSlopeNorm(vmin=pivot.min().min(), vcenter=0, vmax=pivot.max().max())
im = ax.imshow(pivot.values, cmap='RdYlGn', norm=norm, aspect='auto')
ax.set_xticks(range(12)); ax.set_xticklabels(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'])
ax.set_yticks(range(len(pivot.index))); ax.set_yticklabels(pivot.index)
ax.set_title('STR_1716 - STR_1715 monthly Δret heatmap (green = STR_1716 better)', fontsize=12, weight='bold')
fig.colorbar(im, label='Δret (%)', shrink=0.7)
for i in range(len(pivot.index)):
    for j in range(12):
        v = pivot.iloc[i, j]
        if pd.notna(v):
            ax.text(j, i, f'{v:+.1f}', ha='center', va='center', fontsize=7,
                    color='black' if abs(v) < 3 else 'white')
fig.tight_layout()
fig.savefig(OUT_DIR / '09_outperformance_heatmap.png', dpi=110); plt.close(fig)

# ─── Chart 10: Cumulative Δret (STR_1716 - STR_1715) ───────────────────────
cum_d = np.cumsum(ret_1716 - ret_1715) * 100
fig, ax = plt.subplots(figsize=(13, 5))
ax.fill_between(dates, cum_d, 0, where=cum_d > 0, color='#27ae60', alpha=0.4, label='STR_1716 outperform')
ax.fill_between(dates, cum_d, 0, where=cum_d < 0, color='#c0392b', alpha=0.4, label='STR_1715 outperform')
ax.plot(dates, cum_d, color='black', lw=1.2)
ax.axhline(0, color='black', lw=0.5)
ax.set_ylabel('Cumulative Δret (%)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.set_title(f'STR_1716 - STR_1715 cumulative outperformance (final {cum_d[-1]:+.1f}pp)', fontsize=13, weight='bold')
ax.legend(fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '10_cumulative_outperform.png', dpi=110); plt.close(fig)

print(f'[saved] {OUT_DIR}/')
for f in sorted(OUT_DIR.iterdir()):
    print(f'  {f.name}')

# Summary metrics
print()
print('=== 13년 P3 era 핵심 metrics ===')
for k in ['Sharpe', 'Sortino', 'Calmar', 'CAGR%', 'MDD%', 'Vol%']:
    print(f'  {k:<8}: STR_1715 {m_1715[k]:>7.3f}  STR_1716 {m_1716[k]:>7.3f}  Δ {m_1716[k]-m_1715[k]:>+7.3f}')
