# Strategy Diagnostic Report: STR_1049 — STR_1036에 vol_target=0.13 overlay 추가. 현재 ann_vol 15.75%를 13%로 억제. SR 1.284→1.5 기대.
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0420 | **ICIR:** 0.253 | **IC > 0 rate:** 61.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.796 | **Positive rate:** 72.4%
- **3Y Rolling Sharpe (avg):** 0.581

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00165 | **NW t-stat:** 1.234 (not significant)
- **Avg Cross-sectional R²:** 0.0667

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.55%/yr (t=1.405)  | **Adj R²:** 0.5219

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1591 (lower = more diversified)
- **Avg Period Turnover:** 12.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 50.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 50.6% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.51 -> post-2017 -0.91 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
