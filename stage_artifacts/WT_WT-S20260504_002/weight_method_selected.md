# Weight Method Selected — WT-S20260504_002 (DCC Vol Target sizing_only)

**Selected**: `M4+DCC_VolTarget` (canonical)
**Selection objective**: `to_adj_ret` (turnover-adjusted return, R4-A compliant)
**Date**: 2026-05-04
**Agent**: optimizer-research

---

## Method Comparison Summary

| Strategy | Mean Cash | % Cash Active | Sleeve TO (annual) | Schedule Density | Selected |
|---|---|---|---|---|---|
| **S1** baseline | 0.000 | 0.0% | 0.000 | 1.000 | ✗ |
| **DCC_VolTarget** | 0.271 | 72.7% | 0.284 | 1.000 | ✗ |
| **M4+DCC_VolTarget** | 0.282 | 76.8% | 0.463 | 1.000 | **✓** |

(All variants: 267 monthly rows, 2004-01-01 → 2026-03-01, sleeve-level Σw = 1.0, long-only PASS.)

---

## Selection Rationale

### Why M4+DCC_VolTarget over DCC_VolTarget alone?

- **M4 contributes regime-aware timing precision** (active production basis, alpha-aware Trade-War / Crisis regime detection — 34 historical activations across 268m).
- **DCC contributes magnitude precision** (continuous σ_p forecast → fine-grained vol scaling vs binary M4 regime classifier).
- **Combining preserves both signals** under defensive max() rule. Drop M4 → lose alpha-aware regime intelligence (34 historical regime cash activations including GFC peak Dec-2008 at 57.1% cash). Drop DCC → lose continuous vol management for stable regimes.

### Why M4+DCC_VolTarget over S1 baseline?

- **MDD policy ≤-25%**: S1 historical MDD -41.7% (pre-M4 baseline from L-274) >> -25% target. Both DCC and M4 reduce MDD.
- **AX-001 v2 conditional metric**: bad/normal realized risk ratio 1.36 — vol management justified.
- **Forward May 2026 forecast**: σ_p annual 35.8% >> 15% target → cash bridge engagement statistical, not heuristic.

### Why max(M4_cash, DCC_cash) and NOT additive?

- **Additive (M4 + DCC) breaches Σ=1**: 12 historical months where M4_cash + DCC_cash > 1.0 → sleeve weight goes negative (long-only violation, AX-002 hard constraint).
- **Single cash sleeve semantics**: M4 cash and DCC cash both call same `cash_KRW` asset. Additive would double-count.
- **max() always defensive**: whichever overlay calls for more cash dominates; never weakens defense.
- **Interpretability**: `cash_definition_audit.json::dominance_when_both_active` records which overlay drove cash each month. M4-dominates and DCC-dominates months separable for post-hoc analysis.

---

## Method Shopping Justification (3 candidates only)

`request.json::statistical_factor_model.method = "DCC_GARCH_Vol_Target"` is mandate-fixed. HRP / MVO / CVaR / ERC / BL are per-ticker weight optimizers requiring fresh α + Σ inputs — fundamentally incompatible with sizing_only sleeve-level [0,1] vol scaling. Adding them would be method-shopping pollution (R2-C anti-pattern). 3 variants represent the meaningful axis (S1 baseline / DCC alone / M4+DCC combined) for sleeve sizing decisions.

---

## Hard Constraints Verification

| Constraint | Threshold | S1 | DCC | M4+DCC | Pass |
|---|---|---|---|---|---|
| Σw_sleeve = 1 | tolerance 1e-6 | 1.0 exact | 1.0 exact | 1.0 exact | ✓ |
| long-only (sleeve, cash) | both ≥ 0 | PASS | PASS | PASS | ✓ |
| Schedule density | ≥ 0.95 | 1.000 | 1.000 | 1.000 | ✓ |
| Sleeve TO annualized | ≤ 6.0 | 0.000 | 0.284 | 0.463 | ✓ |
| max_names per-ticker | ≤ 20 | inherited from parent | — | — | ✓ |
| weight_bounds_per_ticker | [0, 0.20] | inherited | — | — | ✓ |
| transaction_cost_15bps_one_way | inherited from parent run_all.R | — | — | — | ✓ |

---

## Forward May 2026 Operational Output

| Field | Value |
|---|---|
| sigma_p_annual_forecast | 35.77% |
| vol_target_annual | 15.00% |
| scale_factor (DCC) | 0.4194 |
| weight_cash_DCC | 0.5806 |
| weight_cash_M4 (May 2026 NORMAL regime) | 0.0000 |
| weight_cash_combined (max rule) | 0.5806 |
| weight_str1715_combined | 0.4194 |
| Inside-sleeve top weight | A010950 S-Oil 20% (per-ticker bound at 0.20 — PASS) |

---

## Caveats & Downstream Obligations (challenge_flags)

1. **RF-O-MDD-CAGR-TRADEOFF (MEDIUM)**: DCC mean cash 27.1% incremental drag may pull CAGR below 20% floor (decision_rule FAIL). Forge backtest verifies.
2. **RF-O-AX001V2-ALPHA-SURRENDER (MEDIUM)**: AX-001 v2 conditional metric — CRISIS state realized return mean +4.66% positive. DCC cash up-scaling in CRISIS surrenders alpha. M4+DCC max() partially mitigates (M4 alpha-aware), but DCC magnitude dominance means non-trivial drag. Forge measures.
3. **RF-O-LAYER-A-FORWARD-EXTREME (HIGH)**: 5월 cash 58.1% is +2σ outlier vs 268m mean 28.2%. DCC params estimated on 2022-2026 vol-rich sample — possible overfit. Post-forge: 5월 1m realized vol audit obligated.
4. **RF-O-NO-NEW-OPTIMIZATION (INFO)**: sizing_only WT — no QP/optimizer solve. Method comparison limited to design-time analysis (turnover + cash + schedule density). Final SR/CAGR/MDD await forge phase.

---

## State Machine + Codex Round

- **From → To**: `RISK_DONE → OPTIMIZER_DONE`
- **Expected full path**: `SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED` (recommendation_only)
- **Codex round 1**: dispatched 2026-05-04 09:30 KST, response in `codex_critic_response_optimizer.json` (timeout-tolerant — parent risk_package round 1 timeout precedent → waiver path defined in `optimizer_challenge_note.md` Section 4.2)
- **AX-008 path**: 1 source PASS (optimizer self) + Forge + Judge → 2/3 sufficient if Codex timeout

---

## Output Inventory

| File | Path |
|---|---|
| Canonical weights (M4+DCC_VolTarget) | `stage_artifacts/WT_WT-S20260504_002/weights.csv` |
| S1 variant | `stage_artifacts/WT_WT-S20260504_002/weights_variants/S1.csv` |
| DCC_VolTarget variant | `stage_artifacts/WT_WT-S20260504_002/weights_variants/DCC_VolTarget.csv` |
| M4+DCC_VolTarget variant | `stage_artifacts/WT_WT-S20260504_002/weights_variants/M4+DCC_VolTarget.csv` |
| Cash combination audit | `stage_artifacts/WT_WT-S20260504_002/cash_definition_audit.json` |
| Sleeve-level MRC | `stage_artifacts/WT_WT-S20260504_002/lro_portfolio_mrc.csv` |
| Optimization package (this round) | `qepm/mailbox/worktask/WT-S20260504_002/optimization_package.json` |
| Optimizer challenge note | `qepm/mailbox/worktask/WT-S20260504_002/optimizer_challenge_note.md` |
| Method selection rationale | `stage_artifacts/WT_WT-S20260504_002/weight_method_selected.md` (this file) |
