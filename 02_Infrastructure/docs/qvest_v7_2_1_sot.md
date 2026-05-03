# Qvest v7.2.1 — Active Architecture SOT

**버전**: v7.2.1 "Memory Knowledge Hardening"
**계보**: v6.4.0 → v7.0.0 → v7.0.1 → v7.1.0-lite → v7.2.0 → **v7.2.1** (현재 active)
**발행**: 2026-05-02 Session 76 (도훈 옵션 B, full sync)
**상태**: ACTIVE — 본 문서가 v7.2.1 active architecture **단일 SOT**. 모든 hook / agent / skill / rule이 본 문서 참조.
**전임 SOT**:
- `02_Infrastructure/docs/qvest_v6_4_sot.md` v6.4 — base 흡수, v6.4 헌법 정의는 본 문서로 승계
- `02_Infrastructure/worktask/cert_issuance_paths.md` v1.0 (v6.3.2) — 흡수
- `02_Infrastructure/prompts/qlead_spawn_template.md` v1.0 (v6.3.3) — 흡수

---

## 1. 한 문장 요약

> v7.2.1 = "v6.4 연구 지능 레이어(6 agent) + v7.0 검증 가능한 소프트웨어 커널(우회 불가능한 실행 계약) + v7.1 Solo Operator productivity (search/wt/observe CLI) + v7.2 v8 readiness gate + v7.2.1 Memory Knowledge Hardening (axiom JSON SOT + memory health 6 hard / 6 warning)".

핵심 패러다임 변천:
- **v6.4** (Harness Kernel Stabilization) — Codex Critic Round + 5 Cert + State Machine 단일화
- **v7.0** (Hardening) — "문서상 규칙을 우회 불가능한 실행 계약" — 9 Schema + State Machine 위임 + Event ledger
- **v7.1.0-lite** (Solo Operator Productivity) — "3개월 후에도 즉시 찾을 수 있게" — qvest_search / qvest_wt / INDEX.md / examples
- **v7.2.0** (v8 Readiness Gate) — 14-check write mode strict PASS
- **v7.2.1** (Memory Knowledge Hardening) — axiom JSON SOT + memory_health 12-check + 15 readiness

---

## 2. v7.2.1 Active Path (변경 없음 — v6.4 lifecycle 유지)

```
WorkTask 생성 (wt_create)
    ↓
Alpha Research → alpha_package
    ↓ (PostToolUse codex auto-spawn → critic round)
Risk Research → risk_package
    ↓ (codex round)
Optimizer Research → optimization_package + weights.csv
    ↓ (codex round)
Forge → forge_package + run_all.R + backtest
    ↓ (AX-008 Triangulation: Forge + Codex + Architect 2/3 PASS)
Judge → judge_verdict (Gate 0~18)
    ↓
Governor → governor_admission (PG0~PG3)
    ↓
COMPLETED (book_state.json admit)
```

**State Machine** (v7.0 Sprint 1 sm_validated_advance 위임 + v7.0 Sprint 3 schema precondition):

```
SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE
   → FORGE_DONE → JUDGE_PASSED|JUDGE_FAILED
   → GOVERNOR_ADMITTED|GOVERNOR_REJECTED → COMPLETED|ABORTED
```

임의 phase jump는 **waiver 없이 불가** (v7.0 Sprint 1 sm_validated_advance + Sprint 3 sm_validate_artifacts_schema enforced).

---

## 3. v7.2.1 Active Components

### 3.1 Active Agents (6 + 4 ondemand) — v6.4와 동일

| Agent | 역할 | Active Path | spawn 방식 |
|---|---|---|---|
| **alpha-research** | α̂ (factor specs + ICIR + Harvey-t) | core | Agent tool |
| **risk-research** | Σ + tail + stress + crowding | core | Agent tool |
| **optimizer-research** | weights (MVO/HRP/CVaR/ERC/etc) | core | Agent tool |
| **forge** | run_all.R + backtest 통합 | core | Agent tool |
| **judge** | Gate 0~18 검증 | core | Agent tool |
| **governor** | PG0~PG3 admission + book_state | core | Agent tool |
| architect | 인프라 진단 | ondemand | Agent tool |
| blender | 국면 배분 매트릭스 | ondemand (>=4 Grade A) | Agent tool |
| execution | TWAP/VWAP schedule | ondemand (deployment 시) | Agent tool |
| monitoring | live drift | ondemand (월간) | Agent tool / cron |

