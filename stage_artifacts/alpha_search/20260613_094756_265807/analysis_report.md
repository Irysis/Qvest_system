# Strategy Diagnostic Report: VAE 잠재 팩터 — Variational Autoencoder로 잠재 팩터 추출 후 scoring
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0196 | **ICIR:** 0.117 | **IC > 0 rate:** 51.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.422 | **Positive rate:** 62.7%
- **3Y Rolling Sharpe (avg):** 0.147

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00116 | **NW t-stat:** -0.863 (not significant)
- **Avg Cross-sectional R²:** 0.0664

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -2.15%/yr (t=-0.969)  | **Adj R²:** 0.5860

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0982 (lower = more diversified)
- **Avg Period Turnover:** 24.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 56.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.49 < -0.1 & 초과CAGR -6.6%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 56.2% > 35% & BM상관 0.77 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
