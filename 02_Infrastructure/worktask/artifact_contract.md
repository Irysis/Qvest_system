# Qvest v8.1 WorkTask Artifact Contract

**버전**: v1.0 (2026-05-01 Session 75 Sprint 1 Phase 3)
**JSON SOT**: `02_Infrastructure/worktask/artifact_contract.json`
**Active SOT**: `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md`

## 목적

WT artifact 위치 + 파일명을 **단일 contract**로 고정. hook / agent / schema / docs가 동일 path 참조. file naming drift (optimization vs optimizer 등) 영구 제거.

## 적용 시점

- **Phase 4 (Sprint 2)**: `qvest_hook_router.py`가 본 contract import → matcher 자동 생성
- **Phase 7 (Sprint 2)**: `cert_rules.R` + `cert_rules.json`이 cert eligibility single source 사용
- **Phase 8 (Sprint 3)**: `08_Tests/hooks/*` fixture가 본 contract path pattern으로 생성

## 1. Canonical Paths

| 카테고리 | Path |
|---|---|
| WT metadata root | `qepm/mailbox/worktask/{WT_ID}/` |
| Stage artifacts (heavy) | `stage_artifacts/WT_{ID}/` |
| Governor global | `qepm/mailbox/governor/` |
| WT_ID pattern | `^WT-[DPSH][0-9]{8}_[0-9]{3}$` |

WT_ID prefix:
- `WT-D` → discovery
- `WT-P` → deployment
- `WT-S` → sizing_only
- `WT-H` → hyperparameter_sweep

## 2. Package Files (canonical names)

| Role | Final | Draft | Owner Agent |
|---|---|---|---|
| q-lead | `request.json` | — | q-lead |
| alpha | `alpha_package.json` | `alpha_package_draft.json` | alpha-research |
| risk | `risk_package.json` | `risk_package_draft.json` | risk-research |
| **optimizer** | **`optimization_package.json`** ⭐ | **`optimization_package_draft.json`** ⭐ | optimizer-research |
| forge | `forge_package.json` | `forge_package_draft.json` | forge |
| judge | `judge_verdict.json` | `judge_verdict_draft.json` | judge |
| governor | `governor_admission.json` | `governor_admission_draft.json` | governor |

⭐ **drift 주의**: optimizer agent role과 file name 불일치 — agent role은 `optimizer-research`이지만 file은 `optimization_package` (canonical). `optimizer_package.json` 사용 시 Hook 미발동 (deprecated).

## 3. Self-Adversarial Challenge Files (v8.2 — Codex Round 제거)

**v8.2 (2026)**: 외부 Codex Critic Round 폐지. 메인 에이전트(Opus 4.8)가 각 role 산출 시 **자체 적대검증(Self-Adversarial Challenge)** 을 수행하고 그 기록을 `challenge_note.md`에 남긴다. 구 `codex_critic_response_{role}.json` artifact는 더 이상 생성하지 않는다.

| 항목 | Path |
|---|---|
| Challenge note (self-adversarial record) | `qepm/mailbox/worktask/{WT_ID}/challenge_note.md` |

`role` ∈ `{alpha, risk, optimizer, forge, judge, governor}`.

**Drift existing**: 일부 (구) cycle에서 `risk_challenge_note.md` / `optimizer_challenge_note.md` 등 role-specific name 사용 (역사적). **권장**: role-specific → canonical `challenge_note.md` 집계. 신규 WT는 canonical 사용.

## 4. Certificate Files (5 cert)

| Cert | Path | Trigger |
|---|---|---|
| alpha_discovery | `qepm/mailbox/worktask/{WT_ID}/alpha_discovery_certificate.json` | PostToolUse[Write] alpha_package.json |
| sr_provenance | `qepm/mailbox/worktask/{WT_ID}/sr_provenance_certificate.json` | PostToolUse[Write] forge_package.json |
| schedule_fidelity | `qepm/mailbox/worktask/{WT_ID}/schedule_fidelity_certificate.json` | PostToolUse[Write] optimization_package.json |
| forge_package_validated | `qepm/mailbox/worktask/{WT_ID}/forge_package_validated_certificate.json` | PostToolUse[Write] forge_package.json |
| **governor_concord** | **`qepm/mailbox/governor/governor_concord_certificate.json`** ⭐ | PostToolUse[Write] book_state.json |

⭐ governor_concord는 **global** (per book, not per WT). 다른 4 cert는 **per-WT**.

`governor_concord_with_waiver_certificate.json` 변형 (waiver 시).

## 5. Heavy Outputs (`stage_artifacts/WT_{ID}/`)

### Alpha
- `alpha_scores.parquet` — **Date × Ticker × score panel** (single snapshot 금지, predecessor C2 fix)
- `alpha_validation.json`

### Risk
- `covariance.parquet` (Σ matrix primary)
- `covariance_daily_alt.parquet` (alt estimator)
- `exposure_matrix.parquet` / `factor_covariance.parquet` / `specific_risk.parquet`
- `regime_correlation.parquet` (with bootstrap CI for n<30)
- `tail_risk.json` / `crowding_blend_simulation.csv` / `risk_method_shopping.json`

