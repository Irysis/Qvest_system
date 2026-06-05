"""
705_str1716_telegram_brief.py — STR_1716 PG1 admit Telegram brief + charts

도훈 mandate 2026-05-26:
1. P3 개발 + STR_1716 상세 리뷰 텔레그램
2. 성과 시각화 차트 풍부하게
3. STR_1716 5월 보유비중 제시
"""
import pandas as pd
import numpy as np
import json
import os
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.dates as mdates

# Korean font (best available)
for f in ['NanumGothic', 'Malgun Gothic', 'AppleGothic', 'NanumBarunGothic', 'DejaVu Sans']:
    if any(font.name == f for font in fm.fontManager.ttflist):
        plt.rcParams['font.family'] = f
        break
plt.rcParams['axes.unicode_minus'] = False

PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])
OUT_DIR = PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/charts'
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ─── Load data ──────────────────────────────────────────────────────────────
str1715_pr = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
str1715_pr['Date'] = pd.to_datetime(str1715_pr['date'])
str1715_pr = str1715_pr.sort_values('Date').reset_index(drop=True)

str1716_pr = pd.read_csv(PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/03_period_returns.csv')
str1716_pr['Date'] = pd.to_datetime(str1716_pr['date'])
str1716_pr = str1716_pr.sort_values('Date').reset_index(drop=True)

p3 = pd.read_parquet(PROJECT / '04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet')
p3['Date'] = pd.to_datetime(p3['Date'])

weights_1715 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260512_str1715_sleeve_top20_alpha_2026_04.csv')

# ─── Compute NAVs ──────────────────────────────────────────────────────────
ret_1715 = str1715_pr['ret_net'].values
ret_1716 = str1716_pr['ret_net'].values
nav_1715 = np.cumprod(1 + ret_1715)
nav_1716 = np.cumprod(1 + ret_1716)
dates = str1715_pr['Date']

# Drawdowns
def drawdown(nav):
    cm = np.maximum.accumulate(nav)
    return (nav - cm) / cm

dd_1715 = drawdown(nav_1715)
dd_1716 = drawdown(nav_1716)

# ─── Chart 1: NAV equity curve (log scale) ─────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 6))
ax.semilogy(dates, nav_1715, label='STR_1715 (PG2 baseline)', color='#34495e', lw=1.8)
ax.semilogy(dates, nav_1716, label='STR_1716 (P3 overlay) — PG1 admit', color='#e74c3c', lw=1.8)
ax.axvline(pd.Timestamp('2013-05-01'), color='blue', ls='--', alpha=0.5, label='P3 era start')
ax.set_title('Cumulative NAV — STR_1715 vs STR_1716 (22년 log scale)', fontsize=13, weight='bold')
ax.set_ylabel('NAV (log)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, which='both')
ax.xaxis.set_major_locator(mdates.YearLocator(2))
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '01_nav_equity_curve.png', dpi=110); plt.close(fig)

# ─── Chart 2: Drawdown comparison ───────────────────────────────────────────
fig, ax = plt.subplots(figsize=(13, 5))
ax.fill_between(dates, dd_1715*100, 0, color='#34495e', alpha=0.4, label='STR_1715 DD')
ax.fill_between(dates, dd_1716*100, 0, color='#e74c3c', alpha=0.45, label='STR_1716 DD')
ax.set_title('Drawdown comparison (22년)', fontsize=13, weight='bold')
ax.set_ylabel('Drawdown (%)', fontsize=11); ax.set_xlabel('Date', fontsize=10)
ax.legend(loc='lower left', fontsize=10); ax.grid(alpha=0.3)
ax.axvline(pd.Timestamp('2013-05-01'), color='blue', ls='--', alpha=0.5)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '02_drawdown_compare.png', dpi=110); plt.close(fig)

# ─── Chart 3: Rolling 12-month Sharpe ──────────────────────────────────────
def rolling_sharpe(ret, w=12):
    rs = pd.Series(ret).rolling(w)
    return rs.mean() / (rs.std() + 1e-9) * np.sqrt(12)

