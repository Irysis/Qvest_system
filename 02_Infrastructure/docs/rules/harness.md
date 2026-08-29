# Harness Engineering (Level 0)

**원칙 (v9 2026-08-23 개정)**: **훅은 자본/안전/PIT 경로에만 건다; 프로세스 규칙은 스킬·계약·문서로 강제한다.** 구 원칙("모든 프로세스 규칙은 프롬프트가 아닌 Hook으로 강제")은 등록 훅 47종·Write 팬아웃 37로 귀결돼 리서치 턴 자체를 예산 밖으로 밀어냈다 — 아래 "v9 정합" 절이 현행이고, 그 이전 Tier 표는 사료다.
**v8.1 active**: v6.4 hook router/4 policy JSON 구조를 흡수하고, 현재 SOT는 `qvest_v8_1_sot.md` + `qvest_modes_sot.md` 기준으로 해석한다.

## Tier 1 (전역 hard block)

| Hook | 이벤트 | 강제 대상 |
|---|---|---|
| safety_guard | PreToolUse[W/E/B] | 05_Production / 01_Literature 보호 |
| axiom_enforcement_hook | PreToolUse[W/E] | AX-code 공리 위반 (AX-001/002 warn+context, 나머지 block) |
| ~~codex_round_pre_enforcer~~ | ❌ **DEPRECATED 2026-06-30 (v8.2)** — QEPM Codex Critic Round 제거(Opus 4.8 자체 적대검증으로 대체). 스크립트 `_archive_codex_round_v8_2/`로 이동 · settings.json 미등록. final package 직접 작성 차단은 worktask_sequence_enforcer가 phase 전이로 cover |
| sr_provenance_check | PostToolUse[W/E] (settings.json 직접등록 — 사후 차단: 파일 기록 후 발화) | `ProductionSchedule[N]m` fabrication label hard block. (2026-07-24 정정: 구 표기 "(Pre)"는 오지시 — Pre측 별파일 sr_provenance_pre_certifier는 전 경로 `{}` no-op 실증으로 라우터 dispatch 해제, 파일 FS retain) |

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
| worktask_constraint_enforcer | 25종 + Σw=1 + long-only (v10: 비중 상한 폐지) |
| worktask_spec_validator | request.json schema (task_id format / universe / cost_model_version) |
| ast_spec_gate | AST v1.1 스펙 게이트 (2026-07-25 신설, 라우터 dispatch[Write]) — alpha_package*.json: v1.1은 mechanism 3필드·falsification(field_dictionary 내)·regime_scope·𝒪 밖 연산자·ast_verify FAIL_LOOKAHEAD(+검증계층 경보 `06_Registry/ast_gate_alerts.jsonl`) block / 구식 패키지는 advisory 통과. SOT `qvest_ast_v1_1_sot.md` §7 |
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
| (v10 퇴역) governor_concord_certifier → book_write_guard | BOOK 정본 직접 편집 + legacy book_state 재기입 차단 (PreToolUse) |

## Tier 6 (Self-Adversarial Challenge — v8.2: Codex Round 제거)

QEPM Codex Critic Round(외부 codex auto-spawn)는 **2026-06-30 v8.2에서 폐지**. 메인 에이전트(세션 모델 — 현행 Fable 5)가 자체 적대검증(Self-Adversarial Challenge)을 수행하므로 별도 hook 강제 없음. 적대검증 기록은 `challenge_note.md`(self-adversarial record)로 산출.

| Hook | 상태 |
|---|---|
| ~~codex_round_auto_trigger~~ | ❌ **DEPRECATED 2026-06-30 (v8.2)** — `_draft.json` async background codex spawn 폐지. 스크립트 `_archive_codex_round_v8_2/` 이동 · settings.json 미등록. (S0 Debate codex / RAMP Codex는 별개 시스템 — 영향 없음) |
| ~~codex_round_subagent_stop~~ | ❌ **DEPRECATED 2026-06-30 (v8.2)** — 동일 archive · 미등록 |

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

모든 command Hook에 `trap 'echo "{}"; exit 0' ERR`. (게이트급 4종은 아래 "Fail-open / Fail-closed 원칙" 예외 적용.)

**중요 (v8.0 2026-05-29 정정)**: allow/no-op 출력은 **`{}`** (빈 객체 = 통과). 구 패턴 `{"decision":"allow"}`는 **무효** — 현 Claude Code hook 스키마에서 `decision` 유효값은 `approve`/`block`뿐이라 `"allow"`는 "Invalid input at (root)" 검증오류(회색 노이즈) 유발. 차단은 `{"decision":"block","reason":...}` 또는 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":...}}`. 전 hook 147건 일괄 정정 완료.

