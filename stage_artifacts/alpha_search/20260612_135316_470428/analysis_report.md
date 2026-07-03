# Strategy Diagnostic Report: Asset Growth
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0069 | **ICIR:** 0.069 | **IC > 0 rate:** 54.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.496 | **Positive rate:** 58.2%
- **3Y Rolling Sharpe (avg):** 0.220

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00030 | **NW t-stat:** 0.380 (not significant)
- **Avg Cross-sectional R²:** 0.0557

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.59%/yr (t=-0.133)  | **Adj R²:** 0.4497

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1479 (lower = more diversified)
- **Avg Period Turnover:** 16.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 77.9% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.25 < -0.1 & 초과CAGR -4.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 77.9% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.53 -> post-2017 -0.84 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
