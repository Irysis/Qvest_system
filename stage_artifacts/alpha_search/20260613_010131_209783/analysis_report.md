# Strategy Diagnostic Report: 팩터모멘텀 IC가중 — trailing 3m IC rank로 팩터 비중 조절
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0401 | **ICIR:** 0.266 | **IC > 0 rate:** 61.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.884 | **Positive rate:** 67.4%
- **3Y Rolling Sharpe (avg):** 0.672

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00182 | **NW t-stat:** 1.540 (not significant)
- **Avg Cross-sectional R²:** 0.0651

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.33%/yr (t=1.616)  | **Adj R²:** 0.5575

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1228 (lower = more diversified)
- **Avg Period Turnover:** 9.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 8)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 51.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 51.1% > 35% & BM상관 0.77 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.91 -> post-2017 -0.99 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
