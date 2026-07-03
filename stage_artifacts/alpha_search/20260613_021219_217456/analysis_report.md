# Strategy Diagnostic Report: 국면 속도 적응형 Overlay — MRS 변화 속도에 따라 DD/VT 파라미터 동적 조절
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0404 | **ICIR:** 0.256 | **IC > 0 rate:** 63.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.888 | **Positive rate:** 71.3%
- **3Y Rolling Sharpe (avg):** 0.747

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00211 | **NW t-stat:** 1.660 (not significant)
- **Avg Cross-sectional R²:** 0.0648

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.44%/yr (t=2.040) (significant) | **Adj R²:** 0.4401

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1271 (lower = more diversified)
- **Avg Period Turnover:** 10.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.19 < -0.1 & 초과CAGR -3.0%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -3.0%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
