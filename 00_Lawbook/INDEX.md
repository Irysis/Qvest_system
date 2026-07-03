# Qvest Index

**3개월 후 도훈이 즉시 찾을 수 있게** — 1 page navigation + debug map.
v8.1.0 3-Mode Architecture + FR input-floor hardening (2026-06-12).

---

## 1. Active SOT

- `02_Infrastructure/docs/qvest_v8_1_sot.md` — Qvest active SOT (3-mode constitution + measurement governance + module flow)
- `02_Infrastructure/docs/qvest_modes_sot.md` — 3-mode constitution (per-mode evaluation/self-development + shared honesty gates)
- `02_Infrastructure/docs/qvest_legacy_boundary.md` — v55/S0~S7 격리 정책
- `00_Lawbook/DEPRECATION.md` — active vs legacy 자산 inventory + EOL plan

## 2. Daily Use CLI

| Command | 용도 |
|---|---|
| `/qvest` | Session start + bootstrap (gap 확인 + harness_health 30/29) |
| `/worktask` | WT lifecycle CRUD |
| `qvest_observe wt <ID>` | Per-WT timeline JSON (rebuild + dump) |
| `qvest_wt <ID>` | Per-WT ASCII pretty (alpha/risk/opt/forge/judge/governor tree) |
| `qvest_wt --active` | Book admit WT 1-line summary |
| `qvest_wt --recent N` | Recent N WT (status.json mtime DESC, WT-D9999 자동 제외) |
| `qvest_search "<q>"` | Unified search (lcode/wt/cert/paper/axiom/registry/lawbook/critic/governance) |
| `qvest_search "<q>" --type <T>` | Type 필터 |
| `qvest_search --rebuild` | Force re-index |
| `qvest_observe events --since=24h` | Event ledger query (qepm/observability/events.jsonl) |
| `qvest_observe stats` | Hook count + p50/p99 + decision breakdown |
| `bash 08_Tests/hooks/run_all_hooks.sh` | hook dry-run |
| `02_Infrastructure/tools/qvest_v8_ready --strict --json --no-write` | v8 readiness gate |

## 3. Debug Map

| 증상 | 1차 확인 file |
|---|---|
| Hook block 원인 추적 | `02_Infrastructure/hooks/qvest_hook_router.py` (4 policy 단일 진입) |
| Cert 발급 실패 | `02_Infrastructure/worktask/cert_rules.R` + `02_Infrastructure/hooks/policies/cert_rules.json` (data layer) |
| State transition 거부 | `02_Infrastructure/worktask/state_machine.R` + `state_transitions.json` (11 phase) |
| Schema invalid | `02_Infrastructure/schemas/{packages,certs,state}/` (14 schema, Draft-07) |
| Telegram 차단 | `qepm/telegram/` + `qvest-telegram` skill (v5 ENFORCE) |
| Self-Adversarial Challenge 누락 | challenge_note.md (self-adversarial record) — agent 내 자체 적대검증 (v8.2: Codex Round 훅 제거, 강제 훅 없음) |
| WT phase jump | `02_Infrastructure/worktask/state_machine.R::sm_validated_advance` (force_waiver=TRUE 필요) |
| Cert backfill (Layer 2) | `02_Infrastructure/ops/cert_backfill_audit.R` (--auto / --manual / --dry-run) |
| Measurement Coherence DRIFTED | `02_Infrastructure/portfolio/measurement_basis_audit.R` + bootstrap L7c auto |
| FR pool에 proxy 유입 의심 | `02_Infrastructure/contracts/register_module.R` + `06_Registry/module_quarantine.json` + `02_Infrastructure/regime/build_module_performance.R` |
| Search index stale | `02_Infrastructure/search/build_index.R` (`qvest_search --rebuild`) |
| Synthetic WT residue | `08_Tests/integration/_e2e_cleanup_guard.sh --check` (CI gate) |

## 4. Flow 1-liners

**Hook flow (PreToolUse + PostToolUse)**:
```
Tool → PreToolUse (safety_guard / axiom / agent_role / worktask_*)
     → Tool exec
     → PostToolUse (artifact_validator / pipeline_trigger / 5 cert certifier / lineage_recorder)
     → Stop (auto_commit_on_stop)
```

**Cert flow (5 type, PostToolUse 자동 발급)**:
- `alpha_discovery` — alpha_package.json 4 AND (cor < 0.95 + mech ≥ 50 + factor_specs ≥ 1 + harvey_t ≥ 3)
- `sr_provenance` — forge_package.json 4 field (sr_realized + measurement_basis + weights_csv_dates + density)
- `forge_package_validated` — forge_package.json 8 field
- `schedule_fidelity` — optimization_package.json density ≥ 0.95 OR infeasibility_report
- `governor_concord` — book_state ↔ admission match (or with_waiver)

