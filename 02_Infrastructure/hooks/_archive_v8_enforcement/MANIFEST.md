# v8 → v9 훅 등록 해제 원장 (36종)

> 작성 2026-08-23. 근거 = 승인된 재설계안 `C:/Users/99922/.claude/plans/qvest-encapsulated-wave.md` §3.2(a) · §4 steps 1~4 · §6 결정 D-b~D-e.
> 롤백 태그 `pre-v9-lean-loop`.

## 0. 이 문서가 말하는 것 / 말하지 않는 것

- **말하는 것**: v8.4 시점에 `.claude/settings.json` 또는 라우터 dispatch 로 **등록되어 있던** 47종 중, v9 Lean Loop 에서 **등록만 해제된 36종**의 이름·구 등록 위치·차단력·해제 사유·재등록 레시피.
- **말하지 않는 것**: 파일 삭제·이동·기능 폐기. **한 파일도 옮기거나 지우지 않았다.**

**★파일이 제자리에 남아 있는 이유 (삭제 금지)** — 아래 소비자들이 **경로로 직접 호출**한다. 파일을 옮기면 등록 해제와 무관한 실패가 난다.

| 소비자 | 어떻게 부르는가 |
|---|---|
| `02_Infrastructure/hooks/harness_health.sh` | `REQUIRED_HOOKS` 배열 + ERR trap 검사 — `$HOOKS_DIR/<name>.sh` 존재·실행권한 확인 |
| `02_Infrastructure/memory/memory_knowledge_health.R` W5 | `02_Infrastructure/hooks/axiom_enforcement_hook.sh` 를 하드코딩 경로로 열어 AX-id 문자열 대조. 부재 시 `WARN_5_hook_missing` |
| `02_Infrastructure/ops/hook_e2e_battery.py` | 훅 파일을 stdin payload 로 직접 실행하는 E2E 배터리 |
| `08_Tests/**` 스위트 **31파일** | `bash "$PROJ/02_Infrastructure/hooks/<name>.sh"` 형태 직접 호출 (`test_agent_role_guard.sh` · `test_ast_spec_gate.sh` · `test_hypothesis_precheck_gate.sh` · `test_worktask_sequence_gate.sh` · `test_lockbox_audit_path.R` · `test_ax001_defense_scope.R` 등) |
| `02_Infrastructure/ops/hook_integrity_check.sh` · `boot_currency_check.sh` C6 | 라우터 policy 파일과 settings.json 을 **파일로** 읽어 대조 |

⇒ 등록 해제 = "세션 도구 호출마다 자동 발화하지 않는다"는 뜻이고, **테스트·배터리에서는 그대로 실행되고 그대로 판정한다.**

## 1. 아카이브 사본 (원문 보존)

| 파일 | 내용 |
|---|---|
| `settings.json.v8_20260823.json` | v8 최종 `.claude/settings.json` 전문 (해제 직전 바이트 동일) |
| `router_dispatch_v1.2.json` | v1.2 라우터 dispatch 19-entry 전문 (`02_Infrastructure/hooks/policies/router_dispatch.json` 은 v1.3 = `hooks: []` 로 비움, 파일은 유지) |

## 2. 남은 등록 12종 (대조용 — 해제 대상 아님 · ★v10 2026-09-03 갱신)

`safety_guard` · `legacy_write_block` · `book_write_guard` · `discovery_graduation_gate` · `worktask_constraint_enforcer` · `backtest_contract_audit` · `telegram_direct_call_guard` · `axiom_context_inject` · `overlay_pit_grep` · `boot_stamp_check` · `auto_commit_on_stop` · `auto_push_on_stop`
(13 command / 12 distinct · **Stop 이벤트 등록 0** — SessionEnd 2종)

