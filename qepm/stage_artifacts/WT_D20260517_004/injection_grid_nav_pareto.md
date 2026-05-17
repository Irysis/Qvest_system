# Injection Grid NAV-Level Pareto Admission Curve (Step 4.1)

**Task**: WT-D20260517_004 — DPL-RC v2.0 Path A NAV-level blend
**Agent**: optimizer-research
**Generated**: 2026-05-17
**Design-phase-a (Charter §10 v1.8)**: protocol design only — measurement은 Forge cycle 의무

---

## 1. Paradigm Shift (v3 weights-level → v4 NAV-level)

WT-D20260517_003 A안 weights-level DEFER 3 structural blockers:
- **B1**: G1 classifier recall 0.089 (target ≥ 0.55)
- **B2**: cor 0.9997 by construction (weights-level same-universe 한계)
- **B3**: cross-base measurement mismatch (1715-frozen vs 1715-recomputed)

→ **NAV-level resolution path**:
1. **Universe physical separation**: `comp ⊆ KR_TOP500_LIQ1E8 ∖ STR_1715_top_20`. overlap 0% by construction → cor design choice 자율 (학술 prior 0.3-0.6, Codex C3 honest).
2. **NAV-level blend**: `NAV_blend(t) = (1-a_t)·NAV_1715_5Layer(t) + a_t·NAV_comp(t)`. production 100% retain (R05_overlay 5-layer 무수정).
3. **same-harness Backtest Contract v1.0**: PerformanceAnalytics standard functions only. 1715-recomputed canonical basis, NOT 1715-frozen. cross-base mismatch B3 해소.

## 2. Candidate Space (4 × 4 = 16)

### 2.1 Scorer Stage Hierarchy (alpha-research complement_scorer §1-§4 inherit)

| Stage | Method | Param count | Expected baseline rationale |
|---|---|---|---|
| S1 | Linear PPP (Brandt-Santa-Clara-Valkanov 2009 RFS) | 80 features × 1 = 80 | Closed-form OLS, interpretable. KR T=60 N=20 sample-thin baseline. |
| S2 | Elastic Net (Zou-Hastie 2005 JRSS-B) | 80 + α + λ_1/λ_2 | L1 sparsity + L2 shrinkage. Codex C2 PARTIAL_ACCEPT honest middle-ground. |
| S3 | LightGBM (Ke et al. 2017 NeurIPS) | leaves × depth × η × n_round | Non-linear interaction captured. Wood-Roberts-Zohren 2026 DeePM analog. |
| S4 | DPL-RC Neural (You-Zhang 2025 + Wood et al. 2026) | MLP residual block + dropout 0.3 | Direct Portfolio Learning, end-to-end. Research Philosophy P4 (Phase 3 candidate). |

### 2.2 a_max Grid

```
a_max ∈ {0.05, 0.10, 0.15, 0.20}
```

**Academic rationale (Asness-Frazzini-Pedersen 2014 QMJ + Frazzini-Pedersen 2014 BAB JFE)**:
- 5% = conservative tilt (BAB-style minimal exposure to factor)
- 10% = standard conditional injection (Carry / momentum overlay scale)
- 15% = moderate complement budget
- 20% = aggressive ceiling (single-asset cap 정합, L-281 KR_10y bond admit precedent)

### 2.3 Incremental Admission Caveat

```
Stage N+1 → Stage N 대비 Δ(net_ir | crowding_adj_ret) ≥ 0.10 입증 시 진행.
worst case: 16 candidates (S1~S4 모두 admit)
best case: 4 candidates (S1 only admit, S2+ overfit blocked)
```

복잡도 incremental 정당화 = **Occam razor + Research Philosophy P1 (Factor Zoo 축소)**.

## 3. 7-Axis Admission Measurement (alpha cycle inherit)

### 3.1 Axes

| ID | Metric | Target | Type | Bootstrap CI |
|---|---|---|---|---|
| A1 | overall_SR (annualized) | ≥ 1.97 | maximize | 95% stationary, B=1000 |
| A2 | overall_MDD | ≥ -0.2481 | hard floor | 95% |
| A3 | good_state_drag_SR | ≤ 0.05 | soft cap | 95% |
| A4 | bad_state_improvement_SR | ≥ 0.30 | maximize | 95% |
| A5 | turnover_annualized_blend | ≤ 6.0 | hard cap | 95% |
| A6 | abs_cor(NAV_comp, NAV_1715) | ≤ 0.30 | hard cap | walk-forward OOS pooled (52m, NOT full 124) |
| A7 | p_bad_OOS_AUC | ≥ 0.55 | hard floor (G1) | 95% |

### 3.2 Cost-Aware Net Returns (Charter §15 P2, Jensen-Kelly-Malamud-Pedersen 2022)

```
net_return = gross_return - cost_model_v2.3 (15bps one-way × 2 = 30bps round-trip)
comp_sleeve cost: 25bps one-way (illiquid surcharge, risk_package C7 inherit)
blend_cost_ceiling: 20bps annualized (risk_package risk_constraints inherit)
```

모든 axis는 **net basis** measurement. A1/A4 gross 단독 측정 = Hook block (R4 P3 enforcement).

### 3.3 Bootstrap CI Mandate (Politis-Romano 1994 stationary)

```r
library(boot)
# block length = 12 (annual cycle), B = 1000
sb <- tsboot(returns_blend, statistic = sharpe_stat, R = 1000,
             l = 12, sim = "geom")
ci <- boot.ci(sb, conf = 0.95, type = "perc")
```

