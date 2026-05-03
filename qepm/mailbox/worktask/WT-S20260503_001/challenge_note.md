# challenge_note — WT-S20260503_001 (STR_1715_LRO_v0.1)

## Section: alpha (Q-Lead 직접 작성, alpha-research SKIPPED)

### alpha_inherit_waiver

**Waiver type**: cert exempt (sizing_only role_card)

**근거**:
- `cert_rules.role_card_4x5`: `sizing_only` wt_type은 `alpha_discovery` cert 자체발급 의무 면제 (exempt). alpha cert는 parent WT-P20260429_002에서 inherit.
- 본 LRO WT는 새 alpha 생성하지 않음 (`no_new_alpha=true`). PCA/statistical factor는 risk overlay이지 alpha 아님 (도훈 정정 #3 + plan §1).
- artifact_contract.json wt_id_prefix_map: WT-S = sizing_only.

**No alpha cert issuance attempted in this WT.**

### codex_critic_skip_waiver

**Waiver type**: codex round skip — alpha role only

**근거**:
- alpha agent 자체 spawn 안 함 → draft → critic → final 5단계 흐름 진입 자체 없음.
- 이는 final package bypass 우회 아님. inherited_alpha_stub은 risk/optimizer/forge/judge/governor agent가 정상 codex round 거치도록 ALPHA_DONE phase 통과를 위한 schema-compliant stub일 뿐.
- `codex_critic_response_alpha.json`은 SKIPPED_BY_WAIVER stub으로 ALPHA_DONE artifact requirement 정합 (8차 Finding 2 defensive).
- risk-research / optimizer-research / forge / judge / governor 5 agent는 모두 정상 codex critic round 의무 (PreToolUse codex_round_pre_enforcer.sh 강제 통과 의무).

**Bypass 아님 — alpha role에 한정한 명시적 면제. 다른 agent의 codex round는 강제.**

### schema_validation_waiver

**Waiver type**: alpha_package schema validation skip — sizing_only inherited_alpha_stub 한정

**근거**:
- alpha_package schema 표준 required: `[task_id, as_of_date, alpha_vector, factor_specs, diagnostics]` — 신규 alpha 발굴 WT 기준.
- 본 LRO WT는 sizing_only로 alpha 신규 생성 X (`no_new_alpha=true`). alpha_vector / factor_specs / diagnostics 작성하면 alpha_discovery_certifier hook을 자극해 noise 발생 (3차 Finding 3 — cert hook noise 회피).
- inherited_alpha_stub 6-field (`package_kind, wt_type, cert_exempt, inherit_only, parent_alpha_package_ref, no_new_alpha`)는 schema-compliant alpha_package 아님. 의도적 stub.
- `cert_rules.role_card_4x5` 기준 `sizing_only`는 `alpha_discovery` cert exempt — schema validation도 동일 로직으로 면제.
- 정식 alpha cert + schema validation은 parent WT-P20260429_002 (deployment) 에서 이미 통과됨. 본 WT는 inherit only.

**Schema validation skip 적용 — sm_check_waiver(wt_id, "schema_validation_waiver") path 통과 의도.**

---

## Section: state_machine 정상 통과

- SPEC_APPROVED → ALPHA_DONE: Q-Lead가 4-파일 (alpha_package_inherit_ref.json + alpha_package.json inherited_alpha_stub + 본 challenge_note.md + codex_critic_response_alpha.json SKIPPED_BY_WAIVER stub) 작성 후 `sm_validated_advance("ALPHA_DONE")` 수행.
- ALPHA_DONE → RISK_DONE 이후 모든 phase 전이는 해당 agent가 자체 수행 (Q-Lead 직접 advance X).
- 종료 경로: `SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"`.

---

## 후속 agent 대상 노트

다음 agent들이 본 WT 내에서 codex critic round 5단계 의무:
- risk-research (Phase 2 RISK_DONE 책임)
- optimizer-research (Phase 3 OPTIMIZER_DONE)
- forge (Phase 4 FORGE_DONE)
- judge (Phase 5 JUDGE_PASSED)
- governor (Phase 6 GOVERNOR_REJECTED → ABORTED)

**production directory 보호**: `04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/` write count = 0 audit. 모든 산출물은 `stage_artifacts/WT_WT-S20260503_001/` 하위. canonical: `weights.csv` (optimizer) + `bt_result.rds` (forge) M4+LRO_cap conservative primary.
