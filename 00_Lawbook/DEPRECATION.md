# Qvest Deprecation Inventory

**Effective**: 2026-05-01 (v7.0 Sprint 5)
**Plan**: nifty-tickling-hinton.md Sprint 5

본 문서는 Qvest active path와 legacy 자산을 분리. legacy는 격리 후 점진 archive.

## v55 Legacy (already archived in `_archive_v55/`)

| 자산 | 위치 | Replacement | Status | EOL Plan |
|---|---|---|---|---|
| s0_debate_enforcer.sh | `02_Infrastructure/hooks/_archive_v55/` | v6.0 codex_round_pre_enforcer + codex_round_auto_trigger | ARCHIVED (settings.json 미등록) | retain — read-only block |
| s0_debate_guard.sh | `_archive_v55/` | v6.0 codex_round 통합 | ARCHIVED | retain — read-only block |
| s0_verdict_router.sh | `_archive_v55/` | v6.0 worktask_sequence_enforcer | ARCHIVED | retain — read-only block |
| artifact_validator.sh | `_archive_v55/` | v6.4 worktask_artifact_validator (renamed) | ARCHIVED | retain — read-only block |
| forge_code_guard.sh | `_archive_v55/` | v6.4 backtest_contract_audit | ARCHIVED | retain — read-only block |
| risk_gate.sh | `_archive_v55/` | v6.4 risk-research agent + Σ shrinkage Hook | ARCHIVED | retain — read-only block |

## v55 Legacy 등록/참조 제거 history

### v7.0 Sprint 5 — settings.json 등록 제거
| Hook | Replacement | Action |
|---|---|---|
| role_taxonomy_admission_gate | v6.4 unified_agent_guard + agent_role_guard 통합 | settings.json 등록 제거 (v7.0) → 파일은 retain (file 이동은 v7.1+ 이연) |

### v7.1-lite Sprint 0.3 — harness_health.sh required list 제거
| Hook | 이전 위치 | 제거 사유 |
|---|---|---|
| role_taxonomy_admission_gate.sh | `harness_health.sh` REQUIRED_HOOKS line 27 | settings.json 0건 등록 (v7.0 Sprint 5) — required 의무 0 |
| cash_sleeve_validator.sh | `harness_health.sh` REQUIRED_HOOKS line 74 (Legacy 유지 섹션) | v55 strict cash sleeve audit는 v6.4 risk-research agent로 흡수 — required 의무 0 |

### v7.1-lite 신규 추가
| Hook | 위치 | 역할 |
|---|---|---|
| legacy_write_block.sh | `harness_health.sh` REQUIRED_HOOKS | v7.0 Sprint 5 신규 — `_archive_v55/` write 차단 |

## Active path (v8.1) — DO NOT deprecate

| Component | 역할 |
|---|---|
| `02_Infrastructure/docs/qvest_v8_1_sot.md` | Active SOT — 3-mode constitution + measurement governance |
| `02_Infrastructure/docs/qvest_modes_sot.md` | 3-mode constitution — per-mode evaluation/self-development |
| `02_Infrastructure/hooks/qvest_hook_router.py` | Single hook entry (Phase 4) |
| `02_Infrastructure/hooks/qvest_cert_eval.py` | v7.0 Sprint 1 cert generic evaluator |
| `02_Infrastructure/hooks/policies/*.json` | 4 policy single source |
| `02_Infrastructure/worktask/state_machine.R` | v6.4 Sprint 2 — state machine |
| `02_Infrastructure/worktask/cert_rules.R` | v6.4 Sprint 2 — cert rules |
| `02_Infrastructure/schemas/*` | v7.0 Sprint 3 — 14 JSON schema |
| `02_Infrastructure/contracts/register_module.R` | FR input-floor contract + quarantine split |
| `02_Infrastructure/regime/build_module_performance.R` | FR allowlist consumer + legacy QEPM Grade-A migration exception |

## Deprecated user commands

| Command | 위치 | Replacement | Notice |
|---|---|---|---|
| `/launch-team` | ~~`.claude/commands/launch-team.md`~~ (DELETED 2026-07-05) | Agent tool spawn (v8.1) | 파일 삭제됨 — 역사는 git·qvest_legacy_boundary.md 보존. forge/judge/governor 커맨드도 동일 삭제(동명 AGENT는 현역) |
| `/scout` (slash) | `.claude/commands/scout.md` | alpha-research agent (v6.4 Codex Round 의무) | retained for back-compat — warning 추가 |

## Cron / external dependencies

| Source | Reference | Status |
|---|---|---|
| `/etc/crontab daily_refresh.sh` | `02_Infrastructure/data/daily_refresh.sh` | active — legacy hook 호출 0건 (Sprint 0 audit) |
| External R script | `Sys.which("Rscript")` 호출 | active — wt_advance signature 보존 (Sprint 1) |

## Read-only enforcement

