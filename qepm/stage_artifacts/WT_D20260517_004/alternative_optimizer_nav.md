# Alternative Optimizer Comparison — NAV-Level (Step 4.4)

**Task**: WT-D20260517_004 — DPL-RC v2.0 Path A NAV-level blend
**Agent**: optimizer-research
**Generated**: 2026-05-17
**Framework**: v6.1 R13 parallel method comparison + WT-D20260517_003 8-model framework inherit

---

## 1. 8-Model Comparison Framework (v3 inherit + NAV-level adaptation)

### 1.1 Method List

| ID | Method | Library | NAV-level adaptation |
|---|---|---|---|
| M1 | **MVO** (Markowitz 1952) | `quadprog::solve.QP` | comp_sleeve weights only (1715 retain) |
| M2 | **HRP** (López de Prado 2016) | `02_Infrastructure/portfolio/hrp_core.R` | comp_sleeve hierarchical clustering |
| M3 | **ERC** (Maillard et al. 2010) | direct R impl | comp_sleeve equal risk contribution |
| M4 | **CVaR LP** (Rockafellar-Uryasev 2000) | `Rglpk::Rglpk_solve_LP` | comp_sleeve tail-aware |
| M5 | **Black-Litterman** (Black-Litterman 1992) | direct R impl | comp_sleeve prior + p_bad view |
| M6 | **PPP Linear baseline** (Brandt 2009) | `lm()` | S1 scorer baseline |
| M7 | **LightGBM ranker** (Ke 2017) | `lightgbm::lgb.train` | S3 scorer non-linear |
| M8 | **DPL-RC Neural** (You-Zhang 2025 + Wood 2026) | `torch` R bridge | S4 scorer end-to-end |

### 1.2 NAV-Level Optimizer-Specific Methods (NEW)

본 cycle NAV-level paradigm 도입에 따라 추가 method 후보:

| ID | Method | Rationale |
|---|---|---|
| M9 | **Wealth share fixed-weight** (a_max = 0.10 baseline) | benchmark constant 비교 |
| M10 | **State-conditional injection (BAB-style)** (Frazzini-Pedersen 2014) | a_t binary {0, a_max} |
| M11 | **Continuous-a Bayesian** (Black-Litterman extended) | a_t ∝ posterior p_bad |
| M12 | **Stop-loss-style overlay** (Kritzman 2011 FAJ) | a_t reduce on drawdown trigger |

→ **method_shopping_log v6.1 cap = 10**. M1~M8 (8 base) + M9 (constant baseline) + M10 (BAB-style) = 10 cap 정합.

## 2. Comparison Protocol

### 2.1 Parallel Execution (R13)

```r
library(future)
library(future.apply)
n_workers <- min(5L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

methods <- list(
  list(name = "M1_MVO_lam2_psi03", fn = do_mvo_lambda2),
  list(name = "M2_HRP", fn = do_hrp),
  list(name = "M3_ERC", fn = do_erc),
  list(name = "M4_CVaR_LP_alpha05", fn = do_cvar_lp),
  list(name = "M5_BL_pbad_view", fn = do_bl_view),
  list(name = "M6_PPP_linear", fn = do_ppp_baseline),
  list(name = "M7_LightGBM", fn = do_lgbm),
  list(name = "M8_DPL_RC_Neural", fn = do_dpl_neural),
  list(name = "M9_constant_a10", fn = do_constant_baseline),
  list(name = "M10_BAB_binary", fn = do_bab_binary)
)

# α̂ from alpha_package, Σ from risk_package, p_bad from G1 — main process 1회 계산
results <- future_lapply(methods, function(m) {
  tryCatch(m$fn(alpha_vec, cov_mat, p_bad_vec, constraints),
           error = function(e) list(ok = FALSE, error = conditionMessage(e)))
})
plan(sequential)
```

### 2.2 Metric Collection per Method

각 method에 대해 7-axis admission (injection_grid §3.1 inherit):

