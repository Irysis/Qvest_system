# Strategy Diagnostic Report: Defense + quality base signal
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0342 | **ICIR:** 0.202 | **IC > 0 rate:** 59.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.741 | **Positive rate:** 66.9%
- **3Y Rolling Sharpe (avg):** 0.587

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00084 | **NW t-stat:** 0.628 (not significant)
- **Avg Cross-sectional R²:** 0.0694

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.18%/yr (t=1.214)  | **Adj R²:** 0.4341

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1438 (lower = more diversified)
- **Avg Period Turnover:** 5.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 5, common>50%: 17)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 47.9% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 47.9% > 35% & BM상관 0.71 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.61 -> post-2017 -1.01 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
