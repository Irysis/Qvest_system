# Strategy Diagnostic Report: Defense + IndMom 블렌드 — 방어 + 업종추세 2축
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0327 | **ICIR:** 0.183 | **IC > 0 rate:** 62.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.684 | **Positive rate:** 66.6%
- **3Y Rolling Sharpe (avg):** 0.439

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00060 | **NW t-stat:** 0.398 (not significant)
- **Avg Cross-sectional R²:** 0.0692

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.18%/yr (t=1.087)  | **Adj R²:** 0.5125

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1901 (lower = more diversified)
- **Avg Period Turnover:** 10.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 54.2% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
