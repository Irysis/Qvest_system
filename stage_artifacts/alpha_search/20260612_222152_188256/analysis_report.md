# Strategy Diagnostic Report: Stability-Filtered Ensemble — OOS retention 0.7+ 전략만 앙상블
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0308 | **ICIR:** 0.270 | **IC > 0 rate:** 59.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.717 | **Positive rate:** 68.8%
- **3Y Rolling Sharpe (avg):** 0.498

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00181 | **NW t-stat:** 1.973 (significant)
- **Avg Cross-sectional R²:** 0.0590

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.84%/yr (t=1.097)  | **Adj R²:** 0.6120

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1257 (lower = more diversified)
- **Avg Period Turnover:** 7.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 9)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 46.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 46.6% > 35% & BM상관 0.79 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.65 -> post-2017 -0.79 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
