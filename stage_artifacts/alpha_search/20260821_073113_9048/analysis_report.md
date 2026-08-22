# Strategy Diagnostic Report: DFA_RegimeSignals_StockCast
Generated: 2026-08-21

## Factor Signal Quality
- **IC Mean:** 0.0198 | **ICIR:** 0.128 | **IC > 0 rate:** 55.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.379 | **Positive rate:** 47.9%
- **3Y Rolling Sharpe (avg):** 0.051

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 26720.98566 | **NW t-stat:** 0.717 (not significant)
- **Avg Cross-sectional R²:** 0.0591

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.02%/yr (t=0.004)  | **Adj R²:** 0.4495

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1119 (lower = more diversified)
- **Avg Period Turnover:** 30.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
- **Sample Aligned:** YES [ALIGNED] (overlap: 3036, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 64.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.31 < -0.1 & 초과CAGR -6.5%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.82 -> post-2017 -0.64 — 논문발표 후 알파 소진 패턴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -6.5%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
