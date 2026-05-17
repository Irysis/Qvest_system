# Multi-Sleeve Constraint Validation (Step 4.3)

**Task**: WT-D20260517_004 — DPL-RC v2.0 Path A NAV-level blend
**Agent**: optimizer-research
**Generated**: 2026-05-17
**Charter Reference**: §10 v1.8 (multi_sleeve_charter_exception_request) + L-279~L-281 Hybrid precedent

---

## 1. AX-007 Exemption Double Invocation

### 1.1 AX-007 Constitution

AX-007 [methodological]: `roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절`. **예외 4종**:

1. **multi-sleeve** (sleeve 분리, 각 sleeve own constraints)
2. **long-short** (negative weight 허용)
3. **50+ 분산** (Grinold breadth 확장)
4. **ML sizing** (continuous weight from ML predictor)

### 1.2 Path A NAV-level Blend의 #1 + #4 동시 발현

- **Exemption #1 (multi-sleeve)** by construction:
  - sleeve_A = STR_1715_5_Layer (production retain, max_names = 20)
  - sleeve_B = comp_sleeve (max_names = 20 strict, 1715-external universe)
  - blend wealth share: a_t scalar

- **Exemption #4 (ML sizing)** by construction:
  - comp_sleeve weights from S1/S2/S3/S4 scorer + softmax (continuous ML-derived)
  - a_t = clip(a_max · p_bad_1715(t+1|t), 0, a_max) (continuous ML-derived)

→ **두 AX-007 예외 동시 정합**. L-307~L-313 single-sleeve 100% (1715 PG2) admit precedent inherit 위에 multi-sleeve 확장.

## 2. Sleeve-Level Hard Constraints

### 2.1 Sleeve A — STR_1715_5_Layer (Production Retain)

| Constraint | Value | Source |
|---|---|---|
| max_names | 20 | L-307 admit retain |
| weight_bounds | [0, 0.20] | Production admit retain |
| Σw | = 1 per-sleeve | Production admit retain |
| long_only | true | Production admit retain |
| structure | w_str1715 × m4 × β_AR × β_R05 | L-307 5-Layer architecture |
| Lockbox scope | forge cycle 폐기 (도훈 mandate 2026-05-09) | rules/lockbox-scope.md |

**변형 절대 금지**: alpha-package multi_sleeve_charter_exception_request `production_retain_explicit: true` 강제.

### 2.2 Sleeve B — comp_sleeve (NEW)

| Constraint | Value | Hook L3 |
|---|---|---|
| max_names | 20 strict | worktask_constraint_enforcer.sh |
| weight_bounds | [0, 0.20] | worktask_constraint_enforcer.sh |
| Σw | = 1 per-sleeve | worktask_constraint_enforcer.sh |
| long_only | true | worktask_constraint_enforcer.sh |
| universe | KR_TOP500_LIQ1E8 ∖ STR_1715_top_20 | universe_filter_secondary (risk C7 path B) |
| liquidity_min | 20d avg TV ≥ 2e8 KRW | universe filter |
| sector_active_weight_cap | ≤ 0.30 | risk_package max_sector_weight |
| turnover_annualized | ≤ 6.0 per-sleeve | A5 admission gate |
| cost_model | 25bps one-way (illiquid surcharge) | risk_package comp cost |

### 2.3 Blend-Level (NAV synthetic constraints)

| Constraint | Value | Source |
|---|---|---|
| `a_t` injection range | [0, a_max], a_max ∈ {0.05, 0.10, 0.15, 0.20} | injection_grid §2.2 |
| `a_t` smoothing β_a | default 0.50 (grid 0.30~1.0) | clipping_audit §4.2 |
| `cor(NAV_comp, NAV_1715)` | ≤ 0.30 (walk-forward OOS, 52m) | G2 admission |
| MDD_blend | ≥ -0.2481 (= 1715 admit MDD, no_worse) | A2 admission |
| SR_blend | ≥ 1.97 (= 1715 admit SR + ε) | A1 admission |
| TO_blend_annualized | ≤ 6.0 | A5 admission |
| blend_cost_ceiling | ≤ 20bps annualized | risk_package risk_constraints |

