# Strategy Diagnostic Report: STR_AS_comovement_reconfiguration_rate
Generated: 2026-08-23

## Factor Signal Quality
- **IC Mean:** -0.0281 | **ICIR:** -0.211 | **IC > 0 rate:** 41.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.275 | **Positive rate:** 55.2%
- **3Y Rolling Sharpe (avg):** 0.146

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00164 | **NW t-stat:** -1.491 (not significant)
- **Avg Cross-sectional R²:** 0.0616

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -4.95%/yr (t=-1.095)  | **Adj R²:** 0.4279

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1598 (lower = more diversified)
- **Avg Period Turnover:** 11.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5314, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 76.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.41 < -0.1 & 초과CAGR -9.6%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
