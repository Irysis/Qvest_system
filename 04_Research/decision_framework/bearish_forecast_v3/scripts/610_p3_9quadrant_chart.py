"""
610_p3_9quadrant_chart.py — P3 risk regime 9-Quadrant 시각화

도훈 mandate 2026-05-27:
- σ (변동성) × λ (편향) 9-Quadrant chart
- 최근 trail + 최신 점 강조
- ν (꼬리 두께) color encoding
- KTRI 9-Quadrant 스타일 참조

9 cells (σ low/med/high × λ bear/neutral/bull):
  (high σ, bear) = 🚨 위기
  (low σ, bear)  = 🟠 잠재폭발 (calm before storm)
  (med, neutral) = 💚 평온
  (high, bull)   = ✨ 급등
  (low, bull)    = 🟢 안정 강세
  (med, bear)    = 🟡 약세 진행
  ...

CLI:
    python scripts/610_p3_9quadrant_chart.py [--trail_days 60] [--output 03_models/morning_brief/<date>/9quadrant.png]
"""
from __future__ import annotations
import argparse
import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap, ListedColormap, Normalize
from matplotlib.cm import ScalarMappable

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))

# Font for Korean — register NanumGothic explicitly
import matplotlib.font_manager as fm
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


# ─── 9-Quadrant 정의 ──────────────────────────────────────────────────────────
# σ 컷: low < 1.0%, med 1.0~1.8%, high ≥ 1.8%
SIGMA_LOW = 1.0   # %
SIGMA_HIGH = 1.8  # %
# λ 컷: bear < -0.10, neutral -0.10~+0.10, bull ≥ +0.10
LAM_BEAR = -0.10
LAM_BULL = +0.10

# 9 cells (행=σ desc, 열=λ asc): label + bg color
CELLS = {
    # (sigma_band, lam_band): (label, color, risk_score)
    ('high', 'bear'):    ("🚨 위기",        "#d32f2f", 5),   # 가장 위험
    ('high', 'neutral'): ("⚠️ 혼란",        "#f57c00", 4),
    ('high', 'bull'):    ("✨ 급등",        "#7b1fa2", 4),  # FOMO 경계
    ('med',  'bear'):    ("🟡 약세 진행",    "#fbc02d", 3),
    ('med',  'neutral'): ("🟢 보통",        "#aed581", 2),
    ('med',  'bull'):    ("🌱 강세 진행",    "#66bb6a", 2),
    ('low',  'bear'):    ("🟠 잠재 폭발",    "#ff9800", 3),  # calm before storm
    ('low',  'neutral'): ("💚 평온",        "#43a047", 1),  # 가장 안전
    ('low',  'bull'):    ("🟢 안정 강세",    "#00897b", 2),
}


def classify_sigma(s):
    if s < SIGMA_LOW: return 'low'
    if s < SIGMA_HIGH: return 'med'
    return 'high'

def classify_lam(l):
    if l < LAM_BEAR: return 'bear'
    if l < LAM_BULL: return 'neutral'
    return 'bull'

def cell_of(sigma, lam):
    return (classify_sigma(sigma), classify_lam(lam))


