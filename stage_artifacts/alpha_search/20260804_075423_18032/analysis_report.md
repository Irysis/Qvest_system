# Strategy Diagnostic Report: CV_Vol_liquidity_uncertainty
Generated: 2026-08-04

## Factor Signal Quality
- **IC Mean:** 0.0200 | **ICIR:** 0.199 | **IC > 0 rate:** 60.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.322 | **Positive rate:** 52.5%
- **3Y Rolling Sharpe (avg):** 0.023

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00042 | **NW t-stat:** 0.583 (not significant)
- **Avg Cross-sectional R²:** 0.0556

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.88%/yr (t=-1.659)  | **Adj R²:** 0.6968

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0910 (lower = more diversified)
- **Avg Period Turnover:** 69.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5301, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 64.4% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
