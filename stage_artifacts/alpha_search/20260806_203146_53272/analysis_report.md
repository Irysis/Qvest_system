# Strategy Diagnostic Report: Markov_PredVolRank
Generated: 2026-08-06

## Factor Signal Quality
- **IC Mean:** 0.0244 | **ICIR:** 0.142 | **IC > 0 rate:** 56.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.286 | **Positive rate:** 58.6%
- **3Y Rolling Sharpe (avg):** 0.065

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00026 | **NW t-stat:** -0.208 (not significant)
- **Avg Cross-sectional R²:** 0.0658

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.74%/yr (t=-1.489)  | **Adj R²:** 0.5440

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1207 (lower = more diversified)
- **Avg Period Turnover:** 41.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5303, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
