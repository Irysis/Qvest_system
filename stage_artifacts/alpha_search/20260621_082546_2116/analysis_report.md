# Strategy Diagnostic Report: ReSGA_SizeTail_POS
Generated: 2026-06-21

## Factor Signal Quality
- **IC Mean:** 0.0184 | **ICIR:** 0.117 | **IC > 0 rate:** 55.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.294 | **Positive rate:** 53.0%
- **3Y Rolling Sharpe (avg):** 0.082

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00193 | **NW t-stat:** -0.621 (not significant)
- **Avg Cross-sectional R<U+00B2>:** 0.0608

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.24%/yr (t=-1.955)  | **Adj R<U+00B2>:** 0.8129

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0920 (lower = more diversified)
- **Avg Period Turnover:** 1.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 8, common>50%: 17)
- **Sample Aligned:** YES (overlap: 5272, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 52.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.72 < -0.1 & 초과CAGR -6.0%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 52.7% > 35% & BM상관 0.93 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