## Fail-open / Fail-closed 원칙 (2026-07-03 도훈 confirm, 아키텍처 감사)

- **기본 = fail-open**: hook 내부 오류(파싱 실패·의존성 부재 등)는 ERR trap `{}`로 통과 — 인프라 장애가 리서치 흐름을 막지 않는다.
- **게이트급 4종 예외 = fail-closed**: `safety_guard` · `backtest_contract_audit` · `legacy_write_block` · `discovery_graduation_gate`는 **내부 오류 시 보호대상 경로 write에 한해 block** (오류 = 침묵 통과가 아니라 차단). 근거: discovery_graduation_gate cp949 read 실패 → graduation HARD 침묵 우회 가능 상태였던 실사고 (위 "fail-closed 의무" 절, 06-11 수리).
- **QVEST_SKIP_* 감사 의무**: `QVEST_SKIP_*` 환경변수로 hook을 우회할 때는 사용 내역(변수명·시각·사유)을 `06_Registry/hook_skip_audit.log`에 기록 의무.

## v6.4 진화 (Sprint 2 Phase 4)

신규 `qvest_hook_router.py` 단일 진입 + policy JSON:
- `02_Infrastructure/hooks/policies/state_transitions.json` (WT phase 전이)
- `02_Infrastructure/hooks/policies/role_permissions.json` (agent 역할 경계)
- ~~`02_Infrastructure/hooks/policies/codex_round_contract.json`~~ — ❌ **DEPRECATED 2026-06-30 (v8.2)** QEPM Codex Round 폐지로 `_archive_codex_round_v8_2/` 이동
- `02_Infrastructure/hooks/policies/cert_rules.json` (5 cert eligibility)

→ 각 hook이 정규식 중복 보유 안 함, 동일 policy JSON 참조.

## Worktree 생명주기 + 좌초 수리 감시 (2026-07-25 신규 — 도훈 승인 next_probe ②③)

**문제**: 병렬 세션이 worktree에서 수리를 완료하고도 커밋·병합하지 않으면 세션 종료와 함께 사실상 유실된다. `bootstrap.sh`에 git 점검이 **0건**이라 이 상태가 어디에도 안 보였고, 동일 패턴 실사고 2건(benchmark date32 writer 6일 방치 · lcode_harvester family 수리)의 공통 근본원인이었다.

**2단 감시**:
| 계층 | 위치 | 시점 | 범위 |
|---|---|---|---|
| 부팅 WARN | `bootstrap.sh` §4h | 세션 시작 | 존재/개수/방치일 (경량, ~6s) |
| 감사 + 경보 | `ops/stranded_repairs_audit.sh` | 무인 daily 12:00·20:00 (`Qvest_StrandedRepairs`) | 파일 단위 triage + 충돌 + prune 후보 (2026-08-13 미병합 커밋 편입 후 수 분 대. 구 "~16s"는 미커밋만 보던 시절 값) |

**triage 대상** (2026-08-13 확장): 미커밋(`git status --porcelain`) **∪ 미병합 커밋**(`main...<branch>`). 상태코드에 `B` 가 붙으면 후자 출처(양쪽이면 `M+B`).
> ★확장 이유 — 구판은 미커밋만 봤다. 그런데 Stop 훅 auto-commit 이 세션 변경분을 **자기 브랜치에** 커밋하므로, 파일이 dirty→committed 로 옮겨가는 순간 유실 계수에서 사라진다(main 엔 여전히 없는데). 실측 08-13: 경보는 "유실 4" 인데 미병합 커밋의 main-부재 파일이 **257건**이었고, 08-09 "유실 29"가 08-13 "4"로 준 것도 수리가 아니라 **커밋되어 조용해진** 것이었다. 경보가 줄어든 것과 문제가 고쳐진 것은 겉보기가 같다.

**triage 판정** (변경의 추가 라인이 main 파일에 존재하는가):
- `merged_upstream` — 전량 존재. worktree는 stale 사본, 정리 가능
- `lost` — 전무. main에 없는 진짜 유실 ★조치
- `mostly_lost` — 80%+ 미존재. 사실상 유실 ★조치
- `partial` — 일부만. 별도 경로 반영 또는 충돌 — 수동 확인
- `deletion_only` — 삭제만
- `ledger_divergence` / `scratch_artifact` / `superseded_upstream` — 수리가 아님, 경보 제외 (2026-08-08)

