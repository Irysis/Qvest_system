# Strategy Diagnostic Report: Piotroski F-Score(STR_1099 Grade B 50.6) + BRK overlay → Grade A 확정
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0309 | **ICIR:** 0.231 | **IC > 0 rate:** 61.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.495 | **Positive rate:** 59.6%
- **3Y Rolling Sharpe (avg):** -0.155

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00226 | **NW t-stat:** 1.645 (not significant)
- **Avg Cross-sectional R²:** 0.0719

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.83%/yr (t=-0.316)  | **Adj R²:** 0.1627

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0925 (lower = more diversified)
- **Avg Period Turnover:** 12.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 50.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.50 < -0.1 & 초과CAGR -9.3%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