**State machine (11 phase)**:
```
SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE
              → JUDGE_PASSED → GOVERNOR_ADMITTED → COMPLETED
              (또는 ABORTED / JUDGE_FAILED / GOVERNOR_REJECTED → ABORTED)
```

**Self-Adversarial Challenge (v8.2 — Codex Round 제거, Opus 4.8 자체 적대검증, 모든 agent spawn)**:
```
1. Draft 작성 (메인 에이전트 산출)
2. 자체 적대검증 (Opus 4.8 in-agent self-adversarial challenge — 외부 codex spawn 폐지)
3. challenge_note.md 의무 (self-adversarial record: ACCEPT/PARTIAL/REBUTTAL 분류)
4. Final 작성 (challenge 반영)
- 강제 훅(codex_round_*) 폐지 — 2026-06-30 도훈 mandate, 자산 archive: 00_Lawbook/DEPRECATION.md
```

## 5. Memory & Registry

- `qepm/memory/README.md` — v7.2.1 Memory layer SOT/lifecycle 정의 (지식 계층 + Authority + axiom_class)
- `qepm/memory/methodology_memory_v55_extensions.md` — L-001~L-249+ (active L-codes, qvest_search type=lcode)
- `qepm/memory/methodology_memory.md` — DEPRECATED (L-000~L-129 archive)
- `qepm/memory/axioms/active/AX-*.json` — 8 axioms v7.2.1 (000~005, 007, 008 — AX-006 candidate-only)
- `qepm/memory/axioms/axiom_sot_map.json` — Documented ↔ JSON 매핑 (8 documented + AX-006 evidence_paths)
- `qepm/memory/lessons/L-*.json` — active lessons (qvest_search type=lesson)
- `qepm/memory/evidence_summary/*.json` — 233 factor evidence (qvest_search type=evidence_summary)
- `06_Registry/strategy_registry.json` — 600+ strategies + grades (242KB)
- `06_Registry/idea_registry.json` / `paper_registry.json` / `strategy_grades.json`
- `04_Research/paper_notes/P*.md` — 203 paper notes (qvest_search type=paper)
- `qepm/observability/events.jsonl` — append-only event ledger (retain)
- `qepm/observability/memory_inventory.json` — counts snapshot (v7.2.1)
- `qepm/observability/memory_health_latest.json` — Memory Health Gate latest
- `qepm/observability/timelines/wt_*.json` — per-WT timeline cache (regenerable)
- `qepm/observability/search_index.jsonl` — search index (gitignore, regenerable)

## 6. Schema Locations

- `02_Infrastructure/schemas/packages/` — 6 (alpha/risk/optimization/forge/judge_verdict/governor_admission)
- `02_Infrastructure/schemas/certs/` — 5 (alpha_discovery/sr_provenance/schedule_fidelity/forge_package_validated/governor_concord)
- `02_Infrastructure/schemas/state/` — 4 (book_state/governance_log/artifact_lineage/axiom v7.2.1)
- 검증: `python3 02_Infrastructure/hooks/qvest_hook_router.py validate-schema --schema <name> --package <path>`

## 7. Examples + Tests

- `02_Infrastructure/docs/examples/qvest_workflows/` — 3 표준 WT (Sprint 4) — discovery happy / cert_fail / pit_violation (구 `examples/`, 2026-07-04 이동)
- `08_Tests/hooks/run_all_hooks.sh` — 30 hook dry-run
- `08_Tests/integration/test_execution_path_unified.R` — wt_advance + cert parity 7/7
- `08_Tests/integration/test_wt_lifecycle_e2e.R` — 4 시나리오 12/12
- `08_Tests/integration/_cert_threshold_audit.R` — cert_rules.R hardcode 0건 audit
- `08_Tests/integration/_e2e_cleanup_guard.sh` — synthetic WT residue 0건 CI gate

## 8. Version Tags

- `v6.4.0` — Harness Kernel Stabilization
- `v7.0.0` — Hardening Release (kernel unification + CI + 14 schema + E2E + legacy + observability)
- `v7.0.1` — Residue Hardening Patch (synthetic cleanup + cert refactor + harness_health sync + error masking)
- `v7.1.0-lite` — Solo Operator Productivity Patch (qvest_search + qvest_wt + INDEX + examples)
- `v7.2.0` — v8.0 Design Readiness Gate (14 checks + soak rule + JSON CLI)
- `v7.2.1` — Memory Knowledge Hardening (axiom_schema + AX-007/008 materialize + lcode_corpus + memory_health 6+6 + 15 readiness)

## Maintenance

- 인프라 reorg 시 본 INDEX.md 1줄 업데이트 (CHANGELOG에 "INDEX.md update on infra reorg" 의무)
- 자동생성 X — Lawbook churn 결합 회피
- 새 CLI 추가 시 §2 + §3 (해당하면) update