### 3.2 Active Hooks (v6.4 Phase 4 router + v7.0 Sprint 1 cert hook router 위임 + v7.0 Sprint 5 legacy 0건)

**Tier 1 (전역 hard block)**:
- `safety_guard.sh` — 05_Production/01_Literature 보호
- `axiom_enforcement_hook.sh` — AX-code 위반 차단 (enforcement_mode 분리: documented/block/advisory)
- `codex_round_pre_enforcer.sh` — final package 직접 작성 block
- `legacy_write_block.sh` (v7.0 Sprint 5) — `legacy/v55/` write 차단

**Tier 2 (Agent)**:
- `agent_role_guard.sh` — Alpha/Risk/Opt 역할 경계
- `worktask_sequence_enforcer.sh` — WT 순서

**Tier 3 (Write/Edit mandate)**:
- `worktask_constraint_enforcer.sh` — 20종/bounds/Σw=1
- `worktask_spec_validator.sh` — request.json schema (v7.0 Sprint 3 strict)

**Tier 4 (Post artifact)**:
- `worktask_artifact_validator.sh` — forge_package 8-field
- `red_flag_detector.sh` — RF-A/R/O

**Tier 5 (Positive Certifier — v7.0 Sprint 1 router 위임)**:
- `alpha_discovery_certifier.sh`
- `sr_provenance_check.sh`
- `schedule_fidelity_check.sh`
- `governor_concord_certifier.sh`
- `forge_package_validated_certifier` (artifact_validator 이중 역할)

**Tier 6 (codex round)**:
- `codex_round_auto_trigger.sh` — `_draft.json` PostToolUse async spawn

**Stop event (v7.2.1)**:
- `auto_commit_on_stop.sh` — 세션 종료 auto-commit
- `auto_push_on_stop.sh` (v7.2.1 신규) — Stop event 시 모든 branch GitHub auto-push

**검증**: dry-run 30/30 PASS (v6.4 Sprint 3 시점부터 누적 유지).

### 3.3 Active Certificates (5) — v6.4와 동일 + v7.0 Sprint 1 hook 위임 통일

| Cert | Trigger (PostToolUse Write) | 발급 조건 |
|---|---|---|
| `alpha_discovery_certificate.json` | `alpha_package.json` | cor<0.95 + mech≥50자 + factor_specs≥1 + harvey_t_count≥3 |
| `sr_provenance_certificate.json` | `forge_package.json` | sr_realized_share_based + measurement_basis + weights_csv_unique_dates_count + schedule_density_ratio |
| `schedule_fidelity_certificate.json` | `optimization_package.json` | density≥0.95 OR infeasibility_report |
| `forge_package_validated_certificate.json` | `forge_package.json` | 8-field full schema |
| `governor_concord_certificate.json` | `book_state.json` | admitted_ids ↔ governor_admission match |

**1 Health Score**: `measurement_coherence_health_score` (0-100, Healthy/Warning/Drifted) — `bootstrap.sh` 매 세션 자동 산출. DRIFTED/WARNING 감지 시 `cert_backfill_audit.R --auto` 자동 호출.

### 3.4 Codex Critic Round (의무) — v6.4와 동일

**5단계 흐름** (모든 agent spawn):
1. Draft 작성: `{role}_package_draft.json` (Write tool, `_draft` suffix 필수)
2. PostToolUse `codex_round_auto_trigger.sh` → async background spawn (~9-15분)
3. Codex response 검토: `codex_critic_response_{role}.json`
4. challenge_note.md 의무 (ACCEPT/PARTIAL/REBUTTAL + 학술/L-code/정량 3축)
5. Final 작성: `{role}_package.json` (no _draft) — PreToolUse `codex_round_pre_enforcer.sh` 통과 의무

**우회 시 PreToolUse Hook BLOCK** (single-instance 위반 차단).

**6 role 적용**: alpha / risk / optimizer / forge / judge / governor

### 3.5 Schema (v7.0 Sprint 3 신규 14건 + v7.2.1 +1 = 15건)

