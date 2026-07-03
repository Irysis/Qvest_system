# Strategy Diagnostic Report: Contrarian Factor Timing — 12m 최악 팩터에 가중 (장기 역전)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0252 | **ICIR:** 0.134 | **IC > 0 rate:** 57.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.653 | **Positive rate:** 66.1%
- **3Y Rolling Sharpe (avg):** 0.320

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00265 | **NW t-stat:** 2.105 (significant)
- **Avg Cross-sectional R²:** 0.0874

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.38%/yr (t=0.522)  | **Adj R²:** 0.6714

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1195 (lower = more diversified)
- **Avg Period Turnover:** 19.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 61.4% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 61.4% > 35% & BM상관 0.84 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
