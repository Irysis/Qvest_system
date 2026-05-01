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