**방향(supersede) 판정 = 시각 + 내용 둘 다** (2026-08-13):
`superseded_upstream` 은 ① main 이 그 경로를 나중에 갱신했고 ② **`main_extra_lines` ≥ `missing_in_main`** 일 때만 발급한다. ②가 없으면 시각만으로 방향을 정하게 되는데, triage 는 "이 줄들이 main 에 있나"를 묻고 recency 는 "이 경로를 나중에 손댔나"를 물어 **질문이 다르다** — bulk auto-commit 한 번이면 무조건 "나중"이 된다.
> ★실사고 08-13: `frontier_queue_io.R` 의 CAS·뮤텍스·churn 예산 **162줄**(FQ-122 갱신 2회 유실의 직접 대응)이, main 쪽 무관한 `perl=TRUE` **10줄** 커밋이 더 최신이라는 이유로 `superseded` 로 접혀 경보에서 사라졌다. 그동안 프론티어 큐 writer 는 CAS 없이 돌았다. 근거 수치는 `main_extra_lines` 로 산출물에 남는다.

**계약검사**: `08_Tests/hooks/test_stranded_triage.sh` (18축 — 양성 대조 + 위반 주입 4종 + **돌연변이가 실제로 적용됐는지** 자체를 확인하는 `mutate()` 가드).

**충돌 탐지**: 2개 이상 worktree가 같은 파일을 main 밖에서 수정 중이면 `collisions`에 등재. 병합 순서를 정하지 않으면 뒤에 병합되는 쪽이 앞을 덮는다. 미커밋 + 미병합 커밋 양쪽 모두 대상.

**생명주기 규약**:
1. worktree 작업이 끝나면 **커밋까지가 완료**다. 미커밋 = 미완료.
2. 방치 임계 **3일** — 초과 시 부팅 WARN + 감사 경보.
3. prune 대상 = 미커밋 0 ∧ 미병합 0 (작업이 전부 main에 있음).
4. **자동 prune 금지** — 클린해도 활동 중 세션의 cwd일 수 있다. `--prune` 명시 실행만. `git worktree remove`가 dirty면 자체 거부(2중 안전).
5. 감사기는 worktree에 **절대 쓰지 않는다**(status/diff/rev-list/log만). 타 세션 무간섭.

**산출**: `06_Registry/stranded_repairs.json` (레지스트리) · `.cache/scheduler_logs/stranded_repairs.log` (heartbeat — `--quiet`여도 요약 1줄은 항상 기록. 무인 로그가 비면 침묵 실패와 구분 불가).

**경보**: 유실 또는 충돌 감지 시 `tg_agent_brief()` 경유 텔레그램, 같은 날 1회 스로틀(`.cache/stranded_alert_YYYYMMDD.marker`).

## 참조

- `02_Infrastructure/hooks/*.sh` (톱레벨 61개, s0_enforcer/ 서브디렉토리 포함 64 — 2026-07-24 실측. 구 표기 55는 stale)
- ~~`02_Infrastructure/hooks/_archive_v55/`~~ (Tier 1 cleanup 2026-05-16 삭제 — legacy v55 hooks 6건 영구 폐기)
- `.claude/settings.json` Hook 등록 — **현행 v9 2026-08-23: 11 distinct .sh**(직접 등록만, 라우터 dispatch 폐지. 목록·근거 = 바로 아래 "v9 정합" 절 + `02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md`). 이하 괄호는 **사료**: (47 distinct .sh — v8.1.2 2026-06-11 기준, 아래 정합 절 참조. **v8.2 2026-06-30: codex_round_pre_enforcer + codex_round_auto_trigger 2건 등록 해제 → 45 distinct .sh**. **현행 2026-07-25: 46 distinct .sh** — 직접 29 + 라우터 dispatch 17 (2026-07-25 `ast_spec_gate.sh` dispatch 등재, AST v1.1 Step 3 — settings.json 재등록 불필요·router_dispatch.json만 개정). 2026-07-24 정합 절 참조)
- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (active SOT)
- `02_Infrastructure/docs/qvest_v6_4_sot.md` Section 5 (historical Hook + Cert Matrix. QEPM Codex Round 절은 v8.2에서 폐지 — 현재 미적용, 사료용)

## v9 정합 (2026-08-23 — Lean Loop 감산, 도훈 결정 ④)

**등록 = 11 distinct .sh (직접 등록만 — 라우터 dispatch 폐지).** 남긴 기준은 하나다: **자본·안전·PIT 경로**. 프로세스 규칙(연속성·실측어휘·역할경계·AST·인증서)은 훅에서 내려 스킬·계약·문서로 옮겼다 — 해제분 36종은 **파일 삭제 없이** `02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md`(이름·구 등록 위치·사유·재등록 레시피)와 구 settings/router JSON 사본에 보존한다.

