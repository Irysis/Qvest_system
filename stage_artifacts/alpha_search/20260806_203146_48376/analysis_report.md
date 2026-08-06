# Strategy Diagnostic Report: FX_Intensity_FQ149
Generated: 2026-08-06

## Factor Signal Quality
- **IC Mean:** 0.0234 | **ICIR:** 0.176 | **IC > 0 rate:** 56.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.438 | **Positive rate:** 56.6%
- **3Y Rolling Sharpe (avg):** 0.205

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00160 | **NW t-stat:** 0.915 (not significant)
- **Avg Cross-sectional R²:** 0.0687

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.18%/yr (t=0.044)  | **Adj R²:** 0.6284

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0928 (lower = more diversified)
- **Avg Period Turnover:** 1.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** MEDIUM (persistent>75%: 9, common>50%: 14)
- **Sample Aligned:** YES [ALIGNED] (overlap: 2534, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 61.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