| 위치 | 갯수 | 용도 |
|---|---|---|
| `qepm/schema/state/*.json` | 4 | wt_phase / artifact / role_card / **axiom_schema** (v7.2.1 신규, Draft-07 oneOf) |
| `qepm/schema/cert/*.json` | 5 | 5 cert eligibility |
| `qepm/schema/artifact/*.json` | 6 | alpha/risk/opt/forge/judge/governor package field |

**CI 검증**: GH Actions `validate-schema` job (kernel-only 9-job pipeline) — `REQUIRED_SCHEMAS` named set 15건 강제. v7.2.1 patch 후 30/30 hooks PASS + 15/15 readiness 유지.

### 3.6 Active Path 의무 자산 위치

| 자산 | 경로 | 의무성 |
|---|---|---|
| WT metadata | `qepm/mailbox/worktask/{WT_ID}/` | canonical |
| WT request | `qepm/mailbox/worktask/{WT_ID}/request.json` | 필수 |
| Alpha output | `qepm/mailbox/worktask/{WT_ID}/alpha_package.json` (+ draft) | active |
| Risk output | `qepm/mailbox/worktask/{WT_ID}/risk_package.json` (+ draft) | active |
| Optimizer output | `qepm/mailbox/worktask/{WT_ID}/optimization_package.json` (+ draft) | active |
| Forge output | `qepm/mailbox/worktask/{WT_ID}/forge_package.json` (+ draft) | active |
| Judge output | `qepm/mailbox/worktask/{WT_ID}/judge_verdict.json` (+ draft) | active |
| Governor output | `qepm/mailbox/worktask/{WT_ID}/governor_admission.json` (+ draft) | active |
| Codex response | `qepm/mailbox/worktask/{WT_ID}/codex_critic_response_{role}.json` | 자동 |
| Challenge note | `qepm/mailbox/worktask/{WT_ID}/challenge_note.md` | 의무 |
| Cert files | `qepm/mailbox/worktask/{WT_ID}/{cert}_certificate.json` | auto/backfill |
| Heavy outputs | `stage_artifacts/WT_{ID}/*.parquet|*.csv|*.rds` | active (heavy) |
| Book state | `qepm/mailbox/governor/book_state.json` | global |
| Governance log | `qepm/mailbox/governor/governance_log.json` | global |
| Audit script | `02_Infrastructure/ops/cert_backfill_audit.R` | Layer 2 sweep |
| Coherence audit | `02_Infrastructure/portfolio/measurement_basis_audit.R` | Health score |
| **Event ledger** (v7.0 Sprint 6) | `qepm/observability/events.jsonl` | append-only |
| **Search index** (v7.1) | `qepm/observability/search_index.jsonl` | bootstrap rebuild |
| **Memory inventory** (v7.2.1) | `qepm/observability/memory_inventory.json` | health audit |
| **Memory health** (v7.2.1) | `qepm/observability/memory_health_latest.json` | hard 6 + warning 6 |
| **v8 readiness** (v7.2.0+v7.2.1) | `qepm/observability/readiness/v8_readiness_latest.json` | 15 checks |
| **Axiom JSON SOT** (v7.2.1) | `qepm/memory/axioms/active/AX-*.json` | authoritative (8건) |
| **Axiom map** (v7.2.1) | `qepm/memory/axioms/axiom_sot_map.json` | Documented↔JSON 매핑 |

---

## 4. WorkTask Lifecycle (Charter v1.7 §10 + v6.4 + v7.0 strict)

### 4.1 wt_type 4종 (Role Card)

| wt_type | own cert | inherit | exempt | 용도 |
|---|---|---|---|---|
| **discovery** | alpha_discovery + sr_provenance + schedule_fidelity + forge_package_validated | governor_concord (global) | — | 신규 alpha 탐색 |
| **deployment** | sr_provenance + schedule_fidelity + forge_package_validated + governor_concord | alpha_discovery (from discovery) | — | 검증 alpha 직접 편성 |
| **sizing_only** | governor_concord | alpha + sr + sched + forge_pkg (from parent) | alpha_discovery (passive deny) | weight 변경만 |
| **hyperparameter_sweep** | governor_concord | alpha + sr + sched + forge_pkg (from parent) | alpha_discovery (passive deny) | tuning |