| # | 훅 | 남긴 사유 |
|---|---|---|
| 1 | `safety_guard.sh` | 프로덕션 폴더 / `01_Literature` 쓰기 차단 (W/E/Bash) |
| 2 | `legacy_write_block.sh` | 아카이브·legacy 경로 read-only |
| 3 | `discovery_graduation_gate.sh` | 자본 게이트 — HARD 3종 fail-closed |
| 4 | `worktask_constraint_enforcer.sh` | 고정 축 7종(≤25종·long-only·Σw=1 …) |
| 5 | `telegram_direct_call_guard.sh` | 텔레그램 단일 진입점(`tg_agent_brief()`) |
| 6 | `axiom_context_inject.sh` | 에이전트 지식 주입(≤2,000자, 컨텍스트) |
| 7 | `book_write_guard.sh` | ★v10 승계 — BOOK 정본·legacy book_state 쓰기 차단(writer 경유 강제) |
| 8 | `overlay_pit_grep.sh` | PIT C5 오버레이 타이밍 advisory |
| 9 | `boot_stamp_check.sh` | SessionStart "/qvest 권장" 넛지 |
| 10 | `auto_commit_on_stop.sh` | 세션당 1회 커밋 |
| 11 | `auto_push_on_stop.sh` | 세션당 1회 푸시 |

**Stop 차단 훅 0** — `research_continuity_guard.sh`·`performance_realmeasure_gate.sh` 등록 해제(연속성 계약은 L-code 발행 1지점으로 이동, `continuity-firewall.md` SUSPENDED 배너 참조). `lockbox_audit_trail.sh`(모든 Read)·`ast_spec_gate.sh`·`backtest_contract_audit.sh`·`agent_role_guard.sh`·인증서 4종도 해제 — **룰·계약 텍스트는 존치**하며 위반 판정은 R 계약(`essence_score`/`registry_writer`/`build_bt_result`)과 judge·수동 confirm 이 계속 담당한다.

## Hook 정합 audit (2026-05-16)

- **FS only / 미등록 (5건)**: cash_sleeve_validator (legacy v55) / circuit_breaker / milestone_commit / trail_consistency_checker / attribution_quarterly_trigger (advisory)
- **Deprecated 2026-05-16 (2건)**: forge_code_guard / risk_gate (`_archive_v55/` Tier 1 cleanup 삭제)
- **Phase 1/2 신규 등록 (4건)**: feature_registry_economic_rationale_check / ml_cost_aware_audit / ml_uncertainty_audit / risk_crowding_score_check
- **Active loaded**: 45 distinct .sh (settings.json registered)

## Bash 출력 Unicode 규율 (v8.1.2 2026-06-11 — API 400 invalid high surrogate 방지)

