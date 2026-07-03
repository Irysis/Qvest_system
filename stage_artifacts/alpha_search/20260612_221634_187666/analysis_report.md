# Strategy Diagnostic Report: 5-Sleeve Dispersion CondWeight: 분산도 기반 슬리브 배분 동적 조절
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0444 | **ICIR:** 0.244 | **IC > 0 rate:** 59.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.706 | **Positive rate:** 65.6%
- **3Y Rolling Sharpe (avg):** 0.432

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00389 | **NW t-stat:** 2.507 (significant)
- **Avg Cross-sectional R²:** 0.0802

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.25%/yr (t=0.985)  | **Adj R²:** 0.4659

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2521 (lower = more diversified)
- **Avg Period Turnover:** 21.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 16.7%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 73.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.76 -> post-2017 -0.57 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
