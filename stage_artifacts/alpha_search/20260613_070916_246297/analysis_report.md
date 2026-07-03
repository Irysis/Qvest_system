# Strategy Diagnostic Report: 주간 리밸런싱 — 위기 국면에서만 주간 리밸런싱 (정상 시 월간)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0178 | **ICIR:** 0.133 | **IC > 0 rate:** 56.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.176 | **Positive rate:** 53.4%
- **3Y Rolling Sharpe (avg):** -0.053

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00142 | **NW t-stat:** -1.370 (not significant)
- **Avg Cross-sectional R²:** 0.0606

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -5.79%/yr (t=-2.524) (significant) | **Adj R²:** 0.6174

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0930 (lower = more diversified)
- **Avg Period Turnover:** 40.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 67.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.77 < -0.1 & 초과CAGR -9.4%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 67.0% > 35% & BM상관 0.81 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -9.4%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
