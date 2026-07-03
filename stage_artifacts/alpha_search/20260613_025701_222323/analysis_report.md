# Strategy Diagnostic Report: 국면별 종목수 — 위기 시 N=15 집중, 정상 시 N=30 분산
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0324 | **ICIR:** 0.182 | **IC > 0 rate:** 56.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.592 | **Positive rate:** 61.5%
- **3Y Rolling Sharpe (avg):** 0.401

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00169 | **NW t-stat:** 1.014 (not significant)
- **Avg Cross-sectional R²:** 0.0823

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.87%/yr (t=0.308)  | **Adj R²:** 0.4937

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1180 (lower = more diversified)
- **Avg Period Turnover:** 14.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 13.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 58.9% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.21 < -0.1 & 초과CAGR -3.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 58.9% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: alpha_trend ratio(최근3Y/전체 SR) 0.21 <= 0.3 — 후반부 알파 붕괴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -3.1%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
