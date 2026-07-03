# Strategy Diagnostic Report: Defense-only base signal
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0287 | **ICIR:** 0.141 | **IC > 0 rate:** 55.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.668 | **Positive rate:** 65.8%
- **3Y Rolling Sharpe (avg):** 0.497

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00044 | **NW t-stat:** -0.290 (not significant)
- **Avg Cross-sectional R²:** 0.0752

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.05%/yr (t=0.400)  | **Adj R²:** 0.4551

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1356 (lower = more diversified)
- **Avg Period Turnover:** 5.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 51.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.21 < -0.1 & 초과CAGR -3.2%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