### 4.2 Cert 발급 메커니즘 매트릭스

| 작성 경로 | PostToolUse Hook | Cert 자동 발급 |
|---|---|---|
| **Q-Lead Write/Edit tool** | ✅ | ✅ (eligibility 충족 시) |
| Agent (any) → Write tool | ✅ | ✅ |
| Bash → Rscript → file.write | ❌ | ❌ → Layer 2 `cert_backfill_audit.R --auto` 보완 |
| 외부 editor (vim 등) | ❌ | ❌ → Layer 2 보완 |
| Cron daemon | ❌ | ❌ → Layer 2 보완 |

---

## 5. v7.0 Hardening Layer (우회 불가능한 실행 계약)

### 5.1 v7.0.0 Sprint 0~6 (검증 가능한 소프트웨어 커널)

| Sprint | 추가물 | 검증 |
|---|---|---|
| **0** Preflight | branch + tag + baseline + audit + backup | 4 selftest + HEALTHY 100/100 |
| **1** Execution Hardening | wt_advance → sm_validated_advance 위임 + qvest_cert_eval.py + 5 cert hook router 위임 | integration test 7/7 |
| **2** CI + Versioning | kernel-only 9-job GH Actions + VERSIONING.md semver + CHANGELOG + PR template | CI all green |
| **3** Schema Strict | 14 JSON Schema Draft-07 + validate-schema CLI + sm_validate_artifacts_schema | strict precondition |
| **4** E2E Kernel Tests | 4 synthetic WT 시나리오 (happy / cert_fail passive deny / pit_violation / codex_reject) | 12/12 PASS |
| **5** Legacy Boundary | DEPRECATION.md + legacy_write_block.sh + settings cleanup + /launch-team deprecation warn | legacy active 0건 |
| **6** Observability Ledger | events.jsonl + emit_event (non-blocking) + wt_timeline.R + qvest_observe CLI 5 commands + bootstrap L7e | event 추적 |

### 5.2 v7.0.1 Hardening Patch (도훈 흠 4건 fix)

- 0.1 synthetic WT 5건 safe cleanup + e2e cleanup guard
- 0.2 cert_rules.R refactor (threshold hardcode 제거 → cert_rules.json data layer)
- 0.3 harness_health.sh legacy hook 제거 + DEPRECATION.md 동기화
- 0.4 qvest_observe error masking 완화 (stderr log + cached fallback 명시)

---

## 6. v7.1.0-lite Solo Operator Productivity Layer

### 6.1 Daily Use CLI (3개월 후에도 즉시 찾을 수 있게)

| CLI | 위치 | 용도 |
|---|---|---|
| `qvest_search` | `02_Infrastructure/search/qvest_search` | Unified search 5 type (lcode/feedback/registry/wt/axiom) |
| `qvest_wt` | `02_Infrastructure/observability/qvest_wt` | Per-WT viewer (timeline tree + cert glyphs ✅/❌/⏸/⚪) |
| `qvest_observe` | `02_Infrastructure/observability/qvest_observe` | Event ledger 5 commands (recent / wt / cert / drift / errors) |
| `wt_timeline.R` | `02_Infrastructure/observability/wt_timeline.R` | timeline JSON 생성 |
| `emit_event.sh` | `02_Infrastructure/observability/emit_event.sh` | non-blocking append to events.jsonl |

### 6.2 Lawbook INDEX (Navigation Map)

`00_Lawbook/INDEX.md` (≤150 lines, 8 sections):
1. Active SOT (본 문서로 갱신)
2. Daily Use CLI
3. Debug Map
4. Flow 1-liners
5. Memory & Registry (v7.2.1: README + axiom_sot_map + lessons + evidence_summary + memory_inventory + memory_health_latest)
6. Schema (v7.2.1: state 3→4 axiom_schema 추가)
7. Examples (`examples/qvest_workflows/01~03/`)
8. Tags + Version (v7.2.0 + v7.2.1)

### 6.3 Examples — 3 표준 WT (`examples/qvest_workflows/`)

