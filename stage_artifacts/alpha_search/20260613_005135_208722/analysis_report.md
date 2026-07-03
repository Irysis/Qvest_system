# Strategy Diagnostic Report: 국면별 앙상블 크기 — risk_on: 5전략, crisis: 2전략 (집중)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0356 | **ICIR:** 0.224 | **IC > 0 rate:** 59.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.531 | **Positive rate:** 60.6%
- **3Y Rolling Sharpe (avg):** 0.324

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00128 | **NW t-stat:** 1.059 (not significant)
- **Avg Cross-sectional R²:** 0.0670

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.06%/yr (t=1.076)  | **Adj R²:** 0.2793

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1192 (lower = more diversified)
- **Avg Period Turnover:** 6.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 5, common>50%: 11)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.21 < -0.1 & 초과CAGR -3.7%p < 0 — KR에서 팩터 방향 역작동 의심
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade F — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) -0.10 <= 0.3 — 후반부 알파 붕괴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -3.7%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
