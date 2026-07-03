# Strategy Diagnostic Report: 5축 Strict Vote — 4/5 이상 위기 신호일 때만 방어 (RC_11보다 엄격)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0356 | **ICIR:** 0.224 | **IC > 0 rate:** 59.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.725 | **Positive rate:** 64.9%
- **3Y Rolling Sharpe (avg):** 0.546

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00128 | **NW t-stat:** 1.059 (not significant)
- **Avg Cross-sectional R²:** 0.0670

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.51%/yr (t=0.992)  | **Adj R²:** 0.5230

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1192 (lower = more diversified)
- **Avg Period Turnover:** 6.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 5, common>50%: 11)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 47.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.11 < -0.1 & 초과CAGR -1.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 47.8% > 35% & BM상관 0.74 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.62 -> post-2017 -1.11 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
