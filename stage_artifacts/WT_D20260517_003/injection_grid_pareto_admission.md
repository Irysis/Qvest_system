# DPL-RC Injection Grid Pareto Admission Curve Design

**WT-D20260517_003 · optimizer-research Step 4.1**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Parents**:
- alpha_package.json (factor_specs §dpl_rc_paradigm_main + §complement_scorer_4_stage_incremental + §admission_criteria_7_axis_framework + decision_gates G0-G9)
- risk_package.json (cross_covariance_design + injection_risk_matrix 32 cells + tail_risk_audit_extended + crowding_audit_extended)
- complement_scorer_4_stage.md (Section 5 incremental admission flow)
- conditional_loss_7axis_admission.md (Section 1.3 λ values + Section 4 admission protocol)
- cross_covariance_design.md (Section 1.4 pooled OOS primary + DCC bivariate)
- conditional_risk_attribution.md (Section AX-001 v2 3-axis mapping)

**Mandate (도훈 mandate B.2)**: DESIGN ONLY — Pareto admission curve protocol design, no measurement (Forge cycle responsibility). All point estimates carry `학술 prior, NOT measured` label.

**Hook compliance (PreToolUse worktask_constraint_enforcer + codex_round_pre_enforcer)**:
- max_names ≤ 20 (top-K from complement scorer)
- weight_bounds [0, 0.20]
- Σw = 1 (blend final after renormalization)
- long-only (DPL-RC complement designed long-only)

---

## 0. Step 4.1 핵심 목적

DPL-RC v1.0의 핵심 design output. **Injection grid 16 candidates Pareto frontier identification protocol**.

Traditional optimizer (MVO/HRP/CVaR)는 stock-level weight optimization → 본 cycle 적용 X.

DPL-RC optimizer 역할 = **injection-based blend의 admission decision curve 설계**:

```
candidate(stage, a_max) = (1 - a_t(t; a_max)) · w_1715(t) + a_t(t; a_max) · w_comp_stage(t)
where a_t(t; a_max) = clip(a_max · p_bad_1715(t+1), 0, a_max)
```

→ 4 complement scorer stages × 4 a_max values = **16 candidates** (Section 1)
→ 각 candidate에 대해 **7-axis admission tuple** 측정 (Section 2)
→ Pareto frontier (Section 3) → admission-eligible candidates 자동 식별 (Section 4)

---

## 1. Candidate space — 16 candidates (4 × 4)

### 1.1. 4 complement scorer stages (alpha cycle inherit)

| Stage | Method | Effective params | Source |
|---|---|---|---|
| S1 | Linear PPP (Brandt 2009) | 80 | complement_scorer_4_stage §1 |
| S2 | Elastic Net | ~30-50 (L1 sparsity) | complement_scorer_4_stage §2 |
| S3 | LightGBM | ~3-5K | complement_scorer_4_stage §3 |
| S4 | DPL-RC Neural (Set-Sequence) | ~30K | complement_scorer_4_stage §4 |

### 1.2. 4 a_max values (injection scale)

| a_max | Production interpretation |
|---|---|
| 0.05 | minimal complement injection (5% peak) — 1715 dominant 95%+ |
| 0.10 | moderate (10% peak) — 1715 90%+ baseline |
| 0.15 | meaningful (15% peak) — 1715 85%+ |
| 0.20 | strong (20% peak) — 1715 80%+ baseline |

**Rationale**: a_max ≥ 0.25 → 1715 production lineage 손상 risk + Codex 보수적 admission rule (G4 MDD no_worse) 위반 risk 증가. 5-20% range는 학술 backbone (Asness-Frazzini-Pedersen 2014 BAB 표준 conditional injection scale).

### 1.3. 16 candidate matrix

```
candidate_grid = {(S1, 0.05), (S1, 0.10), (S1, 0.15), (S1, 0.20),
                  (S2, 0.05), (S2, 0.10), (S2, 0.15), (S2, 0.20),
                  (S3, 0.05), (S3, 0.10), (S3, 0.15), (S3, 0.20),
                  (S4, 0.05), (S4, 0.10), (S4, 0.15), (S4, 0.20)}
```

