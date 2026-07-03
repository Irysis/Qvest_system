# Strategy Diagnostic Report: 시장 상태 3변수 — Return+Vol+Breadth 동시 참조 팩터 배분
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0401 | **ICIR:** 0.266 | **IC > 0 rate:** 61.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.948 | **Positive rate:** 64.8%
- **3Y Rolling Sharpe (avg):** 0.102

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00182 | **NW t-stat:** 1.540 (not significant)
- **Avg Cross-sectional R²:** 0.0651

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.99%/yr (t=0.356)  | **Adj R²:** 0.1515

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1228 (lower = more diversified)
- **Avg Period Turnover:** 9.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 8)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.40 < -0.1 & 초과CAGR -7.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.00 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
