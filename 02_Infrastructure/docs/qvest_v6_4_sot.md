# Qvest v6.4 — Active Architecture SOT

**버전**: v6.4 "Harness Kernel Stabilization"
**발행**: 2026-05-01 Session 75 (Sprint 1 Phase 1)
**상태**: ACTIVE — 본 문서가 v6.4 active architecture **단일 SOT**. 모든 hook / agent / skill / rule이 본 문서 참조.
**전임 SOT**:
- `02_Infrastructure/worktask/cert_issuance_paths.md` v1.0 (v6.3.2 부분 SOT) — 본 문서에 흡수
- `02_Infrastructure/prompts/qlead_spawn_template.md` v1.0 (v6.3.3 부분 SOT) — 본 문서에 흡수
- 기존 `CLAUDE.md` 운영 절차 — Phase 2에서 skills/rules로 이동

---

## 1. 한 문장 요약

> v6.4 = "Qvest의 연구 지능(Alpha/Risk/Optimizer/Forge/Judge/Governor)을 건드리지 않고, 그것이 안정적으로 작동하게 만드는 Claude Code-native 하네스 커널".

---

## 2. v6.4 Active Path

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

**state machine** (Phase 5 신규 `state_machine.R` 강제):

```
SPEC_APPROVED
  → ALPHA_DONE
  → RISK_DONE
  → OPTIMIZER_DONE
  → FORGE_DONE
  → JUDGE_PASSED | JUDGE_FAILED
  → GOVERNOR_ADMITTED | GOVERNOR_REJECTED
  → COMPLETED | ABORTED
```

임의 phase jump는 **waiver 없이 불가** (Phase 5 enforced).

---

## 3. v6.4 Active Components

### 3.1 Active Agents (6 + 4 ondemand)

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

### 3.2 Active Hooks (Phase 4 router 도입 후)

**Tier 1 (전역 hard block)**:
- `safety_guard.sh` — 05_Production/01_Literature 보호
- `axiom_enforcement_hook.sh` — AX-code 위반 차단
- **`codex_round_pre_enforcer.sh`** (v6.3.3 → v6.4 router 흡수) — final package 직접 작성 block

**Tier 2 (Agent)**:
- `agent_role_guard.sh` — Alpha/Risk/Opt 역할 경계
- `worktask_sequence_enforcer.sh` — WT 순서

**Tier 3 (Write/Edit mandate)**:
- `worktask_constraint_enforcer.sh` — 20종/bounds/Σw=1
- `worktask_spec_validator.sh` — request.json schema

**Tier 4 (Post artifact)**:
- `worktask_artifact_validator.sh` — forge_package 8-field
- `red_flag_detector.sh` — RF-A/R/O

**Tier 5 (Positive Certifier)**:
- `alpha_discovery_certifier.sh` — alpha cert 4 AND
- `sr_provenance_check.sh` — sr_prov cert 4-field + fabrication block
- `schedule_fidelity_check.sh` — sched cert density ≥0.95
- `governor_concord_certifier.sh` — concord cert + admission bypass block

**Tier 6 (codex round)**:
- `codex_round_auto_trigger.sh` — `_draft.json` PostToolUse async spawn

### 3.3 Active Certificates (5)

| Cert | Trigger (PostToolUse Write) | 발급 조건 |
|---|---|---|
| `alpha_discovery_certificate.json` | `alpha_package.json` | cor<0.95 + mech≥50자 + factor_specs≥1 + harvey_t_count≥3 |
| `sr_provenance_certificate.json` | `forge_package.json` | sr_realized_share_based + measurement_basis + weights_csv_unique_dates_count + schedule_density_ratio |
| `schedule_fidelity_certificate.json` | `optimization_package.json` | density≥0.95 OR infeasibility_report |
| `forge_package_validated_certificate.json` | `forge_package.json` | 8-field full schema |
| `governor_concord_certificate.json` | `book_state.json` | admitted_ids ↔ governor_admission match |

**1 Health Score**: `measurement_coherence_health_score` (0-100, Healthy/Warning/Drifted) — `bootstrap.sh` 매 세션 자동 산출. DRIFTED/WARNING 감지 시 `cert_backfill_audit.R --auto` 자동 호출.

### 3.4 Codex Critic Round (의무)

**5단계 흐름** (모든 agent spawn):
1. Draft 작성: `{role}_package_draft.json` (Write tool, `_draft` suffix 필수)
2. PostToolUse `codex_round_auto_trigger.sh` → async background spawn (~9-15분)
3. Codex response 검토: `codex_critic_response_{role}.json`
4. challenge_note.md 의무 (ACCEPT/PARTIAL/REBUTTAL + 학술/L-code/정량 3축)
5. Final 작성: `{role}_package.json` (no _draft) — PreToolUse `codex_round_pre_enforcer.sh` 통과 의무

**우회 시 PreToolUse Hook BLOCK** (single-instance 위반 차단).

**6 role 적용**: alpha / risk / optimizer / forge / judge / governor

### 3.5 Active Path 의무 자산 위치

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

---

## 4. WorkTask Lifecycle (Charter v1.7 §10 + v6.4)

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

## 5. Hook + Cert + Codex Round Matrix