- **원인 체계**: Claude Code는 Bash tool 출력을 JS(UTF-16) 문자열로 보관 후 약 30k자에서 절단. non-BMP 문자(U+10000+, 이모지)는 surrogate pair 2 code-unit → 절단점에 걸리면 lone surrogate → JSON 직렬화 RFC 8259 위반 → Anthropic API 400. invalid UTF-8 byte 유입도 동일 계열 (anthropics/claude-code#44230 · #16294 · #15027 — closed as not planned, 공식 미수정).
- **방어선**:
  1. `02_Infrastructure/ops/utf8_output_guard.py` — invalid byte + non-BMP + U+FFFD → '?' 줄단위 정제 (BMP-only 유효 UTF-8 보장 → 어떤 절단에도 안전)
  2. bootstrap.sh 자체 재실행 래퍼 (`QVEST_BOOT_SANITIZED`) — 부트 출력 전체(자식 R/Python/백그라운드 포함) 가드 경유. `[boot] utf8_output_guard: ACTIVE` 확인
  3. 임의 커맨드: `bash 02_Infrastructure/ops/safe_run.sh <cmd> [args...]` (exit code 보존)
- **작성 규율**: transcript에 닿는 출력(echo/cat/print)에 **non-BMP 이모지 금지**. BMP 기호(✓ ✅ ❌ ⛔ ★ U+FFFF 이하)는 surrogate-safe하나, 장식은 ASCII 권장. 백그라운드 job은 stdout까지 로그 파일로 리다이렉트 (cleanup.sh 누수 사례 — 비동기 끼어들기 + 파이프 hold). 큰 로그 열람(tail/cat)은 safe_run.sh 경유.
- PostToolUse hook은 tool 출력을 **재작성할 수 없으므로** hook 기반 sanitize는 불가 — 소스/파이프 레벨이 유일한 방어선.

### Hook stdout JSON 규율 (v8.1.2 추보 — 실제 근본 원인, 2026-06-11 확정)
- **실측 진범**: Bash tool 출력이 아니라 **hook의 additionalContext**. `printf '%s' "$MSG" | python3 -c "...json.dumps(sys.stdin.read())"` 패턴에서 hook 런타임의 python text-mode stdin이 UTF-8 한글/이모지를 cp949+surrogateescape로 디코딩 → lone surrogate(\udcXX)를 json.dumps가 그대로 escape 출력 → Claude Code가 대화에 주입 → **그 세션의 모든 후속 요청 400** (위치 고정, 재시도 무효). transcript에는 fs 기록 시 U+FFFD/escape로 남아 1차 스캔을 회피. 오염원 6: auto_commit_on_stop / auto_push_on_stop(Stop마다) · axiom_context_inject(Agent spawn마다) · milestone_commit · role_taxonomy_admission_gate · unified_agent_guard. 세션 8개 오염 실측(06-10 Stop hook 재등록 직후 발병).
- **의무 패턴 (hook이 stdout JSON에 문자열을 실을 때)**: ① bash 변수 → python은 반드시 **`sys.stdin.buffer.read().decode('utf-8','replace')`** (bytes 경유 — locale 레이어 우회) ② **surrogate 스크럽** `0xD800-0xDFFF → '?'` 후 json.dumps ③ hook 상단 `export PYTHONUTF8=1` ④ python `open()`은 read/write 공히 `encoding='utf-8'` 명시. 표준 one-liner는 auto_commit_on_stop.sh 참조. **주의(감사 실증 06-11)**: PYTHONUTF8=1 단독은 불충분 — PEP 540 UTF-8 모드는 stdin errors를 surrogateescape로 설정해 invalid byte가 여전히 surrogate화되고, PYTHONIOENCODING이 있으면 그게 우선한다. **buffer+스크럽 패턴만이 완전 방어** (①②가 본체, ③④는 보조).
- **fail-closed 의무 (게이트 hook의 파일 read)**: `open(...)` 실패가 ERR trap `{}`로 빠지면 **게이트가 침묵 통과**된다 (discovery_graduation_gate 실사고 — 한글 alpha_package 95/112개가 cp949 read 실패 → graduation HARD 우회 가능 상태였음, 06-11 수리). 게이트 판정에 필요한 파일은 try/except로 감싸 **읽기 실패 = block** 처리. content의 heredoc 소스 보간(`'''$CONTENT'''`)은 주입형 — env 변수 경유로 전달.
- **안전한 경로 (오탐 방지)**: bash가 스크립트 파일 내 한글 literal을 **직접 echo**하는 것은 안전 (python text 레이어 없음 — Node가 UTF-8로 정상 디코딩). Bash tool의 일반 커맨드 CP949 출력도 Node lossy decode가 U+FFFD로 안전 처리 (400 원인 아님 — 가독성만 손실, safe_run.sh 권장).
- **환경 영구화**: `setx PYTHONUTF8 1` 적용(2026-06-11, user env) — Claude Code 재시작 후 모든 hook/python에 전파. hook 내 export는 재시작 전에도 유효한 2중 방어.
- **오염 세션 복구**: lone surrogate가 박힌 transcript는 해당 세션 영구 400. 복구 = jsonl 백업 후 string 값 내 surrogate → '?' 스크럽 (06-11 8개 세션 실시, `*.surrogate_bak` 보존).

## 정합 (2026-07-24 — Fable 5 하네스 전수 감사, 57-agent 워크플로우 + 2-렌즈 적대검증)

- **등록 실측 (2026-07-24, 2차 반영 현행 = 45 distinct)**: 1차 감사 시점 48 distinct .sh(직접 32 + 라우터 16, `sr_provenance_pre_certifier.sh` dispatch 해제 — 전 경로 `{}` no-op 실증) → 동일자 2차 C2/C9로 직접 29 + 라우터 16 = **45 distinct** (아래 2차 항목).
- **주입취약 하드게이트 4훅 수리**: `worktask_spec_validator` · `method_shopping_limiter` · `challenge_loop_limiter` · `role_objective_guard` — `'''$CONTENT'''` 소스 보간이 triple-quote/백슬래시 content에서 fail-open이던 결함을 env-경유 + quoted heredoc으로 수리(v8.1.2 constraint_enforcer 선례 패턴). 적대 페이로드 실증 테스트 4/4 block 유지.
- **전달 0 훅 6종 복원**: `mandate_compliance_check` · `rationalization_detector`(0ab8b039 2026-05-29 회귀 — 감지하고도 `{}`만 출력) → PostToolUse `hookSpecificOutput.additionalContext` 실전달. `feature_registry_economic_rationale_check` · `risk_crowding_score_check` · `cache_registry_enforce`(감사 quick-win P2-2 이행) → 라우터 context 채널(`additionalContext` 단일키) 격상.
- **조기-exit 도입 (성능)**: Read 3훅(`selection_contamination_detector`/`covariance_freshness_gate`/`lockbox_audit_trail`) + W/E advisory 7훅에 python 파싱 전 raw-INPUT superset 필터 — 비매치 이벤트에서 python 스폰 0 (비매치 Read 실측 0.16s, 종전 ~0.8s/훅).
- **axiom_context_inject SyntaxError 수리**: 07-13 판정 어휘 규약 추가분의 미이스케이프 따옴표로 python -c 인자가 절단 → 전 Agent spawn 공리 주입이 `{}` 침묵 결손이던 결함 복원 (배터리 axiom_inject.context PASS, 2,482자 주입 확인).
- **milestone_commit 수리**: `git push origin master`(stale ref — milestone 커밋 원격 미도달) → 현재 브랜치 push. L-code 매치에 현행 계층 `stage_artifacts/l_code/<mode>/*.json` 추가. `forge_integration_audit` WT_DIR 절대경로 앵커(0-byte 스냅샷 수리).
- **검증**: `hook_e2e_battery` **11/11 PASS** (종전 10/11 — axiom_inject FAIL 포함).
- **[동일자 2차 — 도훈 승인 C2~C4·C7~C10 실행]**: ① **C2** selection_contamination_detector·covariance_freshness_gate (PreToolUse Read 2건) 등록 해제 — 구조적 상시-allow/무전달 실증, 파일 FS retain, harness_health REQUIRED_HOOKS·pit.md Lockbox 절 동기 개정. lockbox_audit_trail(PostToolUse Read)만 잔존 = Read 이벤트 훅 3→1. ② **C9** agent_stop_continuity_check (SubagentStop) 등록 해제 — 생애 발화 0·escalate 무전달·Continuity Firewall SOT 미등재. SubagentStop 이벤트 등록 0. ③ **C10** milestone_commit s7_disposition·pg2_allocation legacy 레인 제거(AX·L-code 레인 보존). ④ **C7** execution·monitoring `model: opus` 재핀(기계적 역할 비용 차등 — caching.md 예외 2종). ⑤ **C3** 스킬 정리: execution/monitoring=skillOverrides off · 리서치 3종=user-invocable-only+리다이렉트 스텁 · bootstrap 라벨 갱신. ⑥ **C4** kr-inverse-pattern-miner 현행 경로 재작성(hypothesis_index+Distilled+FQ 등재, INV-7 규약 내장). ⑦ **C8** 무인 스케줄러 3종(alpha_search_queue/paper_router/factor_deep_recheck) spend_limit 감지 시 `--model opus` 폴백 배선. → **등록 = 45 distinct .sh (직접 29 + 라우터 16)**.

## 정합 (2026-07-17 — 2주 운영 감사 카운트 실측 + 신규 훅 등재, 도훈 승인 수리)

- **등록 실측 (2026-07-17)**: settings.json **48 distinct .sh** = **직접 31** + **qvest_hook_router dispatch 경유 17**(`02_Infrastructure/hooks/policies/router_dispatch.json` 18건 − `safety_guard.sh` 직접등록 중복 1). 여기에 2026-07-17 `boot_stamp_check.sh` 신규 등록 포함 → **49 distinct .sh** (구 표기 45는 v8.2 시점, CLAUDE.md 구 표기 46은 research_continuity_guard까지만 반영한 드리프트 — 본 절로 정합).
- **v8.2(45) 이후 신규 3건**: `artifact_placement_guard.sh`(2026-07-04, PreToolUse[W/E] 라우터 dispatch — artifact-storage.md 저장위치 advisory warn only) / `overlay_pit_grep.sh`(2026-07-06, PostToolUse[W/E] — pit.md C5 오버레이 신호 타이밍 Level 2 soft advisory) / `research_continuity_guard.sh`(2026-07-13, Stop — 리서치 연속성 가드. 2026-07-15 Continuity Firewall warn→block 승격. 구 동반 표기였던 SubagentStop `agent_stop_continuity_check.sh`는 2026-07-24 C9로 등록 해제 — Firewall SOT에 미등재·발화 0이던 별개 v6.2 산물).
- **hook_e2e_battery 결과 영속화**: 배터리 실행 결과를 `.cache/hook_e2e_battery_latest.json`에 영속 기록 (2026-07-17 구현 — 최근 판정의 세션 간 관측성).

## v8.2 정합 (2026-06-30 — QEPM Codex Critic Round 제거, 도훈 mandate)

- **폐지 근거**: 메인 에이전트가 자체 적대검증(Self-Adversarial Challenge)을 수행 → 외부 Codex Critic Round 중복 (결정 당시 Opus 4.8, 현행 Fable 5 — 논거는 오히려 강화). QEPM 파이프라인에서 완전 제거.
- **등록 해제 (2건, settings.json)**: `codex_round_pre_enforcer`(구 Tier 1) / `codex_round_auto_trigger`(구 Tier 6). → settings.json distinct .sh 47 → **45**.
- **archive 이동**: `codex_round_pre_enforcer.sh` / `codex_round_auto_trigger.sh` / `codex_round_subagent_stop.sh` / `run_codex_qepm_critic.sh` / `policies/codex_round_contract.json` / `prompts/codex_*_critic_prompt.md` 7종 → `02_Infrastructure/hooks/_archive_codex_round_v8_2/` · `prompts/_archive_codex_round_v8_2/`.
- **AX-008 정합**: Verification Triangulation 3-source = Forge + **Self-Adversarial** + Architect (구 Codex 치환). 2/3 PASS 규칙 불변.
- **artifact**: `codex_critic_response_{role}.json` 명세 폐기 → `challenge_note.md`(self-adversarial record). state_transitions.json `codex_critic_response` required 제거.
- **보존(별개 시스템 — 영향 없음)**: S0 Debate codex(codex_critic / r2_codex_verdict / s0_enforcer) · RAMP "Codex"(K_RAMP Q-Lead+agents 역할명) · enabledPlugins `codex@openai-codex`(S0/RAMP codex CLI 사용) · 텔레그램 용어집 do-not-translate "Codex". ⚠ **2026-07-24 감사 실측 정정 + 해제 (도훈 승인 C1)**: enabledPlugins 항목은 **유령 설정**이었음 — `~/.claude/plugins/installed_plugins.json`이 빈 상태(플러그인 미설치·codex-companion.mjs 디스크 부재)라 런타임 무효과, 보존 근거였던 "S0/RAMP codex CLI 사용"도 실체 없음(RAMP Codex=역할명, run_pit_intent_scan v2는 로컬 codex CLI로 이관, S0 stage 스킬 07-05 삭제). **settings.json에서 해제 완료** (2026-07-24 도훈 승인 — DEPRECATION.md 동시 개정. 로컬 codex CLI·debate_helpers는 FS retain).

## v8.1.2 정합 (2026-06-11 — 등록 드리프트 전수 대조, 도훈 confirm)

- **등록 셋**: settings.json 47 distinct .sh (고스트 등록 0 — 등록분 전부 FS 실재). `milestone_commit.sh` **재등록**(PostToolUse[Write]) — 8674cb3 무언급 소실분 복구 (Stop hook 2종과 동일 사건, qvest.md Tier 3 주장과 정합 회복).
- **FS-only 미등록 (의도적, 5건)**: cash_sleeve_validator / circuit_breaker / trail_consistency_checker / attribution_quarterly_trigger / **role_taxonomy_admission_gate**(v55 Scout 전용 — v8.1 흐름 불일치로 강등 확정, 도훈 2026-06-11. 파일 retain).
- **등록 해제 documented (v53/v8.0 폐지)**: unified_agent_guard / task_complete_guard / teammate_idle_guard. **헬퍼/비-hook**: _shared_parse / resolve_project / harness_health / pit_v3_daemon.
- **agent_role_guard 복원**: MSYS ps가 `-o` 미지원이라 PARENT_PID 식별이 항상 실패 → 역할 경계 가드가 이 머신에서 상시 allow였음. bash 내장 `$PPID`로 교체 수리 (battery 13/13 검증).
- **회귀 배터리**: `02_Infrastructure/ops/hook_e2e_battery.py` — 등록 hook 한글 payload 블록/통과 13케이스. hook 파서/이스케이프 변경 시 실행 의무.

## 스위트 총계 래칫 (2026-07-25 신설 · 07-26 갱신)

계측 사망은 실패로 드러나지 않고 **총계가 조용히 줄어드는** 형태로 온다(실사고 3건: hooks 27→0이 "✅ ALL PASS"로 위장 / regime 5→0 / continuity 31→9). 잡히는 유일한 신호가 총계 감소다.

- 감시기 `02_Infrastructure/ops/suite_totals_watch.sh` — `--collect`(4 러너 실행) → `--baseline`(승격) → `--check`(비교, exit 1 = 감소). 기준선 = `06_Registry/suite_totals_baseline.json`.
- **fail 축 동시 수집**(2026-07-26): `total = pass + fail` 구조라 FAIL이 나도 총계는 불변 → 회귀가 감시를 그냥 통과했다. `*_fail > 0`도 exit 1.
- 수집 실패는 **0이 아니라 null**로 기록하고, null 포함 시 **기준선 승격을 거부**한다(불완전 수집을 기준선으로 삼으면 이후 감소를 영영 못 잡는다).
- **현행 기준선 실측 (2026-07-26 21:05)**: `hooks 266`(suite 14) · `regime 5` · `contract_regression 54` · `continuity 31`, fail 축 전부 0. 이력 27 → 34 → 57 → 157 → 182 → 225 → **266** (4트랙 SUITES 편입마다 재승격).
- **차단 실효 실측**: SUITES에서 임의 1 suite 제거 후 재수집 → `hooks 266 → 225 (-41)` 경보 + exit 1 발화 확인, 원복(diff 0). ★기준선이 실측보다 낮으면 래칫은 조용히 무력하므로, **SUITES 편입 후 재승격은 의무**.

## 종료코드 판정 테스트의 사전 점검 의무 (2026-08-02 신설 — 실사고)

총계 래칫이 **못 잡는** 계측 사망이 있다: 총계는 그대로고 pass/fail 만 이동하는 형태다.
`test_deployed_holdings_check.sh` 가 14/14 FAIL(전 케이스 uniform `exit 49`)이었는데, 원인은 검거 실패가
아니라 **검사기 미실행**이었다(worktree 에 venv junction 부재 → bare `python3` = Windows Store 스텁).

★핵심은 다음 변종이다: `-x` 만 보고 인터프리터를 채택하면 **pandas 없는 인터프리터**가 뽑혀
`ModuleNotFoundError` → **rc=1** 이 나오는데, rc=1 은 "위반을 검거했다"의 기대값이다.
돌연변이 실측 = 완전히 죽은 검사기가 **10 pass / 4 fail**. uniform 49 는 이상해 보이지만
10/14 는 "대체로 동작"으로 읽힌다 — 은폐도가 더 높다.

- **종료코드로 판정하는 테스트는, 죽은 프로세스의 rc 가 성공 기대값과 겹치는지를 먼저 물을 것.**
- 인터프리터는 실행 가능(`-x`)이 아니라 **기능 프로브**(필요 모듈 import)로 채택한다.
  bare `python3`/`python` 은 후보에서 제외한다(Store 스텁, rc 49). cf. [[reference-python3-windows-stub-use-qvest-py]]
- 케이스 실행 *전에* **카나리아**(검사 대상 `--help` → rc 0 + 기대 문자열)로 계측 생존을 확정하고,
  실패 시 케이스 결과를 **발행하지 않고** `{"pass":0,"fail":1,"preflight":"<사유>"}` 로 끊는다.
  0/N 은 반드시 "검거 실패"로 오독되기 때문이다.
- 사전 점검 자체도 **위반 주입**으로 고정한다(죽은 인터프리터·죽은 검사기 주입 → 발화 확인).
  주입 대상은 실물이 없으면 **합성**할 것 — "주입 대상 부재 → 자동 통과"는 같은 계통의 새 구멍이다.

정본 구현 = `08_Tests/portfolio/test_deployed_holdings_check.sh`(T14~T16 축). 상세: 메모리
[[project-dead-checker-exitcode-collision-20260802]].

## v8.1.1 정합 (2026-06-10)

- settings.json 46개 hook DIR = `${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 3중 fallback (구 경로 glob 폐기 — 46-hook 전수 침묵사망 사건 수리)
- Stop hook 재등록: auto_commit_on_stop + auto_push_on_stop
- TeammateIdle/TaskCompleted (v53 전용) 등록 해제 — 스크립트 FS retain
- pre_enforcer에 codex stance=STUB 차단 추가 (AX-008 이중방어)
- bootstrap 카나리아: safety_guard block 실증 실패 시 BOOT_FAILS (침묵사망 재발 방지선)
- **차기 (1주 soak 후)**: qvest_hook_router.py 단일 진입 전환 — 이벤트당 1 spawn으로 Write당 35 spawn(~4.6s) 축소. policy JSON 4종은 기존재. soak 조건: 재시작 후 /tmp 로그 7일 무에러.