rs_1715 = rolling_sharpe(ret_1715)
rs_1716 = rolling_sharpe(ret_1716)

fig, ax = plt.subplots(figsize=(13, 5))
ax.plot(dates, rs_1715, color='#34495e', lw=1.5, label='STR_1715 rolling SR')
ax.plot(dates, rs_1716, color='#e74c3c', lw=1.5, label='STR_1716 rolling SR')
ax.axhline(0, color='gray', ls='--', alpha=0.5)
ax.axvline(pd.Timestamp('2013-05-01'), color='blue', ls='--', alpha=0.5)
ax.set_title('12-month Rolling Sharpe Ratio', fontsize=13, weight='bold')
ax.set_ylabel('Rolling SR', fontsize=11)
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '03_rolling_sharpe.png', dpi=110); plt.close(fig)

# ─── Chart 4: Cash overlay timeline ────────────────────────────────────────
cash = str1716_pr['cash_weight'].values * 100

fig, axes = plt.subplots(2, 1, figsize=(13, 7), sharex=True)
axes[0].fill_between(dates, cash, 0, color='#3498db', alpha=0.6)
axes[0].set_ylabel('Cash %', fontsize=11)
axes[0].set_title('STR_1716 P3 Cash Overlay Timeline', fontsize=13, weight='bold')
axes[0].axvline(pd.Timestamp('2013-05-01'), color='blue', ls='--', alpha=0.7, label='P3 era')
axes[0].axhline(60, color='red', ls=':', alpha=0.4, label='cap 60%')
axes[0].legend(loc='upper left', fontsize=9); axes[0].grid(alpha=0.3)

# P3 sigma monthly
p3_monthly = p3.set_index('Date').resample('ME').last().reset_index()
axes[1].plot(p3_monthly['Date'], p3_monthly['sigma'], color='#27ae60', lw=1.2)
axes[1].set_ylabel('P3 sigma (daily %)', fontsize=11)
axes[1].set_xlabel('Date', fontsize=10)
axes[1].grid(alpha=0.3)
axes[1].set_title('P3 sigma forecast monthly', fontsize=11)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '04_cash_overlay_timeline.png', dpi=110); plt.close(fig)

# ─── Chart 5: Yearly returns bar comparison ────────────────────────────────
str1715_pr['Year'] = str1715_pr['Date'].dt.year
str1716_pr['Year'] = str1716_pr['Date'].dt.year
yearly_1715 = str1715_pr.groupby('Year')['ret_net'].apply(lambda x: (1 + x).prod() - 1) * 100
yearly_1716 = str1716_pr.groupby('Year')['ret_net'].apply(lambda x: (1 + x).prod() - 1) * 100

fig, ax = plt.subplots(figsize=(14, 6))
x = np.arange(len(yearly_1715))
w = 0.4
ax.bar(x - w/2, yearly_1715.values, w, label='STR_1715', color='#34495e')
ax.bar(x + w/2, yearly_1716.values, w, label='STR_1716', color='#e74c3c')
ax.set_xticks(x); ax.set_xticklabels(yearly_1715.index.astype(str), rotation=45)
ax.axhline(0, color='black', lw=0.5)
ax.set_ylabel('Annual return (%)', fontsize=11)
ax.set_title('Annual returns comparison (22년)', fontsize=13, weight='bold')
ax.legend(loc='upper left', fontsize=10); ax.grid(alpha=0.3, axis='y')

# Mark crisis years
for i, year in enumerate(yearly_1715.index):
    if year == 2008: ax.text(i, max(yearly_1715[year], yearly_1716[year]) + 5, 'Lehman', ha='center', fontsize=8, color='red')
    if year == 2020: ax.text(i, max(yearly_1715[year], yearly_1716[year]) + 5, 'COVID', ha='center', fontsize=8, color='red')
    if year == 2022: ax.text(i, max(yearly_1715[year], yearly_1716[year]) + 5, 'Bear', ha='center', fontsize=8, color='red')
