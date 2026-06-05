"""
600_morning_brief.py — P2 모델 일간 모닝브리핑 양식 생성

도훈 mandate 2026-05-26: 데일리 브리핑 양식 (markdown 텍스트 + PNG 차트 조합).

Output:
- 03_models/morning_brief/{YYYY-MM-DD}/brief.md  (텔레그램/이메일용 텍스트)
- 03_models/morning_brief/{YYYY-MM-DD}/dist.png  (분포 시각화)
- 03_models/morning_brief/{YYYY-MM-DD}/trend.png (최근 22일 추세)
"""
from __future__ import annotations
import argparse
import importlib.util
import sys
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import numpy as np
import pandas as pd

# Korean font setup (fall back gracefully)
for f in ['NanumGothic', 'Malgun Gothic', 'AppleGothic', 'NanumBarunGothic', 'DejaVu Sans']:
    if any(font.name == f for font in fm.fontManager.ttflist):
        plt.rcParams['font.family'] = f
        break
plt.rcParams['axes.unicode_minus'] = False

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


HSK = _load('hsk', str(ROOT / '03_models' / 'p1_hansen_skewt.py'))


def make_brief(predictions_path, brief_date=None, output_root=None):
    """Generate morning brief for a given date (default: latest available)."""
    df = pd.read_parquet(predictions_path)
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values('Date').reset_index(drop=True)

    if brief_date is None:
        brief_date = df['Date'].max()
    else:
        brief_date = pd.to_datetime(brief_date)

    # Brief row = day with forecast for `brief_date` (i.e. row['Date'] == day before brief_date)
    # Actually our predictions file: row['Date'] = the forecast was made for that day's NEXT-day return.
    # So if we want today's brief, we want the row where Date = previous trading day.
    # Simpler: just use the latest available row as "tomorrow's forecast" (forecast made yesterday).
    today_row = df[df['Date'] == brief_date]
    if len(today_row) == 0:
        # use latest
        today_row = df.iloc[[-1]]
        brief_date = today_row['Date'].iloc[0]
    today = today_row.iloc[0]

    # Yesterday actual — 실제 거래일만 (forward-filled 0% row 제외, 주말/공휴일 skip)
    yesterday_idx = df.index[df['Date'] == brief_date][0]
    has_yest = yesterday_idx > 0
    prev = None
    last_actual_date = None
    if has_yest:
        # 가장 최근 y_actual ≠ 0 (실제 거래) 인 row 찾기
        for k in range(yesterday_idx - 1, max(yesterday_idx - 10, -1), -1):
            y_act = df.iloc[k].get('y_actual', float('nan'))
            if pd.notna(y_act) and abs(y_act) > 1e-8:
                prev = df.iloc[k]
                last_actual_date = df.iloc[k]['Date']
                break
        if prev is None:
            # fallback to direct previous
            prev = df.iloc[yesterday_idx - 1]

    # Recent 22d window
    window_start = max(0, yesterday_idx - 21)
    recent = df.iloc[window_start:yesterday_idx + 1].copy()

    # Setup output dir
    if output_root is None:
        output_root = ROOT / '03_models' / 'morning_brief'
    out_dir = output_root / brief_date.strftime('%Y-%m-%d')
    out_dir.mkdir(parents=True, exist_ok=True)

    # ─── Compose plain-text brief (Telegram-friendly: no md tables/headers) ─
    md = []
    model_name = today_row.iloc[0].get('model', 'P2') if 'model' in today_row.columns else 'P2'
    md.append(f"📊 KOSPI 200 일간 위험 브리핑")
    md.append(f"")
    md.append(f"데이터 기준일 : {brief_date.strftime('%Y-%m-%d (%a)')} 종가 (직전 영업일)")
    md.append(f"적용 대상     : 다음 1 거래일")
    md.append(f"모델          : {model_name} (v3-fast Hansen, hparam-tuned)")
    md.append("───────────────")

    # 1. 시장 진단
    sigma = today['sigma']
    nu = today['nu']
    lam = today['lam']
    mu = today['mu']
    sigma_avg_22d = recent['sigma'].mean()
    sigma_state = "낮음 (안정)" if sigma < 1.0 else ("정상" if sigma < 1.8 else ("높음" if sigma < 2.8 else "매우 높음 ⚠️"))
    lam_state = "강한 bear 편향 ⚠️" if lam < -0.3 else ("bear 편향" if lam < -0.1 else ("중립" if lam < 0.1 else "bull 편향"))
    nu_state = "fat-tail (극단치 잦음) ⚠️" if nu < 8 else ("보통" if nu < 50 else "Normal-like (얇음)")

    md.append(f"🌡️ 오늘의 시장 진단")
    md.append("")
    md.append(f"| 지표 | 값 | 상태 |")
    md.append(f"| 변동성 (σ) | {sigma:.2f}% | {sigma_state} |")
    md.append(f"| 비대칭성 (λ) | {lam:+.3f} | {lam_state} |")
    md.append(f"| 꼬리 두께 (ν) | {nu:.1f} | {nu_state} |")
    md.append(f"| 평균 예측 (μ) | {mu:+.3f}% | — |")
    md.append("")
    md.append(f"한 줄 진단: {sigma_state} · {lam_state} · 꼬리 {nu_state}")
    md.append("───────────────")

    # 2. 위험 한도 + 폭락 확률
    md.append(f"🚨 오늘의 위험 한도")
    md.append("")
    md.append(f"| 한도 | 값 | 의미 |")
    md.append(f"| VaR 5% | {today['var_05']:+.2f}% | 이보다 더 떨어질 확률 5% |")
    md.append(f"| VaR 1% | {today['var_01']:+.2f}% | 이보다 더 떨어질 확률 1% |")
    md.append(f"| VaR 0.5% | {today['var_005']:+.2f}% | 0.5% 극단 영역 |")
    md.append(f"| ES 5% | {today['es_05']:+.2f}% | 5% 영역 발생 시 평균 손실 |")
    md.append("")
    md.append(f"💥 폭락 확률")
    md.append("")
    p5p = today['p_minus_5pct'] * 100
    p7p = today['p_minus_7pct'] * 100
    p10p = today['p_minus_10pct'] * 100
    f5 = 1/today['p_minus_5pct'] if today['p_minus_5pct'] > 0 else 9999
    f7 = 1/today['p_minus_7pct'] if today['p_minus_7pct'] > 0 else 9999
    f10 = 1/today['p_minus_10pct'] if today['p_minus_10pct'] > 0 else 9999
    md.append(f"| 폭락 | 확률 | 빈도 환산 |")
    md.append(f"| P(-5% 이상) | {p5p:.2f}% | {f5:.0f}일에 1번 |")
    md.append(f"| P(-7% 이상) | {p7p:.2f}% | {f7:.0f}일에 1번 |")
    md.append(f"| P(-10% 이상) | {p10p:.3f}% | {f10:.0f}일에 1번 |")
    md.append("───────────────")

    # 3. 직전 forecast 검증
    if prev is not None and pd.notna(prev.get('y_actual', float('nan'))) and abs(prev.get('y_actual', 0)) > 1e-8:
        actual = prev['y_actual']
        var05_pred = prev['var_05']
        pit_pred = prev.get('pit', float('nan'))
        breach = actual < var05_pred
        forecast_date_str = last_actual_date.strftime('%Y-%m-%d (%a)') if last_actual_date is not None else 'N/A'
        actual_date = (last_actual_date + pd.Timedelta(days=1)) if last_actual_date is not None else None
        if actual_date is not None and actual_date.weekday() >= 5:
            actual_date += pd.Timedelta(days=(7 - actual_date.weekday()))
        actual_date_str = actual_date.strftime('%Y-%m-%d (%a)') if actual_date is not None else 'next day'
        md.append(f"📈 직전 forecast 검증")
        md.append(f"Forecast 날짜: {forecast_date_str} 종가 → 실현 날짜: {actual_date_str}")
        md.append("")
        md.append(f"| 항목 | 값 |")
        md.append(f"| 실제 등락률 | {actual:+.2f}% |")
        md.append(f"| 예측 VaR 5% | {var05_pred:+.2f}% |")
        md.append(f"| VaR 5% breach | {'⚠️ YES (큰 손실)' if breach else '✅ NO (한도 내)'} |")
        if pd.notna(pit_pred):
            pit_state = '꼬리 (extreme)' if pit_pred < 0.05 or pit_pred > 0.95 else ('우측' if pit_pred > 0.7 else ('좌측' if pit_pred < 0.3 else '중심'))
            md.append(f"| PIT 위치 | {pit_pred:.3f} ({pit_state}) |")
        md.append("───────────────")
    else:
        prev_with_actual = df[(df.index < yesterday_idx) & df['y_actual'].notna()]
        if len(prev_with_actual) > 0:
            last_actual = prev_with_actual.iloc[-1]
            actual = last_actual['y_actual']
            var05_pred = last_actual['var_05']
            breach = actual < var05_pred
            md.append(f"📈 가장 최근 actual ({last_actual['Date'].date()})")
            md.append("")
            md.append(f"| 항목 | 값 |")
            md.append(f"| 실제 등락률 | {actual:+.2f}% |")
            md.append(f"| 예측 VaR 5% | {var05_pred:+.2f}% |")
            md.append(f"| VaR 5% breach | {'⚠️ YES' if breach else '✅ NO'} |")
            md.append("───────────────")

    # 4. 22일 추세
    recent_with_actual = recent[recent['y_actual'].notna()]
    breach_count_22 = (recent_with_actual['y_actual'] < recent_with_actual['var_05']).sum()
    n_valid = len(recent_with_actual)
    sigma_trend = "상승" if sigma > sigma_avg_22d * 1.1 else ("하락" if sigma < sigma_avg_22d * 0.9 else "안정")
    lam_avg_22d = recent['lam'].mean()
    md.append(f"📉 최근 22 거래일 (1개월) 추세")
    md.append("")
    md.append(f"| 지표 | 22일 평균 | 오늘 | 추세 |")
    md.append(f"| σ 변동성 | {sigma_avg_22d:.2f}% | {sigma:.2f}% | {sigma_trend} |")
    md.append(f"| λ bias | {lam_avg_22d:+.3f} | {lam:+.3f} | {'심화' if lam < lam_avg_22d - 0.05 else '안정'} |")
    if n_valid > 0:
        breach_pct = breach_count_22 / n_valid * 100
        md.append(f"| VaR 5% breach | {breach_count_22}/{n_valid}일 = {breach_pct:.0f}% | — | {'정상' if breach_pct <= 10 else 'OVER ⚠️'} |")
    md.append("───────────────")

    # 5. 알림
    alerts = []
    if sigma > 2.8:
        alerts.append(f"🔴 변동성 매우 높음 (σ={sigma:.2f}%, 평소 1.3% 대비 {sigma/1.3:.1f}x) — position size 검토")
    if lam < -0.3:
        alerts.append(f"🟡 강한 bear 편향 (λ={lam:.3f}) — hedge 검토")
    if today['p_minus_10pct'] * 100 > 1.0:
        alerts.append(f"🔴 P(-10%) 비정상 활성 ({today['p_minus_10pct']*100:.2f}%) — tail risk 큼")
    if today['p_minus_5pct'] * 100 > 5.0:
        alerts.append(f"🟡 P(-5%) 높음 ({today['p_minus_5pct']*100:.2f}%) — 일반적 1% 이하")
    if n_valid > 0 and breach_count_22 / max(n_valid, 1) > 0.18:
        alerts.append(f"🟡 breach 빈도 OVER ({n_valid}일 중 {breach_count_22}회 vs 정상 1-2회)")
    if not alerts:
        alerts.append("🟢 특이사항 없음 — 정상 상태")

    md.append(f"🔔 알림")
    md.append("")
    for a in alerts:
        md.append(f"  · {a}")
    md.append("───────────────")

    # 6. 종합
    risk_level = "🟢 정상"
    if sigma > 2.0 or lam < -0.2 or today['p_minus_10pct'] * 100 > 0.5:
        risk_level = "🟡 주의"
    if sigma > 2.8 or lam < -0.3 or today['p_minus_10pct'] * 100 > 1.0:
        risk_level = "🔴 경계"

    md.append(f"🎯 종합 risk level: {risk_level}")
    md.append("")
    md.append("시각자료: dist.png (오늘 분포 + 위험선) / trend.png (22일 추세)")

    brief_md = "\n".join(md)

    # ─── Save markdown ────────────────────
    (out_dir / 'brief.md').write_text(brief_md, encoding='utf-8')

    # ─── Generate dist.png — today's distribution ───────────────────────
    fig, ax = plt.subplots(figsize=(11, 5.5))
    x = np.linspace(-12, 8, 800)
    # Use Hansen CDF differences as approx PDF
    cdf_vals = HSK.hansen_cdf(x, mu, sigma, nu, lam)
    pdf_vals = np.gradient(cdf_vals, x)
    ax.plot(x, pdf_vals, color='#2c3e50', lw=2.2, label='Today distribution forecast')
    ax.fill_between(x, 0, pdf_vals, where=(x < today['var_05']),
                    color='#e74c3c', alpha=0.30, label=f'VaR 5% region (< {today["var_05"]:+.2f}%)')
    ax.fill_between(x, 0, pdf_vals, where=(x < today['var_01']),
                    color='#c0392b', alpha=0.55, label=f'VaR 1% region (< {today["var_01"]:+.2f}%)')
    # markers
    ax.axvline(today['var_05'], color='#e74c3c', ls='--', lw=1.2)
    ax.axvline(today['var_01'], color='#c0392b', ls='--', lw=1.5)
    ax.axvline(mu, color='#27ae60', ls=':', lw=1.0, label=f'mean (mu={mu:+.3f}%)')
    if prev is not None:
        ax.axvline(prev['y_actual'], color='#3498db', ls='-', lw=1.8,
                   label=f"yesterday actual ({prev['y_actual']:+.2f}%)")
    ax.set_xlabel("다음 1일 KOSPI 등락률 (%)", fontsize=10)
    ax.set_ylabel("Probability density", fontsize=10)
    ax.set_title(f"{model_name} distribution forecast (as of {brief_date.strftime('%Y-%m-%d')})  "
                 f"sigma={sigma:.2f}%  nu={nu:.1f}  lambda={lam:+.3f}", fontsize=11)
    ax.legend(loc='upper left', fontsize=8)
    ax.set_xlim(-12, 8)
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(out_dir / 'dist.png', dpi=110)
    plt.close(fig)

    # ─── Generate trend.png — recent 22d ─────────────────
    fig, axes = plt.subplots(3, 1, figsize=(11, 8), sharex=True)
    dates = recent['Date'].values

    axes[0].plot(dates, recent['sigma'], color='#2c3e50', marker='o', ms=4, lw=1.5)
    axes[0].axhline(1.3, color='gray', ls=':', label='보통 (1.3%)')
    axes[0].set_ylabel('sigma (변동성)', fontsize=10)
    axes[0].set_title('최근 22 거래일 시장 진단 추이', fontsize=11)
    axes[0].legend(fontsize=8); axes[0].grid(alpha=0.25)

    axes[1].plot(dates, recent['lam'], color='#c0392b', marker='o', ms=4, lw=1.5)
    axes[1].axhline(0, color='gray', ls=':', label='중립')
    axes[1].axhline(-0.3, color='red', ls=':', alpha=0.5, label='강한 bear (-0.3)')
    axes[1].set_ylabel('lambda (bear bias)', fontsize=10)
    axes[1].legend(fontsize=8); axes[1].grid(alpha=0.25)

    axes[2].plot(dates, recent['p_minus_5pct'] * 100, color='#e74c3c', marker='o', ms=4, lw=1.5, label='P(-5%)')
    axes[2].plot(dates, recent['p_minus_10pct'] * 100, color='#8b0000', marker='s', ms=4, lw=1.5, label='P(-10%)')
    axes[2].set_ylabel('폭락 확률 (%)', fontsize=10)
    axes[2].set_xlabel('Date', fontsize=10)
    axes[2].legend(fontsize=8); axes[2].grid(alpha=0.25)

    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(out_dir / 'trend.png', dpi=110)
    plt.close(fig)

    return out_dir, brief_md


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--predictions', type=str,
                        default='03_models/daily_predictions/P3_daily.parquet',
                        help='Production source (default P3). P2: 03_models/daily_predictions/P2_daily.parquet')
    parser.add_argument('--date', type=str, default=None, help='YYYY-MM-DD (default: latest)')
    parser.add_argument('--output', type=str, default='03_models/morning_brief')
    args = parser.parse_args()
    pred_path = ROOT / args.predictions
    out_root = ROOT / args.output
    out_dir, md = make_brief(pred_path, args.date, out_root)
    print(f"[brief] saved to {out_dir}")
    print(f"\n{'=' * 70}\n{md}\n{'=' * 70}")


if __name__ == "__main__":
    main()
