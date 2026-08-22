# Strategy Diagnostic Report: MacroBetaMom_v3_precomputed
Generated: 2026-08-22

## Factor Signal Quality
- **IC Mean:** -0.0025 | **ICIR:** -0.022 | **IC > 0 rate:** 49.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.295 | **Positive rate:** 56.4%
- **3Y Rolling Sharpe (avg):** 0.079

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00021 | **NW t-stat:** -0.271 (not significant)
- **Avg Cross-sectional R²:** 0.0585

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.71%/yr (t=-0.845)  | **Adj R²:** 0.4593

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1301 (lower = more diversified)
- **Avg Period Turnover:** 69.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5314, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 70.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.37 < -0.1 & 초과CAGR -7.6%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
