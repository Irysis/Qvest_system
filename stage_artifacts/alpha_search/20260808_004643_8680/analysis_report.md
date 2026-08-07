# Strategy Diagnostic Report: FQ110_JumpShare_A
Generated: 2026-08-08

## Factor Signal Quality
- **IC Mean:** -0.0278 | **ICIR:** -0.248 | **IC > 0 rate:** 37.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.642 | **Positive rate:** 63.6%
- **3Y Rolling Sharpe (avg):** 0.473

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00088 | **NW t-stat:** -0.972 (not significant)
- **Avg Cross-sectional R²:** 0.0576

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.83%/yr (t=0.487)  | **Adj R²:** 0.4898

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1374 (lower = more diversified)
- **Avg Period Turnover:** 12.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5305, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.5% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