| Tier | Hook | 이벤트 | 대상 | Phase 4 Router 경유? |
|---|---|---|---|---|
| 1 hard | safety_guard | PreToolUse[W/E/B] | 05_Production / 01_Literature | yes (Phase 4) |
| 1 hard | axiom_enforcement_hook | PreToolUse[W/E] | AX-code 위반 | yes |
| 1 hard | **codex_round_pre_enforcer** ⭐ | PreToolUse[W/E] | final package 직접 작성 | yes |
| 1 hard | sr_provenance_check (Pre) | PreToolUse[W/E] | ProductionSchedule[N]m fabrication | yes |
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
| **6 codex** | **codex_round_auto_trigger** ⭐ | PostToolUse[W/E] | `_draft.json` async spawn | yes |

**모두 `qvest_hook_router.py` 단일 진입** (Phase 4). policy JSON 4종 (`state_transitions.json` / `role_permissions.json` / `codex_round_contract.json` / `cert_rules.json`) 공통 참조.

---

## 6. Active Skills + Rules (Phase 9 재배치 후)

### 6.1 Skills (`.claude/skills/`)

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WT lifecycle 절차 (CLAUDE.md에서 이동) |
| `qvest-hook-debug` | Hook 디버깅 + dry-run test |
| `qvest-codex-round` | Codex Critic Round 5단계 흐름 |
| `qvest-telegram` | tg_agent_brief 사용법 + ENFORCE v5 규칙 |
| `qvest-cert-paths` | cert 발급 경로 6 row matrix (v6.3.2 cert_issuance_paths.md 흡수) |

### 6.2 Rules (`.claude/rules/`)

| Rule | 용도 |
|---|---|
| `pit.md` | C1~C15 PIT checklist (CLAUDE.md에서 이동) |
| `harness.md` | Hook engineering Tier 1~6 (CLAUDE.md에서 이동) |
| `codex-round.md` | Codex Critic Round protocol |
| `axioms.md` | AX-000~005 + 본문 |
| `paths.md` | protected paths (05_Production / 01_Literature) |

---

## 7. Q-Lead 역할 경계 (v6.4)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / 텔레그램 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ✅ Phase 0 안전장치 (git tag + memory backup)
- ✅ Phase 검토 + Sprint 진행
- ❌ Rscript 직접 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (Hook L3 자동 차단)

---

## 8. v6.4 완료 기준 (도훈 명시)

- ✅ 최신 active architecture가 본 SOT 1건으로 설명됨
- ⏳ CLAUDE.md 200~300줄 (Phase 2)
- ⏳ Artifact 위치/파일명 hook+agent+schema+docs 일치 (Phase 3)
- ⏳ Codex Critic Round 우회 dry-run 차단 (Phase 6+8)
- ⏳ WorkTask 순서 위반 dry-run 차단 (Phase 5+8)
- ⏳ cert hook + backfill 동일 기준 (Phase 7)
- ✅ 기존 전략/레지스트리/산출물 보존 (원칙 명시)

---

## 9. Sprint 진행 상태

| Sprint | Phase | 상태 |
|---|---|---|
| 0 | 안전장치 (git tag + memory + mailbox + WT snapshot) | ✅ 완료 (Session 75 13:43) |
| 1 | Phase 1 SOT 본 문서 + qvest_legacy_boundary.md | 🔄 진행 중 |
| 1 | Phase 2 CLAUDE.md 경량화 | ⏳ 대기 |
| 1 | Phase 3 artifact_contract.json | ⏳ 대기 |
| 2 | Phase 4 Hook Kernel router | ⏳ 후속 세션 |
| 2 | Phase 5 State Machine | ⏳ 후속 |
| 2 | Phase 6 Codex Round v6.4 lifecycle | ⏳ 후속 |
| 2 | Phase 7 Cert Layer 단일화 | ⏳ 후속 |
| 3 | Phase 8 Dry-run Tests | ⏳ 후속 |
| 3 | Phase 9 Subagent/Skill 재배치 | ⏳ 후속 |
| 3 | Phase 9.5 E2E dry-run cycle | ⏳ 후속 |

---

## 10. 참조 (Read-only)

- Plan: `/home/quant/.claude/plans/nifty-tickling-hinton.md`
- Charter: `02_Infrastructure/worktask/common_charter.md` v1.7
- Legacy boundary: `02_Infrastructure/docs/qvest_legacy_boundary.md` (Sprint 1 Phase 1 동반 발행)
- Cert paths (deprecated, 흡수됨): `02_Infrastructure/worktask/cert_issuance_paths.md` v1.0
- Spawn template (Phase 9 skill로 이동 예정): `02_Infrastructure/prompts/qlead_spawn_template.md` v1.0
- L-codes: `methodology_active.md` (L-269 L-270 본 세션 신규)
- Rollback: `git tag pre-v6.4-migration` + `/tmp/memory_pre_v6_4_*.tar.gz` + `/tmp/mailbox_pre_v6_4_*.tar.gz`

---

## 변경 이력

- **v6.4** — 2026-05-01 Session 75 — Sprint 1 Phase 1 발행. Codex 검증한 9-phase patch 시작. v6.3.3 base 위에 hook kernel + state machine + cert 단일화 + dry-run tests + skill/rule 재배치.

---

**다음 단계**: Sprint 1 Phase 1 동반 `qvest_legacy_boundary.md` 발행.