`02_Infrastructure/hooks/legacy_write_block.sh` (Sprint 5 신규):
- PreToolUse[Write|Edit] matcher
- target dirs: `_archive_v55/`, `legacy/`, `_archive_4_6/`
- decision: **block**

## File 이동 (Sprint 5 마지막)

Hidden dependency 0 확인 후:
- `02_Infrastructure/legacy/v55/` 신규
- `git mv` _archive_v55 → legacy/v55/
- tag: `legacy_v55_isolated_2026_05_XX`

## v7.0 외부 평가 기준

- ✅ active path와 legacy 격리
- ✅ active hook list에 legacy 0건 (Sprint 5 종료 후)
- ✅ legacy_write_block.sh 작동
- ✅ DEPRECATION.md inventory 명문화

## v8.2 Codex Critic Round 제거 (2026-06-30, 도훈 mandate)

QEPM 파이프라인에서 **외부 Codex Critic Round를 완전 제거**. 메인 에이전트가 Opus 4.8로 자체 적대검증(self-adversarial challenge)을 수행하므로 외부 codex spawn은 중복. AX-008은 `Forge + Codex + Architect` → `Forge + Self-Adversarial + Architect`로 치환(3-source 2/3 불변). draft→codex→challenge_note→final 5단계 → in-agent self-adversarial로 reframe.

**범위 한정**: 본 제거는 **QEPM Codex Critic Round 전용**. **S0 Debate codex**(codex_critic / s0_enforcer / s0_debate_*) · **RAMP "Codex"**(K_RAMP·ramp-orchestrator의 Q-Lead+agent 역할명) · 텔레그램 용어집 do-not-translate "Codex"는 **별개 시스템으로 유지**.

**[개정 2026-07-24 — 도훈 승인 C1]** enabledPlugins `codex@openai-codex` 항목은 **해제**. Fable 5 하네스 감사 실측: `~/.claude/plugins/installed_plugins.json` 빈 상태(플러그인 미설치·codex-companion.mjs 디스크 부재)로 런타임 무효과인 **유령 설정**이었고, 원 보존 근거 "S0/RAMP가 codex CLI 사용"도 실체 부재(RAMP Codex=역할명, `run_pit_intent_scan.sh` v2는 로컬 codex CLI로 이관 완료 — 플러그인 비의존, S0 stage 스킬은 2026-07-05 삭제). 로컬 codex CLI(`C:/Users/99922/AppData/Roaming/npm/codex`)와 debate_helpers 스크립트는 FS retain — 플러그인 설정과 무관하게 동작. 근거: `04_Research/01_reports/fable5_harness_audit_20260724.md` §3 C1.

| 자산 | 이전 위치 | Action | Replacement |
|---|---|---|---|
| codex_round_pre_enforcer.sh | `02_Infrastructure/hooks/` | → `02_Infrastructure/hooks/_archive_codex_round_v8_2/` | self-adversarial in-agent |
| codex_round_auto_trigger.sh | `02_Infrastructure/hooks/` | → `_archive_codex_round_v8_2/` | self-adversarial in-agent |
| codex_round_subagent_stop.sh | `02_Infrastructure/hooks/` | → `_archive_codex_round_v8_2/` | self-adversarial in-agent |
| run_codex_qepm_critic.sh | `02_Infrastructure/hooks/` | → `_archive_codex_round_v8_2/` | self-adversarial in-agent |
| codex_round_contract.json | `02_Infrastructure/hooks/` | → `_archive_codex_round_v8_2/` | challenge_note.md (self-adversarial record) |
| codex_{role}_critic_prompt.md × 6 (alpha/risk/optimizer/forge/judge/governor) | `02_Infrastructure/prompts/` | → `02_Infrastructure/prompts/_archive_codex_round_v8_2/` | self-adversarial in-agent |
| qepm_codex_base_context.md | `02_Infrastructure/prompts/` | → `02_Infrastructure/prompts/_archive_codex_round_v8_2/` | self-adversarial in-agent |
| `qvest-codex-round` skill | `.claude/skills/qvest-codex-round/` | **DELETED** | self-adversarial in-agent (각 agent 정의 내장) |

**연계 변경**(타 파일, 본 inventory 참조용): settings.json 훅 3개 등록 제거 · state_transitions.json `codex_critic_response` required 제거 · AX-008 Codex→Self-Adversarial 치환 · 6 agent 정의 self-adversarial 전환 · CLAUDE.md 정정 · `02_Infrastructure/docs/rules/codex-round.md` = DEPRECATED 스텁.

## 2026-08-23 v9 Lean Loop — 훅 등록 해제 36종·라우터 dispatch 폐지·Stop 훅 0·부팅 검사 28항 폐지(→ health_full.sh 주간)·스케줄러 4종 비활성 예정(도훈 실행)

**근거**: 승인된 재설계안 `C:/Users/99922/.claude/plans/qvest-encapsulated-wave.md` (전수 점검 §1 + 기전 진단 §2 + 재설계 §3 + 실행 §4 + 검증 §5 + 결정 §6).
**롤백**: `git tag pre-v9-lean-loop`. 훅 설정 변경은 **다음 세션부터** 적용된다(현행 세션에는 무영향).

