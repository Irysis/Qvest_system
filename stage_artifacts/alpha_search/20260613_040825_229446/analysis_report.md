# Strategy Diagnostic Report: [진단] 국면 시그널 상호작용 — 2축 쌍별 AND vs OR 비교
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0268 | **ICIR:** 0.131 | **IC > 0 rate:** 55.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.473 | **Positive rate:** 61.6%
- **3Y Rolling Sharpe (avg):** 0.313

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00080 | **NW t-stat:** -0.499 (not significant)
- **Avg Cross-sectional R²:** 0.0758

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.96%/yr (t=0.444)  | **Adj R²:** 0.2977

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1357 (lower = more diversified)
- **Avg Period Turnover:** 5.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.36 < -0.1 & 초과CAGR -6.3%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -6.3%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