- `01_discovery_happy_path` (3 cert ISSUED)
- `02_cert_fail_passive_deny` (alpha NOT_ISSUED + lifecycle 진행 + governor REJECTED)
- `03_*` (배포 lifecycle)

---

## 7. v7.2.0 + v7.2.1 Readiness + Memory Hardening

### 7.1 v8 Readiness Gate (15 checks, write mode strict)

`02_Infrastructure/validation/v8_readiness_gate.R` — `bootstrap.sh` Step 7d 자동 호출 (--no-write 13/15 PASS + 2 SKIP).

| Check | 의미 |
|---|---|
| hook_dryrun | 30/30 hooks PASS |
| e2e_kernel | 12 pass / 0 fail (e2e+production guards) |
| router_selftest / state_machine_selftest / cert_rules_selftest | 3 selftest |
| schema_active_wt | 활성 WT schema validate |
| legacy_active_hook_zero / synthetic_residue_zero | 0건 유지 |
| qvest_search / qvest_wt / timeline_generation | CLI smoke |
| registry_integrity | book_state ↔ admission match |
| release_metadata | tag + CHANGELOG entry 일치 |
| soak_record | 3-day soak run history |
| **memory_health** (v7.2.1) | hard 6 + warning 6 (자세히 §7.3) |
| (1 reserve) | v7.3 timeline_e2e 추가 예정 |

**최종 검증** (2026-05-02 17:22:55 strict run): 15/15 PASS (PASS=13, SKIP=2 e2e+timeline).

### 7.2 Axiom JSON SOT (v7.2.1)

| 자원 | 위치 | 갯수 |
|---|---|---|
| Active axioms (authoritative) | `qepm/memory/axioms/active/AX-*.json` | 8 (000~005, 007, 008) |
| Axiom map (Documented↔JSON) | `qepm/memory/axioms/axiom_sot_map.json` | documented=8 |
| Schema | `qepm/schema/state/axiom_schema.json` | Draft-07 oneOf |
| Documented (Q-Lead 인지) | `.claude/rules/axioms.md` | 본 문서와 동기화 |
| Derived cache (NOT authoritative) | `.cache/axiom_core.json` | bootstrap regenerate, STALE WARN |

**Hard fail 기준**: active JSON ↔ axioms.md 불일치만. derived cache는 WARN.

**enforcement_mode 분리** (v7.2.1):
- `documented`: AX-000 / AX-007 / AX-008 (3건, immutable / hook hard-block X)
- `block`: AX-001 (1건, hard-block 일부 패턴)
- `advisory`: AX-002 / AX-003 / AX-004 / AX-005 (4건, warn + context, v7.3 block 검토)

**AX-006 candidate-only**: `qepm/memory/axioms/candidates/CAND_20260419_signal_portfolio_translation_failure_L-160_L-165_PENDING_2of3.json` (Q3 2026-07-17 review).

### 7.3 Memory Knowledge Health (v7.2.1)

`02_Infrastructure/memory/memory_knowledge_health.R` — `bootstrap.sh` Step 4 (foreground HARD 0 / WARN ≤6).

**12 check** (hard 6 + warning 6):

| 분류 | check | 기준 |
|---|---|---|
| hard | axiom_active_count | 8 |
| hard | axiom_sot_consistency | active ↔ axioms.md 일치 |
| hard | lcode_corpus_unique | ≥200 (현 237) |
| hard | review_log_schema | named set |
| hard | search_index_freshness | 7d |
| hard | memory_inventory_complete | 모든 type 표기 |
| warning | review_log_variants | ≤17 (현 17 정상) |
| warning | soft_mrs_parse | parse fail OK |
| warning | axiom_core_cache | STALE OK |
| warning | feedback_count | drift 감지 |
| warning | external_info_count | INFO only |
| warning | (1 reserve) | — |

**보조 helper 2건** (v7.2.1):
- `02_Infrastructure/memory/memory_metadata_normalize.R` — fallback chain hard fail (selftest 2/2)
- `02_Infrastructure/memory/lcode_corpus_rebuild.R` — 25 source → 237 unique L-codes (list-of-objects retain, promote.R:44 + review.R:43 critical 호환)

---

## 8. Hook + Cert + Codex Round Matrix (v7.2.1 갱신)

