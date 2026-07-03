# Strategy Diagnostic Report: STR_1036 DD Brake 완화: DD_med 4%→8%, DD_short 2%→5%
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0458 | **ICIR:** 0.266 | **IC > 0 rate:** 64.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.703 | **Positive rate:** 63.8%
- **3Y Rolling Sharpe (avg):** 0.318

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00301 | **NW t-stat:** 2.201 (significant)
- **Avg Cross-sectional R²:** 0.0801

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.13%/yr (t=0.527)  | **Adj R²:** 0.0988

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1006 (lower = more diversified)
- **Avg Period Turnover:** 14.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.42 < -0.1 & 초과CAGR -8.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.00 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