# ─── Plot ─────────────────────────────────────────────────────────────────────
def plot_9quadrant(df: pd.DataFrame, trail_days: int = 60, output: Path = None,
                    title_suffix: str = ""):
    """9-Quadrant scatter with trail.

    df: Date, sigma, lam, nu, mu, p_minus_5pct columns required.
    """
    df = df.sort_values('Date').reset_index(drop=True).copy()
    df['Date'] = pd.to_datetime(df['Date'])
    # σ axis: clamp to [0, 5%] for view
    df['sigma_plot'] = df['sigma'].clip(0, 5.0)
    # λ axis: clamp to [-0.5, +0.5]
    df['lam_plot'] = df['lam'].clip(-0.5, 0.5)
    # Risk score from cell
    df['cell'] = df.apply(lambda r: cell_of(r['sigma'], r['lam']), axis=1)
    df['risk_score'] = df['cell'].map(lambda c: CELLS[c][2])

    # Recent trail
    trail = df.tail(trail_days).reset_index(drop=True)
    latest = trail.iloc[-1]

    # Build figure
    fig = plt.figure(figsize=(15, 10), constrained_layout=True)
    gs = fig.add_gridspec(3, 4, height_ratios=[1, 1, 0.6], width_ratios=[2.5, 1, 1, 1])

    # ── Main 9-Quadrant panel ────────────────────────────────────────────────
    ax = fig.add_subplot(gs[:2, :2])

    # 9 cell bg rectangles
    x_edges = [0, SIGMA_LOW, SIGMA_HIGH, 5.0]
    y_edges = [-0.5, LAM_BEAR, LAM_BULL, 0.5]
    x_centers = [(x_edges[i] + x_edges[i+1]) / 2 for i in range(3)]
    y_centers = [(y_edges[i] + y_edges[i+1]) / 2 for i in range(3)]

    for i, s_band in enumerate(['low', 'med', 'high']):
        for j, l_band in enumerate(['bear', 'neutral', 'bull']):
            label, color, _ = CELLS[(s_band, l_band)]
            x0, x1 = x_edges[i], x_edges[i+1]
            y0, y1 = y_edges[j], y_edges[j+1]
            rect = patches.Rectangle((x0, y0), x1 - x0, y1 - y0,
                                       linewidth=0.5, edgecolor='white',
                                       facecolor=color, alpha=0.18)
            ax.add_patch(rect)
            # cell label
            ax.text(x_centers[i], y_centers[j], label, ha='center', va='center',
                    fontsize=11, fontweight='bold', alpha=0.55, color='#222')

    # Trail points — color by nu (fat-tail intensity)
    # nu < 10: red (strong fat-tail), 10~30: orange, 30~100: yellow, 100~1000: green, >1000: gray (degenerate)
    def nu_color(nu_val):
        if nu_val < 5: return '#b71c1c'      # very fat-tail (extreme)
        if nu_val < 10: return '#d32f2f'     # strong fat-tail
        if nu_val < 30: return '#f57c00'     # moderate fat-tail
        if nu_val < 100: return '#fbc02d'    # mild fat-tail
        if nu_val < 1000: return '#558b2f'   # near-normal
        return '#9e9e9e'                     # degenerate
    trail_colors = [nu_color(n) for n in trail['nu']]

    # alpha gradient (older = more transparent)
    alphas = np.linspace(0.3, 0.95, len(trail))

    # size by |mu|+1 (location distance from 0)
    sizes = 40 + np.abs(trail['mu']) * 20

    # Scatter trail
    for i in range(len(trail)):
        ax.scatter(trail['sigma_plot'].iloc[i], trail['lam_plot'].iloc[i],
                    c=trail_colors[i], s=sizes.iloc[i], alpha=alphas[i],
                    edgecolors='#222', linewidths=0.3, zorder=3)

    # Connect line (trail thread)
    ax.plot(trail['sigma_plot'].values, trail['lam_plot'].values,
            color='#555', alpha=0.25, linewidth=0.8, zorder=2)

    # Latest point — bigger, highlighted
    ax.scatter(latest['sigma_plot'], latest['lam_plot'],
                c=nu_color(latest['nu']), s=350, alpha=1.0,
                edgecolors='black', linewidths=2.5, zorder=10, marker='*')
    ax.annotate(f"{latest['Date'].strftime('%m-%d')}\n"
                f"σ={latest['sigma']:.2f}% λ={latest['lam']:+.2f}\nν={latest['nu']:.0f}",
                xy=(latest['sigma_plot'], latest['lam_plot']),
                xytext=(20, 20), textcoords='offset points',
                fontsize=10, fontweight='bold',
                bbox=dict(boxstyle='round,pad=0.5', facecolor='white', alpha=0.9,
                           edgecolor='black', linewidth=1.5),
                arrowprops=dict(arrowstyle='->', color='black', lw=1.2),
                zorder=11)

    # Grid lines (boundaries)
    for x in [SIGMA_LOW, SIGMA_HIGH]:
        ax.axvline(x, color='#666', linestyle='--', linewidth=0.8, alpha=0.5, zorder=1)
    for y in [LAM_BEAR, LAM_BULL]:
        ax.axhline(y, color='#666', linestyle='--', linewidth=0.8, alpha=0.5, zorder=1)

    ax.set_xlim(0, 5.0)
    ax.set_ylim(-0.5, 0.5)
    ax.set_xlabel(r'$\sigma$ (변동성, %)', fontsize=12, fontweight='bold')
    ax.set_ylabel(r'$\lambda$ (비대칭, bear ← → bull)', fontsize=12, fontweight='bold')
    ax.set_title(f'P3 Risk Regime 9-Quadrant Map (최근 {trail_days}일 궤적){title_suffix}',
                 fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.2)

    # Cell legend
    legend_text = (
        f"σ low: < {SIGMA_LOW}%   med: {SIGMA_LOW}~{SIGMA_HIGH}%   high: ≥ {SIGMA_HIGH}%\n"
        f"λ bear: < {LAM_BEAR}   neutral: {LAM_BEAR}~{LAM_BULL}   bull: ≥ {LAM_BULL}\n"
        f"ν color: 빨강(<10, 강 fat-tail) → 주황(<30) → 노랑(<100) → 초록(<1000) → 회색(>1000 degenerate)"
    )
    ax.text(0.02, -0.18, legend_text, transform=ax.transAxes,
            fontsize=9, color='#333', verticalalignment='top',
            bbox=dict(boxstyle='round,pad=0.4', facecolor='#f5f5f5', alpha=0.85))

    # ── Sidebar: risk_score 시계열 ────────────────────────────────────────────
    ax_rs = fig.add_subplot(gs[0, 2:])
    # Whole window (last 252d) risk score trend
    window = df.tail(252).reset_index(drop=True)
    rs_smooth = window['risk_score'].rolling(5, min_periods=1).mean()
    ax_rs.fill_between(window['Date'], 0, rs_smooth, alpha=0.3, color='#d32f2f')
    ax_rs.plot(window['Date'], rs_smooth, color='#d32f2f', linewidth=1.5)
    ax_rs.axhspan(0, 1.5, alpha=0.1, color='green', label='안전(1)')
    ax_rs.axhspan(1.5, 2.5, alpha=0.1, color='yellowgreen', label='보통(2)')
    ax_rs.axhspan(2.5, 3.5, alpha=0.1, color='orange', label='주의(3)')
    ax_rs.axhspan(3.5, 4.5, alpha=0.1, color='darkorange', label='경계(4)')
    ax_rs.axhspan(4.5, 5.5, alpha=0.1, color='red', label='위기(5)')
    ax_rs.set_ylim(0.5, 5.5)
    ax_rs.set_title('Risk Score 시계열 (5d smooth, 최근 252일)', fontsize=11, fontweight='bold')
    ax_rs.set_ylabel('Risk Score (1-5)')
    ax_rs.grid(True, alpha=0.3)
    ax_rs.tick_params(axis='x', rotation=20, labelsize=8)

    # ── Sidebar: ν 시계열 ────────────────────────────────────────────────────
    ax_nu = fig.add_subplot(gs[1, 2:])
    ax_nu.semilogy(window['Date'], window['nu'].clip(lower=1), color='#1e88e5', linewidth=1.2)
    ax_nu.axhspan(0, 10, alpha=0.15, color='red', label='강 fat-tail (<10)')
    ax_nu.axhspan(10, 100, alpha=0.15, color='orange', label='fat-tail (10~100)')
    ax_nu.axhspan(100, 1000, alpha=0.15, color='yellowgreen', label='near-normal (100~1000)')
    ax_nu.axhspan(1000, 1e7, alpha=0.15, color='gray', label='degenerate (>1000)')
    ax_nu.set_ylim(1, 1e7)
    ax_nu.set_title('ν (꼬리 두께) 시계열 (log scale)', fontsize=11, fontweight='bold')
    ax_nu.set_ylabel('ν (log)')
    ax_nu.grid(True, alpha=0.3, which='both')
    ax_nu.tick_params(axis='x', rotation=20, labelsize=8)

    # ── Bottom: μ + λ 시계열 ─────────────────────────────────────────────────
    ax_ml = fig.add_subplot(gs[2, :])
    ax_ml.plot(window['Date'], window['mu'], color='#388e3c', linewidth=1.0,
                label=r'$\mu$ (평균 예측, %)')
    ax_ml.plot(window['Date'], window['lam'], color='#d32f2f', linewidth=1.0,
                label=r'$\lambda$ (비대칭)')
    ax_ml.axhline(0, color='black', linewidth=0.6, alpha=0.4)
    ax_ml.axhline(LAM_BEAR, color='red', linewidth=0.5, linestyle='--', alpha=0.4)
    ax_ml.axhline(LAM_BULL, color='green', linewidth=0.5, linestyle='--', alpha=0.4)
    ax_ml.legend(loc='upper left', fontsize=9)
    ax_ml.set_title('μ (평균 예측) + λ (비대칭) 시계열 (최근 252일)', fontsize=11, fontweight='bold')
    ax_ml.grid(True, alpha=0.3)
    ax_ml.tick_params(axis='x', rotation=20, labelsize=8)

    # Save
    if output:
        output = Path(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, dpi=120, bbox_inches='tight', facecolor='white')
        print(f'[9quad] saved → {output}')
    return fig


