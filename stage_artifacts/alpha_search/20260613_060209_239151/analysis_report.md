# Strategy Diagnostic Report: 적응형 종목수 — 시그널 강도에 따라 N=15~30 동적 조절
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0268 | **ICIR:** 0.131 | **IC > 0 rate:** 55.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.457 | **Positive rate:** 60.9%
- **3Y Rolling Sharpe (avg):** 0.352

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00080 | **NW t-stat:** -0.499 (not significant)
- **Avg Cross-sectional R²:** 0.0758

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.49%/yr (t=0.200)  | **Adj R²:** 0.3774

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1955 (lower = more diversified)
- **Avg Period Turnover:** 7.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 13.3%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.5% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.33 < -0.1 & 초과CAGR -5.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
