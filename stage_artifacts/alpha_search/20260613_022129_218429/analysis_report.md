# Strategy Diagnostic Report: 국면 지속성 필터 — MRS 위기 2개월 연속 확인 후에만 방어 전환
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0324 | **ICIR:** 0.204 | **IC > 0 rate:** 62.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.732 | **Positive rate:** 63.9%
- **3Y Rolling Sharpe (avg):** 0.137

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00350 | **NW t-stat:** 2.961 (significant)
- **Avg Cross-sectional R²:** 0.0614

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.82%/yr (t=0.713)  | **Adj R²:** 0.1057

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1571 (lower = more diversified)
- **Avg Period Turnover:** 10.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.36 < -0.1 & 초과CAGR -7.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.00 <= 0.3 — 후반부 알파 붕괴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -7.1%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
