# Strategy Diagnostic Report: STR_AS_FX_HEDGING_PROXY
Generated: 2026-08-04

## Factor Signal Quality
- **IC Mean:** -0.0078 | **ICIR:** -0.069 | **IC > 0 rate:** 48.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.259 | **Positive rate:** 55.9%
- **3Y Rolling Sharpe (avg):** -0.001

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00014 | **NW t-stat:** -0.067 (not significant)
- **Avg Cross-sectional R²:** 0.0815

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.41%/yr (t=-0.652)  | **Adj R²:** 0.5092

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1404 (lower = more diversified)
- **Avg Period Turnover:** 3.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 8)
- **Sample Aligned:** YES [ALIGNED] (overlap: 2532, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
