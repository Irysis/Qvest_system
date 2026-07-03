# Strategy Diagnostic Report: 계층적 팩터 — 1차 필터(Quality Gate) → 2차 정렬(FM Composite) → 3차 가중(NCO)
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0343 | **ICIR:** 0.222 | **IC > 0 rate:** 58.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.663 | **Positive rate:** 70.0%
- **3Y Rolling Sharpe (avg):** 0.499

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00153 | **NW t-stat:** 1.362 (not significant)
- **Avg Cross-sectional R²:** 0.0649

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.45%/yr (t=1.047)  | **Adj R²:** 0.4524

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1468 (lower = more diversified)
- **Avg Period Turnover:** 6.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 45.3% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.20 < -0.1 & 초과CAGR -2.9%p < 0 — KR에서 팩터 방향 역작동 의심
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 45.3% > 35% & BM상관 0.71 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
