"""
620_p3_dashboard_charts.py — P3 dashboard 4 신규 차트 (도훈 mandate 2026-05-27)

Charts:
1. Fan chart (시간 × quantile band) — Bank of England 양식
2. Risk Score calendar heatmap (GitHub contribution graph 양식)
3. PIT histogram + Reliability diagram (calibration 검증)
4. Density ridge plot (joy plot, monthly distribution slices)
"""
from __future__ import annotations
import argparse
import importlib.util
import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.font_manager as fm
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))

# Korean font
KR_FONT_PATHS = [
    '/home/quant/.local/share/fonts/NanumGothic-Regular.ttf',
    '/home/quant/.local/share/fonts/NanumGothic-Bold.ttf',
    '/mnt/c/Windows/Fonts/malgun.ttf',
]
_kr_font = None
for fp in KR_FONT_PATHS:
    if Path(fp).exists():
        try:
            fm.fontManager.addfont(fp)
            _kr_font = fm.FontProperties(fname=fp).get_name()
            break
        except Exception:
            pass
if _kr_font:
    plt.rcParams['font.family'] = [_kr_font, 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


HSK = _load("p1_hansen_skewt", str(ROOT / "03_models" / "p1_hansen_skewt.py"))


# ─── Data loading + enrichment ────────────────────────────────────────────────
def load_p3_data():
    src = ROOT / "03_models" / "p3_trial19" / "all_predictions.parquet"
    dat = pd.read_parquet(src)
    dat['Date'] = pd.to_datetime(dat['Date'])
    dat = dat.sort_values('Date').reset_index(drop=True)

    # merge live daily inference
    daily_path = ROOT / "03_models" / "daily_predictions" / "P3_daily.parquet"
    if daily_path.exists():
        daily = pd.read_parquet(daily_path)
        daily['Date'] = pd.to_datetime(daily['Date'])
        new_rows = daily[~daily['Date'].isin(dat['Date'])]
        if len(new_rows):
            common = [c for c in dat.columns if c in daily.columns]
            dat = pd.concat([dat[common], new_rows[common]], ignore_index=True)
            dat = dat.sort_values('Date').reset_index(drop=True)

    # derive quantiles (q05, q25, q50, q75, q95) from Hansen params
    for tau in [0.05, 0.25, 0.50, 0.75, 0.95]:
        col = f'q_{int(tau*100):02d}'
        dat[col] = HSK.hansen_quantile(
            np.full(len(dat), tau),
            dat['mu'].values, dat['sigma'].values,
            dat['nu'].values, dat['lam'].values,
        )

    # forward 22d cumulative
    dat['y_cum'] = dat['y_actual'].fillna(0).cumsum()
    dat['fwd22'] = dat['y_cum'].shift(-22) - dat['y_cum']
    dat.loc[dat.Date > (dat.Date.max() - pd.Timedelta(days=22)), 'fwd22'] = np.nan

    # risk score (expanding z + clip ±3 + composite weights)
    def expanding_z(s, min_obs=60):
        mu = s.expanding(min_obs).mean()
        sd = s.expanding(min_obs).std() + 1e-8
        return ((s - mu) / sd).clip(-3, 3)
    z_sigma   = expanding_z(dat['sigma'])
    z_lam     = expanding_z(dat['lam'])
    z_mu      = expanding_z(dat['mu'])
    z_inv_nu  = expanding_z(1 / dat['nu'].clip(lower=1))
    z_var05   = expanding_z(dat['var_05'])
    dat['risk_raw']   = 0.7*z_sigma + 0.5*(-z_lam) + 0.3*(-z_mu) + 0.3*z_inv_nu + 0.4*(-z_var05)
    dat['risk_score'] = (3.0 + dat['risk_raw']).clip(1, 5)

    return dat


# ─── Chart 1: Fan chart ───────────────────────────────────────────────────────
def chart_fan(dat: pd.DataFrame, out_path: Path, window_days=252):
    sub = dat.tail(window_days).reset_index(drop=True)
    fig, ax = plt.subplots(figsize=(12, 6), constrained_layout=True)

    # Fan bands (50% / 90% / outer)
    ax.fill_between(sub['Date'], sub['q_05'], sub['q_95'],
                     color='#FF7043', alpha=0.18, label='90% band (q05-q95)')
    ax.fill_between(sub['Date'], sub['q_25'], sub['q_75'],
                     color='#FF7043', alpha=0.35, label='50% band (q25-q75)')

    # Median line
    ax.plot(sub['Date'], sub['q_50'], color='#B71C1C',
             linewidth=1.0, alpha=0.7, label='median (q50)')

    # Realized return overlay (1d)
    ax.scatter(sub['Date'], sub['y_actual'], s=8, c='#1565C0',
                alpha=0.65, zorder=5, label='실현 1d 수익률')

    # Out-of-band markers (realized exceeds 90% band)
    out_lower = sub[sub['y_actual'] < sub['q_05']]
    out_upper = sub[sub['y_actual'] > sub['q_95']]
    if len(out_lower):
        ax.scatter(out_lower['Date'], out_lower['y_actual'], s=40,
                    facecolors='none', edgecolors='red', linewidths=1.5,
                    zorder=6, label=f'하단 위반 ({len(out_lower)}건, 기대 ~{int(0.05*len(sub))})')
    if len(out_upper):
        ax.scatter(out_upper['Date'], out_upper['y_actual'], s=40,
                    facecolors='none', edgecolors='blue', linewidths=1.5,
                    zorder=6, label=f'상단 위반 ({len(out_upper)}건)')

    ax.axhline(0, color='black', linewidth=0.5, alpha=0.4)
    latest_date = sub['Date'].max()
    ax.set_xlim(sub['Date'].min(), latest_date + pd.Timedelta(days=5))
    ax.set_title(f'P3 Fan Chart — 1일 수익률 분포 시계열 (최근 {window_days}일)',
                  fontsize=13, fontweight='bold')
    ax.set_ylabel('1일 log return (%)', fontsize=11)
    ax.set_xlabel('Date', fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper left', fontsize=9, ncol=2)
    ax.tick_params(axis='x', rotation=20)
    fig.savefig(out_path, dpi=120, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    return out_lower, out_upper


# ─── Chart 2: Risk Score calendar heatmap ─────────────────────────────────────
def chart_calendar(dat: pd.DataFrame, out_path: Path, year=None):
    if year is None:
        year = int(dat['Date'].max().year)
    sub = dat[(dat['Date'] >= f'{year}-01-01') & (dat['Date'] <= f'{year}-12-31')].copy()
    sub['weekday'] = sub['Date'].dt.weekday  # Mon=0, Sun=6
    sub['week'] = sub['Date'].dt.isocalendar().week

    # Build 7×53 grid (rows = weekday, cols = ISO week)
    grid = np.full((7, 54), np.nan)
    for _, r in sub.iterrows():
        wd = int(r['weekday'])
        wk = int(r['week'])
        if 0 <= wd < 7 and 0 <= wk < 54:
            grid[wd, wk] = r['risk_score']

    # Color: red → green inverse (high risk = red)
    cmap = LinearSegmentedColormap.from_list(
        'risk', ['#1B5E20', '#7CB342', '#FBC02D', '#F4511E', '#B71C1C'], N=100)

    fig, ax = plt.subplots(figsize=(15, 4), constrained_layout=True)
    im = ax.imshow(grid, aspect='auto', cmap=cmap, vmin=1, vmax=5,
                    interpolation='none', origin='lower')
    ax.set_yticks(range(7))
    ax.set_yticklabels(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'], fontsize=9)
    ax.set_xticks(range(0, 54, 4))
    ax.set_xticklabels([f'W{w}' for w in range(0, 54, 4)], fontsize=8)
    ax.set_title(f'{year} P3 Risk Score Calendar Heatmap (1=안전, 5=위기)',
                  fontsize=13, fontweight='bold')

    # Latest day marker
    if len(sub):
        latest = sub.iloc[-1]
        lwd = int(latest['weekday'])
        lwk = int(latest['week'])
        ax.scatter([lwk], [lwd], s=200, marker='*', facecolors='gold',
                    edgecolors='black', linewidths=1.5, zorder=10)

    cbar = plt.colorbar(im, ax=ax, fraction=0.03, pad=0.02)
    cbar.set_label('Risk Score', fontsize=10)
    fig.savefig(out_path, dpi=120, bbox_inches='tight', facecolor='white')
    plt.close(fig)


# ─── Chart 3: PIT histogram + Reliability diagram ─────────────────────────────
def chart_pit_reliability(dat: pd.DataFrame, out_path: Path, window=None):
    sub = dat.dropna(subset=['pit', 'y_actual'])
    if window:
        sub = sub.tail(window)

    fig, axes = plt.subplots(1, 2, figsize=(13, 5.5), constrained_layout=True)

    # ── 3a. PIT histogram ─────────────────────────────────────────────────────
    ax = axes[0]
    counts, edges, _ = ax.hist(sub['pit'].values, bins=10, range=(0, 1),
                                 color='#FF7043', edgecolor='black', linewidth=0.6,
                                 alpha=0.85)
    expected = len(sub) / 10
    ax.axhline(expected, color='#1565C0', linestyle='--', linewidth=2,
                label=f'Uniform 기대값 = {expected:.0f}')
    # Chi-square stat
    chi2 = ((counts - expected)**2 / expected).sum()
    from scipy.stats import chi2 as chi2_dist
    pval = 1 - chi2_dist.cdf(chi2, df=9)
    ax.set_xlim(0, 1)
    ax.set_xlabel('PIT 값 (0~1)', fontsize=11)
    ax.set_ylabel('빈도', fontsize=11)
    ax.set_title(f'PIT Histogram (n={len(sub)})\n'
                  f'chi² = {chi2:.2f}, p = {pval:.4f}  {"PASS" if pval > 0.05 else "FAIL"} @ 0.05',
                  fontsize=11, fontweight='bold')
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)

    # ── 3b. Reliability diagram (VaR levels) ──────────────────────────────────
    ax = axes[1]
    # nominal vs realized breach rate for VaR levels
    var_levels = [0.001, 0.005, 0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.50]
    # For each level α, count realized < q_α (interpolate from pit)
    realized_rates = []
    for alpha in var_levels:
        rate = (sub['pit'] < alpha).mean()
        realized_rates.append(rate)
    ax.plot([0, 0.5], [0, 0.5], color='gray', linestyle='--',
             alpha=0.6, label='perfect calibration')
    ax.scatter(var_levels, realized_rates, s=80, c='#B71C1C',
                edgecolors='black', linewidths=1, zorder=5)
    for v, r in zip(var_levels, realized_rates):
        ax.annotate(f'{int(v*100)}%', xy=(v, r), xytext=(5, 5),
                     textcoords='offset points', fontsize=8)
    ax.set_xlim(0, 0.55)
    ax.set_ylim(0, max(0.55, max(realized_rates) * 1.1))
    ax.set_xlabel('Nominal VaR 수준 (α)', fontsize=11)
    ax.set_ylabel('실현된 위반율', fontsize=11)
    ax.set_title('Reliability Diagram\n(nominal α vs realized breach rate)',
                  fontsize=11, fontweight='bold')
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)

    fig.suptitle(f'P3 Calibration 검증 (window: {sub.Date.min().date()} ~ {sub.Date.max().date()})',
                  fontsize=13, fontweight='bold')
    fig.savefig(out_path, dpi=120, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    return pval


# ─── Chart 4: Density ridge plot (monthly slices) ─────────────────────────────
def chart_ridge(dat: pd.DataFrame, out_path: Path, months=12):
    # Last N months distribution samples (from each day's Hansen params)
    end_date = dat['Date'].max()
    start_date = end_date - pd.DateOffset(months=months)
    sub = dat[(dat['Date'] >= start_date) & (dat['Date'] <= end_date)].copy()
    sub['YearMonth'] = sub['Date'].dt.to_period('M')
    month_groups = list(sub.groupby('YearMonth'))

    # Estimate PDF for each month
    x_grid = np.linspace(-8, 8, 300)
    fig, ax = plt.subplots(figsize=(12, 9), constrained_layout=True)

    n_months = len(month_groups)
    cmap = plt.cm.viridis(np.linspace(0.15, 0.85, n_months))
    offset_step = 0.5

    for idx, (ym, grp) in enumerate(month_groups):
        # average params for that month
        mu_m = grp['mu'].mean()
        sigma_m = grp['sigma'].mean()
        nu_m = grp['nu'].mean()
        lam_m = grp['lam'].mean()
        # Sample 500 from Hansen with these params (using inverse CDF)
        u_samp = np.random.uniform(0.001, 0.999, 500)
        samples = HSK.hansen_quantile(u_samp, mu_m, sigma_m, nu_m, lam_m)
        samples = samples[(samples >= -8) & (samples <= 8)]
        if len(samples) < 10:
            continue
        # Histogram density
        density, _ = np.histogram(samples, bins=x_grid, density=True)
        # Smooth (simple moving avg)
        if len(density) > 5:
            density = np.convolve(density, np.ones(5)/5, mode='same')
        x_mid = (x_grid[:-1] + x_grid[1:]) / 2
        y_base = idx * offset_step
        ax.fill_between(x_mid, y_base, y_base + density * 4,
                          color=cmap[idx], alpha=0.75, edgecolor='black', linewidth=0.4)
        # Month label
        ax.text(-7.8, y_base + 0.05, str(ym), fontsize=9, fontweight='bold',
                 verticalalignment='bottom')

    ax.set_xlim(-8, 8)
    ax.set_ylim(-0.2, n_months * offset_step + 1)
    ax.set_yticks([])
    ax.axvline(0, color='black', linewidth=0.5, alpha=0.4)
    ax.set_xlabel('1일 log return (%)', fontsize=11)
    ax.set_title(f'P3 Monthly Distribution Ridge Plot (최근 {months}개월)\n'
                  f'각 행 = 해당 월 평균 Hansen 분포 (μ̄, σ̄, ν̄, λ̄)',
                  fontsize=13, fontweight='bold')
    fig.savefig(out_path, dpi=120, bbox_inches='tight', facecolor='white')
    plt.close(fig)


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output_dir', type=str, default=None)
    parser.add_argument('--fan_window', type=int, default=252)
    parser.add_argument('--ridge_months', type=int, default=12)
    args = parser.parse_args()

    dat = load_p3_data()
    latest_date = dat['Date'].max().date()
    print(f'[dashboard] data: {len(dat)} rows  latest={latest_date}')

    if args.output_dir is None:
        out_dir = ROOT / "03_models" / "morning_brief" / str(latest_date)
    else:
        out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Fan chart
    fan_path = out_dir / 'p3_fan_chart.png'
    out_lo, out_hi = chart_fan(dat, fan_path, window_days=args.fan_window)
    print(f'[1/4] Fan chart → {fan_path}')
    print(f'      band breaches (last {args.fan_window}d): lower {len(out_lo)}, upper {len(out_hi)} (expected ~{int(0.05*args.fan_window)} each)')

    # 2. Calendar heatmap
    cal_path = out_dir / 'p3_calendar_heatmap.png'
    chart_calendar(dat, cal_path, year=latest_date.year)
    print(f'[2/4] Calendar heatmap → {cal_path}')

    # 3. PIT + Reliability
    pit_path = out_dir / 'p3_pit_reliability.png'
    pval = chart_pit_reliability(dat, pit_path)
    print(f'[3/4] PIT + Reliability → {pit_path}  (chi² p={pval:.4f})')

    # 4. Density ridge
    ridge_path = out_dir / 'p3_density_ridge.png'
    chart_ridge(dat, ridge_path, months=args.ridge_months)
    print(f'[4/4] Density ridge → {ridge_path}')


if __name__ == "__main__":
    main()
