# Changelog

All notable changes to Qvest are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](00_Lawbook/VERSIONING.md).

## [v7.2.1] — 2026-05-02

**Memory Knowledge Hardening Patch** — Memory layer SOT/enforcement/safety 정합화 (도훈 audit-revised v6 plan, 32 critical 모두 반영)

### Added
- `qepm/memory/README.md` — 지식 계층 (Lv0~Lv3) + Authority + axiom_class + Lifecycle + SOT reconciliation
- `qepm/observability/memory_inventory.json` — counts snapshot (active 8, candidates 5, deprecated 6, review_log 24, lessons 3, evidence 233, regime 10)
- `qepm/memory/axioms/axiom_sot_map.json` — 9 axiom 매핑 (8 documented active + AX-006 candidate-only with 3 evidence_paths)
- `02_Infrastructure/schemas/state/axiom_schema.json` — Draft-07, oneOf for active/candidate/deprecated, enforcement_mode enum 4값 (documented|advisory|block|none)
- `qepm/memory/axioms/active/AX-007.json` — Single-sleeve top20 mechanism break (enforcement_mode=documented)
- `qepm/memory/axioms/active/AX-008.json` — Verification Triangulation (enforcement_mode=documented)
- `02_Infrastructure/memory/memory_metadata_normalize.R` — promote helper (객체+파일+dry-run + fallback chain)
- `02_Infrastructure/memory/lcode_corpus_rebuild.R` — 4 source 통합 (lcodes list-of-objects 유지)
- `02_Infrastructure/memory/memory_knowledge_health.R` — Hard fail 6 + Warning 6 (external INFO 격하)
- CI `memory_health_smoke` job — axiom_schema validate + health hard fail 0 + qvest_search smoke
- v8_readiness_gate `check_memory_health` — 15번째 check

### Changed
- `02_Infrastructure/hooks/qvest_hook_router.py::SCHEMA_NAME_MAP` — `"axiom"` alias 추가
- `02_Infrastructure/search/build_index.R` — 5 type 추가 (lesson, axiom_candidate, axiom_deprecated, axiom_review, evidence_summary)
- `02_Infrastructure/search/_query.py::format_result()` — authority/axiom_class/memory_kind 노출 + 신규 filter
- `02_Infrastructure/axiom/review.R` — apply=FALSE default, --apply flag 의무, review_log/dryrun/ 하위 분리
- `02_Infrastructure/axiom/promote.R` — normalize_axiom_metadata helper 호출 1줄 (scoring logic 변경 X)
- `02_Infrastructure/validation/v8_readiness_gate.R` — schema count hardcode 제거 + memory_health 15번째 check
- `.github/workflows/qvest-kernel-ci.yml::schema_validate` — named REQUIRED_SCHEMAS set (15)
- `.claude/rules/axioms.md` — SOT 정의 명시 + .cache/axiom_core.json "derived cache" 격하
- 19 JSON metadata patch (active 6 + candidates 5 + deprecated 6 + 신규 active 2)

### Behavior unchanged (v7.3 분리)
- AX-007/008 신규 hook hard-block regex 도입 X (enforcement_mode=documented)
- AX-002~005 advisory 유지 (block 강화는 v7.3)
- promote.R scoring algorithm 변경 X
- 14 기존 schema 변경 X (axiom_schema 추가만)
- lcodes list-of-objects 구조 retain (promote.R:44 + review.R:43 호환성 critical)

### Verification
- 15/15 v8_readiness_gate (PASS=13, SKIP=2)
- memory_health hard fail 0 (warnings 3 정상)
- promote helper selftest 2/2 PASS (fallback chain + hard fail)
- lcode_corpus rebuild 38 → 237 unique L-codes (max L-272)
- 19 JSON metadata router validate-schema PASS

---

## [v7.2.0] — 2026-05-01

**v8.0 Design Readiness Gate** — 자동 판정 도구 (도훈 명시 prompt)

### Added
- `02_Infrastructure/validation/v8_readiness_gate.R` (~610 LoC) — `run_v8_readiness_gate()` + 14 checks
  * hook_dryrun / e2e_kernel / router_selftest / state_machine_selftest / cert_rules_selftest
  * schema_active_wt / legacy_active_hook_zero / synthetic_residue_zero
  * qvest_search / qvest_wt / timeline_generation
  * registry_integrity / release_metadata / soak_record
- `02_Infrastructure/tools/qvest_v8_ready` — bash CLI (`--strict` / `--no-strict` / `--json` / `--no-write`)
  * Exit code: 0=PASS, 1=FAIL, 2=WARN
  * Human-readable: glyph table + next actions
- `qepm/observability/readiness/README.md` — gate 사용법 + 3-day soak rule + 실패 조치
- `08_Tests/integration/test_v8_readiness_gate.R` — 12 test scenarios PASS
- `resolve_tool()` helper — qvest_search/qvest_wt/qvest_observe 후보 path 탐색
- CI job `v8_readiness_smoke` — integration test + CLI smoke

### Fixed
- 한글 path WSL 호환 — `run_cmd(... wd = project_root)` + relative path args
- E2E kernel + timeline_generation write mode — auto cleanup_guard 호출
- selftest -e 인자 shell escape — 임시 R script file 패턴