| Axis | Type | Selection role |
|---|---|---|
| A1 overall_SR | maximize | secondary (filter by crowding_adj_ret) |
| A2 MDD | hard floor ≥ -0.2481 | hard constraint |
| A3 good_drag | soft cap ≤ 0.05 | hard constraint |
| A4 bad_improvement | maximize | secondary |
| A5 turnover | hard cap ≤ 6.0 | hard constraint |
| A6 cor | hard cap ≤ 0.30 | hard constraint |
| A7 p_bad AUC | hard floor ≥ 0.55 | hard constraint (G1) |
| **crowding_adj_ret** | maximize | **primary (selection_objective)** |

### 2.3 Cost-Aware Net Comparison

모든 method는 **net basis** (Charter §15 P2):
- gross SR = arithmetic SR before cost
- **net SR = arithmetic SR after 15bps 1715 + 25bps comp + 20bps blend ceiling**
- Hook L3 block: SR 단독 선택 = R4 P3 violation

## 3. DPL-RC NAV-level vs Baselines Expected Value-Add

### 3.1 Value-Add 3 Components (학술 prior, NOT measured)

**Component 1: Non-linear Interaction Capture**
- M6 PPP linear baseline: feature interactions 부재
- M7 LightGBM: leaf-based non-linearity
- M8 DPL-RC Neural: continuous non-linearity + dropout regularization
- Expected Δ net_IR M8 vs M6: +0.05~0.15 (학술 prior, KR T=60 N=80 features sample-thin caveat)

**Component 2: End-to-End Optimization**
- M1~M5: two-stage (predict α̂/Σ → optimize w)
- M8: direct portfolio learning (features → weights, You-Zhang 2025 RFS Phase 3)
- Expected Δ crowding_adj_ret M8 vs M1: +0.03~0.08 (Phase 3 emerging area)

**Component 3: State-Conditional Injection**
- M9 constant baseline: a_t = a_max constant (no state info)
- M10 BAB binary: a_t ∈ {0, a_max} (state info Boolean)
- M8 DPL-RC Neural: a_t continuous from p_bad posterior
- Expected Δ A4 bad_improvement M8 vs M9: +0.10~0.30 (conditional injection 핵심 가치)

### 3.2 Incremental Admission Decision Rule

```
admit Stage N+1 IF:
  net_IR_(N+1) > net_IR_N + 0.10
  AND crowding_adj_ret_(N+1) > crowding_adj_ret_N + 0.05
  AND NOT R4 degenerate (Spearman > 0.95 AND Jaccard > 0.80)

ELSE Stage N retain (Occam razor + L-326 over-param mandate)
```

## 4. Selection Objective Compliance (v6.1 R4 P3)

### 4.1 Hook L3 Enforcement

```
optimization_package.json::selection_objective ∈ {
  "net_ir", "to_adj_ret", "uncertainty_penalty", "crowding_adj_ret"
}
```

**FORBIDDEN**: `selection_objective = "sharpe"` (단독 SR) — Hook block (R4 P3 violation).

### 4.2 본 cycle 선택: `crowding_adj_ret`

**Rationale**:
- comp_sleeve = 1715 외부 universe, **crowding 측정 의무** (Acadian 80 features)
- 1715 production crowding은 retain (L-307 validated)
- comp 신규 crowding penalty 적용해야 4th orthogonal source 의의

```
crowding_adj_ret = A1_overall_SR - φ_cr · crowding_score_c
φ_cr = 0.10 (risk_package crowding inherit)
crowding_score_c = comp sleeve crowding score (Acadian framework)
```

v3 inherit retain (selection_objective_v6_1_R4_P3_compliance: true).

## 5. method_shopping_log Mandate

### 5.1 Format (HARD spec)

```json
{
  "optimizer_agent": {
    "candidates_tried": 10,
    "method_shopping_cap": 10,
    "selection_objective": "crowding_adj_ret",
    "method_log": [
      {
        "name": "M1_MVO_lam2_psi03",
        "net_ir": null,
        "crowding_adj_ret": null,
        "selected": false,
        "design_only_note": "Forge cycle measurement binding"
      },
      ...
    ]
  }
}
```

