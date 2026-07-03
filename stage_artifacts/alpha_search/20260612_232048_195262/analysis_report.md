# Strategy Diagnostic Report: 팩터 수 앙상블 — 2F/4F/7F 세 전략의 score 합산
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0284 | **ICIR:** 0.181 | **IC > 0 rate:** 59.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.651 | **Positive rate:** 65.9%
- **3Y Rolling Sharpe (avg):** 0.370

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00215 | **NW t-stat:** 2.449 (significant)
- **Avg Cross-sectional R²:** 0.0842

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.55%/yr (t=0.245)  | **Adj R²:** 0.6775

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1247 (lower = more diversified)
- **Avg Period Turnover:** 16.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 62.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 62.2% > 35% & BM상관 0.85 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.60 -> post-2017 -0.55 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
