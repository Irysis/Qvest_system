# Strategy Diagnostic Report: FQ094_RetAutoCorr_B
Generated: 2026-08-08

## Factor Signal Quality
- **IC Mean:** -0.0043 | **ICIR:** -0.051 | **IC > 0 rate:** 47.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.071 | **Positive rate:** 39.4%
- **3Y Rolling Sharpe (avg):** -0.233

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00076 | **NW t-stat:** -1.486 (not significant)
- **Avg Cross-sectional R²:** 0.0565

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -11.26%/yr (t=-3.984) (significant) | **Adj R²:** 0.6095

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2223 (lower = more diversified)
- **Avg Period Turnover:** 91.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 66.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5305, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 86.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.82 < -0.1 & 초과CAGR -13.7%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 86.6% > 35% & BM상관 0.73 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [x] FMT-05: Turnover Toxicity — AUTO: 연환산 회전율 3525% > 1,100% — 15bps 비용이 알파 소진
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
