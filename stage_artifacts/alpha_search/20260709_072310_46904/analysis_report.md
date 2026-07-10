# Strategy Diagnostic Report: Chen-Welch 2026 Profitability Survivors
Generated: 2026-07-09

## Factor Signal Quality
- **IC Mean:** 0.0115 | **ICIR:** 0.083 | **IC > 0 rate:** 55.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.561 | **Positive rate:** 64.2%
- **3Y Rolling Sharpe (avg):** 0.403

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00030 | **NW t-stat:** 0.276 (not significant)
- **Avg Cross-sectional R²:** 0.0608

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.33%/yr (t=0.773)  | **Adj R²:** 0.4624

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1738 (lower = more diversified)
- **Avg Period Turnover:** 5.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 12)
- **Sample Aligned:** YES (overlap: 5261, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 52.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.11 < -0.1 & 초과CAGR -1.8%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.11 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
