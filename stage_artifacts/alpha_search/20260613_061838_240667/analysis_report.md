# Strategy Diagnostic Report: 외국인 순매수 국면 — 외국인 대규모 매도 시 방어 전환
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0358 | **ICIR:** 0.229 | **IC > 0 rate:** 60.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.676 | **Positive rate:** 68.9%
- **3Y Rolling Sharpe (avg):** 0.478

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00120 | **NW t-stat:** 1.020 (not significant)
- **Avg Cross-sectional R²:** 0.0660

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.20%/yr (t=0.878)  | **Adj R²:** 0.5297

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1374 (lower = more diversified)
- **Avg Period Turnover:** 11.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 9)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 48.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.10 < -0.1 & 초과CAGR -1.4%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 48.8% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.51 -> post-2017 -1.00 — 논문발표 후 알파 소진 패턴
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -1.4%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
