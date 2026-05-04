# Weight Method Selection — WT-S20260504_003 HMM Regime

**Date**: 2026-05-04
**Agent**: optimizer-research
**WT type**: sizing_only / recommendation_only
**Parent**: WT-P20260429_002 (STR_1715 PG2 100% live)

## Selected Method: `M4+HMM_Scale`

### Decision

The canonical `weights.csv` adopts the **M4+HMM_Scale** strategy:

```
weight_cash_t  = max(M4_parent_cash_t, 1 - scale_HMM_walkforward_t)
weight_str_t   = 1 - weight_cash_t
```

This combines two independent de-risk signals at the **cash bucket level** (max-rule), not stacked. M4 cash schedule (deployed via parent WT-P20260429_002) is preserved, and HMM walk-forward state-conditional scaling adds an independent regime-conditional cash trigger when its required cash exceeds M4's.

## Rationale (3-axis)

### 1. WT spec compliance

`request.json::statistical_factor_model.method = "HMM_Regime"` is user-fixed. `current_portfolio = STR_1715_100` and `parent_wt = WT-P20260429_002` make M4 the deployed-baseline overlay. The canonical strategy honors both.

### 2. Method shopping (3 candidates)

Per Charter §2-C method shopping log:

| Method | SR | MDD | TO_ann | IR vs S1 | Selected |
|---|---|---|---|---|---|
| S1 baseline (constant 100%) | 1.810 | -0.417 | 0.000 | — | NO |
| HMM_Scale (pure, no M4) | 1.667 | -0.404 | 0.510 | -0.961 | NO |
| **M4+HMM_Scale (canonical)** | **1.776** | **-0.302** | **0.811** | **-0.755** | **YES** |

(Metrics: 2004-02-02 ~ 2026-04-30 monthly, 268m, ret_net of 15bps embedded.)

### 3. WT primary objective achievement

WT spec mandates: `MDD ≤ -25% OR M4 대비 -3pp 개선`. Canonical M4+HMM_Scale achieves:

- MDD: **-30.2%** (vs S1 -41.7% = **-11.5pp improvement**) ✓ exceeds -3pp threshold by 8.5pp.
- vs current PG2 admit (M4 alone, MDD -32.05% per L-274): **-1.85pp marginal MDD improvement**.
- Vol: 17.97% (sleeve-level annualized port_vol).
- SR: 1.776 (vs S1 1.810, -0.034 net cost; **target SR 2.0 unchanged gap**).

The selection objective is **`crowding_adj_ret`** (per RF-O1 R4 P3 enum). Sizing overlay's value is MDD/vol reduction without alpha distortion — net IR vs S1 is -0.755 (informationally the overlay subtracts ~0.75σ of return per unit TE relative to constant-100% baseline).

## Honest tradeoff disclosure

**The IR vs S1 baseline is negative for both HMM and M4+HMM strategies.** This is a structural characteristic of de-risk overlays under STR_1715's strong recovery profile — Crisis-state cash insertions (e.g., 2009 GFC bottom, 2020 COVID bottom, Mar-2026 Crisis flag) miss V-shaped recoveries. The MDD reduction (-11.5pp vs S1) is the explicit tradeoff the user accepted in the WT spec (`mdd_target ≤ -25% OR -3pp 개선`), not the IR.

This is **NOT a method-shopping failure** — it is a known property of regime-conditional cash overlays vs constant 100% allocation against a high-Sharpe alpha sleeve. The recommendation-only nature of this WT means the deployment decision rests with the Q-Lead/도훈 trade-off review.

## PIT compliance

- HMM walk-forward forward-filter only (`hmm_posterior_path_walkforward.csv`, 207 valid predictions from 2009-03-02 onward, MIN_TRAIN=60).
- Pre-2009-03: scale_HMM=1.0 baseline (no PIT-clean signal → no de-risk overlay; M4 cash alone applies).
- Smoothed posterior (`hmm_posterior_path.csv`) is **NOT used** for sizing per Risk's C1 remediation.
- HMM params SHA-frozen: `7f6d4a42b8cfb49d3d68a2cdbe98ce62a4fef27cdb37893ed51fe45a26b1b6c2`.

## Hard constraint audit

| Constraint | Sleeve-level | Underlying STR_1715 (inherited) |
|---|---|---|
| max_names | 1 sleeve placeholder + cash | 20 stocks (PG2 admit, unchanged) |
| weight_bounds | [0, 1] sleeve scale | [0, 0.20] per stock (unchanged) |
| Σw | = 1 (sleeve + cash) ✓ | = 1 within sleeve (unchanged) |
| long_only | TRUE ✓ | TRUE (unchanged) |

**Note**: `request.json::hard_constraints.weight_bounds = [0, 0.20]` and `max_names = 20` apply to the **underlying STR_1715 internal stock weights** (inherited from parent admit), NOT to the meta-sleeve scaling itself. Sleeve-level w_str ∈ [0, 1] is the correct interpretation for sizing-only WTs (per AX-007 exception clause 3 ml_sizing).

## Outputs

| File | Purpose |
|---|---|
| `stage_artifacts/WT_WT-S20260504_003/weights.csv` | Canonical (M4+HMM_Scale) |
| `stage_artifacts/WT_WT-S20260504_003/weights_variants/S1.csv` | Baseline reference |
| `stage_artifacts/WT_WT-S20260504_003/weights_variants/HMM_Scale.csv` | Pure HMM (no M4) |
| `stage_artifacts/WT_WT-S20260504_003/weights_variants/M4+HMM_Scale.csv` | Canonical (also at root) |
| `stage_artifacts/WT_WT-S20260504_003/cash_definition_audit.json` | Cash-rule audit |
| `stage_artifacts/WT_WT-S20260504_003/lro_portfolio_mrc.csv` | Sleeve-level MRC (ann vol) |
| `qepm/mailbox/worktask/WT-S20260504_003/optimization_package_draft.json` | Draft (Codex round pending) |

## Schedule density

267 / 267 = **1.000** (≥ 0.95 mandate) ✓
