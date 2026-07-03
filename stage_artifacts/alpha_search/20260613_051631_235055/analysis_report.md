# Strategy Diagnostic Report: Walk-Forward CV 블렌드 — 3개 train window 예측 평균으로 가중 결정
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0404 | **ICIR:** 0.256 | **IC > 0 rate:** 63.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.912 | **Positive rate:** 69.4%
- **3Y Rolling Sharpe (avg):** 0.661

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00211 | **NW t-stat:** 1.660 (not significant)
- **Avg Cross-sectional R²:** 0.0648

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.12%/yr (t=1.587)  | **Adj R²:** 0.5209

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1271 (lower = more diversified)
- **Avg Period Turnover:** 10.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 49.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 49.2% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.95 -> post-2017 -0.95 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