**★한 파일도 삭제·이동하지 않았다.** 전부 *등록 해제*이고, 해제된 훅은 `harness_health.sh` · `memory_knowledge_health.R` W5 · `02_Infrastructure/ops/hook_e2e_battery.py` · `08_Tests` 스위트 31파일이 **경로로 직접 호출**하므로 제자리에 남는다.

| 자산 | 이전 상태 | Action | Replacement |
|---|---|---|---|
| 훅 36종 (Stop blockers 2 · research-path blockers 11 · router-only 5 · advisory noise 7 · side-effect & certifier 11) | `.claude/settings.json` 직접 등록 또는 라우터 dispatch | **등록 해제** (FS retain) | 자본·안전 게이트 11종 직접 등록 — 이름·구 등록 위치·차단력·사유·**재등록 레시피** = `02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md` |
| `qvest_hook_router.py` dispatch 경로 | `PreToolUse[Write\|Edit]` 1-command → 19훅 fan-out | **dispatch 폐지** | `router_dispatch.json` v1.3 = `events.PreToolUse.hooks: []` (파일 유지 — selftest·C6·`hook_integrity_check` 가 **부재**를 FAIL 로 읽음). 구 19-entry 원문 = `_archive_v8_enforcement/router_dispatch_v1.2.json`. 라우터 스크립트 자체는 FS retain(`classify`/`check-*` 서브커맨드는 계속 쓰임) |
| `Stop` 이벤트 등록 | 훅 4종(commit/push + 차단 2종) | **Stop 키 삭제 = 등록 0** | commit/push 2종 → `SessionEnd`(턴당 → 세션당 1회, timeout 120). 차단 2종 = 해제(§6 D-c·D-j) — 연속성 계약은 L-code 발행 1곳으로 이동 |
| 부팅 검사 28항 | `.claude/commands/qvest.md` 체크리스트 + `bootstrap.sh` | **폐지** | 주간/수동 `health_full.sh`. "WARN 발화 = 즉시 수리 의무" 문구 삭제 — `boot_currency_check.sh` 는 "digest 등재 — 수리는 도훈 지시 시 태스크로 분리 (v9 2026-08-23)" 로 개정 |
| `boot_currency_check.sh` C9·C10·C11·C11b | 부팅마다 AuditWatch 디제스트·venv 카나리아 판정 | **은퇴 → 1줄 PASS** | 코드는 `_bcc_retired_c9_c11b()`(호출자 없음)로 파일 안에 보존. 사유 = 스케줄러 비활성 시 해소 불가 FAIL 4건 상시 발생 |
| `boot_stamp_check.sh` 훅 무결성 호출부 | 매 SessionStart `ops/hook_integrity_check.sh` 실행 | **호출 제거** | 라우터 폐지로 판정 대상 소멸 + 남기면 v9 settings.json 을 읽고 "worktree 폴백 미적용" **거짓 경고** 주입(v8 라우터 command 전용 지문). 훅 등록 점검은 `boot_currency_check.sh` C6 + 주간 `health_full.sh` |
| 스케줄러 `Qvest_InsiderBackfill` · `Qvest_AuditWatch` · `Qvest_StrandedRepairs` · `Qvest_MonthlyDistill` | 등록·활성 | **비활성 예정** (도훈이 직접 `schtasks /Change /TN "Qvest_X" /DISABLE` 실행 — 본 커밋 범위 밖) | 롤백 `/ENABLE`. 유지 = `DailyRefresh`·`MorningBrief`·`MorningReboot`·`WeeklyCleaner` |

**동반 갱신된 래칫**(해제 상태를 정상으로 읽도록 — 안 고치면 매 부팅/주간 검사가 정상 상태를 결함으로 보고한다):
`harness_health.sh` `REQUIRED_HOOKS` 28→12(유지 11 + 자기 자신) 및 ERR trap 목록 · `ops/hook_fire_coverage.sh` `EXPECTED_DEFAULT`/`UNCOVERED` · `ops/hook_integrity_check.sh` 직접 등록 모드 PASS 경로 신설 · `memory/memory_knowledge_health.R` W7(Stop→SessionEnd, 이벤트 위치까지 검사) · 동 W8(병목 지도 아카이브 — 갱신 의무 폐지, no-op PASS) · `ops/handbook_facts_audit.sh` 차단 훅 목록 + 프론티어 큐 2파일 합산 · `08_Tests/hooks/run_all_hooks.sh` 프로필 필터 2종 + `REGISTRY_GUARD_STRICT` 에 `infra_backlog.json` 추가 · `08_Tests/hooks/profiles/lean.exclude` 신설(25 suite 제외 실측, 167→142).

**포인터**: 해제 원장 `02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md` · 재설계 전문 `C:/Users/99922/.claude/plans/qvest-encapsulated-wave.md`.