### Optimizer
- `weights.csv` — Date × Ticker × weight long form, **schedule density ≥ 0.95 mandate**
- `blend_simulation.csv` / `method_metrics_standalone.csv`
- `composite_alpha_panel.parquet`

### Forge
- `run_all.R` (entrypoint)
- `bt_result.rds` — 10-component (Backtest Result Contract v1.0)
- `bt_result_*.csv` × 10 / `bt_result.xlsx` (11-sheet)
- `audit_log.json`

## 6. Lineage / Governance

| File | Path | Purpose |
|---|---|---|
| `artifact_lineage.json` | `qepm/mailbox/worktask/{WT_ID}/` | R11 lineage tracking |
| `governance_log.json` | `qepm/mailbox/worktask/{WT_ID}/` | WT lifecycle event log |
| `governance_log.json` | `qepm/mailbox/governor/` | Global cert backfill / admit |

## 7. Status File

`qepm/mailbox/worktask/{WT_ID}/status.json` schema:

```json
{
  "task_id": "WT-D20260501_001",
  "current_phase": "ALPHA_DONE",
  "updated_at": "2026-05-01T13:11:36+0900",
  "blocker": null,
  "abort_reason": "...",
  "hold_reason": "...",
  "lessons_learned": ["..."],
  "successor_wt": "WT-D20260501_NNN"
}
```

`current_phase` enum:
- `SPEC_APPROVED`
- `ALPHA_DONE` / `RISK_DONE` / `OPTIMIZER_DONE` / `FORGE_DONE`
- `JUDGE_PASSED` / `JUDGE_FAILED`
- `GOVERNOR_ADMITTED` / `GOVERNOR_REJECTED`
- `COMPLETED` / `ABORTED`
- 보조: `ARCHIVED_REJECTED_BY_CODEX` / `ABORTED_CERT_DENIED_HONEST` / `ALPHA_RISK_DONE_HELD_*`

## 8. Scripts Directory

`qepm/mailbox/worktask/{WT_ID}/scripts/`:
- agent가 작성한 R/Python 재현 script
- `alpha_research_run.R` / `alpha_generate_*.R` / `risk_research.R` / `optimizer_research_run.R` / `build_alpha_package_draft.R` / `finalize_alpha_package.R` etc.

## 9. Drift Resolution

**해결됨 (Phase 3)**:

| Deprecated | Canonical |
|---|---|
| `optimizer_package_draft.json` | `optimization_package_draft.json` |
| `optimizer_package.json` | `optimization_package.json` |
| `judge_package.json` | `judge_verdict.json` |
| `governor_package.json` | `governor_admission.json` |

**Self-adversarial challenge note 명명 (v8.2)**:

| 패턴 | 해결 방향 |
|---|---|
| `challenge_note.md` vs `risk_challenge_note.md` etc | canonical `challenge_note.md` (self-adversarial record) 집계. role-specific은 역사적 drift |

**Scan command**:
```bash
grep -rE 'optimizer_package|judge_package|governor_package' \
  .claude/agents/ 02_Infrastructure/hooks/ 02_Infrastructure/prompts/
```

→ Phase 4 (Sprint 2)에서 router 도입 시 deprecated reference 자동 검출 + fix.

## 10. Phase 4+7+8 Import 의무

- **Phase 4 hook router** (`qvest_hook_router.py`): 본 contract.json import → file path matcher 자동 생성. 각 hook 정규식 중복 보유 금지.
- **Phase 7 cert_rules**: 본 contract.json의 `certificate_files.{cert}.eligibility_*` field 단일 source. hook auto-cert + Layer 2 backfill 동일 사용.
- **Phase 8 dry-run tests** (`08_Tests/hooks/*`): 본 contract path pattern으로 fixture 자동 생성.

## 11. 변경 이력

- **v1.0** — 2026-05-01 Session 75 Sprint 1 Phase 3 — 신규 발행. drift 4건 해결 + 1건 Phase 6 보류. Phase 4/7/8 import 의무 명시.
- **v8.2** — 2026 — 외부 Codex Critic Round 제거 정합. Section 3 `Codex Critic Round Files` → `Self-Adversarial Challenge Files` reframe (구 `codex_critic_response_{role}.json` artifact 폐지, `challenge_note.md` = self-adversarial record 유지). JSON `codex_critic_round_files` → `self_adversarial_files`. AX-008 source = Forge + Self-Adversarial + Architect (2/3 불변). 참조에서 deprecated `codex-round.md` 제거. Section 7 `ARCHIVED_REJECTED_BY_CODEX`는 과거 artifact 기록값이라 enum 유지(historical).

## 참조

- `02_Infrastructure/worktask/artifact_contract.json` (JSON SOT)
- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (Active Path 의무 자산 위치)
- `.claude/skills/qvest-worktask/SKILL.md` Section 2~5
- AX-008 v2.0 (결정 수치는 R 계약 산출만 인용 · 독립 검증 = Judge — 2026-09-23 도훈 AX-D5, 구 v1.1 3자 교차검증 2-of-3 은 `AX-008.json::history` 사료) — `.claude/rules/axioms.md`
- L-270 (Bayesian validation + drift evidence)
