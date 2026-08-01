# Strategy Diagnostic Report: SPEC_MASS_LOWVOL
Generated: 2026-08-02

## Factor Signal Quality
- **IC Mean:** 0.0081 | **ICIR:** 0.077 | **IC > 0 rate:** 54.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.517 | **Positive rate:** 63.1%
- **3Y Rolling Sharpe (avg):** 0.262

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00049 | **NW t-stat:** 0.794 (not significant)
- **Avg Cross-sectional R²:** 0.0678

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.87%/yr (t=-0.388)  | **Adj R²:** 0.6196

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0992 (lower = more diversified)
- **Avg Period Turnover:** 64.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 57.5% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.25 < -0.1 & 초과CAGR -3.9%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 57.5% > 35% & BM상관 0.74 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