### Verified (strict mode, write report)
- **14/14 PASS, Overall PASS, ready_for_v8_design = TRUE**
- exit code 0
- production / book_state / registry 무손상

### Notes
- Tag `v7.2.0` (MINOR — readiness gate 신규)
- 3-day soak rule: 최근 3일 내 readiness gate 2회+ critical=0 → soak_record PASS
- v8 설계 착수 가능 (도훈 명시 승인 후)

## [v7.1.0] — 2026-05-01

**Solo Operator Productivity Patch** (v7.1-lite — Sprint 1~4)

### Added
- `02_Infrastructure/search/build_index.R` — JSONL search index builder (1502 rows, 9 source types)
- `02_Infrastructure/search/qvest_search` + `_query.py` — unified search CLI (AND keyword + casefold + type filter + WT-D9999 default exclusion + --no-auto-rebuild)
- `02_Infrastructure/observability/qvest_wt` + `_wt_pretty.py` — per-WT viewer (ASCII timeline tree, --certs/--failures/--lineage/--json/--active/--recent N)
- `00_Lawbook/INDEX.md` — single-page navigation map (119 lines, 8 sections — Active SOT / Daily CLI / Debug Map / Flow / Memory & Registry / Schemas / Examples / Tags)
- `examples/qvest_workflows/` — 3 standard reference WTs (01 happy / 02 cert_fail / 03 pit_violation)
- CI jobs: `search_smoke` + `qvest_wt_smoke` + `schema_validate` examples whitelist mapping
- `qepm/observability/readiness/` — v8 design readiness gate scaffold

### Changed
- `.gitignore` — `qepm/observability/search_index.jsonl` (regenerable)

### Notes
- Tag `v7.1.0` (MINOR semver — backward compatible)
- Display name: `Qvest v7.1.0-lite`
- archive policy (events.jsonl rotation 90+ days) deferred to v7.2

## [v7.0.1] — 2026-05-01

**Residue Hardening Patch** (v7.1-lite Sprint 0)

### Fixed
- Synthetic WT 5건 cleanup (WT-D99990101_001~_004 + WT-D99999999_999) + `_e2e_cleanup_guard.sh` 4-step safe procedure
- `cert_rules.R` 4 함수 threshold hardcode 제거 → `cert_rules.json` data layer (public API/outcome unchanged)
- `harness_health.sh` REQUIRED_HOOKS legacy 제거 (role_taxonomy_admission_gate / cash_sleeve_validator) + DEPRECATION.md 동기화
- `qvest_observe` error masking 완화 — `>/dev/null 2>&1 || true` triple silent 제거 → stderr log + cached fallback 명시

### Added
- `08_Tests/integration/_cert_threshold_audit.R` — R AST 기반 numeric literal 검출 (round(x,3L) integer L-suffix allow)
- `08_Tests/integration/_e2e_cleanup_guard.sh` — `--list`/`--force`/`--check` modes

### Notes
- Tag `v7.0.1` (PATCH semver)
- Public API + eligibility outcome 100% 보존 (kernel behavior unchanged)
- v7.0 contract 위반 0건

## [v7.0.0] — 2026-05-01

**v7.0 Hardening Release** — "문서상 규칙을 우회 불가능한 실행 계약으로 바꾸는 release"

### 외부 평가 8 기준 (Codex 명시)
- ✅ wt_advance 우회 불가 (Sprint 1)
- ✅ hook / backfill / router cert 판정 일치 (Sprint 1)
- ✅ CI green (Sprint 2 — yaml 작성, 실제 push 후 run)
- ✅ package / cert / state schema validation 작동 (Sprint 3)
- ✅ synthetic WT E2E 4개 PASS — 12/12 (Sprint 4)
- ✅ active path에서 legacy hook 제거 (Sprint 5 — role_taxonomy_admission_gate 제거)
- ✅ per-WT timeline 생성 가능 (Sprint 6 — wt_timeline.R + qvest_observe CLI)
- ✅ CHANGELOG + semver 정착 (Sprint 2)

### Sprint 6 — Observability Ledger
- Added: `qepm/observability/events.jsonl` — append-only event ledger (JSONL fallback, SQLite v7.1 이연)
- Added: `02_Infrastructure/observability/emit_event.sh` — non-blocking event emitter (Codex revised #7: 항상 exit 0)
- Added: `02_Infrastructure/observability/wt_timeline.R` — per-WT timeline builder
  * events / phases / certs / failures / retry_count / artifact_lineage 6-section JSON
  * `--wt-id <ID>` 또는 `--rebuild-active-book` 두 mode
- Added: `02_Infrastructure/observability/qvest_observe` — CLI 5 commands
  * `wt <ID> [--phases|--failures|--certs]` — Timeline display
  * `events --since=<TIME> [--hook=<NAME>]` — events query
  * `stats --metric=<NAME>` — aggregated p50/p99 + decisions
- **Changed**: `02_Infrastructure/ops/bootstrap.sh` — L7e 신규 (Active book WT timeline rebuild 자동 호출)

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
