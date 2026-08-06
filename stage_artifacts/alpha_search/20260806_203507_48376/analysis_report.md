# Strategy Diagnostic Report: VolRankReverse_FQ092
Generated: 2026-08-06

## Factor Signal Quality
- **IC Mean:** -0.0159 | **ICIR:** -0.141 | **IC > 0 rate:** 42.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.636 | **Positive rate:** 63.2%
- **3Y Rolling Sharpe (avg):** 0.486

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00012 | **NW t-stat:** 0.179 (not significant)
- **Avg Cross-sectional R²:** 0.0560

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.64%/yr (t=0.201)  | **Adj R²:** 0.5757

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1401 (lower = more diversified)
- **Avg Period Turnover:** 14.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5303, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 60.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) -0.06 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
