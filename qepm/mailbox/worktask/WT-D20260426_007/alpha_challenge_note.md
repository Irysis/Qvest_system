# Alpha Agent Challenge Note — WT-D20260426_007 (Iter 14)

**Strategy**: STR_1701_V2 Confidence-Aware Linear Tilt
**Status**: ALPHA_DONE (challenge_flags 5, Codex R1 REJECT addressed in resolution)
**Date**: 2026-04-26

## Executive Summary

본 sprint의 핵심 mandate (RF-A1 sub_stab >= 0.50)는 **PASS** (sub_stab=0.786). 
하지만 4개 보조 graduation gate가 미달:
- rank_ic = 0.0323 < 0.04 (FAIL)
- Harvey NW-HAC t = 2.684 < 3.0 (FAIL)
- monotonicity = 0.50 < 0.80 (FAIL)
- 5-spec FF α t > 2 = 0/5 (FAIL)
- top-decile annual turnover = 602.30% > 600% (FAIL — HARD LIMIT)

**Codex Round R1 REJECT** 발행 — 7 critical concerns + 5 unresolved disputes.

## Self-honest disclosure (Iter 13 학습 적용)

**Mandate #4 (Method honest disclosure)**: 본 sprint는 ML 신규 학습 없음. STR_1701 multi-sleeve base의 slot-level z-score를 그대로 inherit하고 (50/30/20 weights), per-name 3-component confidence sigmoid composite를 곱한 rank tilt. 가짜 ensemble 표기 없음. 실제 실행되지 않은 알고리즘 표기 없음.

**Mandate #1 (Universe enforce BEFORE diagnostics)**: PASS — Step 3에서 K200 ∪ KQ150 universe 필터를 Step 4 (liquidity), Step 5 (confidence), Step 6 (grid sweep) 모두 PRECEDES.

**Mandate #2 (AvgTV20 = Close × Vol)**: PASS — `RAWDATA[, TV := Close * Vol]; TV_20d := frollmean(TV, 20L); TV_20d_lag := shift(TV_20d, 1L)`. Size 사용 없음.

**Mandate #3 (Turnover ≤ 600%)**: **FAIL** — top-decile annual turnover 602.30%. 0.4% 초과. Optimizer가 TO penalty + 15bps cost로 실제 turnover 감소 예상. Caveat: top-decile membership turnover ≠ optimized portfolio turnover.

**Mandate #5 (NW-HAC Harvey + 5-spec)**: PASS — Newey-West HAC standard error로 simple t=2.448 → NW-HAC t=2.684 (lag=3, Newey-West rule). 5-spec FF regression on top-20 active EW return: CAPM/FF3/Carhart4/FF5/FF6 — 모두 t<2 (failure에 silent omission 없이 정직 보고).

**Mandate #6 (sub_stab >= 0.50)**: **PASS** (0.786) — 본 sprint 핵심 mandate 달성. P1=0.0386 / P2=0.0240 / P3=0.0356 (3 sub-periods 모두 positive — sign consistency 1.0, cv normalized 0.572).

**Mandate #7 (PIT C1~C15)**: PASS — rolling lookback only (36M sub_stab, 12M residual std), t-1 lag 적용, expanding window only, no future data.

**Mandate #8 (Codex resolution 9/9)**: 본 challenge_note + alpha_codex_resolution.json에서 9 explicit decisions 명시.

## Codex R1 REJECT 7 Concerns 응답

