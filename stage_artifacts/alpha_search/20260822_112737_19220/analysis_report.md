# Strategy Diagnostic Report: DFA_FM_A5E_Stock25
Generated: 2026-08-22

## Factor Signal Quality
- **IC Mean:** 0.0313 | **ICIR:** 0.204 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.852 | **Positive rate:** 59.1%
- **3Y Rolling Sharpe (avg):** 0.654

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00184 | **NW t-stat:** 1.339 (not significant)
- **Avg Cross-sectional R²:** 0.0626

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.39%/yr (t=0.894)  | **Adj R²:** 0.5055

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1239 (lower = more diversified)
- **Avg Period Turnover:** 25.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4756, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade F — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 59.8% > 35% & BM상관 0.70 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.78 -> post-2017 -0.65 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
