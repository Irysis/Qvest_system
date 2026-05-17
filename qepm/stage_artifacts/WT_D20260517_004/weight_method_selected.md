# Weight Method Selected — WT-D20260517_004 (Design-Phase-A)

**Task**: WT-D20260517_004 — DPL-RC v2.0 Path A NAV-Level Blend
**Agent**: optimizer-research
**Date**: 2026-05-17
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)

---

## Selected Method

**`DESIGN_ONLY_NO_SELECTION`** — Forge cycle 측정 후 도훈 explicit a_max + stage 선택.

본 cycle은 design phase A. 단일 winner 선택 = Forge cycle Phase B/C 의무 binding.

## Selection Objective

```
selection_objective = "crowding_adj_ret"
crowding_adj_ret = A1_overall_SR - φ_cr · crowding_score_c
φ_cr = 0.10 (risk_package crowding inherit)
crowding_score_c = comp sleeve crowding (Acadian 80 features)
```

**v6.1 R4 P3 정합**:
- `sharpe` 단독 최대화 = Hook L3 block
- `net_ir` / `to_adj_ret` / `uncertainty_penalty` / `crowding_adj_ret` ∈ enum
- 본 cycle 선택 = `crowding_adj_ret` (comp 신규 universe crowding 측정 의무)

## Method Decision Framework (Forge cycle binding)

### 1. Hard Constraint Filter (Pareto Step 1)

```
HC1: max_names per-sleeve ≤ 20
HC2: 0 ≤ w ≤ 0.20
HC3: Σw = 1 per-sleeve
HC4: long_only
HC5: G1 AUC ≥ 0.55
HC6: A2 MDD ≥ -0.2481
HC7: A3 drag ≤ 0.05
HC8: A6 cor ≤ 0.30
HC9: A7 p_bad AUC ≥ 0.55
```

### 2. Pareto Dominance (Step 2)

axes (maximize): (A1 overall_SR, A4 bad_state_improvement, -A5 turnover)

complexity O(16²) = 256 pairwise. expected front size 2-5 candidates.

### 3. Tiebreaker

```
primary: crowding_adj_ret = A1 - 0.10 · crowding_score_c
secondary: heavy_tail_adjusted = net_ir - 0.05 · (Hill_alpha > 3.0 ? 1 : 0)
```

heavy-tail HRP/CVaR priority (Codex C5 PARTIAL_ACCEPT inherit).

### 4. Incremental Admission

```
Stage N+1 admit IF:
  Δ net_IR > 0.10
  AND Δ crowding_adj_ret > 0.05
  AND NOT R4 degenerate (Spearman > 0.95 AND Jaccard > 0.80)

ELSE Stage N retain (Occam + L-326 over-param mandate)
```

## Candidate Space (Forge cycle 측정 대상)

| Stage | Method | a_max grid | Sub-cells (hyperparam) |
|---|---|---|---|
| S1 | Linear PPP (Brandt 2009) | {0.05, 0.10, 0.15, 0.20} | small grid |
| S2 | Elastic Net (Zou-Hastie 2005) | {0.05, 0.10, 0.15, 0.20} | α + λ_1/λ_2 |
| S3 | LightGBM (Ke 2017) | {0.05, 0.10, 0.15, 0.20} | 18 sub-cells |
| S4 | DPL-RC Neural (You-Zhang 2025 + Wood 2026) | {0.05, 0.10, 0.15, 0.20} | 108 sub-cells |

Total: 16 injection cells × ~200 hyperparameter sub-cells = **226 effective candidates**.

## Alternative Optimizer Comparison (10 methods)

| ID | Method | Library | Scope |
|---|---|---|---|
| M1 | MVO_lam2_psi03 | quadprog | comp_sleeve weights |
| M2 | HRP | hrp_core.R | comp_sleeve hierarchical |
| M3 | ERC | direct R | comp_sleeve equal risk contribution |
| M4 | CVaR_LP_alpha05 | Rglpk | comp_sleeve tail-aware |
| M5 | BL_pbad_view | direct R | Bayesian view |
| M6 | PPP_linear_baseline | lm() | S1 baseline |
| M7 | LightGBM_ranker | lightgbm | S3 non-linear |
| M8 | DPL_RC_Neural | torch R bridge | S4 end-to-end |
| M9 | constant_a10_baseline | direct R | NAV-level constant |
| M10 | BAB_binary_state_conditional | direct R | a_t ∈ {0, a_max} |