| Tier | Hook | 이벤트 | 대상 | Phase 4 Router 경유? |
|---|---|---|---|---|
| 1 hard | safety_guard | PreToolUse[W/E/B] | 05_Production / 01_Literature | yes |
| 1 hard | axiom_enforcement_hook | PreToolUse[W/E] | AX-code 위반 (mode 분리) | yes |
| 1 hard | codex_round_pre_enforcer | PreToolUse[W/E] | final package 직접 작성 | yes |
| 1 hard | sr_provenance_check (Pre) | PreToolUse[W/E] | ProductionSchedule[N]m fabrication | yes |
| 1 hard | **legacy_write_block** (v7.0) | PreToolUse[W/E] | legacy/v55/ write | yes |
| 2 agent | agent_role_guard | PreToolUse[Agent] | role 경계 | yes |
| 2 agent | worktask_sequence_enforcer | PreToolUse[Agent] | WT 순서 | yes |
| 3 mandate | worktask_constraint_enforcer | PreToolUse[W/E] | 20종/bounds/Σw=1 | yes |
| 3 mandate | worktask_spec_validator | PreToolUse[W/E] | request.json schema | yes |
| 4 post | worktask_artifact_validator | PostToolUse[W] | forge_package 8-field | yes |
| 4 post | red_flag_detector | PostToolUse[W] | RF-A/R/O | yes |
| 5 cert | alpha_discovery_certifier | PostToolUse[W/E] | alpha_package.json | yes |
| 5 cert | sr_provenance_check (Post) | PostToolUse[W/E] | forge_package.json | yes |
| 5 cert | schedule_fidelity_check | PostToolUse[W/E] | optimization_package.json | yes |
| 5 cert | governor_concord_certifier | PostToolUse[W/E] | book_state.json | yes |
| 6 codex | codex_round_auto_trigger | PostToolUse[W/E] | `_draft.json` async spawn | yes |
| stop | auto_commit_on_stop | Stop | 세션 종료 commit | n/a |
| stop | **auto_push_on_stop** (v7.2.1) | Stop | GitHub auto-push | n/a |

**모두 `qvest_hook_router.py` 단일 진입** (v6.4 Phase 4). policy JSON 4종 (`state_transitions.json` / `role_permissions.json` / `codex_round_contract.json` / `cert_rules.json`) 공통 참조.

---

## 9. Active Skills + Rules (v6.4 Phase 9 + v7.x 신규)

### 9.1 Skills (`.claude/skills/`)

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WT lifecycle 절차 |
| `qvest-hook-debug` | Hook 디버깅 + dry-run test |
| `qvest-codex-round` | Codex Critic Round 5단계 흐름 |
| `qvest-telegram` | tg_agent_brief 사용법 + ENFORCE v5 |
| `qvest-cert-paths` | cert 발급 경로 6 row matrix |

### 9.2 Rules (`.claude/rules/`)

| Rule | 용도 |
|---|---|
| `pit.md` | C1~C15 PIT checklist |
| `harness.md` | Hook engineering Tier 1~6 |
| `codex-round.md` | Codex Critic Round protocol |
| `axioms.md` | AX-000~008 본문 (v7.2.1 SOT 정의 + cache_core 격하) |
| `answer-principles.md` | 8원칙 + 5금지 (Level 0 헌법) |
| `caching.md` | Anthropic 5분 TTL + ScheduleWakeup ≤270s |
| `factor-db.md` | C13~C15 + load_month_factors 경유 |
| `backtest-contract.md` | bt_result 10-component (v1.0) |

---

## 10. Q-Lead 역할 경계 (v7.2.1)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / 텔레그램 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ✅ Phase 0 안전장치 (git tag + memory backup)
- ✅ Sprint 진행 + 헌법(CLAUDE.md) + SOT 갱신
- ❌ Rscript 직접 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (Hook L3 자동 차단)

---

## 11. v7.2.1 완료 기준 (도훈 audit 32 critical 모두 반영)

