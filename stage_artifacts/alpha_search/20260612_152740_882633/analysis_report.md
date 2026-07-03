# Strategy Diagnostic Report: Quality + reversal base signal from overlay spec
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0420 | **ICIR:** 0.424 | **IC > 0 rate:** 68.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.701 | **Positive rate:** 70.7%
- **3Y Rolling Sharpe (avg):** 0.474

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00236 | **NW t-stat:** 2.516 (significant)
- **Avg Cross-sectional R²:** 0.0583

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.98%/yr (t=0.756)  | **Adj R²:** 0.6908

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0995 (lower = more diversified)
- **Avg Period Turnover:** 21.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 52.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 52.0% > 35% & BM상관 0.83 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.96 -> post-2017 -0.83 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