method_shopping_log cap = 10 (v6.1 R2-C compliant).

## CRISIS Regime Boundary Shrink Layer (Codex C5 신규)

```
trigger: m4 regime CRISIS 발화
bounds: [0, 0.10] (50% shrink from default [0, 0.20])
a_t_cap: 0.05 (a_max grid minimum)
cash_sleeve_fallback: weights_residual → cash (β_R05=0.3 cash control L-307 precedent)
```

academic backbone: L-129 + L-307 + AX-001 v2 conditional defense.

## confidence_vector Hard Binding (Codex C5)

```r
dispatch_weight_method(
  alpha = alpha_package$alpha_vector,
  cov = risk_package$security_covariance,
  confidence = alpha_package$confidence_vector,   # HARD binding
  ...
)
```

applicable methods: M1 MVO + M5 BL + M4 CVaR LP.
fail action if confidence_vector absent: Forge cycle BLOCK + alpha rework.

## Cost Decomposition (Codex C6)

| Layer | Rate (one-way) | Basis |
|---|---|---|
| 1715 sleeve | 15bps | base mandate v2.3_kr_retail_15bps |
| comp sleeve | 25bps | illiquid surcharge (exception pending) |
| Cross-sleeve rebalance | 15bps | base rate (1715 inherit) |
| Blend annualized ceiling | 20bps | risk_package risk_constraints inherit |

**TO annualization explicit**: `TO_annualized = Σ_{t=1..12 over rolling year} TO_monthly_t × 2` (round-trip ×2 NOT ×12 — Iter 3 fabrication 차단).

## Charter §8 No Silent Override (Codex C7)

3 challenge_flags emit:
- `OPTIMIZER_CHALLENGE_C2_MAX_NAMES_UNION_40_EXCEPTION_PENDING` (CRITICAL)
- `OPTIMIZER_CHALLENGE_C6_COMP_COST_25BPS_VS_BASE_15BPS_EXCEPTION_PENDING` (HIGH)
- `OPTIMIZER_CHALLENGE_C8_BETA_NEUTRALIZATION_IMPLICIT_SHORT_DEFERRED` (MEDIUM)

`challenge_review_objection = true` 정정 (silent override 차단).

## Codex Round Disposition

- stance: REJECT (veto_flag=false)
- 8 concerns: CRITICAL 2 + HIGH 5 + MEDIUM 1
- disposition: 3 ACCEPT + 4 PARTIAL_ACCEPT + 1 REBUTTAL (C3 path mismatch)
- Q-Lead Escalate: TRIGGERED_AUTONOMOUS (도훈 mandate 묻지말고 무한 리서치)
- challenge_note: `qepm/mailbox/worktask/WT-D20260517_004/challenge_note_optimizer-research.md`

## Next Step

Q-Lead 보고 (Telegram tg_agent_brief) → 도훈 explicit confirm/escalate decision → Forge cycle 진입 (Phase B + C, ~6-10h GPU).

## References

- v6.1 R4 P3 selection_objective
- v6.1 R4-A confidence-aware MVO
- v6.1 R2-C method_shopping_log cap 10
- v6.1 R13 parallel method comparison
- Charter §10 v1.8 wt_type=discovery_design_phase_a Role Card
- Charter §8 No Silent Override
- L-279~L-281 Hybrid 70/15/15 multi-sleeve precedent
- L-307~L-313 STR_1715 PG2 lineage
- L-326 over-param + TO ×2 mandate
- L-328 design-measurement separation
- L-129 CRISIS regime boundary shrink
- WT-D20260517_003 v3 inherit (3 blockers learning)
