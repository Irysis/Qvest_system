# Strategy Diagnostic Report: STR_1033/1107/1108/1109 Phase 4 regime_engine_daily.R 교체 (C11 필수 수정)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0406 | **ICIR:** 0.244 | **IC > 0 rate:** 63.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.315 | **Positive rate:** 49.9%
- **3Y Rolling Sharpe (avg):** 0.032

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00164 | **NW t-stat:** 1.186 (not significant)
- **Avg Cross-sectional R²:** 0.0678

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.02%/yr (t=0.598)  | **Adj R²:** 0.0964

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1302 (lower = more diversified)
- **Avg Period Turnover:** 11.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.41 < -0.1 & 초과CAGR -8.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.00 <= 0.3 — 후반부 알파 붕괴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -8.1%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
