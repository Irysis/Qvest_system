# Strategy Diagnostic Report: FQ100_ipm_sector_neutral
Generated: 2026-08-09

## Factor Signal Quality
- **IC Mean:** 0.0127 | **ICIR:** 0.138 | **IC > 0 rate:** 58.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.677 | **Positive rate:** 66.5%
- **3Y Rolling Sharpe (avg):** 0.412

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00057 | **NW t-stat:** -0.713 (not significant)
- **Avg Cross-sectional R²:** 0.0577

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.03%/yr (t=0.756)  | **Adj R²:** 0.6118

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0900 (lower = more diversified)
- **Avg Period Turnover:** 4.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 9)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5305, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 60.3% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 60.3% > 35% & BM상관 0.81 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
