# Strategy Diagnostic Report: 5축 연속 국면 — MRS+Disp+Vol+DD+Breadth 연속 z-score 합산
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0248 | **ICIR:** 0.119 | **IC > 0 rate:** 58.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.824 | **Positive rate:** 69.3%
- **3Y Rolling Sharpe (avg):** 0.533

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00267 | **NW t-stat:** 1.761 (not significant)
- **Avg Cross-sectional R²:** 0.0951

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.05%/yr (t=1.561)  | **Adj R²:** 0.6365

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1095 (lower = more diversified)
- **Avg Period Turnover:** 16.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 57.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 57.2% > 35% & BM상관 0.83 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.68 -> post-2017 -0.32 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