# ─── Risk level analytical readout (오늘) ────────────────────────────────────
def summarize_today(df: pd.DataFrame) -> dict:
    latest = df.sort_values('Date').iloc[-1]
    cell = cell_of(latest['sigma'], latest['lam'])
    label, color, score = CELLS[cell]
    return {
        'date': str(pd.to_datetime(latest['Date']).date()),
        'mu': float(latest['mu']),
        'sigma': float(latest['sigma']),
        'nu': float(latest['nu']),
        'lam': float(latest['lam']),
        'p_minus_5pct': float(latest.get('p_minus_5pct', float('nan'))),
        'p_minus_10pct': float(latest.get('p_minus_10pct', float('nan'))),
        'sigma_band': classify_sigma(latest['sigma']),
        'lam_band': classify_lam(latest['lam']),
        'cell_label': label,
        'risk_score': score,
    }


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet',
                        help='P3 predictions parquet (trial19 WF CV + recent daily inference)')
    parser.add_argument('--trail_days', type=int, default=60)
    parser.add_argument('--output', type=str, default=None,
                        help='Output PNG path (default: morning_brief/<date>/9quadrant.png)')
    parser.add_argument('--asof', type=str, default=None,
                        help='Filter end date (YYYY-MM-DD, default: latest)')
    args = parser.parse_args()

    src = Path(args.source)
    if not src.is_absolute():
        src = PROJECT_ROOT / src
    df = pd.read_parquet(src)
    df['Date'] = pd.to_datetime(df['Date'])
    if args.asof:
        df = df[df['Date'] <= pd.to_datetime(args.asof)]

    # also merge in P3_daily.parquet for latest live inference
    daily_path = ROOT / '03_models' / 'daily_predictions' / 'P3_daily.parquet'
    if daily_path.exists():
        daily = pd.read_parquet(daily_path)
        daily['Date'] = pd.to_datetime(daily['Date'])
        # Only take rows not already in df
        new_rows = daily[~daily['Date'].isin(df['Date'])]
        if len(new_rows):
            print(f'[9quad] merging {len(new_rows)} live inference rows from P3_daily.parquet')
            cols_common = [c for c in df.columns if c in daily.columns]
            df = pd.concat([df[cols_common], new_rows[cols_common]],
                            ignore_index=True).sort_values('Date').reset_index(drop=True)

    summary = summarize_today(df)
    print(f"[9quad] Today readout ({summary['date']}):")
    print(f"  μ={summary['mu']:+.3f}%  σ={summary['sigma']:.2f}%  ν={summary['nu']:.1f}  λ={summary['lam']:+.3f}")
    print(f"  cell: ({summary['sigma_band']}, {summary['lam_band']}) → {summary['cell_label']}  (score={summary['risk_score']}/5)")

    if args.output:
        out = Path(args.output)
    else:
        date_str = summary['date']
        out = ROOT / '03_models' / 'morning_brief' / date_str / '9quadrant.png'
    if not out.is_absolute():
        out = PROJECT_ROOT / out

    plot_9quadrant(df, trail_days=args.trail_days, output=out,
                    title_suffix=f"\n오늘({summary['date']}): {summary['cell_label']} (Risk Score {summary['risk_score']}/5)")

    print(f'\n[9quad] done.')


if __name__ == '__main__':
    main()
