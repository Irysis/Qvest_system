# Strategy Diagnostic Report: [진단+전략] 팩터 Decay 분석 → 팩터별 최적 리밸런싱 주기 멀티팩터
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0478 | **ICIR:** 0.320 | **IC > 0 rate:** 65.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.896 | **Positive rate:** 67.8%
- **3Y Rolling Sharpe (avg):** 0.683

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00254 | **NW t-stat:** 2.098 (significant)
- **Avg Cross-sectional R²:** 0.0657

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.24%/yr (t=1.481)  | **Adj R²:** 0.5501

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1288 (lower = more diversified)
- **Avg Period Turnover:** 11.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 8)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 51.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 51.6% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.91 -> post-2017 -0.99 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