fig.tight_layout()
fig.savefig(OUT_DIR / '05_yearly_returns.png', dpi=110); plt.close(fig)

# ─── Chart 6: P3 era zoom ──────────────────────────────────────────────────
mask = dates >= pd.Timestamp('2013-05-01')
nav_p3_1715 = nav_1715[mask] / nav_1715[mask][0]
nav_p3_1716 = nav_1716[mask] / nav_1716[mask][0]

fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
axes[0].plot(dates[mask], nav_p3_1715, color='#34495e', lw=1.8, label='STR_1715')
axes[0].plot(dates[mask], nav_p3_1716, color='#e74c3c', lw=1.8, label='STR_1716')
axes[0].set_yscale('log')
axes[0].set_ylabel('NAV (normalized to P3 start)', fontsize=11)
axes[0].set_title('P3 Era Zoom: 2013-05 ~ 2026-04 (13년 isolated)', fontsize=13, weight='bold')
axes[0].legend(loc='upper left', fontsize=10); axes[0].grid(alpha=0.3, which='both')

axes[1].fill_between(dates[mask], dd_1715[mask]*100, 0, color='#34495e', alpha=0.4, label='STR_1715 DD')
axes[1].fill_between(dates[mask], dd_1716[mask]*100, 0, color='#e74c3c', alpha=0.45, label='STR_1716 DD')
axes[1].set_ylabel('Drawdown (%)', fontsize=11); axes[1].set_xlabel('Date', fontsize=10)
axes[1].legend(loc='lower left', fontsize=10); axes[1].grid(alpha=0.3)
fig.autofmt_xdate(); fig.tight_layout()
fig.savefig(OUT_DIR / '06_p3_era_zoom.png', dpi=110); plt.close(fig)

# ─── Chart 7: Risk metrics radar ───────────────────────────────────────────
# Compute metrics for both
def calc_m(ret):
    nav = np.cumprod(1 + ret); cm = np.maximum.accumulate(nav); dd = (nav - cm) / cm
    return {'CAGR': (nav[-1] ** (12/len(ret)) - 1) * 100,
            'Sharpe': ret.mean() / (ret.std() + 1e-9) * np.sqrt(12),
            'Sortino': ret.mean() / (ret[ret < 0].std() + 1e-9) * np.sqrt(12),
            'Calmar': ((nav[-1] ** (12/len(ret)) - 1)) / max(abs(dd.min()), 1e-9),
            'MDD_inv': 1 - abs(dd.min()),  # higher = less drawdown
            'Hit': (ret > 0).mean()}

m1715 = calc_m(ret_1715)
m1716 = calc_m(ret_1716)
m1716_p3 = calc_m(ret_1716[156:])  # actually wrong, P3 era is last 156

# bar chart of normalized metrics
labels = ['Sharpe', 'Sortino', 'Calmar', 'CAGR%', 'MDD↓%', 'Hit%']
v1715 = [m1715['Sharpe'], m1715['Sortino'], m1715['Calmar'], m1715['CAGR'],
         abs(drawdown(nav_1715).min())*100, m1715['Hit']*100]
v1716 = [m1716['Sharpe'], m1716['Sortino'], m1716['Calmar'], m1716['CAGR'],
         abs(drawdown(nav_1716).min())*100, m1716['Hit']*100]

fig, ax = plt.subplots(figsize=(12, 5))
x = np.arange(len(labels))
ax.bar(x - 0.2, v1715, 0.4, label='STR_1715', color='#34495e')
ax.bar(x + 0.2, v1716, 0.4, label='STR_1716', color='#e74c3c')
ax.set_xticks(x); ax.set_xticklabels(labels)
ax.set_title('Risk-adjusted metrics comparison', fontsize=13, weight='bold')
ax.legend(loc='upper right', fontsize=10); ax.grid(alpha=0.3, axis='y')
for i, (a, b) in enumerate(zip(v1715, v1716)):
    ax.text(i - 0.2, a + max(v1715)*0.02, f'{a:.2f}', ha='center', fontsize=8)
    ax.text(i + 0.2, b + max(v1716)*0.02, f'{b:.2f}', ha='center', fontsize=8)
