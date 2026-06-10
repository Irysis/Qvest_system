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
| ~~forge_code_guard~~ | ❌ **DEPRECATED 2026-05-16** (`_archive_v55/` 삭제 — Tier 1 cleanup. OPT-1~11 강제는 axiom_enforcement_hook + worktask_spec_validator로 대체) |
| backtest_contract_audit | Backtest Result Contract v1.0 audit |
| ~~milestone_commit~~ | ⚠️ **FS retain / settings 미등록 2026-05-16** — auto_commit_on_stop으로 대체. 활성화 필요 시 settings.json PreToolUse 추가 |

## Tier 4 (Post artifact validation)

| Hook | 강제 대상 |
|---|---|
| worktask_artifact_validator | forge_package 8-field schema + PIT 패턴 |
| red_flag_detector | RF-A / RF-R / RF-O 자동 감지 |
| pipeline_trigger | DONE → TODO 라우팅 |
| cash_sleeve_validator | (legacy v55) cash_allocation role 검증 — FS retain / settings 미등록 |
| ~~trail_consistency_checker~~ | ⚠️ **FS retain / settings 미등록 2026-05-16** — 3-trail 일관성은 worktask_artifact_validator로 cover |
| ~~circuit_breaker~~ | ⚠️ **FS retain / settings 미등록 2026-05-16** — 3회 실패 warn은 events.jsonl 통한 후속 분석 가능 |
| ~~risk_gate~~ | ❌ **DEPRECATED 2026-05-16** (`_archive_v55/` 삭제 — Tier 1 cleanup. tail_risk 검증은 risk_crowding_score_check + risk-research agent 영역) |
| answer_principles_grep | 회피 표현 + 검증 증거 카운트 (Level 2 soft alert) |
| feature_registry_economic_rationale_check | Phase 1.A — 신규 factor economic_rationale 의무 |
| ml_cost_aware_audit | Phase 1.A — Net-of-Cost ML loss 의무 |
| ml_uncertainty_audit | Phase 1.A — μ̃ = μ̂ - k·SE(μ̂) 의무 |
| risk_crowding_score_check | Phase 2.C — crowding_score_per_factor 의무 |
| attribution_quarterly_trigger | Phase 2.D advisory — Brinson + Carhart 4 분기별 (FS retain / settings 미등록 의도적 advisory) |

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
| ~~teammate_idle_guard~~ | TeammateIdle | ❌ 등록 해제 2026-06-10 (v53 전용 — FS retain) |
| ~~task_complete_guard~~ | TaskCompleted | ❌ 등록 해제 2026-06-10 (v53 전용 — FS retain) |
| harness_health | 부트스트랩 | Hook 건강 체크 + `--profile` latency 측정 |

## Tier 의미

- **L1 bootstrap**: 세션 시작 시 1회 실행
- **L2 soft gate**: 검증 실패 시 경고 + 로그
- **L3 hard block**: 위반 시 도구 실행 자체를 물리적 차단
- **L4 구조 강제**: JSON 스키마 + agent_id 추적 + LLM 판정으로 우회 불가

## ERR trap 필수

모든 command Hook에 `trap 'echo "{}"; exit 0' ERR`.

**중요 (v8.0 2026-05-29 정정)**: allow/no-op 출력은 **`{}`** (빈 객체 = 통과). 구 패턴 `{"decision":"allow"}`는 **무효** — 현 Claude Code hook 스키마에서 `decision` 유효값은 `approve`/`block`뿐이라 `"allow"`는 "Invalid input at (root)" 검증오류(회색 노이즈) 유발. 차단은 `{"decision":"block","reason":...}` 또는 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":...}}`. 전 hook 147건 일괄 정정 완료.

## v6.4 진화 (Sprint 2 Phase 4)

신규 `qvest_hook_router.py` 단일 진입 + 4 policy JSON:
- `02_Infrastructure/hooks/policies/state_transitions.json` (WT phase 전이)
- `02_Infrastructure/hooks/policies/role_permissions.json` (agent 역할 경계)
- `02_Infrastructure/hooks/policies/codex_round_contract.json` (Codex Round 의무)
- `02_Infrastructure/hooks/policies/cert_rules.json` (5 cert eligibility)

→ 각 hook이 정규식 중복 보유 안 함, 동일 policy JSON 참조.

## 참조

- `02_Infrastructure/hooks/*.sh` (현재 55개 — Phase 1/2 hooks 신규 5건 포함)
- ~~`02_Infrastructure/hooks/_archive_v55/`~~ (Tier 1 cleanup 2026-05-16 삭제 — legacy v55 hooks 6건 영구 폐기)
- `.claude/settings.json` Hook 등록 (45 distinct .sh)
- `02_Infrastructure/docs/qvest_v6_4_sot.md` Section 5 (Hook + Cert + Codex Round Matrix)

## Hook 정합 audit (2026-05-16)

- **FS only / 미등록 (5건)**: cash_sleeve_validator (legacy v55) / circuit_breaker / milestone_commit / trail_consistency_checker / attribution_quarterly_trigger (advisory)
- **Deprecated 2026-05-16 (2건)**: forge_code_guard / risk_gate (`_archive_v55/` Tier 1 cleanup 삭제)
- **Phase 1/2 신규 등록 (4건)**: feature_registry_economic_rationale_check / ml_cost_aware_audit / ml_uncertainty_audit / risk_crowding_score_check
- **Active loaded**: 45 distinct .sh (settings.json registered)

## v8.1.1 정합 (2026-06-10)

- settings.json 46개 hook DIR = `${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 3중 fallback (구 경로 glob 폐기 — 46-hook 전수 침묵사망 사건 수리)
- Stop hook 재등록: auto_commit_on_stop + auto_push_on_stop
- TeammateIdle/TaskCompleted (v53 전용) 등록 해제 — 스크립트 FS retain
- pre_enforcer에 codex stance=STUB 차단 추가 (AX-008 이중방어)
- bootstrap 카나리아: safety_guard block 실증 실패 시 BOOT_FAILS (침묵사망 재발 방지선)
- **차기 (1주 soak 후)**: qvest_hook_router.py 단일 진입 전환 — 이벤트당 1 spawn으로 Write당 35 spawn(~4.6s) 축소. policy JSON 4종은 기존재. soak 조건: 재시작 후 /tmp 로그 7일 무에러.
