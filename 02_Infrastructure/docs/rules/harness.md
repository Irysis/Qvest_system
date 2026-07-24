# Harness Engineering (Level 0)

**원칙**: 모든 프로세스 규칙은 프롬프트가 아닌 Hook으로 강제. "엄밀함은 사라지지 않고 이동한다."
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
| worktask_constraint_enforcer | 25종 + bounds [0, 0.20] + Σw=1 + long-only |
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

## 참조

- `02_Infrastructure/hooks/*.sh` (톱레벨 61개, s0_enforcer/ 서브디렉토리 포함 64 — 2026-07-24 실측. 구 표기 55는 stale)
- ~~`02_Infrastructure/hooks/_archive_v55/`~~ (Tier 1 cleanup 2026-05-16 삭제 — legacy v55 hooks 6건 영구 폐기)
- `.claude/settings.json` Hook 등록 (47 distinct .sh — v8.1.2 2026-06-11 기준, 아래 정합 절 참조. **v8.2 2026-06-30: codex_round_pre_enforcer + codex_round_auto_trigger 2건 등록 해제 → 45 distinct .sh**. **현행 2026-07-24: 48 distinct .sh** — 직접 32 + 라우터 dispatch 16, 아래 2026-07-24 정합 절)
- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (active SOT)
- `02_Infrastructure/docs/qvest_v6_4_sot.md` Section 5 (historical Hook + Cert Matrix. QEPM Codex Round 절은 v8.2에서 폐지 — 현재 미적용, 사료용)

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

- **등록 실측 (2026-07-24)**: settings.json **48 distinct .sh** = 직접 32 + 라우터 dispatch 16 (`sr_provenance_pre_certifier.sh` dispatch 해제 — 전 경로 `{}` 출력만 가능한 구조적 no-op 실증, 파일 FS retain·router_dispatch.json v1.1 _doc 참조).
- **주입취약 하드게이트 4훅 수리**: `worktask_spec_validator` · `method_shopping_limiter` · `challenge_loop_limiter` · `role_objective_guard` — `'''$CONTENT'''` 소스 보간이 triple-quote/백슬래시 content에서 fail-open이던 결함을 env-경유 + quoted heredoc으로 수리(v8.1.2 constraint_enforcer 선례 패턴). 적대 페이로드 실증 테스트 4/4 block 유지.
- **전달 0 훅 6종 복원**: `mandate_compliance_check` · `rationalization_detector`(0ab8b039 2026-05-29 회귀 — 감지하고도 `{}`만 출력) → PostToolUse `hookSpecificOutput.additionalContext` 실전달. `feature_registry_economic_rationale_check` · `risk_crowding_score_check` · `cache_registry_enforce`(감사 quick-win P2-2 이행) → 라우터 context 채널(`additionalContext` 단일키) 격상.
- **조기-exit 도입 (성능)**: Read 3훅(`selection_contamination_detector`/`covariance_freshness_gate`/`lockbox_audit_trail`) + W/E advisory 7훅에 python 파싱 전 raw-INPUT superset 필터 — 비매치 이벤트에서 python 스폰 0 (비매치 Read 실측 0.16s, 종전 ~0.8s/훅).
- **axiom_context_inject SyntaxError 수리**: 07-13 판정 어휘 규약 추가분의 미이스케이프 따옴표로 python -c 인자가 절단 → 전 Agent spawn 공리 주입이 `{}` 침묵 결손이던 결함 복원 (배터리 axiom_inject.context PASS, 2,482자 주입 확인).
- **milestone_commit 수리**: `git push origin master`(stale ref — milestone 커밋 원격 미도달) → 현재 브랜치 push. L-code 매치에 현행 계층 `stage_artifacts/l_code/<mode>/*.json` 추가. `forge_integration_audit` WT_DIR 절대경로 앵커(0-byte 스냅샷 수리).
- **검증**: `hook_e2e_battery` **11/11 PASS** (종전 10/11 — axiom_inject FAIL 포함).

## 정합 (2026-07-17 — 2주 운영 감사 카운트 실측 + 신규 훅 등재, 도훈 승인 수리)

- **등록 실측 (2026-07-17)**: settings.json **48 distinct .sh** = **직접 31** + **qvest_hook_router dispatch 경유 17**(`02_Infrastructure/hooks/policies/router_dispatch.json` 18건 − `safety_guard.sh` 직접등록 중복 1). 여기에 2026-07-17 `boot_stamp_check.sh` 신규 등록 포함 → **49 distinct .sh** (구 표기 45는 v8.2 시점, CLAUDE.md 구 표기 46은 research_continuity_guard까지만 반영한 드리프트 — 본 절로 정합).
- **v8.2(45) 이후 신규 3건**: `artifact_placement_guard.sh`(2026-07-04, PreToolUse[W/E] 라우터 dispatch — artifact-storage.md 저장위치 advisory warn only) / `overlay_pit_grep.sh`(2026-07-06, PostToolUse[W/E] — pit.md C5 오버레이 신호 타이밍 Level 2 soft advisory) / `research_continuity_guard.sh`(2026-07-13, Stop — 리서치 연속성 가드. 2026-07-15 Continuity Firewall warn→block 승격, SubagentStop `agent_stop_continuity_check.sh` 동반).
- **hook_e2e_battery 결과 영속화**: 배터리 실행 결과를 `.cache/hook_e2e_battery_latest.json`에 영속 기록 (2026-07-17 구현 — 최근 판정의 세션 간 관측성).

