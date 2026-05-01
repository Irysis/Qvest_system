# Cert Auto-Issuance Paths — Charter v1.2 §10 + Qvest v6.3.2 SOT

**버전**: v1.0 (2026-05-01 Session 75 발행, Qvest v6.3.2 동반)
**목적**: 5 certificate 자동 발급이 어떤 경로로 동작하는지 단일 진실. 도훈 직접 개입 / Q-Lead orchestration / Agent spawn / 외부 R script 등 모든 경로의 발급 여부를 명시.
**근거**: L-266 / L-267 / L-268 + Session 75 E2E dry-run 6/6 PASS

---

## 1. 발급 경로 매트릭스

| # | 경로 | Hook 발동 | Cert 자동 발급 | 보완 경로 |
|---|---|---|---|---|
| 1 | **도훈 → Q-Lead → Write tool** | ✅ PostToolUse[Write\|Edit] | ✅ **자동** (eligibility 충족 시) | — |
| 2 | Q-Lead → `Agent(subagent_type="alpha-research")` 등 → Write tool | ✅ | ✅ 자동 | — |
| 3 | Q-Lead → Forge agent → Write tool | ✅ | ✅ 자동 | — |
| 4 | Q-Lead → Bash → `Rscript ... -e 'jsonlite::write_json(...)'` | ❌ | ❌ | Layer 2 sweep (다음 부팅 또는 수동) |
| 5 | 도훈 외부 editor (vim / RStudio / Cursor / notepad) 직접 저장 | ❌ | ❌ | Layer 2 sweep |
| 6 | Cron `daily_refresh.sh` / 외부 daemon이 R script로 file write | ❌ | ❌ | Layer 2 sweep |

**핵심 원리**:
- Hook은 Claude Code Write/Edit tool의 `tool_input.file_path` + `tool_input.content` 만 본다.
- Bash 안에서 호출되는 R script의 `file.create` / `jsonlite::write_json` / `writeLines` 는 Hook 시야 밖.
- "정규 파이프라인" vs "직접 개입" 구분은 무관. **변수는 'Claude Code Write tool 경유 여부' 단일.**

---

## 2. Eligibility 조건 (누가 작성하든 동일)

발급 조건은 작성 주체와 무관하게 동일하게 검증된다. 미충족 시 cert 미발급 (passive deny, block 아님).

| Cert | matcher | 조건 (AND) |
|---|---|---|
| `alpha_discovery_certificate.json` | `alpha_package.json` | `diagnostics.alpha_inheritance_cor < 0.95` + mechanism cited ≥ 50자 (`hypothesis_summary` ‖ `factor_specs[].economic_rationale`) + `factor_specs.length ≥ 1` + `diagnostics.harvey_t_specs_pass_count ≥ 3` |
| `sr_provenance_certificate.json` | `forge_package.json` | 4-field: `sr_realized_share_based` + `measurement_basis_primary == "forge_realized_share_based"` + `weights_csv_unique_dates_count` + `schedule_density_ratio` |
| `forge_package_validated_certificate.json` | `forge_package.json` | 8-field: 위 4 + `task_id` + `backtest_summary` + `alpha_sig_dates_count` + `schedule_density_pass` + `pure_function_violation` |
| `schedule_fidelity_certificate.json` | `optimization_package.json` | `weights_csv_unique_dates / sig_dates_count ≥ 0.95` OR `infeasibility_report` / `schedule_skip_justified` 명시 |
| `governor_concord_certificate.json` | `book_state.json` | `admitted_ids` 각 STR마다 `governor_admission.json.allocation_decided[STR]` 존재 + `book_weights[STR]` ≈ expected (\|Δ\| < 0.01). 일부 mismatch 시 `_with_waiver` cert 발급 (5-row waiver_log 명시 시) |

**Hard Block 1건** (Charter §9/§10 system integrity):
- `forge_package.json` / `run_all.R` / `run_forge*.R` 의 `method` 필드 또는 본문에 `ProductionSchedule[N]m` 패턴 매치 → `sr_provenance_check.sh` PostToolUse[Write\|Edit] **차단**. 라벨 변경 후 재시도. STR_1715 Iter 31 violation 패턴 재발 방지.

---

## 3. Layer 2 Bootstrap Sweep (보완 경로)

경로 4·5·6 (외부 file write) 발생 시 cert 부재 → 다음 세션 부팅 시 자동 backfill.

```bash
# 자동 (bootstrap.sh L7c)
# DRIFTED/WARNING tier 감지 시 자동 호출
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --auto

# 수동 (즉시)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX_NNN --manual
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX_NNN --dry-run  # 실 발급 없이 audit만
```

**Layer 2 동작**:
- `book_state.json` `admitted_ids` 순회 + WT lineage 추적 (str_id 정확 / 부분 / `discovery_of` / `forge_package.deployment_lineage` / `alpha_lineage_chain` 매칭)
- 5 cert eligibility 함수 호출 (`check_alpha_discovery_eligibility` / `check_sr_provenance_eligibility` / `check_schedule_fidelity_eligibility` / `check_forge_package_validated_eligibility` / `check_governor_concord_eligibility`)
- ELIGIBLE 시 cert 파일 직접 작성 (Option B — Hook bypass, schema는 Hook과 동일)
- `governance_log.json` `RETROACTIVE_CERT_ISSUANCE` entry 자동 기록

---

## 4. 운영 권장 패턴

### 4-A. 도훈 직접 개입 시 (가장 흔한 케이스)

✅ **권장**: "Q, STR_XXX의 alpha_package에 Y factor 추가해" 형식으로 Q-Lead에 지시. Q-Lead가 Write/Edit tool로 작성 → cert 자동 발급.