- **cap = 10 strict** (v6.1 R2-C 위반 시 Hook block)
- **candidates_tried = 10** (M1~M10 명시)
- **selected**: 본 cycle = DESIGN_ONLY_NO_SELECTION (forge cycle 도훈 explicit a_max + stage 후 결정)

## 6. Hyperparameter Grid per Method

### 6.1 MVO (M1)

```
lambda ∈ {1.0, 2.0, 5.0}
psi (confidence-aware) ∈ {0.0, 0.3, 0.5}
bounds = [0, 0.20]
max_names = 20
```

→ 9 sub-cells. Best by crowding_adj_ret 선택.

### 6.2 CVaR LP (M4)

```
alpha_cvar ∈ {0.05, 0.10}
cvar_target ∈ {-0.05, -0.03}
```

→ 4 sub-cells.

### 6.3 LightGBM (M7)

```
num_leaves ∈ {15, 31, 63}
max_depth ∈ {4, 6, 8}
learning_rate ∈ {0.05, 0.1}
n_round = early_stopping
```

→ 18 sub-cells. CV 3-fold walk-forward.

### 6.4 DPL-RC Neural (M8)

```
hidden_dim ∈ {32, 64, 128}
dropout ∈ {0.2, 0.3, 0.5}
λ_to ∈ {0.1, 0.5, 1.0}
λ_corr ∈ {0.5, 1.0, 2.0, 5.0}
batch_size = 32
epochs = walk-forward early stop
```

→ 108 sub-cells. CV 3-fold.

**Total sub-cells across 10 methods**: ~200. **Forge cycle compute estimate ~6-10h GPU**.

## 7. Risk Inherit Methods (risk_package secondary)

### 7.1 Σ Estimator Choices

| Estimator | Use case |
|---|---|
| Ledoit-Wolf Oracle (primary) | T=60 N=20 default |
| Gerber + RMT (backup) | outlier robust, α > 0.95 trigger |

→ MVO / BL / CVaR LP methods 모두 LW primary. fallback Gerber+RMT.

### 7.2 Crowding Inherit

risk_package crowding_audit Acadian 80 features framework → 모든 method crowding_score_c 측정.

## 8. v3 method_comparison_design_only Inherit

WT-D20260517_003 optimization_package.json `method_comparison_design_only` 구조 retain:

```json
{
  "method_comparison_design_only": {
    "candidate_count": 10,
    "selection_objective": "crowding_adj_ret",
    "measurement_responsibility": "forge_agent_phase_b_c",
    "winner_decision_rule": "Pareto frontier + crowding_adj_ret tiebreaker",
    "incremental_admission_caveat": "Stage N+1 → +0.10 net_IR + +0.05 crowding_adj_ret threshold"
  }
}
```

## 9. Design-Only Scope Statement

**본 comparison framework은 design-only** (Charter §10 v1.8). 실제 10 method × hyperparameter grid 측정 + best selection = **Forge cycle 의무**.

optimizer-research cycle 산출 = **method registry + protocol + hyperparam grid + admission decision rule**. measurement responsibility = forge agent.

---

## References

- Markowitz 1952 — MVO foundation
- Maillard-Roncalli-Teiletche 2010 — ERC
- López de Prado 2016 — HRP
- Rockafellar-Uryasev 2000 — CVaR LP
- Black-Litterman 1992 — Bayesian view incorporation
- Brandt-Santa-Clara-Valkanov 2009 RFS — PPP linear
- Ke et al. 2017 NeurIPS — LightGBM
- Frazzini-Pedersen 2014 JFE — BAB conditional injection
- Kritzman 2011 FAJ — pure overlay stop-loss precedent
- You-Zhang 2025 — Direct Portfolio Learning
- Wood-Roberts-Zohren 2026 DeePM — neural portfolio
- WT-D20260517_003 v3 alternative_optimizer_comparison.md inherit
- v6.1 R13 parallel + R2-C method_shopping cap 10
