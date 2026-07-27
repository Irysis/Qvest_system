# Strategy Diagnostic Report: RESID_INFO_VOL
Generated: 2026-07-27

## Factor Signal Quality
- **IC Mean:** 0.0024 | **ICIR:** 0.026 | **IC > 0 rate:** 50.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.531 | **Positive rate:** 63.7%
- **3Y Rolling Sharpe (avg):** 0.348

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00027 | **NW t-stat:** 0.385 (not significant)
- **Avg Cross-sectional R²:** 0.0555

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.80%/yr (t=0.213)  | **Adj R²:** 0.5189

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1147 (lower = more diversified)
- **Avg Period Turnover:** 85.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5296, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 62.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.15 < -0.1 & 초과CAGR -2.7%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 62.1% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
