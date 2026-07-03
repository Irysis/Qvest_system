# Strategy Diagnostic Report: [진단] FM Lookback Sweep — 1m/3m/6m/9m/12m × 3 국면 = 15건
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0243 | **ICIR:** 0.162 | **IC > 0 rate:** 57.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.540 | **Positive rate:** 59.6%
- **3Y Rolling Sharpe (avg):** -0.150

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00108 | **NW t-stat:** 1.276 (not significant)
- **Avg Cross-sectional R²:** 0.0798

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.79%/yr (t=-0.295)  | **Adj R²:** 0.1633

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0865 (lower = more diversified)
- **Avg Period Turnover:** 13.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 51.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.49 < -0.1 & 초과CAGR -9.2%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -9.2%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
