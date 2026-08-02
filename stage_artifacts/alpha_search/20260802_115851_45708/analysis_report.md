# Strategy Diagnostic Report: FQ081_DuPont_IndRel_Cond
Generated: 2026-08-02

## Factor Signal Quality
- **IC Mean:** 0.0149 | **ICIR:** 0.185 | **IC > 0 rate:** 58.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.694 | **Positive rate:** 69.7%
- **3Y Rolling Sharpe (avg):** 0.426

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00027 | **NW t-stat:** 0.382 (not significant)
- **Avg Cross-sectional R²:** 0.0582

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.25%/yr (t=1.335)  | **Adj R²:** 0.5873

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1053 (lower = more diversified)
- **Avg Period Turnover:** 9.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5241, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 59.0% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