★v9(08-23) 판 대비 변경 3건: **`governor_concord_certifier` 등록 해제**(v10 governor 폐지 — 감시 대상 소멸, 자리를 `book_write_guard` 가 승계) · **`book_write_guard` 신설 등록**(BOOK 정본 writer 경유 강제 + legacy `book_state.json` 재기입 차단) · **`backtest_contract_audit` 재등록**(2026-08-24, 아래 §3.2 #3 참조 — 해제 사유였던 `.py` 자체합성 idiom 가지만 제거하고 원장 integrity 게이트는 복원).

## 3. 해제 36종

`구 등록` 열의 `settings:L###` 은 `settings.json.v8_20260823.json` 의 줄 번호, `router #N` 은 `router_dispatch_v1.2.json` 의 `events.PreToolUse.hooks[]` 1-기준 색인(전 항목 matcher = PreToolUse).
`재등록` 열은 해당 이벤트 그룹의 `hooks[]` 안에 넣을 조각이다. 모든 조각의 공통 접두 = `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}; bash "$DIR/02_Infrastructure/hooks/` + 파일명 + `"`, 뒤에 아래 표의 **suffix** 를 그대로 붙인다.

```jsonc
// 재등록 조각 형식 (matcher 는 아래 표의 '구 이벤트/matcher' 값을 그대로 사용)
{
  "matcher": "<matcher>",
  "hooks": [
    { "type": "command",
      "command": "DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}; bash \"$DIR/02_Infrastructure/hooks/<name>.sh\"<suffix>" }
  ]
}
```

### 3.1 Stop blockers (2) — 모든 턴에 걸리던 차단 훅

| # | 스크립트 | 구 등록 (이벤트/matcher) | 차단력 | 사유 범주 | 재등록 suffix | mandate·문서 |
|---|---|---|---|---|---|---|
| 1 | `performance_realmeasure_gate.sh` | Stop (matcher 없음) · settings:L299-306 | **block** | Stop blockers | (없음) | 2026-06-17 도훈 mandate · memory `feedback-performance-real-code-only`. **해제 = 플랜 D-c** — 규칙 자체는 텍스트로 존치(`hurdle_result.json` 값만 인용) |
| 2 | `research_continuity_guard.sh` | Stop (matcher 없음) · settings:L308-316 | **block** | Stop blockers | (없음) | 2026-07-15 도훈 mandate · `02_Infrastructure/docs/rules/continuity-firewall.md` · `02_Infrastructure/docs/rules/answer-principles.md` 6호. **해제 = 플랜 D-j** — 연속성 계약은 L-code 발행 1곳으로 이동 |

### 3.2 research-path blockers (11) — 리서치 쓰기 경로를 실제로 막던 게이트

| # | 스크립트 | 구 등록 | 차단력 | 사유 범주 | 재등록 suffix | mandate·문서 |
|---|---|---|---|---|---|---|
| 3 | `backtest_contract_audit.sh` | router #1 · Write\|Edit | block | research-path blockers | ` 2>>/tmp/backtest_contract_audit.log \|\| true` | `.claude/rules/backtest-contract.md` L3 hard block · `python-policy.md` §5. **해제 = 플랜 D-d** (.py 자체합성 idiom 차단이 v8.4 ML 레인에 걸림; 룰은 텍스트 존치) — ★**2026-08-24 재등록**(PreToolUse[Write], `.py` idiom 가지 제거 · 양성/음성/돌연변이 10/10 실증 `08_Tests/hooks/test_backtest_contract_audit_gate.R`). 현행 등록 12종에 포함 = §2 |
| 4 | `axiom_enforcement_hook.sh` | router #3 · Write\|Edit | block | research-path blockers | (없음) | `.claude/rules/axioms.md` "Hook 강제" 절 (AX-001 block / AX-002 advisory). ★`memory_knowledge_health.R` W5 가 이 **파일**을 계속 읽으므로 이동 금지 |
| 5 | `agent_role_guard.sh` | router #5 · Write\|Edit | block | research-path blockers | (없음) | `.claude/rules/pit.md` "Hook 계층". 2026-07-03 감사: agent marker writer 부재로 **구조적 상시-allow** — 등록되어 있어도 판정한 적 없음 |
| 6 | `worktask_spec_validator.sh` | router #7 · Write | block | research-path blockers | (없음) | v6.1 WT spec 검증 · `.claude/skills/qvest-worktask/SKILL.md` |
| 7 | `worktask_sequence_enforcer.sh` | PreToolUse\[Agent\] · settings:L80-87 | block | research-path blockers | ` 2>>/tmp/worktask_seq.log \|\| true` | v6.1 WT 순차 실행 강제 (Level 3). 6-agent 는 v9 에서 자본 층 입구로만 남음 |
| 8 | `method_shopping_limiter.sh` | router #9 · Write | block | research-path blockers | ` 2>>/tmp/method_shopping.log \|\| true` | v6.1 R2 Selection Freedom 제약 |
| 9 | `role_objective_guard.sh` | router #10 · Write | block | research-path blockers | ` 2>>/tmp/role_objective.log \|\| true` | v6.1 R4 Role-specific Objective |
| 10 | `challenge_loop_limiter.sh` | router #11 · Write | warn/block | research-path blockers | ` 2>>/tmp/challenge_loop.log \|\| true` | v6.1 R3 Challenge Loop round 제한 |
| 11 | `dispatch_measurement_gate.sh` | router #16 · Write | block | research-path blockers | ` 2>>/tmp/dispatch_measurement_gate.log \|\| true` | FR 배분 실측 강제 · `.claude/rules/measurement-graduation.md` §1 |
| 12 | `ast_spec_gate.sh` | router #18 · Write | block (내부 오류도 fail-closed) | research-path blockers | ` 2>>/tmp/ast_spec_gate.log \|\| true` | `02_Infrastructure/docs/qvest_ast_v1_1_sot.md` par.7 (2026-07-25 도훈 승인). **해제 = 플랜 D-e** — QEPM 경로 전용, `ast_verify` 는 계약 경로에 존치 |
| 13 | `hypothesis_precheck_gate.sh` | router #19 · Write\|Edit | block (fail-closed) | research-path blockers | ` 2>>/tmp/hypothesis_precheck_gate.log \|\| true` | 2026-08-16 폐쇄루프 감사 구간⑫ 수리. v9 에서 Step 0 lookup 은 advisory 로 강등 |

### 3.3 router-only (5) — 라우터에만 있던 좁은 필드 검사

| # | 스크립트 | 구 등록 | 차단력 | 사유 범주 | 재등록 suffix | mandate·문서 |
|---|---|---|---|---|---|---|
| 14 | `feature_registry_economic_rationale_check.sh` | router #12 · Write\|Edit | block(필드 부재 시) | router-only | ` 2>>/tmp/feature_rationale.log \|\| true` | 7 Trends P1 · `02_Infrastructure/docs/rules/research_philosophy.md` |
| 15 | `risk_crowding_score_check.sh` | router #13 · Write\|Edit | block(필드 부재 시) | router-only | ` 2>>/tmp/risk_crowding.log \|\| true` | 7 Trends P5 · `research_philosophy.md` |
| 16 | `cache_registry_enforce.sh` | router #14 · Write\|Edit | block | router-only | ` 2>>/tmp/cache_registry_enforce.log \|\| true` | 도훈 mandate 2026-05-15 (신규 `.cache/*.parquet` registry entry 강제) |
| 17 | `factor_rotation_pit_guard.sh` | router #15 · Write\|Edit | advisory | router-only | ` 2>>/tmp/factor_rotation_pit_guard.log \|\| true` | `02_Infrastructure/docs/rules/factor-rotation.md` |
| 18 | `artifact_placement_guard.sh` | router #17 · Write\|Edit | advisory | router-only | ` 2>>/tmp/artifact_placement_guard.log \|\| true` | 2026-07-04 파일위생 mandate · `02_Infrastructure/docs/rules/artifact-storage.md` |

### 3.4 advisory noise (7) — 판정력 없이 매 쓰기에 붙던 경고

| # | 스크립트 | 구 등록 | 차단력 | 사유 범주 | 재등록 suffix | mandate·문서 |
|---|---|---|---|---|---|---|
| 19 | `answer_principles_grep.sh` | PostToolUse Write\|Edit · settings:L129-137 | warn | advisory noise | ` 2>>/tmp/answer_principles.log \|\| true` | `02_Infrastructure/docs/rules/answer-principles.md` 참조 절 (Level 2 soft alert) |
| 20 | `mandate_compliance_check.sh` | PostToolUse Write\|Edit · settings:L210-218 | warn (L2 soft) | advisory noise | (없음) | v6.2 unified mandate verifier (구 5훅 통합) |
| 21 | `rationalization_detector.sh` | PostToolUse Write\|Edit · settings:L219-227 | warn (L2 soft) | advisory noise | (없음) | Tier 4 자기합리화 문구 탐지 · `pit.md` 금지 표현 |
| 22 | `red_flag_detector.sh` | PostToolUse Write · settings:L156-164 | warn (L2 soft) | advisory noise | ` 2>>/tmp/red_flag_detector.log \|\| true` | Red Flag 감지 + `challenge_flags` 주입 |
| 23 | `dispatch_allocation_auditor.sh` | PostToolUse Write · settings:L119-128 | advisory | advisory noise | ` 2>>/tmp/dispatch_allocation_auditor.log \|\| true` | 도훈 2026-06-05 (FR 배분 산출물 구조 기록) |
| 24 | `ml_uncertainty_audit.sh` | PostToolUse Write · settings:L264-273 | advisory | advisory noise | ` 2>>/tmp/ml_uncertainty_audit.log \|\| true` | 7 Trends P3 · `research_philosophy.md` |
| 25 | `ml_cost_aware_audit.sh` | PostToolUse Write · settings:L274-283 | advisory | advisory noise | ` 2>>/tmp/ml_cost_aware_audit.log \|\| true` | 7 Trends P2 · `research_philosophy.md` |

### 3.5 side-effect & certifier (11) — 로그·인증서·부수효과 (PostToolUse = 구조상 차단 불가)

| # | 스크립트 | 구 등록 | 차단력 | 사유 범주 | 재등록 suffix | mandate·문서 |
|---|---|---|---|---|---|---|
| 26 | `pipeline_trigger.sh` | PostToolUse Write\|Bash · settings:L100-108 | side-effect | side-effect & certifier | ` >> /tmp/pipeline_trigger.log 2>&1 \|\| true` | V7 Pipeline Trigger. v8 이 읽지 않는 **레거시 mailbox 라우팅** (실측 발화량 최다 2종 중 하나) |
| 27 | `milestone_commit.sh` | PostToolUse Write · settings:L109-118 | side-effect (commit+push) | side-effect & certifier | ` 2>>/tmp/milestone_commit.log \|\| true` | v8.1.2 2026-06-11 도훈 confirm. v9 는 `SessionEnd` 커밋/푸시 1회로 대체 |
| 28 | `worktask_artifact_validator.sh` | PostToolUse Write · settings:L147-155 | warn (schema) | side-effect & certifier | ` 2>>/tmp/worktask_validator.log \|\| true` | v6.1 WT 3-package schema 검증 |
| 29 | `lockbox_audit_trail.sh` | PostToolUse **Read** · settings:L165-173 | log | side-effect & certifier | ` 2>>/tmp/lockbox_audit.log \|\| true` | `.claude/rules/pit.md` "Hook 계층"(2026-07-24 "유지" 승인). **해제 = 플랜 D-b** — 모든 Read 당 1프로세스인데 판정 기능 없음 |
| 30 | `forge_integration_audit.sh` | PostToolUse **Bash** · settings:L174-182 | log | side-effect & certifier | ` 2>>/tmp/forge_audit.log \|\| true` | v6.1 R12 Forge Integration Hash 감사 |
| 31 | `lockbox_post_judge_seal.sh` | PostToolUse Write · settings:L183-191 | side-effect (봉인) | side-effect & certifier | ` 2>>/tmp/lockbox_seal.log \|\| true` | v6.1 R2-B · `02_Infrastructure/docs/rules/lockbox-scope.md` |
| 32 | `lineage_recorder.sh` | PostToolUse Write · settings:L192-200 | log | side-effect & certifier | ` 2>>/tmp/lineage_recorder.log \|\| true` | v6.1 R11 lineage (git commit + input hash + seed) |
| 33 | `reproducibility_validator.sh` | PostToolUse Write · settings:L201-209 | flag | side-effect & certifier | ` 2>>/tmp/reproducibility.log \|\| true` | v6.1 R11 재현성 smoke flag |
| 34 | `schedule_fidelity_check.sh` | PostToolUse Write\|Edit · settings:L228-236 | cert 발급 | side-effect & certifier | ` 2>>/tmp/schedule_fidelity.log \|\| true` | v1.2 Schedule Fidelity Certifier. `state_transitions.json` 에서 `optional_artifacts` → WT 전이 무영향 |
| 35 | `sr_provenance_check.sh` | PostToolUse Write\|Edit · settings:L237-245 | cert 발급 | side-effect & certifier | ` 2>>/tmp/sr_provenance.log \|\| true` | v1.2 SR Provenance Certifier. 동일 — `optional_artifacts` |
| 36 | `alpha_discovery_certifier.sh` | PostToolUse Write\|Edit · settings:L246-254 | cert 발급 (passive deny) | side-effect & certifier | ` 2>>/tmp/alpha_discovery_certifier.log \|\| true` | v7.0 Sprint 1 router 위임. 동일 — `optional_artifacts` |

## 4. 집계 대조

| 구분 | 수 |
|---|---|
| v8 등록 distinct `.sh` (settings 직접 29 ∪ router 19, `safety_guard` 중복 1 제외) | 47 |
| v9 유지 | 11 |
| **해제 (본 원장)** | **36** |
| 범주별 | Stop blockers 2 · research-path blockers 11 · router-only 5 · advisory noise 7 · side-effect & certifier 11 |

## 5. 롤백

1. 전체 되돌리기: `git checkout pre-v9-lean-loop -- .claude/settings.json 02_Infrastructure/hooks/policies/router_dispatch.json`
2. 라우터만 되돌리기: 이 폴더의 `router_dispatch_v1.2.json` 을 `02_Infrastructure/hooks/policies/router_dispatch.json` 으로 복사 + `settings.json` PreToolUse 첫 그룹에 v8 라우터 command 재삽입(`settings.json.v8_20260823.json` L50-58).
3. 개별 1종만 되돌리기: §3 표의 `구 등록` matcher + `재등록 suffix` 로 위 조각을 만들어 해당 이벤트에 추가. **`.claude/settings.json` 의 `_doc*` 문자열에는 `.sh` 파일명을 쓰지 말 것** — `boot_currency_check.sh` C6 가 이 파일의 `[A-Za-z0-9_]+\.sh` 토큰을 세어 CLAUDE.md 선언과 대조하므로 주석에 적힌 이름이 총계를 부풀린다.
4. 되돌린 뒤 반드시 함께 갱신: `CLAUDE.md` 의 `settings.json N distinct .sh` 줄 · `harness_health.sh` `REQUIRED_HOOKS` · `hook_fire_coverage.sh` `EXPECTED_DEFAULT`/`UNCOVERED` · `memory_knowledge_health.R` W7.

## v10 (2026-08-29) — lockbox 제도 폐지 (도훈 지시 "lock box 개념은 삭제. 반박 금지")
- `lockbox_audit_trail.sh` / `lockbox_post_judge_seal.sh` / `selection_contamination_detector.sh` / `lockbox_paths.sh`: **영구 퇴역** (재등록 금지 — 제도 자체가 소멸). 파일은 RETIRED 배너와 함께 존치.
- 관련 R: `lockbox_paths.R`·`judge_oos_helper.R`·`judge_lockbox_harness.R` RETIRED, `windowing.R` 3-window 재작성(no-op stub), `v61_compliance_audit.R` P2 축 retired.
- 검사: `test_lockbox_audit_path.R` 퇴역(SUITES 제거).
- ⚠보존: `overlay_pit_guard.R`(C5 SIGNAL_CUTOFF = PIT 기계) + `overlay_pit_grep.sh` 등록 훅 — lockbox 아님, 무변경.
