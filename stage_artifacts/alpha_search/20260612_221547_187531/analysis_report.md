# Strategy Diagnostic Report: STR_1051 — STR_1048 + Margin Gate. fwd_margin < 0 종목 제거 후 Top 30.
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0401 | **ICIR:** 0.259 | **IC > 0 rate:** 62.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.693 | **Positive rate:** 68.1%
- **3Y Rolling Sharpe (avg):** 0.501

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00191 | **NW t-stat:** 1.618 (not significant)
- **Avg Cross-sectional R²:** 0.0654

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.43%/yr (t=0.963)  | **Adj R²:** 0.5152

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1350 (lower = more diversified)
- **Avg Period Turnover:** 7.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 49.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 49.6% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.56 -> post-2017 -1.04 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