**Incremental admission caveat (complement_scorer_4_stage §5.1)**: Stage N+1은 Stage N 대비 incremental gain 입증 후에만 진행 → Forge cycle 실제 측정 시 S2/S3/S4 candidate가 자동 ABORT 가능. 본 design은 **all 16 candidates measurable** assumption (worst-case full grid).

---

## 2. Per-candidate metric measurement protocol (7-axis admission)

각 candidate (stage, a_max)에 대해 다음 tuple 측정:

| Axis | Metric | Target | Measurement scope | Source |
|---|---|---|---|---|
| A1 | Overall SR | ≥ 1.97 | Walk-forward OOS 52m aggregation | alpha_package §admission_criteria_7_axis_explicit + cross_covariance_design §1.1 |
| A2 | Overall MDD | ≥ -24.81% | Walk-forward OOS 52m aggregation | alpha_package + risk_package injection_risk_matrix |
| A3 | Good-state drag SR | ≤ 0.05 | bad/good state split (alpha cycle Definition 1 default) | conditional_risk_attribution §AX-001 v2 mapping |
| A4 | Bad-state improvement SR | ≥ +0.30 | bad state SR(blend) - bad state SR(1715) | conditional_risk_attribution + AX-001 v2 axis 1 |
| A5 | Turnover (annualized) | ≤ 6 | TO_blend = Σ a_t · TO_comp_t (annualized) | conditional_loss_7axis §3.5 |
| A6 | Cor vs 1715 (pooled OOS) | ≤ 0.3 | walk-forward OOS pooled (52m, NOT full 124) | cross_covariance_design §1.1 + §1.4 |
| A7 | p_bad OOS AUC | ≥ 0.55 | classifier OOS validation 3 sub-windows | p_bad_classifier_protocol.md + AX-001 v2 axis 3 |

### 2.1. Walk-forward OOS measurement protocol (C1 strict)

**Lockbox 정합 (alpha-research / risk-research / optimizer-research)**:
- 5 walk-forward windows, each W = (Train 60m, Val 12m, Test 12m), purge 1m + embargo 1m
- OOS test pooling: 52m net test (5 × 12m - overlap purge)
- **G2/G3/G4/G5/G6 모든 admission OOS only** (C1 strict, Codex C4 ACCEPT lineage)

### 2.2. p_bad classifier prerequisite (HARD gate G1)

**모든 candidate measurement은 G1 PASS 후에만 진행**:
- AUC ≥ 0.55 + Brier < 0.24 + bad_recall ≥ 0.60
- G1 fail → HARD ABORT (사후 regime fitting 차단) — p_bad_classifier_protocol §6.4 lineage
- G1 stability G8 (3 sub-windows AUC ≥ 0.55) 동시 만족 시 a_t injection 신뢰 가능

### 2.3. Bad-state SR computation

Bad-state subset SR (axis A4):
```
SR_bad_blend(stage, a_max) = mean(r_blend_t | bad_1715_t = 1) / std(r_blend_t | bad_1715_t = 1) · sqrt(12)
SR_bad_1715 = mean(r_1715_t | bad_1715_t = 1) / std(r_1715_t | bad_1715_t = 1) · sqrt(12)
A4 = SR_bad_blend - SR_bad_1715
```

**Sample size caveat (conditional_risk_attribution §Sample thin handling)**: bad state n=25-30 sig_dates → bootstrap CI (Politis-Romano 1994, B=1000, 95%) mandate. CI width > 1.5x point → DEFER.

### 2.4. Cost-aware net return (P2 정합)

모든 SR 측정은 **net of cost (15bps one-way)**:
```
r_blend_net,t = r_blend_gross,t - 15bps · TO_blend_t
```

Research Philosophy P2 (Cost > Gross) + Charter §15 + Backtest Contract v1.0 정합.

---

## 3. Pareto frontier identification protocol

### 3.1. Multi-objective formulation

7 axes 중 admission threshold 외 **2-3 axis 우선 multi-objective**:

