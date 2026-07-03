# Strategy Diagnostic Report: STR_1036 Short DD Brake 완전 제거 (이중 헤지 해소)
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0420 | **ICIR:** 0.253 | **IC > 0 rate:** 61.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.701 | **Positive rate:** 69.7%
- **3Y Rolling Sharpe (avg):** 0.373

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00165 | **NW t-stat:** 1.234 (not significant)
- **Avg Cross-sectional R²:** 0.0667

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.39%/yr (t=0.402)  | **Adj R²:** 0.2971

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1591 (lower = more diversified)
- **Avg Period Turnover:** 12.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.3% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.27 < -0.1 & 초과CAGR -4.6%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.00 <= 0.3 — 후반부 알파 붕괴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