- ✅ active architecture가 본 SOT 1건으로 설명됨 (v6.4 Sprint 1 Phase 1 → v7.2.1 full sync)
- ✅ CLAUDE.md ~270 lines 유지 + Active Version v7.2.1 명시
- ✅ Artifact 위치/파일명 hook+agent+schema+docs 일치
- ✅ Codex Critic Round 우회 dry-run 차단 (PreToolUse codex_round_pre_enforcer)
- ✅ WorkTask 순서 위반 dry-run 차단 (sm_validated_advance + sm_validate_artifacts_schema)
- ✅ cert hook + backfill 동일 기준 (cert_rules.json data layer)
- ✅ 기존 전략/레지스트리/산출물 보존 (legacy 격리 — qvest_legacy_boundary.md)
- ✅ v8 readiness 15/15 PASS (write mode strict, 2026-05-02)
- ✅ memory_health hard 0 (warnings 3 정상)
- ✅ AX-007/008 documented only (v7.3 분리)
- ✅ lcodes 구조 보존 (list-of-objects retain, 237 unique)
- ✅ 30/30 hooks PASS

---

## 12. v8 후속 (이연)

- v7.1 (확장 layer 본격): SQLite event DB / Daily brief Telegram SLO / Dashboard / Shiny UI / legacy file 이동 (`legacy/v55/`)
- v7.3: AX-002 advisory → block 강화 / AX-003/004/005 advisory → block 강화 / AX-007/008 hook hard-block 도입 검토
- v7.3: timeline_e2e check 추가 (15 → 16 readiness)
- v8: 신규 design (15/15 readiness PASS 후 시작 가능)

---

## 13. 참조 (Read-only)

- Plan v6.4: `/home/quant/.claude/plans/nifty-tickling-hinton.md`
- Charter: `02_Infrastructure/worktask/common_charter.md` v1.7
- Legacy boundary: `02_Infrastructure/docs/qvest_legacy_boundary.md`
- v6.4 SOT (전임): `02_Infrastructure/docs/qvest_v6_4_sot.md`
- VERSIONING: `VERSIONING.md` semver
- CHANGELOG: `CHANGELOG.md` (v6.4.0 / v7.0.0 / v7.0.1 / v7.1.0 / v7.2.0 / v7.2.1)
- Lawbook INDEX: `00_Lawbook/INDEX.md`
- L-codes 신규 (v7.0~v7.2.1): L-271 ~ L-275 — `methodology_active.md`
- Rollback: `git tag pre-v6.4-migration` / `v6.4.0` / `v7.0.0` / `v7.0.1` / `v7.1.0` / `v7.2.0` / `v7.2.1`

---

## 변경 이력

- **v7.2.1** — 2026-05-02 Session 76 (도훈 옵션 B full sync) — v6.4 SOT base 흡수 + v7.0 Hardening 7 sprint + v7.0.1 patch + v7.1.0-lite Solo Operator productivity 5 sprint + v7.2.0 v8 readiness gate 14-check + v7.2.1 Memory Knowledge Hardening 흡수 (axiom JSON SOT + memory_health 12-check + 15 readiness + auto-push). L-275 적립.
- **v7.2.0** — 2026-05-02 — v8 readiness gate 14 check write mode strict PASS + CHANGELOG v7.2.0 entry + 3-day soak record.
- **v7.1.0-lite** — 2026-05-02 — Solo Operator productivity 5 sprint (qvest_search + qvest_wt + INDEX.md + 3 examples). 15 atomic commits.
- **v7.0.1** — 2026-05-02 — 도훈 흠 4건 fix (synthetic cleanup / cert_rules data layer / legacy hook 제거 / qvest_observe error masking).
- **v7.0.0** — 2026-05-02 — Hardening 7 sprint (Preflight / Execution / CI Versioning / Schema Strict / E2E Kernel / Legacy Boundary / Observability Ledger). "검증 가능한 소프트웨어 커널" 패러다임.
- **v6.4.0** — 2026-05-01 Session 75 — Harness Kernel Stabilization release. Sprint 0+1+2+3 9-phase 누적. Codex Critic Round 3중 장치 + 5 Cert + State Machine 단일화.
- **v6.4 Sprint 1 Phase 1** — 2026-05-01 — qvest_v6_4_sot.md 발행 (전임 SOT, v7.2.1로 흡수).

---

**다음 단계**: v7.3 design (AX hook hard-block 강화 + timeline_e2e check 추가) 또는 v8 새로운 design.
