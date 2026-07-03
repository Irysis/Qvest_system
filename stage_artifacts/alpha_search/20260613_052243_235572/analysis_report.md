# Strategy Diagnostic Report: Max Sharpe 팩터 포트폴리오 — 7팩터 Tangency Portfolio 가중
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0241 | **ICIR:** 0.158 | **IC > 0 rate:** 57.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.472 | **Positive rate:** 56.7%
- **3Y Rolling Sharpe (avg):** 0.259

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00117 | **NW t-stat:** 1.052 (not significant)
- **Avg Cross-sectional R²:** 0.0633

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.13%/yr (t=-0.047)  | **Adj R²:** 0.4564

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1569 (lower = more diversified)
- **Avg Period Turnover:** 10.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 57.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.35 < -0.1 & 초과CAGR -5.2%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 57.1% > 35% & BM상관 0.71 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
