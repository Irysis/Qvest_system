# Strategy Diagnostic Report: [진단] 국면 시그널 Ablation — 9축 중 1축씩 제거 시 합산 국면 성과 변화
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0203 | **ICIR:** 0.184 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.925 | **Positive rate:** 69.6%
- **3Y Rolling Sharpe (avg):** 0.722

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00091 | **NW t-stat:** 1.248 (not significant)
- **Avg Cross-sectional R²:** 0.0546

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.26%/yr (t=1.645)  | **Adj R²:** 0.7060

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0933 (lower = more diversified)
- **Avg Period Turnover:** 10.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 62.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 62.1% > 35% & BM상관 0.80 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 1.34 -> post-2017 -0.71 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
