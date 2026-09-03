<!-- ★RETIRED (v10 2026-09-02): v8.1 cert 발급 경로 매트릭스 — v9(2026-08-23) 훅 감산으로 cert 발급 훅 0 · v10 governor_concord/book_state admit 폐지. bootstrap.sh L7c sweep 은 boot_lean 세션 부팅에서 미발화(health_full.sh 경유 주간/수동만 조건부 발화). wt_check_graduation() 의 cert 파일 검사는 레거시 코드 잔존 — v10 등급은 authoritative_remeasure.json::essence_grade 만 인용. 재열람 = git pre-v10-2layer -->
---
name: qvest-cert-paths
description: Qvest v8.1 Cert 발급 경로 매트릭스. Q-Lead Write tool 경유 vs Bash Rscript / 외부 editor / Cron daemon 비교.
---

# Qvest Cert Auto-Issuance Paths Skill

**v8.1 active**: v6.3.2/v6.4 cert path SOT를 흡수. 현재 해석 기준은 `qvest_v8_1_sot.md` + `qvest_modes_sot.md`.

## 1. 발급 경로 매트릭스 (6 row)

| # | 경로 | Hook 발동 | Cert 자동 발급 | 보완 경로 |
|---|---|---|---|---|
| 1 | **도훈 → Q-Lead → Write tool** | ✅ PostToolUse[Write\|Edit] | ✅ **자동** (eligibility 충족 시) | — |
| 2 | Q-Lead → Agent (alpha-research 등) → Write tool | ✅ | ✅ 자동 | — |
| 3 | Q-Lead → Forge agent → Write tool | ✅ | ✅ 자동 | — |
| 4 | Q-Lead → Bash → `Rscript ... -e 'jsonlite::write_json(...)'` | ❌ | ❌ | Layer 2 sweep (다음 부팅 또는 수동) |
| 5 | 도훈 외부 editor (vim / RStudio / Cursor / notepad) 직접 저장 | ❌ | ❌ | Layer 2 sweep |
| 6 | Cron `daily_refresh.sh` / 외부 daemon이 R script로 file write | ❌ | ❌ | Layer 2 sweep |

**핵심 원리**: Hook은 Claude Code Write/Edit tool의 `tool_input.file_path` + `tool_input.content` 만 본다.

## 2. Eligibility 조건 (5 cert)

| Cert | matcher (PostToolUse) | 조건 |
|---|---|---|
| `alpha_discovery_certificate.json` | `alpha_package.json` | cor < 0.95 + mech ≥ 50자 + factor_specs ≥ 1 + harvey_t_count ≥ 3 |
| `sr_provenance_certificate.json` | `forge_package.json` | 4-field (sr_realized_share_based + measurement_basis + weights_csv_unique_dates_count + schedule_density_ratio) |
| `forge_package_validated_certificate.json` | `forge_package.json` | 8-field full schema |
| `schedule_fidelity_certificate.json` | `optimization_package.json` | density ≥ 0.95 OR infeasibility_report |
| `governor_concord_certificate.json` | `book_state.json` (global) | admitted_ids ↔ governor_admission match |

**Hard Block 2건** (Charter §9/§10):
1. `ProductionSchedule[N]m` fabrication label (sr_provenance / schedule_fidelity)
2. `governor_admission.json` 부재 STR을 book_state admit (governor_concord)

## 3. Layer 2 Sweep — 외부 작성 보완

```bash
# 자동 (bootstrap.sh L7c, DRIFTED/WARNING tier 시 자동)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --auto

# 수동 (즉시)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX_NNN --manual

# Dry-run
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX_NNN --dry-run
```

## 4. 운영 권장 패턴

### 도훈 직접 개입 시
✅ **권장**: "Q, STR_XXX의 alpha_package에 X factor 추가해" 형식 → Q-Lead Write tool 경유 → cert 자동 발급.
❌ **비권장**: 외부 editor 직접 저장. cert 미발급 → 다음 부팅 sweep까지 cert 공백.
- 부득이 외부 작업 후 즉시 `cert_backfill_audit.R --target=WT-XXX --manual` 실행.

### 정규 3-Agent 파이프라인 시
6 agent 모두 Claude Code Write tool 경유 → cert 자동 발급. 단 Forge agent가 Bash Rscript 호출 시 R script file write는 Hook 시야 밖 → Layer 2 sweep 보완.

### Cron / daemon
`daily_refresh.sh` / `cleanup.sh` 등 외부 file write는 cert 시스템 시야 밖. cert-relevant 파일 (alpha_package / forge_package / book_state) 수정 시 Layer 2 sweep 호출 의무.

## 5. Role Card 4×5 (wt_type 별)

| wt_type | own | inherit | exempt | optional |
|---|---|---|---|---|
| **discovery** | alpha_discovery + sr_provenance + schedule_fidelity + forge_package_validated | — | — | governor_concord (global) |
| **deployment** | sr + sched + forge_pkg + concord | alpha_discovery (from discovery_of) | — | — |
| **sizing_only** | concord | alpha + sr + sched + forge_pkg | — | — |
| **hyperparameter_sweep** | concord | alpha + sr + sched + forge_pkg | — | — |

`02_Infrastructure/worktask/role_card_cert_inheritance.R` — 룰셋 단일 진입.

## 6. 4-Layer Defense (L-269 lesson)

| Layer | 메커니즘 |
|---|---|
| **L1** Silent Fail Hardening | Hook ERR trap log + isinstance guard |
| **L2** Bootstrap Auto Sweep | `cert_backfill_audit.R --auto` |
| **L3** Charter v1.7 §10 Lineage-aware Audit | role_card_cert_inheritance + measurement_basis_audit |
| **L5** Positive Certifier (PostToolUse) | 5 hook auto-issue |
| HardBlk1 | sr_provenance fabrication label |
| HardBlk2 | governor_concord admission graduation bypass |

L4 (FileChanged event)는 영구 deferred (`CLAUDE_FILE_PATH` 미주입 + race risk → L-267 B-3 채택).

## 7. E2E 검증 결과 (Session 75 dry-run, L-268)

| 시나리오 | 결과 |
|---|---|
| 인프라 정찰 | ✅ |
| Q-Lead Write tool 양의 시나리오 | ✅ 4/5 cert auto-issue |
| Layer 2 sweep dry-run | ✅ idempotent |
| 음의 시나리오 (cert 부재 admit) | ✅ pass=FALSE detection |
| Hard block (fabrication label) | ✅ block 발동 |
| Cleanup + HEALTHY | ✅ 100/100 유지 |

## 참조

- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (Active SOT)
- `02_Infrastructure/docs/qvest_v6_4_sot.md` (historical SOT, read-only retain)
- `02_Infrastructure/worktask/cert_rules.R` (Phase 7 single source)
- `02_Infrastructure/hooks/policies/cert_rules.json` (policy JSON)
- `02_Infrastructure/ops/cert_backfill_audit.R` (Layer 2)
- `02_Infrastructure/portfolio/measurement_basis_audit.R` (Health Score)
- Self-Adversarial(구 Codex Round — v8.2 폐지): `.claude/rules/axioms.md` AX-008 + `02_Infrastructure/docs/rules/harness.md` Tier 6 (codex-round.md는 DEPRECATED 스텁)
- L-262 (deployment WT cert backfill) / L-267 (Layer 4 deferred) / L-268 (E2E 6/6 PASS)