### 2.4 max_names_union (Charter §10 v1.8 exception)

```
sleeve_A.max_names + sleeve_B.max_names = 20 + 20 = 40 union maximum
```

**Charter §10 v1.8 base rule**: max_names_total ≤ 20.
**Exception request**: alpha_package multi_sleeve_charter_exception_request — 도훈 explicit confirm + governor admission gate audit pending.

→ **risk_package challenge_flags[0] RISK_CHALLENGE_C6_HARD_CONSTRAINT_OVERRIDE_PENDING** 정합. resolution path:
1. 도훈 explicit confirm (Q-Lead 보고 후)
2. governor admission gate audit (Charter §10 v1.8 multi_sleeve formal exception path)
3. reject 시 paradigm DEFER

## 3. 7 Hard Constraints Sleeve-Level Validation Table

| ID | Constraint | Sleeve A (1715) | Sleeve B (comp) | Blend |
|---|---|---|---|---|
| HC1 | Σw = 1 | ✓ (retain) | ✓ (strict) | a + (1-a) = 1 ✓ |
| HC2 | 0 ≤ w ≤ 0.20 | ✓ (retain) | ✓ (strict) | a ∈ [0, 0.20] ✓ |
| HC3 | long_only | ✓ (retain) | ✓ (strict) | ✓ |
| HC4 | max_names ≤ 20 | ✓ (retain) | ✓ (strict) | union 40 exception |
| HC5 | TE / active neutral | inherit (1715 active mgmt retain) | active neutral comp sleeve target | blend active TE measure |
| HC6 | sector_cap ≤ 0.30 | inherit (1715 retain) | strict (universe filter) | blend sector measure |
| HC7 | ADV / liquidity | inherit (LIQ 2e8) | strict (1e8 universe filter) | blend ADV measure |
| HC8 | TO ≤ 6.0/yr | inherit (1715 retain) | strict (A5 admission) | blend TO ≤ 6.0 |

**Hook L3 enforcement**: `worktask_constraint_enforcer.sh` sleeve-level binding 적용. union 40은 governor exception path 별도.

## 4. AX-007 + AX-001 v2 Joint Compliance

### 4.1 AX-001 v2 (방어형 conditional)

```
AX-001 v2: 방어형 팩터는 조건부 성과 (crisis_alpha + MDD 완화 + bad/normal IC ratio)
```

comp_sleeve 역할 = **bad_state-conditional complement** → AX-001 v2 적용:

| Axis | Threshold | Source |
|---|---|---|
| crisis_alpha_bad_state_improvement_sr | ≥ 0.30 | risk_package ax_001_v2_three_axis |
| mdd_alleviation_no_worse_than_str_1715 | ≥ -0.2481 | risk_package ax_001_v2_three_axis |
| bad_normal_ic_ratio_min | ≥ 2.0 | risk_package ax_001_v2_three_axis |

**All 3 axes PASS 필수**. ANY axis FAIL = HARD ABORT.

### 4.2 STR_1715 PG2 N/A_PURE_OVERLAY Precedent (L-307)

L-307: STR_1715 PG2 admit = `AX-001 v2 ruling: N/A_PURE_OVERLAY` (Kritzman-Page-Turkington 2011 FAJ inherit).

→ **본 cycle은 AX-001 v2 strict 적용**: comp_sleeve는 pure overlay NOT (NAV-level small injection이지만 conditional injection mechanism이므로 defensive factor 조건부 평가 의무).

## 5. multi_sleeve_charter_exception_request Governance Audit

### 5.1 Request Body (alpha_package inherit)

```json
{
  "exception_type": "multi_sleeve_admission_2_sleeve_blend",
  "Charter_rule_overridden": "§10 v1.8 max_names_total ≤ 20 (base) → 40 union (exception)",
  "academic_backbone": "L-279 Hybrid 70/15/15 precedent (3-sleeve admit) + AX-007 exemption #1 + AX-001 v2 conditional",
  "max_names_per_sleeve_retain": 20,
  "production_lineage_safety": "STR_1715 PG2 100% retain (production READ ONLY, safety_guard hook)",
  "approval_required_by": ["도훈 explicit confirm", "governor admission gate"]
}
```

