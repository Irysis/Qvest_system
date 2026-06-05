"""
707_str1716_charts_to_may22.py — STR_1716 charts extended to 2026-05-22

도훈 mandate 2026-05-26: 4/1 → 5/22까지 최신 데이터 반영.

5월 partial month estimate:
  STR_1715 = KOSPI 200 5/1~5/22 cumulative (beta=1.0 conservative proxy)
  STR_1716 = STR_1715 × (1 - P3 cash overlay May 60%)
  Disclaimer: STR_1715 production weights로 정확 계산 가능하나 conservative proxy 사용
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
import matplotlib.colors as mcolors

for f in ['NanumGothic', 'Malgun Gothic', 'AppleGothic', 'NanumBarunGothic', 'DejaVu Sans']:
    if any(font.name == f for font in fm.fontManager.ttflist):
        plt.rcParams['font.family'] = f; break
plt.rcParams['axes.unicode_minus'] = False

PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])
OUT_DIR = PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/charts_13y_to_may22'
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ─── Load STR_1715 + STR_1716 to 2026-04 + extend to 5/22 ───────────────────
s1715 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
s1716 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/03_period_returns.csv')
s1715['Date'] = pd.to_datetime(s1715['date'])
s1716['Date'] = pd.to_datetime(s1716['date'])
mask = s1716['Date'] >= pd.Timestamp('2013-05-01')
s1715 = s1715[mask].sort_values('Date').reset_index(drop=True)
s1716 = s1716[mask].sort_values('Date').reset_index(drop=True)

# Compute May partial
bm = pd.read_parquet(PROJECT / '.cache' / 'benchmark.parquet')
bm['Date'] = pd.to_datetime(bm['Date'])
may_data = bm[(bm['Date'] >= '2026-04-30') & (bm['Date'] <= '2026-05-22')].sort_values('Date').reset_index(drop=True)
kospi_may_ret = may_data.iloc[-1]['BM_Close'] / may_data.iloc[0]['BM_Close'] - 1
cash_may = 0.60  # P3 forecast at 4/30 → full cap

str1715_may_partial = kospi_may_ret  # beta=1 proxy
str1716_may_partial = str1715_may_partial * (1 - cash_may)
print(f'May partial (4/30 ~ 5/22):')
print(f'  KOSPI 200 cumulative: {kospi_may_ret*100:+.3f}%')
print(f'  STR_1715 (proxy beta=1.0): {str1715_may_partial*100:+.3f}%')
print(f'  STR_1716 (cash 60%): {str1716_may_partial*100:+.3f}%')

# Append May partial
may22 = pd.Timestamp('2026-05-22')
new_row_1715 = pd.DataFrame([{'date': '2026-05-22', 'Date': may22, 'ret_net': str1715_may_partial}])
new_row_1716 = pd.DataFrame([{'date': '2026-05-22', 'Date': may22, 'ret_net': str1716_may_partial}])
s1715 = pd.concat([s1715, new_row_1715], ignore_index=True)
s1716 = pd.concat([s1716, new_row_1716], ignore_index=True)

dates = s1716['Date']
ret_1715 = s1715['ret_net'].values
ret_1716 = s1716['ret_net'].values
nav_1715 = np.cumprod(1 + ret_1715)
nav_1716 = np.cumprod(1 + ret_1716)
dd_1715 = (nav_1715 - np.maximum.accumulate(nav_1715)) / np.maximum.accumulate(nav_1715)
dd_1716 = (nav_1716 - np.maximum.accumulate(nav_1716)) / np.maximum.accumulate(nav_1716)

# KOSPI 200 cumulative proxy (benchmark NAV)
bm_p3era = bm[bm.Date >= pd.Timestamp('2013-05-01')].sort_values('Date').reset_index(drop=True)
bm_monthly = bm_p3era.copy()
bm_monthly['m'] = bm_monthly.Date.dt.to_period('M').dt.start_time
bm_month_close = bm_monthly.groupby('m')['BM_Close'].last()
# Need to align to STR_1716 dates
bm_aligned = []
prev_close = None
for d in dates:
    sub = bm[bm.Date <= d]
    if len(sub) > 0:
        bm_aligned.append(sub.iloc[-1]['BM_Close'])
    else:
        bm_aligned.append(prev_close)
    prev_close = bm_aligned[-1]
bm_aligned = np.array(bm_aligned, dtype=np.float64)
nav_bm = bm_aligned / bm_aligned[0]

# ─── Chart 1: NAV (13년 to 5/22) ────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 6))
ax.semilogy(dates, nav_1715, label=f'STR_1715 baseline ({nav_1715[-1]:.2f}x)', color='#34495e', lw=1.8)
ax.semilogy(dates, nav_1716, label=f'STR_1716 P3 overlay ({nav_1716[-1]:.2f}x)', color='#e74c3c', lw=1.8)
ax.semilogy(dates, nav_bm, label=f'KOSPI 200 ({nav_bm[-1]:.2f}x)', color='#3498db', lw=1.3, alpha=0.7)
ax.axvspan(pd.Timestamp('2026-04-01'), pd.Timestamp('2026-05-22'), color='orange', alpha=0.15, label='5월 partial (proxy)')
ax.set_title(f'NAV — 2013-05 ~ 2026-05-22 (13y + May partial)', fontsize=13, weight='bold')
ax.set_ylabel('NAV (log)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, which='both')
ax.xaxis.set_major_locator(mdates.YearLocator(1))
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '01_nav_to_may22.png', dpi=110); plt.close(fig)

# ─── Chart 2: Drawdown ──────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 5))
ax.fill_between(dates, dd_1715*100, 0, color='#34495e', alpha=0.4, label=f'STR_1715 (MDD {abs(dd_1715.min())*100:.1f}%)')
ax.fill_between(dates, dd_1716*100, 0, color='#e74c3c', alpha=0.5, label=f'STR_1716 (MDD {abs(dd_1716.min())*100:.1f}%)')
ax.axvspan(pd.Timestamp('2026-04-01'), pd.Timestamp('2026-05-22'), color='orange', alpha=0.15)
ax.set_title(f'Drawdown — to 2026-05-22', fontsize=13, weight='bold')
ax.set_ylabel('Drawdown (%)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='lower left', fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '02_drawdown_to_may22.png', dpi=110); plt.close(fig)

# ─── Chart 3: Yearly returns (2013-2026) ────────────────────────────────────
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
ax.set_title('연도별 returns (to 2026-05-22, 2026 = 5/22까지)', fontsize=13, weight='bold')
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, axis='y')

# Mark events
for i, year in enumerate(years):
    if year == 2020: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, 'COVID\n+10pp', ha='center', fontsize=7, color='red', weight='bold')
    if year == 2022: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '+7pp', ha='center', fontsize=7, color='red', weight='bold')
    if year == 2024: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '계엄', ha='center', fontsize=7, color='red')
    if year == 2026: ax.text(i, max(y1715.iloc[i], y1716.iloc[i]) + 3, '5/22\npartial', ha='center', fontsize=7, color='orange', weight='bold')
fig.tight_layout()
fig.savefig(OUT_DIR / '03_yearly_returns_to_may22.png', dpi=110); plt.close(fig)

# ─── Chart 4: 2026 zoom ─────────────────────────────────────────────────────
mask_2026 = s1716['Date'].dt.year == 2026
d2026 = s1716[mask_2026]['Date']
r1715_2026 = ret_1715[mask_2026.values]
r1716_2026 = ret_1716[mask_2026.values]
nav1715_2026 = np.cumprod(1 + r1715_2026) * 100
nav1716_2026 = np.cumprod(1 + r1716_2026) * 100

fig, ax = plt.subplots(figsize=(12, 5))
ax.plot(d2026, nav1715_2026, color='#34495e', lw=2, marker='o', label=f'STR_1715 ({nav1715_2026[-1]-100:+.1f}%)')
ax.plot(d2026, nav1716_2026, color='#e74c3c', lw=2, marker='o', label=f'STR_1716 ({nav1716_2026[-1]-100:+.1f}%)')
ax.axhline(100, color='black', lw=0.5, ls='--')
ax.set_title('2026 YTD zoom (2026-01-02 ~ 2026-05-22)', fontsize=13, weight='bold')
ax.set_ylabel('NAV (start=100)', fontsize=11)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '04_2026_ytd_zoom.png', dpi=110); plt.close(fig)

# ─── Chart 5: Metrics to 5/22 ───────────────────────────────────────────────
ANN = 12
def m(r):
    nav = np.cumprod(1 + r); cm = np.maximum.accumulate(nav); d = (nav - cm) / cm
    return {
        'Sharpe': r.mean() / (r.std() + 1e-9) * np.sqrt(ANN),
        'Sortino': r.mean() / (r[r < 0].std() + 1e-9) * np.sqrt(ANN),
        'Calmar': (nav[-1] ** (ANN/len(r)) - 1) / max(abs(d.min()), 1e-9),
        'CAGR%': (nav[-1] ** (ANN/len(r)) - 1) * 100,
        'MDD%': abs(d.min()) * 100,
        'Vol%': r.std() * np.sqrt(ANN) * 100,
    }
m_1715 = m(ret_1715); m_1716 = m(ret_1716)
labels = ['Sharpe', 'Sortino', 'Calmar', 'CAGR%', 'MDD%', 'Vol%']
v1715 = [m_1715[l] for l in labels]; v1716 = [m_1716[l] for l in labels]

fig, ax = plt.subplots(figsize=(13, 6))
x = np.arange(len(labels))
ax.bar(x - 0.2, v1715, 0.4, label='STR_1715', color='#34495e')
ax.bar(x + 0.2, v1716, 0.4, label='STR_1716', color='#e74c3c')
ax.set_xticks(x); ax.set_xticklabels(labels)
ax.set_title(f'Metrics — 2013-05 ~ 2026-05-22 (n={len(ret_1716)} 월)', fontsize=13, weight='bold')
ax.legend(loc='upper right', fontsize=10); ax.grid(alpha=0.3, axis='y')
for i, (a, b) in enumerate(zip(v1715, v1716)):
    ax.text(i - 0.2, a + max(v1715+v1716)*0.015, f'{a:.2f}', ha='center', fontsize=9)
    ax.text(i + 0.2, b + max(v1715+v1716)*0.015, f'{b:.2f}', ha='center', fontsize=9)
fig.tight_layout()
fig.savefig(OUT_DIR / '05_metrics_to_may22.png', dpi=110); plt.close(fig)

# ─── Chart 6: Cumulative outperform ─────────────────────────────────────────
cum_d = np.cumsum(ret_1716 - ret_1715) * 100
fig, ax = plt.subplots(figsize=(13, 5))
ax.fill_between(dates, cum_d, 0, where=cum_d > 0, color='#27ae60', alpha=0.4, label='STR_1716 outperform')
ax.fill_between(dates, cum_d, 0, where=cum_d < 0, color='#c0392b', alpha=0.4, label='STR_1715 outperform')
ax.plot(dates, cum_d, color='black', lw=1.2)
ax.axhline(0, color='black', lw=0.5)
ax.axvspan(pd.Timestamp('2026-04-01'), pd.Timestamp('2026-05-22'), color='orange', alpha=0.15, label='5월 partial')
ax.set_ylabel('Cumulative Δret (%)', fontsize=11)
ax.set_title(f'Cumulative outperformance to 5/22 (final {cum_d[-1]:+.1f}pp)', fontsize=13, weight='bold')
ax.legend(loc='upper left', fontsize=9); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '06_cumulative_outperform_to_may22.png', dpi=110); plt.close(fig)

print()
print('=== Metrics — 2013-05 ~ 2026-05-22 ===')
for k in labels:
    print(f'  {k:<8}: STR_1715 {m_1715[k]:>7.3f}  STR_1716 {m_1716[k]:>7.3f}  Δ {m_1716[k]-m_1715[k]:>+7.3f}')

print()
print(f'2026 YTD (n={mask_2026.sum()} 월):')
print(f'  STR_1715 YTD: {nav1715_2026[-1]-100:+.2f}%')
print(f'  STR_1716 YTD: {nav1716_2026[-1]-100:+.2f}%')

print(f'\n[saved] {OUT_DIR}/')
for f in sorted(OUT_DIR.iterdir()):
    print(f'  {f.name}')
