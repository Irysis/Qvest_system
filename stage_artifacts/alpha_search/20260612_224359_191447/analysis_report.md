# Strategy Diagnostic Report: Score-Weighted 전략 앙상블 — Hurdle Score 비례 가중
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0312 | **ICIR:** 0.159 | **IC > 0 rate:** 57.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.832 | **Positive rate:** 67.6%
- **3Y Rolling Sharpe (avg):** 0.633

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00040 | **NW t-stat:** 0.295 (not significant)
- **Avg Cross-sectional R²:** 0.0703

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.10%/yr (t=0.753)  | **Adj R²:** 0.5352

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1148 (lower = more diversified)
- **Avg Period Turnover:** 8.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 58.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
