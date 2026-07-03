# Strategy Diagnostic Report: Fundamental Momentum (Delta_* 시그널) — 재무지표 변화율 기반 모멘텀 (DART 이미 계산)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0324 | **ICIR:** 0.204 | **IC > 0 rate:** 62.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.870 | **Positive rate:** 68.8%
- **3Y Rolling Sharpe (avg):** 0.583

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00350 | **NW t-stat:** 2.961 (significant)
- **Avg Cross-sectional R²:** 0.0614

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.26%/yr (t=2.020) (significant) | **Adj R²:** 0.5187

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1571 (lower = more diversified)
- **Avg Period Turnover:** 10.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 56.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 56.0% > 35% & BM상관 0.78 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.92 -> post-2017 -0.30 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
