# Strategy Diagnostic Report: VoltRank_MC
Generated: 2026-08-03

## Factor Signal Quality
- **IC Mean:** 0.0237 | **ICIR:** 0.141 | **IC > 0 rate:** 56.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.266 | **Positive rate:** 57.3%
- **3Y Rolling Sharpe (avg):** 0.064

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00012 | **NW t-stat:** 0.085 (not significant)
- **Avg Cross-sectional R²:** 0.0661

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.98%/yr (t=-1.797)  | **Adj R²:** 0.5700

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1120 (lower = more diversified)
- **Avg Period Turnover:** 40.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.49 < -0.1 & 초과CAGR -8.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