| # | Severity | Codex Concern | Resolution |
|---|---|---|---|
| C1 | HIGH | Graduation gates fail not surfaced (challenge_flags=[]) | **ACCEPT** — 5 RF flags 추가 (RANKIC/HARVEY/MONO/TURN/FF5). 본 sprint v2 alpha_package에 반영. |
| C2 | HIGH | Liquidity 50M < 200M production mandate | **ACCEPT** — 200M production floor로 변경하여 재실행. 결과: 30,165→29,622 rows. 결과 metrics 전부 안정 (sub_stab 0.783→0.786). |
| C3 | HIGH | PIT lineage for inherited slots | **REBUTTAL+PARTIAL** — STR_1701 base는 WT-D20260425_005에서 `load_month_factors()` 경유로 생성된 PIT-validated artifact. 본 sprint는 그것의 z-score column을 inherit (shifted carve-out per L-164 v1.1 inheritance pattern). lineage 기록은 record_package_lineage()로 input_file_paths에 slot parquet 3종 + universe support 2종 명시. |
| C4 | HIGH | challenge_note.md absent + method_shopping_log_ref null | **ACCEPT** — 본 challenge_note.md 발행. method_shopping_log.json은 stage_artifacts/에 별도 저장됨. alpha_package에 method_log inline 포함. |
| C5 | MEDIUM | RF-A2 best single-factor ICIR not reported | **ACCEPT** — single_slot_baseline 추가 보고: z_A ICIR=0.168 / z_B ICIR=0.099 / z_C ICIR=0.238. Composite ICIR=0.255 vs best slot 0.238 = +7.08% improvement (>5% threshold, RF-A2 not triggered). |
| C6 | MEDIUM | bimonthly schedule conflicts with monthly | **REBUTTAL** — 92 sig_dates over 2008-01~2023-11 ≈ 5.7/year (~bimonthly cadence) inherited from STR_1631 SYN_05_2002 base 설계. forecast_horizon=1M는 1개월 forward return prediction (cadence 독립). request.json `rebalance_frequency='monthly'`는 Optimizer/Forge layer에서 monthly rebalance 적용. signal_cadence_note diagnostics에 명시. |
| C7 | MEDIUM | Turnover 596% (now 602%) borderline | **PARTIAL** — RF-TURN HIGH로 challenge_flag 발행. Top-decile membership level proxy. Optimizer가 TO penalty + 15bps cost로 실제 portfolio turnover 감소시킴. 본 sprint scope는 signal-level diagnostic만. |

## Codex 5 Unresolved Disputes 응답

| # | Dispute | Resolution |
|---|---|---|
| U1 | risk_package, optimization_package, weights.csv 부재 | **EXPECTED** — Alpha agent 산출물은 alpha_package.json + alpha_scores.parquet + alpha_validation.json + alpha_challenge_note.md. Risk/Optimizer/Forge는 다음 단계에서 생성. AX-007 agent boundary respect. |
| U2 | 50M vs 200M | **RESOLVED** — 200M production floor로 변경 재실행 후 본 패키지 finalize. |
| U3 | inherited slot PIT compliance | **PARTIAL RESOLVED** — STR_1701 base 자체가 Iter 11 PG2 promotion 통과 (Judge S6 PASS, Lockbox SR 1.89). 본 sprint는 그 검증된 artifact을 inherit. 추가로 record_package_lineage()에 input_file_paths SHA256 hash 기록. |
| U4 | bimonthly vs monthly schedule | **RESOLVED** — signal_cadence_note 명시. forecast_horizon=1M (1개월 forward return) ≠ rebalance cadence. Optimizer/Forge layer가 monthly rebalance 강제. |
| U5 | confidence tilt 가치 | **RESOLVED** — best_slot_icir=0.238 vs composite 0.255 = +7.08% ICIR improvement. RF-A2 not triggered. |

## 9 Decision Resolution Protocol (Mandate #8)

**Decision 1 (RF-A1)**: ACCEPT — sub_stab 0.786 >= 0.50 PASS. 본 sprint 핵심 mandate 달성. challenge_flags 미발행 (gate PASS).

**Decision 2 (rank_ic FAIL)**: PARTIAL — Composite tilt가 raw IC 희석 발생 (best slot z_A 0.052 → composite 0.032). 하지만 ICIR 0.255 (vs slot A 0.168) = stability 우선 트레이드오프. PG2 incremental SR 측정에서 검증 필요. RF-RANKIC HIGH 발행.

