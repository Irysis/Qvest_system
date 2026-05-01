# Changelog

All notable changes to Qvest are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](00_Lawbook/VERSIONING.md).

## [Unreleased — v7.0.0]

### Sprint 5 — Legacy Boundary
- Added: `00_Lawbook/DEPRECATION.md` — active vs legacy 자산 inventory + EOL plan
- Added: `02_Infrastructure/hooks/legacy_write_block.sh` — PreToolUse[Write|Edit] read-only enforcement (`_archive_v55/` + `legacy/v55/` + `_archive_4_6/`)
- **Removed**: `.claude/settings.json` `role_taxonomy_admission_gate` hook 등록 (v55 legacy)
- Added: `.claude/settings.json` `legacy_write_block` hook 등록 (PreToolUse[Write|Edit])
- **Changed**: `.claude/commands/launch-team.md` — DEPRECATION WARNING 추가 (v6.4 `/qvest` 대체)
- Active hook list legacy 0건 ✅
- File 이동 (Sprint 5 마지막 step `git mv _archive_v55 → legacy/v55/`)는 v7.1로 이연 (hidden dependency 추가 audit 후)

### Sprint 4 — E2E Kernel Tests (12/12 PASS)
- Added: `08_Tests/integration/test_wt_lifecycle_e2e.R` — 4 synthetic WT scenarios (Codex revised #4/#5)
  * (1) Happy path WT-D99990101_001: 4 cert ISSUED + 6 schema VALID
  * (2) Cert fail passive deny WT-D99990102_001: alpha NOT_ISSUED but RISK/OPT/FORGE/JUDGE 진행 → Governor REJECTED
  * (3) PIT violation WT-D99990103_001: lookahead pattern injected → judge FAIL
  * (4) Codex reject WT-D99990104_001: stance=REJECT + 9 HIGH critical concerns → escalate trigger MET
- Production guard: book_state 무손상 (synthetic year 9999 admit 0건, admitted_ids 1건 retain)
- Cleanup obligation: on.exit 4 WT 디렉토리 + temp governor dir 제거
- 결과: 12 pass / 0 fail / 12 total ✅

### Sprint 3 — Schema Strict (14 schema)
- Added: `02_Infrastructure/schemas/` — 14 JSON Schema Draft-07 (6 packages + 5 certs + 3 state)
- Added: `qvest_hook_router.py validate-schema` CLI (jsonschema import)
- Added: `cert_rules.R::cr_validate_schema()` — router 위임 wrapper
- Added: `state_machine.R::sm_validate_artifacts_schema()` — phase → schema 매핑
- **Changed**: `sm_validated_advance()` — schema validation을 state transition precondition으로 통합 (waiver 없으면 invalid schema → block)
- Added CI: `schema_validate` job — 14 schema parse + Draft-07 valid + invalid fixture rejection smoke test
- Real WT validation 5/8 PASS (3 outdated fixture: forge sr_realized_share_based / judge verdict / governance_log events 부재)

### Sprint 2 — CI + Versioning
- Added: `.github/workflows/qvest-kernel-ci.yml` — kernel-only CI (9 jobs)
- Added: `00_Lawbook/VERSIONING.md` — semver strict policy
- Added: `CHANGELOG.md` — Keep a Changelog format
- Added: `.github/pull_request_template.md` — sprint / test / rollback checklist

### Sprint 1 — Execution Path Hardening
- **Changed (BREAKING)**: `wt_advance()` now delegates to `sm_validated_advance()`. Phase jump without waiver is blocked. Existing callers preserve signature `(task_id, new_phase, blocker=NULL)`.
- Added: `02_Infrastructure/hooks/qvest_cert_eval.py` — generic JSON-driven cert eligibility evaluator (single responsibility, separate from router)
  - `evaluate(cert_name, package_path, **kwargs)` — generic dispatch
  - `issue_certificate(cert_name, package_path, output_path, ...)` — 5 cert 공통 issue helper
  - CLI: selftest / evaluate / issue
- **Changed**: `qvest_hook_router.py::check_cert_eligibility()` — `qvest_cert_eval.evaluate()` 위임 (5 cert hardcoded logic 제거)
- **Changed**: `cert_backfill_audit.R` — `check_*_eligibility()` 4/5 → `cr_check_*()` 위임 (alpha_discovery / sr_provenance / forge_package_validated). schedule_fidelity / governor_concord retain (source 차이).
- **Changed**: `alpha_discovery_certifier.sh` — 147 LoC inline Python → 50 LoC router 위임
- **Changed**: `sr_provenance_check.sh` — Branch 1 cert 발급 부분만 위임 (Hard block + warn 검증 retain)
- **Changed**: `worktask_artifact_validator.sh` — forge_package_validated cert 부분만 위임 (schema 검증 retain)
- Added: `08_Tests/integration/test_execution_path_unified.R` — 7 시나리오 PASS (wt_advance 위임 + cert 3-source parity + waiver block)

### Sprint 0 — Preflight
- Added: `v7.0-hardening` branch + `pre-v7.0-hardening-start` tag
- Added: `tests/baseline/v6_4_0_baseline.json` — 4 selftest + measurement_basis HEALTHY 100/100
- Added: `tests/baseline/dependency_audit.txt` — 120 lines (3 group: A wt_advance/cert / B legacy / C telegram)
- Added: `/tmp/memory_pre_v7_0_*.tar.gz` + `/tmp/mailbox_pre_v7_0_*.tar.gz` — backup

## [v6.4.0] — 2026-05-01

### Added — Harness Kernel Stabilization (Sprint 1+2+3)

**Sprint 1**: SOT 단일화 (qvest_v6_4_sot.md + legacy_boundary) + CLAUDE.md 436→270 lines + 8 rules + 3 skills + artifact_contract drift 4건 해결.

**Sprint 2**:
- `02_Infrastructure/hooks/qvest_hook_router.py` (340 LoC) — single hook entry point
- `02_Infrastructure/hooks/policies/{state_transitions,role_permissions,codex_round_contract,cert_rules}.json` — 4 policy JSON
- `02_Infrastructure/worktask/state_machine.R` (200 LoC) — 11 phase / 11 transition table
- `02_Infrastructure/worktask/cert_rules.R` (290 LoC) — 5 cert eligibility single source
- SubagentStop hook

**Sprint 3**:
- Dry-run tests **30/30 PASS** (codex_round 3 + sequence 10 + role_guard 8 + cert 9)
- 2 추가 skills (qvest-hook-debug + qvest-cert-paths)
- **E2E 10/10 PASS** (state machine + cert + role card + drift scan 0 hits + WT_003 BHEQ pattern BLOCK 정확 + health HEALTHY 100/100)

### Reference
- L-269 v6.0 Codex Critic Round 3중 장치 영구 정착
- L-270 v6.3.3 검증 + Bayesian
- L-271 v6.4.0 Release verification

## [v6.3.3] — 2026-05-01

### Added
- v6.0 Codex Critic Round 3중 장치 영구 정착 (L-269)
- `codex_round_pre_enforcer.sh` PreToolUse hook (130 LoC, final {role}_package.json 작성 시 _draft + critic_response 부재 block)
- `qlead_spawn_template.md` — 5단계 흐름 + 6 role + Self-Check

## [v6.0] — 2026-04-23

### Added — QEPM 3-Agent WorkTask
- alpha-research / risk-research / optimizer-research / forge / judge / governor 6-agent
- WorkTask lifecycle (SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_ADMITTED → COMPLETED)

## [v5.5] — 2026-04-19

### Added — v55 strict
- TeamCreate teammate 4인 + Hook 17종
- v55 5-sleeve + GAP 4-axis

## [v5.3] — 2026-04-13

### Added — v53 TeamCreate
- TeamCreate (Q-Lead 1 + teammate 4)
- Hook 17종 통합
