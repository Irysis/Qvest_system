# Strategy Diagnostic Report: N=20 Crisis — 위기 시 종목수 20으로 축소 + Defense Heavy
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0356 | **ICIR:** 0.224 | **IC > 0 rate:** 59.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.491 | **Positive rate:** 58.7%
- **3Y Rolling Sharpe (avg):** 0.382

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00128 | **NW t-stat:** 1.059 (not significant)
- **Avg Cross-sectional R²:** 0.0670

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.41%/yr (t=1.186)  | **Adj R²:** 0.2605

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1359 (lower = more diversified)
- **Avg Period Turnover:** 7.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 7)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.19 < -0.1 & 초과CAGR -3.3%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) -0.72 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
