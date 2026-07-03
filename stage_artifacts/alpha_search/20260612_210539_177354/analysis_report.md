# Strategy Diagnostic Report: STR_1036 Sleeve-Level VT 완전 제거 (4중→2중 오버레이)
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0458 | **ICIR:** 0.266 | **IC > 0 rate:** 64.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.767 | **Positive rate:** 69.7%
- **3Y Rolling Sharpe (avg):** 0.592

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00301 | **NW t-stat:** 2.201 (significant)
- **Avg Cross-sectional R²:** 0.0801

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.92%/yr (t=0.804)  | **Adj R²:** 0.5527

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1006 (lower = more diversified)
- **Avg Period Turnover:** 14.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 48.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.18 < -0.1 & 초과CAGR -2.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 48.1% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