- **width > 1.5 → DEFER trigger** (risk_package bootstrap_ci_width_defer_trigger inherit)
- **52m sample → SE ≈ 1/√52 = 0.139, 95% CI half-width ≈ 0.27** (Codex C7 honest)

## 4. Pareto Frontier Protocol

### 4.1 Filter Step 1 — Hard Constraint Gate

```
HC1: max_names per-sleeve ≤ 20 (Hook L3)
HC2: long-only weights ≥ 0 (Hook L3)
HC3: weight_bounds [0, 0.20] (Hook L3)
HC4: Σw = 1 per-sleeve (Hook L3)
HC5: G1 AUC ≥ 0.55 (alpha-research G1 admission)
HC6: A2 MDD ≥ -0.2481
HC7: A3 drag ≤ 0.05
HC8: A6 cor ≤ 0.30
HC9: A7 p_bad AUC ≥ 0.55
```

→ ANY violation = candidate filtered OUT.

### 4.2 Filter Step 2 — Pareto Dominance on (A1, A4, -A5)

```
Multi-objective axes:
- A1 (overall_SR, maximize)
- A4 (bad_state_improvement, maximize)
- -A5 (negative turnover, maximize = minimize TO)

Domination rule:
candidate i dominates j ⟺
  A1_i ≥ A1_j AND A4_i ≥ A4_j AND -A5_i ≥ -A5_j
  AND (strict > in at least one axis)

Complexity: O(16²) = 256 pairwise = trivial
```

### 4.3 Tiebreaker — crowding_adj_ret

```
crowding_adj_ret = A1 - φ_cr · crowding_score_c
φ_cr = 0.10 (risk_package crowding inherit)
crowding_score_c = comp sleeve crowding (Acadian 80 features)
```

risk_package selection_objective = `condition_number` (Σ side).
optimizer selection_objective = **`crowding_adj_ret`** (R4 P3 정합, v3 inherit).

### 4.4 Expected Pareto Front Size

학술 prior 2-5 candidates (NOT measured). 다음 패턴 expected:
- **Low a_max + simple stage** (S1_a05): 보수, A1 marginal, A4 marginal, A5 lowest. defense corner.
- **Mid a_max + ML stage** (S3_a10 / S3_a15): balanced. likely admit candidate.
- **High a_max + neural stage** (S4_a20): aggressive. A1 highest possible, A5 risk, A2 MDD risk.

## 5. λ_corr Grid Search (risk_package C7 PARTIAL_ACCEPT primary path)

### 5.1 Motivation

risk_package β neutralization fallback DEFERRED (long-only compliance audit pending). primary path = **λ_corr training-side enforce**:

```
L_total = -E[r_blend] + γ_to · |Δw| + λ_corr · cor²(NAV_comp, NAV_1715)
```

### 5.2 Grid

```
λ_corr ∈ {0.5, 1.0, 2.0, 5.0}
```

| λ_corr | Behavior |
|---|---|
| 0.5 | mild cor penalty, primary focus on alpha |
| 1.0 | balanced (default) |
| 2.0 | aggressive cor anchor (risk C7 alternative B candidate) |
| 5.0 | extreme cor anchor (may hurt A1 if comp universe constrained) |

### 5.3 Secondary Path — Individual Stock Pre-Filter

```
universe filter: |cor_pre(stock_i, NAV_1715)| ≤ 0.4 individual-stock filter
```

primary λ_corr 모두 G2 FAIL 시 trigger. universe-stage cor anchoring.

### 5.4 Tertiary DEFERRED

β neutralization: long-only audit governor + execution agent post-process. design-only deferred.

## 6. Output Locations (Forge cycle binding)

| Artifact | Path | Format |
|---|---|---|
| 16 candidate raw metrics | `stage_artifacts/WT_D20260517_004/candidate_metrics_16cells.parquet` | Parquet (forge measure) |
| Pareto frontier extraction | `stage_artifacts/WT_D20260517_004/pareto_frontier.csv` | CSV |
| λ_corr grid sweep | `stage_artifacts/WT_D20260517_004/lambda_corr_grid_4values.csv` | CSV |
| Bootstrap CI per cell | `stage_artifacts/WT_D20260517_004/bootstrap_ci_per_cell.csv` | CSV |
| Admission decision per cell | `stage_artifacts/WT_D20260517_004/admission_per_cell.json` | JSON |

## 7. Design-Only Scope Statement (Charter §10 v1.8)

**본 protocol은 design-only**. 16 candidate metric 측정 + Pareto algorithm 실행 + 도훈 explicit a_max 선택 = **Forge cycle 의무 binding**.

optimizer-research cycle 산출 = **protocol design + decision framework**. measurement responsibility = forge agent.

---

## References

- Asness-Frazzini-Pedersen 2014 QMJ (Quality Minus Junk) — a_max 5-20% conditional injection range
- Brandt-Santa-Clara-Valkanov 2009 RFS — PPP linear scorer baseline
- Ferson-Schadt 1996 JF — conditional alpha foundation
- Frazzini-Pedersen 2014 JFE BAB — small injection precedent
- Jensen-Kelly-Malamud-Pedersen 2022 — cost-aware portfolio framework
- López de Prado 2018 AFML §7 — walk-forward OOS pooled
- Politis-Romano 1994 — stationary bootstrap CI
- Wood-Roberts-Zohren 2026 DeePM — neural portfolio learning
- You-Zhang 2025 — Direct Portfolio Learning (DPL)
- L-279~L-281 Hybrid 70/15/15 — multi-sleeve admit precedent
- WT-D20260517_003 v3 inherit (3 blockers learning)