fig.tight_layout()
fig.savefig(OUT_DIR / '07_metrics_comparison.png', dpi=110); plt.close(fig)

# ─── Compute 5월 보유비중 ──────────────────────────────────────────────────
# Latest P3 forecast (5/25)
latest_p3 = p3.iloc[-1]
sigma_d = latest_p3['sigma']; lam_v = latest_p3['lam']; p10_v = latest_p3['p_minus_10pct']

sigma_ann = sigma_d * np.sqrt(252) / 100
expo_vt = min(0.15 / max(sigma_ann, 0.05), 1.0)
cash_vt = max(0, 1 - expo_vt)
tail_extra = min(30 * p10_v, 0.40)
lam_extra = 0.20 if lam_v < -0.15 else 0.0
cash_total = min(cash_vt + tail_extra + lam_extra, 0.60)
equity_exposure = 1 - cash_total

# Apply to STR_1715 weights
holdings_1716 = weights_1715.copy()
holdings_1716['Weight_sleeve_str1715'] = holdings_1716['Weight_sleeve']
holdings_1716['Weight_str1716_pct'] = holdings_1716['Weight_sleeve'] * equity_exposure * 100

# Save 5월 holdings
holdings_out = holdings_1716[['rank', 'Ticker', 'Name', 'Sector', 'Weight_sleeve_str1715', 'Weight_str1716_pct']].copy()
holdings_out.columns = ['rank', 'Ticker', 'Name', 'Sector', 'STR_1715_weight', 'STR_1716_weight_pct']
holdings_out.to_csv(OUT_DIR / '08_str1716_may2026_holdings.csv', index=False)

# Chart 8: 5월 보유비중 bar
fig, ax = plt.subplots(figsize=(13, 7))
y_pos = np.arange(len(holdings_out))
bars1 = ax.barh(y_pos - 0.2, holdings_out['STR_1715_weight'] * 100, 0.4, color='#34495e', label='STR_1715 (PG2)')
bars2 = ax.barh(y_pos + 0.2, holdings_out['STR_1716_weight_pct'], 0.4, color='#e74c3c', label='STR_1716 (PG1)')
ax.set_yticks(y_pos)
ax.set_yticklabels([f"{r['Ticker'][:8]} {r['Name'][:15]}" for _, r in holdings_out.iterrows()], fontsize=8)
ax.invert_yaxis()
ax.set_xlabel('Weight (%)', fontsize=11)
ax.set_title(f'STR_1716 (PG1) vs STR_1715 (PG2) — 5월 보유비중\n'
             f'Cash overlay: {cash_total*100:.1f}% (vol={expo_vt:.2f}, tail+{tail_extra*100:.1f}, λ+{lam_extra*100:.0f})',
             fontsize=12, weight='bold')
ax.legend(loc='lower right', fontsize=9); ax.grid(alpha=0.3, axis='x')
fig.tight_layout()
fig.savefig(OUT_DIR / '09_may2026_holdings.png', dpi=110); plt.close(fig)

print(f'5월 보유비중 ({latest_p3["Date"].date()} P3 기준):')
print(f'  Cash: {cash_total*100:.1f}% (vol_target {expo_vt*100:.1f}%, tail boost +{tail_extra*100:.1f}%, λ boost +{lam_extra*100:.0f}%)')
print(f'  Equity exposure: {equity_exposure*100:.1f}%')
print(f'\nTop 20 holdings:')
print(holdings_out[['rank', 'Ticker', 'Name', 'STR_1715_weight', 'STR_1716_weight_pct']].to_string(index=False, float_format='{:.3f}'.format))

print(f'\n[saved] {OUT_DIR}/')
for f in sorted(OUT_DIR.iterdir()):
    print(f'  {f.name}')
