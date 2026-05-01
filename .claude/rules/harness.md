# Harness Engineering (Level 0)

**원칙**: 모든 프로세스 규칙은 프롬프트가 아닌 Hook으로 강제. "엄밀함은 사라지지 않고 이동한다."
**v6.4 진화**: Phase 4 `qvest_hook_router.py` + 4 policy JSON 단일 진입 (Sprint 2 후 전환). 본 rule은 v6.3.3 (router 도입 전) 17~18 hook 구조 + v6.4 router 후 매핑.

## Tier 1 (전역 hard block)

| Hook | 이벤트 | 강제 대상 |
|---|---|---|
| safety_guard | PreToolUse[W/E/B] | 05_Production / 01_Literature 보호 |
| axiom_enforcement_hook | PreToolUse[W/E] | AX-code 공리 위반 (AX-001/002 warn+context, 나머지 block) |
| **codex_round_pre_enforcer** ⭐ v6.3.3 | PreToolUse[W/E] | final package 직접 작성 block (`{role}_package.json`) |
| sr_provenance_check (Pre) | PreToolUse[W/E] | `ProductionSchedule[N]m` fabrication label hard block |

## Tier 2 (Agent)

| Hook | 강제 대상 |
|---|---|
| agent_role_guard | Alpha/Risk/Optimizer 역할 경계 |
| worktask_sequence_enforcer | WT 순서 (Alpha→Risk→Optimizer→Forge→Judge→Governor) |
| unified_agent_guard | Stage 순서 + 1인 다역할 차단 |
| s0_debate_guard | (legacy v55) S0 1인 다역할 스폰 차단 |
| role_taxonomy_admission_gate | (legacy v55) 6-role 분류 admission |

## Tier 3 (Write/Edit hard mandate)

| Hook | 강제 대상 |
|---|---|
| worktask_constraint_enforcer | 20종 + bounds [0, 0.20] + Σw=1 + long-only |
| worktask_spec_validator | request.json schema (task_id format / universe / cost_model_version) |
| forge_code_guard | OPT-1~11 + S1 overlay 금지 |
| backtest_contract_audit | Backtest Result Contract v1.0 audit |
| milestone_commit | 마일스톤 auto-commit + secret scan |

## Tier 4 (Post artifact validation)

| Hook | 강제 대상 |
|---|---|
| worktask_artifact_validator | forge_package 8-field schema + PIT 패턴 |
| red_flag_detector | RF-A / RF-R / RF-O 자동 감지 |
| pipeline_trigger | DONE → TODO 라우팅 |
| cash_sleeve_validator | (legacy v55) cash_allocation role 검증 |
| trail_consistency_checker | 3-trail 일관성 |
| circuit_breaker | 3회 연속 실패 warn |
| risk_gate | tail_risk 검증 |
| answer_principles_grep | 회피 표현 + 검증 증거 카운트 (Level 2 soft alert) |

## Tier 5 (Positive Certifier)

| Hook | 발급 cert |
|---|---|
| alpha_discovery_certifier | `alpha_discovery_certificate.json` (4 AND 조건) |
| sr_provenance_check (Post) | `sr_provenance_certificate.json` (forge_package 4-field) |
| schedule_fidelity_check | `schedule_fidelity_certificate.json` (density≥0.95 OR infeasibility) |
| worktask_artifact_validator | `forge_package_validated_certificate.json` (8-field) |
| governor_concord_certifier | `governor_concord_certificate.json` (book_state↔admission match) |

## Tier 6 (Codex Round)

| Hook | 강제 대상 |
|---|---|
| **codex_round_auto_trigger** ⭐ v6.0 | PostToolUse[W/E] `_draft.json` async background spawn |

## 기타 (Stop / FileChanged / Teammate)

| Hook | 이벤트 | 강제 대상 |
|---|---|---|
| auto_commit_on_stop | Stop | 세션 종료 auto-commit |
| s0_verdict_router | FileChanged[S0_VERDICT_*] | (legacy v55) APPROVE/REVISE/REJECT 라우팅 |
| s0_debate_enforcer | PostToolUse[W] | (legacy v55) 3-Round 상태 머신 |
| teammate_idle_guard | TeammateIdle | idle teammate 재할당 |
| task_complete_guard | TaskCompleted | 파이프라인 다음 단계 트리거 |
| harness_health | 부트스트랩 | Hook 건강 체크 + `--profile` latency 측정 |

## Tier 의미

- **L1 bootstrap**: 세션 시작 시 1회 실행
- **L2 soft gate**: 검증 실패 시 경고 + 로그
- **L3 hard block**: 위반 시 도구 실행 자체를 물리적 차단
- **L4 구조 강제**: JSON 스키마 + agent_id 추적 + LLM 판정으로 우회 불가

## ERR trap 필수

모든 command Hook에 `trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR`.

## v6.4 진화 (Sprint 2 Phase 4)

신규 `qvest_hook_router.py` 단일 진입 + 4 policy JSON:
- `02_Infrastructure/hooks/policies/state_transitions.json` (WT phase 전이)
- `02_Infrastructure/hooks/policies/role_permissions.json` (agent 역할 경계)
- `02_Infrastructure/hooks/policies/codex_round_contract.json` (Codex Round 의무)
- `02_Infrastructure/hooks/policies/cert_rules.json` (5 cert eligibility)

→ 각 hook이 정규식 중복 보유 안 함, 동일 policy JSON 참조.

## 참조

- `02_Infrastructure/hooks/*.sh` (현재 18개)
- `02_Infrastructure/hooks/_archive_v55/` (legacy 폐기 hook 6건)
- `.claude/settings.json` Hook 등록
- `02_Infrastructure/docs/qvest_v6_4_sot.md` Section 5 (Hook + Cert + Codex Round Matrix)
