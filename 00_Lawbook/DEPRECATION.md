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
| `/launch-team` | `.claude/commands/launch-team.md` | `/qvest` (v6.4 Codex Round 자동 spawn) | deprecation warning Sprint 5 추가 |
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

**범위 한정**: 본 제거는 **QEPM Codex Critic Round 전용**. **S0 Debate codex**(codex_critic / s0_enforcer / s0_debate_*) · **RAMP "Codex"**(K_RAMP·ramp-orchestrator의 Q-Lead+agent 역할명) · 텔레그램 용어집 do-not-translate "Codex" · enabledPlugins `codex@openai-codex`(S0/RAMP가 codex CLI 사용)는 **별개 시스템으로 유지**.

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
