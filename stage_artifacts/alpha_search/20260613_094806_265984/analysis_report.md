# Strategy Diagnostic Report: 국면 조건부 슬리브 배분 — v7.1 MRS에 따라 3-sleeve(STR_1037+STR_943+STR_898) 가중을 동적으로 조절. RISK_ON: Consensus heavy(50%), CRISIS: Defense heavy(60%)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0090 | **ICIR:** 0.040 | **IC > 0 rate:** 50.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.602 | **Positive rate:** 68.4%
- **3Y Rolling Sharpe (avg):** 0.398

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00047 | **NW t-stat:** -0.305 (not significant)
- **Avg Cross-sectional R²:** 0.1003

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.41%/yr (t=-0.168)  | **Adj R²:** 0.5952

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0936 (lower = more diversified)
- **Avg Period Turnover:** 13.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 7)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.21 < -0.1 & 초과CAGR -2.8%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 59.0% > 35% & BM상관 0.79 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -2.8%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
