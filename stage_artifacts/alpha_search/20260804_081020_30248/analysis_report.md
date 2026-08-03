# Strategy Diagnostic Report: STR_AS_FX_INTENSITY
Generated: 2026-08-04

## Factor Signal Quality
- **IC Mean:** 0.0236 | **ICIR:** 0.177 | **IC > 0 rate:** 56.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.370 | **Positive rate:** 54.0%
- **3Y Rolling Sharpe (avg):** 0.126

## Stress Periods
- **Outperform rate vs BM:** 0.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00165 | **NW t-stat:** 0.933 (not significant)
- **Avg Cross-sectional R²:** 0.0685

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.27%/yr (t=-0.334)  | **Adj R²:** 0.6242

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0859 (lower = more diversified)
- **Avg Period Turnover:** 1.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** MEDIUM (persistent>75%: 11, common>50%: 20)
- **Sample Aligned:** YES [ALIGNED] (overlap: 2512, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 60.5% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
