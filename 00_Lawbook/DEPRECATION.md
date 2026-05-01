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

## v55 Legacy still REGISTERED in settings.json (Sprint 5 제거 대상)

| Hook | Replacement | Action |
|---|---|---|
| role_taxonomy_admission_gate | v6.4 unified_agent_guard + agent_role_guard 통합 | settings.json 제거 (Sprint 5) → 파일은 retain (Sprint 5 마지막 단계 이동) |

## Active path (v6.4) — DO NOT deprecate

| Component | 역할 |
|---|---|
| `02_Infrastructure/hooks/qvest_hook_router.py` | Single hook entry (Phase 4) |
| `02_Infrastructure/hooks/qvest_cert_eval.py` | v7.0 Sprint 1 cert generic evaluator |
| `02_Infrastructure/hooks/policies/*.json` | 4 policy single source |
| `02_Infrastructure/worktask/state_machine.R` | v6.4 Sprint 2 — state machine |
| `02_Infrastructure/worktask/cert_rules.R` | v6.4 Sprint 2 — cert rules |
| `02_Infrastructure/schemas/*` | v7.0 Sprint 3 — 14 JSON schema |

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