```
Maximize:
  (1) A1 overall SR (target ≥ 1.97)
  (2) A4 bad-state improvement (target ≥ +0.30)
  (3) -A5 turnover (target ≤ 6, equivalent to minimization)

Subject to (hard constraints):
  A2 ≥ -24.81% (MDD no_worse, 코덱스 보수적)
  A3 ≤ 0.05 (good-state drag, alpha core preserve)
  A6 ≤ 0.3 (cor, 4th sleeve qualification)
  A7 ≥ 0.55 (p_bad OOS AUC, state predictability)
  G1 PASS (p_bad classifier)
  Σw = 1, w ∈ [0, 0.20], top_K ≤ 20 (Hook L3)
```

**Rationale for 3-objective Pareto (vs 7-axis full)**:
- A2/A3/A6/A7는 **hard constraint** (Pareto에서 filter 후 dominance check)
- A1/A4/A5는 **trade-off frontier** — DPL-RC paradigm essence
  - A1 ↑ + A4 ↑ vs A5 ↑ (more injection → more TO)
  - Stage 4 Neural 더 복잡 → A1/A4 향상 vs A5 (turnover) cost
- A5 (TO)는 production cost-aware constraint이지만 frontier value에서 보임 (소량 ↑ = a_max ↑ trade-off)

### 3.2. Pareto dominance criterion

Candidate $c_i = (A1_i, A4_i, -A5_i)$ Pareto-dominates $c_j$ iff:
```
A1_i >= A1_j AND A4_i >= A4_j AND -A5_i >= -A5_j
AND (A1_i > A1_j OR A4_i > A4_j OR -A5_i > -A5_j)
AND c_i passes ALL hard constraints (A2, A3, A6, A7, G1)
```

### 3.3. Algorithm — Pareto front extraction

```python
def pareto_front(candidates):
    """
    candidates: list of dicts with keys A1, A2, A3, A4, A5, A6, A7, g1_pass, hard_pass
    returns: subset that is non-dominated
    """
    # Step 1: filter by hard constraints
    feasible = [c for c in candidates if
                c['A2'] >= -0.2481 and
                c['A3'] <= 0.05 and
                c['A6'] <= 0.3 and
                c['A7'] >= 0.55 and
                c['g1_pass'] and
                c['hard_pass']]  # 20/0.20/Σw=1/long-only
    # Step 2: Pareto dominance on (A1, A4, -A5)
    front = []
    for ci in feasible:
        dominated = False
        for cj in feasible:
            if ci is cj: continue
            if (cj['A1'] >= ci['A1'] and
                cj['A4'] >= ci['A4'] and
                -cj['A5'] >= -ci['A5'] and
                (cj['A1'] > ci['A1'] or cj['A4'] > ci['A4'] or -cj['A5'] > -ci['A5'])):
                dominated = True
                break
        if not dominated:
            front.append(ci)
    return front
```

**Complexity**: O(16²) = 256 comparisons → trivial.

### 3.4. Tiebreaker — selection objective `crowding_adj_ret`

v6.1 R4 P3 정합 (init prompt §v61_selection_objective). Pareto front에 multiple candidates 잔존 시:

```
selection_score(c) = A1_c - φ_cr · crowding_score_c
where:
  crowding_score_c = Acadian 2026 + role checklist composite (risk_package §crowding_audit_extended)
  φ_cr = 0.1 (default crowding penalty weight)
```

**Rationale**:
- A1 (SR) 1순위 (production target gap 0.0464 closure)
- crowding penalty 2순위 (Acadian 2026 + role checklist L-219 family saturation)
- `crowding_adj_ret` = `net_ir` family 정합 (v6.1 R4 P3 enum 옵션)

선택 metric 명시 단일화: 도훈 명시 mandate 부재 시 default `crowding_adj_ret`.

### 3.5. 학술 prior expected Pareto behavior (NOT measured)

**Frazzini-Pedersen (2014) BAB + Asness-Frazzini-Pedersen (2014) QMJ + Ferson-Schadt (1996) 학술 prior**:
- a_max 증가 → A4 (bad-state improvement) monotonic 증가 (BAB conditional 정합)
- a_max 증가 → A5 (turnover) monotonic 증가
- a_max 증가 → A1 (overall SR) initial 증가 후 plateau / 감소 (drag penalty + TO cost dominate)
- Stage 복잡도 증가 (S1→S4) → A1/A4 marginal 향상, A5 변동 작음