❌ **비권장**: 외부 editor (vim / RStudio) 직접 저장. cert 미발급 → 다음 부팅 sweep까지 cert 공백.
- 부득이 외부 작업 후 즉시 `Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX --manual` 실행해 backfill.

### 4-B. 정규 3-Agent 파이프라인 시

알파/리스크/옵티마이저 agent는 모두 Claude Code Write tool 사용 → cert 자동 발급.
Forge agent도 Write tool 경유 시 자동. **단** Forge agent가 R script CLI를 Bash 호출하면 그 R script 내부 file write는 Hook 시야 밖 → Layer 2 sweep 보완.

### 4-C. Cron / daemon 작업

`daily_refresh.sh` / `cleanup.sh` 등 외부 file write는 cert 시스템 시야 밖. 이들이 cert-relevant 파일 (alpha_package / forge_package / book_state) 수정한다면 매번 Layer 2 sweep 호출 의무.

---

## 5. E2E 검증 결과 (Session 75 dry-run, L-268)

| # | 시나리오 | 결과 |
|---|---|---|
| 1 | 인프라 정찰 | ✅ 5 cert hook + cert_backfill_audit.R + wt_check_graduation 매핑 확인 |
| 2 | 양의 시나리오 (Q-Lead Write tool) | ✅ **4/5 cert PostToolUse Hook 자동 발급** (alpha_discovery + sr_provenance + forge_package_validated + schedule_fidelity) |
| 3 | Layer 2 sweep dry-run | ✅ admit 안 된 WT는 skip 정상, HEALTHY 100/100 유지 |
| 4 | 음의 시나리오 (cert 부재 admit) | ✅ `wt_check_graduation` `pass=FALSE` `reason="deployment_cert_insufficient"` |
| 5 | Hard block (fabrication label) | ✅ `sr_provenance_check.sh` `ProductionSchedule5m` 감지 → BLOCK |
| 6 | Cleanup + final HEALTHY | ✅ HEALTHY 100/100 유지 |

**미검증 1건**: `governor_concord_certifier.sh` admission graduation bypass hard block (book_state admit 시도 시 `governor_admission.json` 부재 → 차단). Production state 오염 risk 회피로 dry-run에서 skip. 다음 정식 admit cycle (Iter 9 등) 발생 시 자연 검증.

---

## 6. 5 Cert + 4 Layer + 1 Hard Block 종합 방어 (Session 75 정합)

| Layer | 메커니즘 | 적용 시점 | 입증 L-code |
|---|---|---|---|
| **L1** Silent Fail Hardening | Hook ERR trap log + isinstance guard | Hook 자체 안전성 | L-263 |
| **L2** Bootstrap Auto Sweep | `bootstrap.sh` L7c `cert_backfill_audit.R --auto` | 다음 세션 부팅 시 / 수동 호출 시 | L-264 + 본 세션 idempotent |
| **L3** Lineage-aware Audit | Charter v1.7 §10 Role Card 4×5 + `find_lineage_wts()` + `role_card_cert_inheritance.R` | 발급/검증 시 lineage WT inherit | L-265 |
| **L5** Positive Certifier (PostToolUse Hook) | 5 hook (alpha_discovery / sr_provenance / schedule_fidelity / worktask_artifact_validator / governor_concord) | Claude Code Write/Edit tool 경유 시 | L-268 |
| **Hard Block 1** | `sr_provenance_check` ProductionSchedule[N]m fabrication 차단 | forge_package / run_all.R Edit 시 | L-268 PASS |
| **Hard Block 2** | `governor_concord_certifier` admission graduation bypass | book_state admit 시 | L-268 미검증 (자연 발동 대기) |

**참고**: L4 (FileChanged event)는 영구 deferred (L-267 B-3 채택). `CLAUDE_FILE_PATH` 미주입 + mtime hack race risk → Layer 2 영구 fallback 채택.

---

## 7. 변경 이력

- **v1.0** — 2026-05-01 Session 75 — Qvest v6.3.2 동반 발행. E2E dry-run 6/6 PASS 입증 후 SOT 명문화.

---

## 참조

- `02_Infrastructure/worktask/common_charter.md` v1.7 §10 (Role Card 4×5)
- `02_Infrastructure/worktask/role_card_cert_inheritance.R` (own/inherit/exempt/optional 룰셋)
- `02_Infrastructure/ops/cert_backfill_audit.R` (Layer 2 sweep)
- `02_Infrastructure/portfolio/measurement_basis_audit.R` (HEALTHY 100/100 산출)
- `02_Infrastructure/hooks/alpha_discovery_certifier.sh` (Charter §10 4-condition AND)
- `02_Infrastructure/hooks/sr_provenance_check.sh` (4-field + fabrication hard block)
- `02_Infrastructure/hooks/schedule_fidelity_check.sh` (density ≥ 0.95 OR infeasibility)
- `02_Infrastructure/hooks/worktask_artifact_validator.sh` (8-field forge_package)
- `02_Infrastructure/hooks/governor_concord_certifier.sh` (book_state ↔ admission match + bypass hard block)
- `02_Infrastructure/worktask/worktask_manager.R::wt_check_graduation()` (deployment 분기 4 cert 검사)
- L-262 (deployment WT cert backfill 패턴) / L-263 (silent fail hardening) / L-264 (Layer 2 sweep) / L-265 (Charter v1.7 §10) / L-266 (FileChanged infra 검증) / L-267 (B-3 채택) / **L-268 (E2E 6/6 PASS)**
