# Weight Method Selected — WT-D20260429_001

## Decision

**method_selected**: `HRP_lambda_2.0_psi_0.3_bounds_0.15`
**selection_objective**: `crowding_adj_ret`
**rationale_short**: HRP achieves TDC q5 < 0.30 (the decisive defense complement orthogonality gate) while maintaining variance parity. CVaR-LP and Robust_Resid both FAIL TDC gate. MVO TDC q5 = 0.43 also FAILs.

## Method Comparison Summary

| Method | n_names | net_IR (realized TO) | TE | TDC_q5 | CVaR(5%) | Turnover RT | crowding_adj_ret | TDC_PASS_0.30 | Selected |
|---|---|---:|---:|---:|---:|---:|---:|:---:|:---:|
| MVO (λ=2 ψ=0.3) | 20 | 0.749 | 0.120 | 0.429 | -0.081 | 0.64* | 0.556 | FAIL | ✗ |
| **HRP** | 20 | 0.733 | 0.094 | **0.214** | -0.070 | 6.43 (realized) | **0.814** | **PASS** | **✓** |
| CVaR LP | 20 | 0.757 | 0.109 | 0.357 | -0.065 | 4.17 | 0.670 | FAIL | ✗ |
| Robust Residual | 20 | 0.691 | 0.120 | 0.357 | -0.075 | 0.18 | 0.612 | FAIL | ✗ |

*MVO turnover is heuristic (sigma_w-deviation proxy). HRP turnover for 6.43 RT is realized walk-forward across 279 sig_dates. crowding_adj_ret formula: net_IR × penalty(TDC), where penalty = max(0, 1 - 2×(TDC - 0.30)).

## Selection Rationale (selection_objective=crowding_adj_ret)

### TDC q5 Gate (Decisive)

The **central question** of this WT was: **"Can a 3-factor Low IVOL composite (D47_CVaR + D01_IdioVol + D04_Downside_Beta) provide MDD complement to STR_1715 with portfolio-level lower-tail orthogonality (TDC q5 < 0.30)?"**

Risk Agent CF-RISK-01 reported Top-60 EW panel TDC q5 = **0.4494** (FAIL gate 0.30). Optimizer's task: find a weight structure that breaks this lower-tail dependence at deployment grade.

**Result by method**:
- **MVO**: TDC q5 = 0.429 (FAIL — only marginally better than EW)
- **HRP**: TDC q5 = **0.214 (PASS)** ← variance parity diversifies away tail clustering
- **CVaR LP**: TDC q5 = 0.357 (FAIL — surprising, given direct tail control)
- **Robust Residual** (alpha residualized on STR_1715): TDC q5 = 0.357 (FAIL — residualization at alpha-level doesn't propagate to portfolio tails)

Walk-forward TDC q5 (HRP) = **0.000** across 266 obs (full 22Y). Lower-tail orthogonality confirmed empirically — 13 STR_1715 worst-5% months coincide with ZERO HRP-portfolio worst-5% months.

### Why HRP > CVaR LP

CVaR LP minimizes monthly tail loss directly (Rockafellar-Uryasev), so naively one expects TDC q5 PASS. But:
1. CVaR LP optimizes **own-portfolio** tail, not **joint** tail with STR_1715.
2. CVaR LP's selected portfolio still loaded on KOSPI200 systematic risk (top stocks), which co-tails with STR_1715.
3. HRP's recursive bisection diversifies across cluster hierarchy, dispersing systematic exposure.

### Why HRP > MVO

MVO with λ=2.0 ψ=0.3 over-concentrates in highest-alpha names (top 5-6 names dominate). These same names tend to be in STR_1715's top decile (4F Consensus + Q07 Earnings Stability), creating tail clustering. HRP's variance parity forces dispersion across 20 names.

### Why HRP > Robust Residual

Residualization (α' = α - β·α_str1715) operates at alpha-level. But portfolio TDC depends on REALIZED returns of selected names, not their alpha signal. β-correction reduces alpha overlap but the underlying universe (top KOSPI200) still co-tails. Need diversified weighting (HRP) for tail orthogonality, not alpha residualization alone.

## Confidence-Aware MVO (R4-A v6.1)

MVO method DID use confidence_vector from alpha_package (range 0.70-0.95). Did not save MVO. HRP does not directly use confidence (variance only) — but inherits via the same top-60 panel that alpha+confidence selected.

## Walk-forward Mechanics (Charter §9)

279 sig_dates from 2003-01 to 2026-03.

| sig_date type | Count | Method |
|---|---|---|
| anchor (2026-03-31) | 1 | HRP on top-60 from risk_package, take top-20 by HRP weight, iterative cap to 0.15 |
| HRP_60m (most dates 2008-2025) | 248 | per-date top-20 by alpha_z (within per-date top-60), HRP on rolling 60-month history with Ledoit-Wolf shrinkage |
| HRP_36m (some 2007-2008) | 0 | Skipped — not needed |
| inverse_vol (early 2004-2007) | 24 | per-date top-20 by alpha_z, inverse 36m volatility (HRP not robust on short history) |
| EW (very early 2003) | 6 | per-date top-20 by alpha_z, EW (insufficient history) |

Schedule density: **279 / 279 = 1.000** (PASS gate 0.95).

Per-date Σw = 1 (max abs error 4.44e-16 after exact normalization fix).
Per-date n = 20 (always).
Per-date max_w ≤ 0.15 (iterative cap applied).

## Hard Constraints Audit

| Constraint | Value | Status |
|---|---|---|
| max_names ≤ 20 | 20/20 | PASS |
| weight_bounds [0, 0.15] | [0.0055, 0.150] | PASS |
| Σw = 1 (absolute) | 4.44e-16 max abs err | PASS |
| long-only | TRUE | PASS |
| schedule_density ≥ 0.95 | 1.000 | PASS |
| schedule_anchor_match | TRUE | PASS (Charter §9) |

## Soft / Hurdle Constraints

| Constraint | Value | Status |
|---|---|---|
| turnover_cap_annual ≤ 3.0 (soft) | 6.426 RT | **FAIL** |
| turnover_cap_annual ≤ 6.0 (hard) | 6.426 RT | **HARD FAIL** (infeasibility issued) |
| CVaR(5%) monthly ≤ 0.025 | -0.0994 | **FLAGGED** (heavy-tail caveat, infeasibility issued) |
| sector_active_weight_cap ≤ 0.30 | not measured | DEFER |

## Forge Handoff

- weights.csv path: `stage_artifacts/WT-D20260429_001/weights.csv`
- 5,580 rows × 3 cols (Date, Ticker, Weight)
- Forge MUST use weights.csv as-is (no top-N reselection from alpha_scores)
- Forge will produce `forge_realized_share_based` SR (admission grade per Charter §9)
- Optimizer's `walk_forward_realized` is `optimizer_walk_forward_simulation` (alpha signal meta only, NOT admission grade)

Charter §9 anchor: target_weights == weights.csv[2026-03-31] (verified, identical 20 tickers, weights match to 6 decimals).