**Expected dominant region (학술 prior, NOT measured)**:
- a_max ∈ {0.10, 0.15} sweet spot
- Stage 2-3 (interpretable + non-linear gain) > Stage 4 (Neural over-param risk)
- Stage 1 baseline은 paradigm validity baseline check (incremental gain 입증 baseline)

→ Forge cycle empirical measurement에서 Pareto front은 **2-5 candidates** 예상 (학술 prior, NOT measured).

---

## 4. Admission decision flow

### 4.1. Multi-stage gate (decision_gates G0-G9 정합)

```
[Step 0] G0 PIT compliance audit (Forge cycle pit_audit_v3.json)
  → FAIL → HARD ABORT

[Step 1] G1 p_bad classifier OOS gate (AUC ≥ 0.55 + Brier < 0.24 + recall ≥ 0.60)
  → FAIL → HARD ABORT (사후 regime fitting 차단)
  → PASS → proceed

[Step 2] G8 p_bad sub-window stability (3 windows AUC ≥ 0.55)
  → FAIL → soft warning, mark candidate AUC_unstable
  → PASS → proceed

[Step 3] Measure 16 candidates → 7-axis tuple per candidate
  → Forge cycle responsibility (~6h compute alpha + ~3.5h risk)

[Step 4] Apply hard constraint filter (Pareto algorithm Section 3.3 step 1)
  → A2 / A3 / A6 / A7 / G1 / Hook L3 모두 PASS 만 잔존
  → If 0 candidate survives → DEFER (admission infeasible)

[Step 5] Pareto frontier extraction (Section 3.3 step 2)
  → 2-5 candidates 예상 (학술 prior)

[Step 6] Tiebreaker — crowding_adj_ret rank
  → Top 1-3 candidates 명시
  → 도훈 explicit selection 시 도훈 mandate retain (override authorized)

[Step 7] G9 AX-008 verification triangulation
  → Forge + Codex + Architect 2/3 PASS
  → FAIL → DEFER

[Step 8] Governor admission decision
  → admit (1-a_t)·w_1715 + a_t·w_comp_stageX with a_max=Y
  → book_state mutation (1715 100% → 1715 (1-a_t) + complement a_t)
  → OR DEFER (Pareto front insufficient gain)
  → OR REJECT (multiple stages incremental fail)
```

### 4.2. ABORT triggers

| Trigger | Condition | Action |
|---|---|---|
| G0 PIT fail | Forge audit fail | HARD ABORT |
| G1 p_bad fail | AUC<0.55 OR Brier>0.24 OR recall<0.60 | HARD ABORT |
| Stage 1 marginal | (1-a_max)·1715 + a_max·S1 SR < 1715 SR + 0.02 | ABORT cycle |
| All bad-state def fail | Step 3.2 9 candidates all fail | ABORT cycle |
| Pareto front empty | hard constraints filter survives 0 | DEFER |
| MDD worse than 1715 | ANY candidate A2 < -24.81% | HARD ABORT per candidate (Codex 보수적) |
| Codex REJECT veto=true | Codex Round critic veto fired | DEFER |

### 4.3. Incremental admission interaction (complement_scorer §5.1)

S1/S2/S3/S4 4-stage incremental admission이 이미 alpha cycle에서 정의되어 있음:
- Stage N+1 vs Stage N: SR + 0.05 OR MDD + 1-2pp OR cor - 0.05 (3 중 1+)
- Stage N incremental fail → Stage N retain final, stop

**Pareto admission decision는 incremental admission 통과한 stages에서만 진행**:
```
forge_cycle_active_stages = {S1}                          # baseline
                          ∪ {S2 if S2 incr S1 PASS}
                          ∪ {S3 if S3 incr S2 PASS}
                          ∪ {S4 if S4 incr S3 PASS}
candidates_active = forge_cycle_active_stages × {0.05, 0.10, 0.15, 0.20}
```