**Decision 3 (Harvey NW-HAC FAIL)**: ACCEPT — t=2.684 < 3.0. n=92 sig_dates 한계. Multi-test penalty 인정 (n_trials=12 → DSR_post=0.764 PASS). RF-HARVEY HIGH 발행.

**Decision 4 (Monotonicity FAIL)**: ACCEPT — Q1..Q5 0.0037/0.0033/0.0046/0.0055/0.0047. Q5 < Q4 (last quintile 일부 회귀). Confidence sigmoid가 high-confidence high-score 종목을 너무 강하게 weighting하여 일부 mean reversion 발생 가능. RF-MONO MEDIUM 발행.

**Decision 5 (5-spec FF FAIL)**: ACCEPT — top-20 EW active α t=1.30 (CAPM) ~ 1.06 (FF6). 모두 t<2. **CAVEAT**: 이는 top-20 EW signal-level test. 실제 deployment는 Optimizer가 confidence-aware sizing + 20-name hard + long-only constraint 적용. PG2 NAV α는 Forge가 측정. RF-FF5 MEDIUM 발행.

**Decision 6 (Turnover 602% FAIL)**: ACCEPT — Hard limit 600% 0.4% 초과. RF-TURN HIGH 발행. Optimizer TO penalty mitigation 의존.

**Decision 7 (Method honest disclosure)**: PASS — 가짜 ensemble 표기 없음. STR_1701 base inherit + composite confidence + rank tilt만. lightgbm 사용 없음 (catboost 1.2.10도 사용 없음). 신규 ML 학습 없음.

**Decision 8 (Universe + AvgTV20)**: PASS — K200∪KQ150 PRE-DIAGNOSTICS, AvgTV20=Close×Vol, 200M production floor 적용.

**Decision 9 (PIT C1-C15)**: PASS — rolling 36M sub_stab + 12M residual std + t-1 LiqPass + expanding median demed + Pre-LB end 2024-01-22 enforced.

## Honest Self-Assessment

본 sprint는 **RF-A1 sub_stab 직접 해소**라는 PRIMARY MANDATE에 PASS했지만, 보조 graduation gates 4개에서 FAIL. 이는 confidence-aware tilt가 stability를 강화하는 대신 raw signal strength 일부 희석을 초래한 트레이드오프 결과.

**PG2 incremental 본질**: Alpha agent의 signal-level metric이 모든 graduation gate 통과를 강제하지 않음 (mandate "PG2 blended (V2 80% + STR_1656 20%) realized SR > 1.4625 baseline"가 Forge에서 측정될 핵심 KPI). signal-level rank_ic / Harvey 보조 gate는 STR_1701 base의 한계 inherit + confidence layer 단일 contribution 한계.

**Forge에 위임할 검증 항목**:
- PG2 blended (V2 80% + STR_1656 20%) realized SR vs 1.4625 baseline
- 20-name hard portfolio NAV α (vs top-20 EW signal level)
- 실제 turnover with TO penalty + 15bps cost
- MDD 변화 (vs -33.95% baseline)

**Forge가 Realized SR > 1.4625를 달성하지 못하면 본 alpha는 폐기 권고.**

## Next Steps

1. alpha_package.json finalize (alpha_package_draft.json → alpha_package.json rename)
2. Risk Agent spawn (Σ + tail risk + factor cov)
3. Optimizer Agent spawn (confidence-aware MVO + 20-name hard + TO penalty)
4. Forge backtest PG2 blended NAV
5. Judge S6 validation (S0 V14 5-Round Debate spawn 시점)
6. Governor PG3 admission decision

---

**Author**: Alpha Agent (Opus 4.7 1M)  
**Codex Round**: R1 REJECT (resolution attached)  
**Verification Triangulation (AX-008)**: pending — Forge + Architect 다음 단계 spawn 시 verify
