# Strategy Diagnostic Report: Insider + Consensus 블렌드 — DART 내부자 + 애널리스트 결합
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0404 | **ICIR:** 0.256 | **IC > 0 rate:** 63.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.724 | **Positive rate:** 65.8%
- **3Y Rolling Sharpe (avg):** 0.488

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00211 | **NW t-stat:** 1.660 (not significant)
- **Avg Cross-sectional R²:** 0.0648

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.25%/yr (t=1.704)  | **Adj R²:** 0.3319

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1271 (lower = more diversified)
- **Avg Period Turnover:** 10.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.63 -> post-2017 -0.98 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