worst case (all incremental PASS): 16 candidates.
best case (S2 incremental fail): 4 candidates (S1 × 4 a_max).

---

## 5. Method shopping log (v6.1 R2-C compliance)

본 step은 traditional method shopping (MVO/HRP/CVaR/ERC/PPO 비교) 아님 — DPL-RC injection-based paradigm. 그러나 v6.1 R2-C는 method comparison ≥ 3건 mandate.

**method_shopping_log applied to injection admission strategies** (3 methods, NOT 16 candidates):

| Method | Description | Selection? | Rationale |
|---|---|---|---|
| `injection_grid_pareto_admission` | 16 candidates 7-axis Pareto frontier + tiebreaker (본 design) | **YES (primary)** | DPL-RC paradigm 정합, design objective, alpha cycle inherit |
| `single_a_max_optimal_grid` | a_max ∈ {0.05, ..., 0.20} grid search at S1 only | NO | Stage incremental opportunity 손실 (S2-S4 가능성 0) |
| `bo_bayesian_optim_a_max` | Bayesian opt a_max continuous [0, 0.25] | NO | T=124 sample insufficient for Bayesian opt + production interpretability ↓ + Pareto inherent multi-objective |

**Method comparison count**: 3 (≥ 3 minimum, ≤ 10 cap).

---

## 6. Expected Pareto curve shape (학술 prior, NOT measured)

학술 prior (Ferson-Schadt 1996 + AFP 2014 + Avramov 2023 + Wood 2026 정합) 추정:

```
          A4 (bad-state improvement)
              ▲
      0.60   │     · S3@0.20
             │     · S4@0.20
      0.50   │   · S3@0.15
             │     · S4@0.15
      0.40   │ · S3@0.10
             │   · S4@0.10  ← expected Pareto sweet spot
      0.30   │· S3@0.05   ◄─── G6 threshold (target ≥ +0.30)
             │ · S2@0.10
      0.20   │· S2@0.05
             │· S1@0.05
      0.10   │
             │
       0.00  └──────────────────────────────► A1 (overall SR)
              1.95   1.98   2.00   2.02   2.05
                  ▲
              G3 threshold (target ≥ 1.97)
```

**학술 prior expected (NOT measured)**:
- S3 (LightGBM) + a_max ∈ {0.10, 0.15} = expected sweet spot
- S1 (PPP) + a_max ∈ {0.05} = robust baseline
- S4 (Neural) marginal vs S3 (Avramov 2023 §V.B empirical finding)

**a_max selection priors**:
- a_max=0.05: A4 small, A2 retained, low risk, conservative admit
- a_max=0.10: A4 meaningful, A2 retained, balanced
- a_max=0.15: A4 strong, A2 marginal, moderate risk
- a_max=0.20: A4 strong, A2 borderline at G4 (-24.81%), high risk

**Forge cycle measurement mandate**:
- 학술 prior estimates 폐기
- 실제 walk-forward 5-window OOS aggregation
- bootstrap CI 95% for all 7 axes (Politis-Romano 1994)
- DSR Bailey-LdP n_trials=7200 (alpha cycle inherit)

---

## 7. Charter §15 Research Philosophy alignment

| Principle | DPL-RC Pareto admission application |
|---|---|
| P1 Factor Zoo 축소 | 4 scorer stages (interpretable to Neural) — `redundancy_cluster_id` 정합 inherit (v2 fmp_ranking) |
| P2 Cost-aware Alpha | A5 turnover ≤ 6 hard constraint + λ_to penalty + net return measurement (15bps) |
| P3 Uncertainty-aware | p_bad classifier OOS gate G1 + bootstrap CI mandate (Politis-Romano) |
| P4 Direct Portfolio Learning | ★ DPL-RC paradigm 핵심 — features → injection-weighted blend weights 직접 |
| P5 Risk Model + Crowding | A6 cor ≤ 0.3 (anti-crowding) + tiebreaker crowding_adj_ret |
| P6 Implementation Discipline | TO ≤ 6 + LIQ 2e8 + max_names 20 + bounds [0, 0.20] + Σw=1 hard |
| P7 Attribution & Feedback | Sleeve 분리 (1715 + complement) → bad/good state contribution 분해 가능 |

