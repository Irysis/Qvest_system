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

## v8.1.1 정합 (2026-06-10)

- settings.json 46개 hook DIR = `${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 3중 fallback (구 경로 glob 폐기 — 46-hook 전수 침묵사망 사건 수리)
- Stop hook 재등록: auto_commit_on_stop + auto_push_on_stop
- TeammateIdle/TaskCompleted (v53 전용) 등록 해제 — 스크립트 FS retain
- pre_enforcer에 codex stance=STUB 차단 추가 (AX-008 이중방어)
- bootstrap 카나리아: safety_guard block 실증 실패 시 BOOT_FAILS (침묵사망 재발 방지선)
- **차기 (1주 soak 후)**: qvest_hook_router.py 단일 진입 전환 — 이벤트당 1 spawn으로 Write당 35 spawn(~4.6s) 축소. policy JSON 4종은 기존재. soak 조건: 재시작 후 /tmp 로그 7일 무에러.
