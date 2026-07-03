# Strategy Diagnostic Report: FM+역FM 블렌드 — 단기(3m) 역FM + 장기(12m) FM 결합
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0420 | **ICIR:** 0.265 | **IC > 0 rate:** 55.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.581 | **Positive rate:** 65.5%
- **3Y Rolling Sharpe (avg):** 0.330

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00256 | **NW t-stat:** 2.422 (significant)
- **Avg Cross-sectional R²:** 0.0861

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.72%/yr (t=-0.325)  | **Adj R²:** 0.6903

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0890 (lower = more diversified)
- **Avg Period Turnover:** 24.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 61.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 61.0% > 35% & BM상관 0.84 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
