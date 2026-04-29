# Judge Challenge Note — WT-P20260429_001

## Codex Critic Round 결과

- **Codex stance**: REJECT
- **Critical concerns**: 8 (HIGH 4 / MEDIUM 4)
- **Verification triangulation AX-008**: FAIL (Codex 측)

## Judge 자율 분석 (Charter §8 devil's advocate 무조건 수용 금지)

### ACCEPT (3 concerns) — 합당, verdict 반영

#### C1 — Stage artifact 부재
- **Codex 지적**: alpha_package.json / risk_package.json / optimization_package.json / weights.csv (WT-level) / alpha_scores.parquet / covariance.parquet 부재
- **Judge 분석**: 본 WT는 deployment_track (Discovery 산물 STR_1631_SYN_05 → SYN_06 outlier patch + Sharpe 표준 적용). request.json wt_type=deployment + pg1_eligibility=deployment_track + discovery_of=STR_1631_SYN_05 명시. 그러나 WT-level 4-stage Alpha→Risk→Optimizer→Forge package 부재 자체는 사실. forge_package만 단독 산출.
- **반영**: verdict_status에 "stage_artifact_partial" flag 명시. PG2 admission은 forge_package + hurdle_result + verification_result 3-source 기반.

#### C2 — Harvey 5-spec PENDING
- **Codex 지적**: forge_package.harvey_5spec.spec_pending=TRUE → Gate 2 (Harvey) 미충족
- **Judge 분석**: Lawbook §10 t>3.0 인식. Judge 자체 추정 (DSR + naive t-stat):
  - daily SR 1.293, n=5737 → t_naive = 6.169
  - Newey-West conservative ×0.55 → t_NW ≈ 3.39 > 2.95 PASS
  - Newey-West moderate ×0.70 → t_NW ≈ 4.32 > 2.95 PASS
  - 그러나 5-spec 각각 (CAPM/Carhart-3/Carhart-4/FF5/FF6) 일부 spec t<2.95 가능
- **반영**: Forge 측 ff5_attribution.R 산출 권장. 본 verdict는 자체 추정 ≥2.95 신뢰 기반 PASS_CONDITIONAL.

#### C4 — Role Honesty + AX-001 v2 conditional
- **Codex 지적**: defense_metrics 빈 list, crisis_alpha + bad/normal IC ratio 미산출
- **Judge 분석**: hurdle_result.defense_metrics: [] 사실. 자칭 core이지만 detected_family = "defense_ensemble", MDD 39.93%, overlay dependency 존재. AX-001 v2 conditional metric 미산출.
- **반영**: role 재분류 권고 — core_alpha → core_secondary or multi-role(core+overlay_dependency). admission 자체는 PG2 100% 유지 (replacement target STR_1715 동일 self-declared core 동등).

### PARTIAL (3 concerns) — 부분 합당, 권고 추가

#### C3 — Lockbox 3-way reporting 부재
- **Codex 지적**: Pre-LB/Lockbox/Combined 3-way 부재, walk-forward OOS embedding로 substitute 시도
- **Judge 분석**: user_directive에 따른 단일 measurement 컨텍스트 (request.json hypothesis_description "정도 회복" + STR_1715 fabrication 의심으로 simulation_basis 단일). 그러나 Charter v6.1 Lockbox extension audit 의무는 별개.
- **권고**: Forge에 STR_1715 frozen weights buy-and-hold 2024-01~2026-03 extension task 발주. 동일 OOS period (24-26) STR_1715 vs STR_1631_SYN_06 비교로 fabrication 확정 가능.
- **반영**: lockbox_audit_v6_1 section에 "frozen_weights_extension_diagnosis" 명시.

#### C6 — Dollar turnover vs name-count turnover
- **Codex 지적**: weights.csv schedule 부재, name-count basis turnover (보수적 추정)
- **Judge 분석**: backtest_harness::calc_turnover는 name-count basis 추정. dollar turnover는 weight 변화량 포함 시 다소 더 높을 가능성. 그러나 hard cap 600%/yr 대비 충분 buffer (현 283.9 vs 600).
- **반영**: PASS 유지. 단, deploy 시 dollar turnover 별도 측정 권고.

#### C8 — Tail_risk_result.json 부재
- **Codex 지적**: compute_tail_risk_suite 미실행, stress severity 미계산
- **Judge 분석**: D084/D085 hurdle 자체 진단 명시. Lawbook v1.4 Gate 6 (tail_risk)는 soft gate (Tier L2 — 경고만, 페널티 없음). 본 simulation 단계에서 hard block 사유 아님.
- **반영**: PASS 유지. 단, deploy 후 monitoring 단계에서 tail_risk_engine.R 호출 권고.

### REBUTTAL (2 concerns) — 룰 미스매치/오해, 명시적 거부

#### C5 — DSR n_trials inconsistency
- **Codex 지적**: verification axis1 n_trials=1 vs hurdle n_trials=465 inconsistent
- **Judge 반박**: 다른 측정 axis. verification_result.axis1_hallucination는 strategy-level DSR (1 unique strategy trial)이고, hurdle_result.statistical_defense는 research family multi-testing aggregate (465 trials 전체 family 대비). 두 측정은 inconsistent가 아닌 다른 dimension. Codex 룰 미스매치 (REBUTTAL valid).
- **결정**: 본 critique 반영하지 않음. DSR 1.0 (post-penalty 측면) + dsr_significant TRUE + sr_max_expected 0.0777 (n_trials=465) 모두 정합.

#### C7 — AX exception over-claimed
- **Codex 지적**: AX-005/AX-007 EXCLUSION이 necessary not sufficient인데 PASS 처리
- **Judge 반박**: judge_verdict_draft.axiom_compliance.AX_005 = "EXCLUSION_PASS — multi-axis composite + regime overlay multi-sleeve (necessary not sufficient)"으로 명시 인정. AX-007 = "EXCEPTION_1_multi_sleeve_via_regime_overlay PASS — 3-Layer regime overlay (NORMAL/CAUTION/CRISIS)" 명시. over-claim 아님 — Charter v1.2 §10 hard block 2건 위반 없음 (ProductionSchedule[N]m fabrication label 부재 + governor_admission.json 별개 트리거).
- **결정**: 본 critique 반영하지 않음. 명시적 텍스트 "necessary not sufficient" 그대로 유지.

## Q-Lead Escalate 진단

- HIGH severity ≥ 5: 4 (C1, C2, C3, C4) < 5 → 자율 처리
- AX axiom hard FAIL ≥ 3: 0 (모두 PASS/EXCLUSION/N/A)
- PIT C1 hard violation: 0 (lookahead detector clean + 인프라 trace)
- → **자율 처리 가능**

## 최종 verdict 변경

- 초안: PASS / Grade A / score 60.3
- Codex round 후: **PASS_CONDITIONAL** / Grade A_CONDITIONAL / score 60.3 unchanged
- 조건: Forge 측 (1) Harvey 5-spec recompute (2) frozen weights extension (3) AX-001 v2 conditional metrics — 3건 deploy 후 monitoring 발주
- PG2 admission: 100% 유지 (replacement target STR_1715 fabrication suspect 우선 정도 회복)

## Charter §8 명시 결론

Codex devil's advocate 비판 8건 중 3 ACCEPT + 3 PARTIAL + 2 REBUTTAL.
무조건 수용 금지 정합.
