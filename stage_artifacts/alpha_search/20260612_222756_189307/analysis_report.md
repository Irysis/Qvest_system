# Strategy Diagnostic Report: Composite Quality — GP+PiotroskiF+DeltaROE+(-Accruals) + BRK overlay
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0403 | **ICIR:** 0.264 | **IC > 0 rate:** 61.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.654 | **Positive rate:** 65.3%
- **3Y Rolling Sharpe (avg):** 0.467

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00188 | **NW t-stat:** 1.647 (not significant)
- **Avg Cross-sectional R²:** 0.0647

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.71%/yr (t=0.644)  | **Adj R²:** 0.5364

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1369 (lower = more diversified)
- **Avg Period Turnover:** 8.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 9)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 48.4% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.13 < -0.1 & 초과CAGR -1.7%p < 0 — KR에서 팩터 방향 역작동 의심
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade F — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 48.4% > 35% & BM상관 0.77 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.54 -> post-2017 -1.10 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