### 5.2 Governance Decision Flow

```
Step 1: Forge cycle measurement (16 candidates + Pareto + λ_corr grid)
Step 2: Q-Lead report → 도훈 review
Step 3: 도훈 explicit confirm (a_max + stage 선택)
   ├── confirm → governor admission gate
   │   ├── all 9 gates + AX-008 ≥ 2/3 PASS → admit
   │   └── ANY gate FAIL → DEFER
   └── reject → paradigm DEFER
```

**현재 상태**: design_phase_a 완료, Forge cycle pending.

## 6. L-279 Multi-Sleeve Admit Precedent 정합 분석

### 6.1 L-279 Hybrid 70/15/15 Admit Profile

```
Sleeve 1: STR_1715_AR_threshold_overlay (70% weight)
Sleeve 2: TSMOM_ETF_rotation (15% weight)
Sleeve 3: KR_10y_bond_ETF (15% weight)
admitted_ids: 3-source orthogonal
book_state: v2.1 mutated
```

### 6.2 본 cycle 정합 매핑

| 항목 | L-279 (3-sleeve) | 본 cycle (2-sleeve NAV blend) |
|---|---|---|
| sleeve count | 3 | 2 |
| weight allocation basis | fixed static (70/15/15) | conditional dynamic (a_t bad-state) |
| max_names per-sleeve | 20 each | 20 each (1715 retain + comp NEW) |
| max_names union | 60 (theoretical) | 40 (theoretical) |
| AX-007 exemption | #1 (multi-sleeve) | #1 (multi-sleeve) + #4 (ML sizing) |
| AX-001 v2 | conditional (TSMOM defensive) | conditional (comp bad-state) |
| Backtest Contract | v1.0 PerformanceAnalytics standard | v1.0 same-harness 1715-recomputed |

→ **L-279 precedent 직접 정합**. multi-sleeve admit framework 검증된 path retain.

### 6.3 차별점 (NAV-level blend specific)

- L-279 = static weight allocation
- 본 cycle = **dynamic conditional injection** (`a_t` time-varying)

→ 추가 audit 항목:
- `a_t` smoothing β_a constraint (clipping_audit §4.2)
- effective TO 3-layer decomposition (clipping_audit §4.3)
- conditional vs unconditional sleeve mix → AX-001 v2 strict 적용

## 7. Hook L3 Block Test Matrix

Forge cycle 실행 시 다음 hook 자동 발동:

| Hook | Trigger | Expected Behavior |
|---|---|---|
| `worktask_constraint_enforcer.sh` | weights.csv write | sleeve-level constraint check |
| `axiom_enforcement_hook.sh` | AX-007 / AX-001 violation | block on hard violation |
| `safety_guard.sh` | 05_Production/ write | block (1715 production READ ONLY) |
| `codex_round_pre_enforcer.sh` | optimization_package.json write | block if _draft + critic_response 부재 |

→ 본 design-phase-a `_draft` + critic_response 2-file precondition 정합 후 final write.

## 8. Output (Design-Only Scope)

본 validation은 **design-only**. 실제 sleeve-level constraint adherence test = forge cycle 의무:
- `stage_artifacts/WT_D20260517_004/sleeve_constraint_test_per_cell.csv` (16 cells × 8 HC)
- `stage_artifacts/WT_D20260517_004/exception_request_governance_decision.json` (도훈 confirm 후 update)

---

## References

- L-279~L-281 — Hybrid 70/15/15 multi-sleeve admit (3-source orthogonal)
- L-307 — STR_1715 PG2 single-sleeve admit (5-Layer architecture)
- AX-007 — single_sleeve_long_only_top20 exemption 4 cases
- AX-001 v2 — defensive factor conditional evaluation
- Charter §10 v1.8 — multi_sleeve_charter_exception_request formal path
- Kritzman-Page-Turkington 2011 FAJ — pure overlay precedent (L-307)
- risk_package risk_constraints_for_dpl_rc_v2_forge — sleeve constraints inherit
- alpha_package multi_sleeve_charter_exception_request — exception body