---

## 8. Q-Lead handoff — Forge cycle mandate

### 8.1. Forge cycle responsibility (도훈 mandate B.2)

- p_bad classifier training + OOS validation (G1 + G8)
- 4-stage complement scorer training (incremental admission)
- per-candidate (stage, a_max) 7-axis measurement (walk-forward 5-window OOS)
- Pareto front extraction (Section 3.3 algorithm)
- Crowding score per candidate (Acadian 2026 + role checklist composite)
- Tiebreaker rank by selection objective `crowding_adj_ret`
- bootstrap CI 95% for all metrics (Politis-Romano 1994)

### 8.2. Forge artifacts expected

```
stage_artifacts/WT_D20260517_003/
├── pareto_candidates_16_metrics.parquet     # 16 rows × 7 axes
├── pareto_front_filtered.parquet            # 2-5 candidates 예상
├── tiebreaker_rank.json                     # crowding_adj_ret ranking
├── admission_decision.json                  # 도훈 explicit selection 후 final
└── bootstrap_ci_per_candidate.parquet       # 16 × 7 × {mean, lo, hi}
```

### 8.3. Governor mutation pre-spec

admit 시 `book_state.json` mutation pre-spec:
```json
{
  "admitted_ids": ["STR_1715_AR_on_M4_R05_overlay_PG2",
                   "STR_DPL_RC_complement_stage_X_amax_Y_PG2"],
  "book_weights_dynamic": {
    "STR_1715_AR_on_M4_R05_overlay_PG2": "1 - a_t (t-time)",
    "STR_DPL_RC_complement_stage_X_amax_Y_PG2": "a_t = clip(a_max·p_bad(t+1), 0, a_max)"
  },
  "a_max_admitted": "Y (도훈 explicit selection)",
  "selected_stage": "X (Forge cycle measured incremental admission)",
  "lineage": "STR_1715 (1-a_t) + DPL-RC complement (a_t) — Direct Portfolio Learning Residual Complement paradigm"
}
```

### 8.4. Deploy cutoff

- alpha cycle deploy_cutoff: 2026-04 canonical (PIT cutoff)
- Forge run_all.R: deploy_cutoff "2026-04" inherit
- Lockbox policy: alpha/risk/optimizer-research 3 단계 lockbox 적용, Forge cycle 자동 frozen 후 PG2 deploy

---

## 9. Self-check (Charter §10 Role Card discovery_design_phase_a)

| Requirement | Status |
|---|---|
| `factor_specs ≥ 1` (Hook codex_round_pre_enforcer) | N/A optimizer (alpha 영역) |
| `method_shopping_log ≥ 3` (v6.1 R2-C) | ✅ 3 methods (injection_grid_pareto / single_a_max / bo_bayesian) |
| `selection_objective` enum (v6.1 R4 P3) | ✅ `crowding_adj_ret` (default tiebreaker) |
| Hard constraints documented | ✅ Section 2 + Section 4.1 |
| PIT compliance (C1 OOS only) | ✅ Section 2.1 walk-forward OOS only |
| AX-001 v2 mapping | ✅ Section 2 A3/A4 ↔ AX-001 v2 axis 1/2 |
| AX-007 exemption | ✅ multi-sleeve (1715 + complement) + ML sizing (4-stage scorer) exemption #1 + #4 |
| Research Philosophy 7 principles | ✅ Section 7 explicit mapping |
| Codex Round mandate | Forthcoming — `_draft` 작성 후 background spawn |
| 학술 prior NOT measured label | ✅ Section 3.5 + Section 6 명시 |

---

## 10. Submission

**Submitted**: 2026-05-17 optimizer-research Step 4.1.
**Deliverable**: `stage_artifacts/WT_D20260517_003/injection_grid_pareto_admission.md` (본 file)
**Next**: Step 4.2 Decision-induced ranking clipping audit (Wang-Hasuike 2026 KKT)
