# Strategy Diagnostic Report: ARFIMA_TSMOM
Generated: 2026-08-21

## Factor Signal Quality
- **IC Mean:** -0.0033 | **ICIR:** -0.034 | **IC > 0 rate:** 48.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.827 | **Positive rate:** 71.1%
- **3Y Rolling Sharpe (avg):** 0.545

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00028 | **NW t-stat:** -0.363 (not significant)
- **Avg Cross-sectional R²:** 0.0558

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.10%/yr (t=1.890)  | **Adj R²:** 0.5303

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1173 (lower = more diversified)
- **Avg Period Turnover:** 18.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5313, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 64.3% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 64.3% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.73 -> post-2017 -0.34 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