## v8.2 정합 (2026-06-30 — QEPM Codex Critic Round 제거, 도훈 mandate)

- **폐지 근거**: 메인 에이전트가 자체 적대검증(Self-Adversarial Challenge)을 수행 → 외부 Codex Critic Round 중복 (결정 당시 Opus 4.8, 현행 Fable 5 — 논거는 오히려 강화). QEPM 파이프라인에서 완전 제거.
- **등록 해제 (2건, settings.json)**: `codex_round_pre_enforcer`(구 Tier 1) / `codex_round_auto_trigger`(구 Tier 6). → settings.json distinct .sh 47 → **45**.
- **archive 이동**: `codex_round_pre_enforcer.sh` / `codex_round_auto_trigger.sh` / `codex_round_subagent_stop.sh` / `run_codex_qepm_critic.sh` / `policies/codex_round_contract.json` / `prompts/codex_*_critic_prompt.md` 7종 → `02_Infrastructure/hooks/_archive_codex_round_v8_2/` · `prompts/_archive_codex_round_v8_2/`.
- **AX-008 정합**: Verification Triangulation 3-source = Forge + **Self-Adversarial** + Architect (구 Codex 치환). 2/3 PASS 규칙 불변.
- **artifact**: `codex_critic_response_{role}.json` 명세 폐기 → `challenge_note.md`(self-adversarial record). state_transitions.json `codex_critic_response` required 제거.
- **보존(별개 시스템 — 영향 없음)**: S0 Debate codex(codex_critic / r2_codex_verdict / s0_enforcer) · RAMP "Codex"(K_RAMP Q-Lead+agents 역할명) · enabledPlugins `codex@openai-codex`(S0/RAMP codex CLI 사용) · 텔레그램 용어집 do-not-translate "Codex". ⚠ **2026-07-24 감사 실측 정정**: enabledPlugins 항목은 **유령 설정** — `~/.claude/plugins/installed_plugins.json`이 빈 상태(플러그인 미설치·codex-companion.mjs 디스크 부재)라 런타임 무효과. 보존 근거였던 "S0/RAMP codex CLI 사용"도 실체 없음(RAMP Codex=역할명, run_pit_intent_scan v2는 로컬 codex CLI로 이관, S0 stage 스킬 07-05 삭제). 해제는 본 v8.2 결정문의 번복이므로 도훈 confirm 대기 항목.

## v8.1.2 정합 (2026-06-11 — 등록 드리프트 전수 대조, 도훈 confirm)

- **등록 셋**: settings.json 47 distinct .sh (고스트 등록 0 — 등록분 전부 FS 실재). `milestone_commit.sh` **재등록**(PostToolUse[Write]) — 8674cb3 무언급 소실분 복구 (Stop hook 2종과 동일 사건, qvest.md Tier 3 주장과 정합 회복).
- **FS-only 미등록 (의도적, 5건)**: cash_sleeve_validator / circuit_breaker / trail_consistency_checker / attribution_quarterly_trigger / **role_taxonomy_admission_gate**(v55 Scout 전용 — v8.1 흐름 불일치로 강등 확정, 도훈 2026-06-11. 파일 retain).
- **등록 해제 documented (v53/v8.0 폐지)**: unified_agent_guard / task_complete_guard / teammate_idle_guard. **헬퍼/비-hook**: _shared_parse / resolve_project / harness_health / pit_v3_daemon.
- **agent_role_guard 복원**: MSYS ps가 `-o` 미지원이라 PARENT_PID 식별이 항상 실패 → 역할 경계 가드가 이 머신에서 상시 allow였음. bash 내장 `$PPID`로 교체 수리 (battery 13/13 검증).
- **회귀 배터리**: `02_Infrastructure/ops/hook_e2e_battery.py` — 등록 hook 한글 payload 블록/통과 13케이스. hook 파서/이스케이프 변경 시 실행 의무.

## v8.1.1 정합 (2026-06-10)

- settings.json 46개 hook DIR = `${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 3중 fallback (구 경로 glob 폐기 — 46-hook 전수 침묵사망 사건 수리)
- Stop hook 재등록: auto_commit_on_stop + auto_push_on_stop
- TeammateIdle/TaskCompleted (v53 전용) 등록 해제 — 스크립트 FS retain
- pre_enforcer에 codex stance=STUB 차단 추가 (AX-008 이중방어)
- bootstrap 카나리아: safety_guard block 실증 실패 시 BOOT_FAILS (침묵사망 재발 방지선)
- **차기 (1주 soak 후)**: qvest_hook_router.py 단일 진입 전환 — 이벤트당 1 spawn으로 Write당 35 spawn(~4.6s) 축소. policy JSON 4종은 기존재. soak 조건: 재시작 후 /tmp 로그 7일 무에러.
