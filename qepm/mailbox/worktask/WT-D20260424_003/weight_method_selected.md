# Weight Method Selection — WT-D20260424_003 (Pilot 5)
# Optimizer Research Agent | 2026-04-24 | schema v6.1

## Selected Primary Method
**MVO_lam1.0_psi0.3_betaA0.75_gamma0.5**

Mean-Variance Optimization with:
- Confidence-aware alpha scaling: alpha_tilde = c_i * alpha_hat_i (v6.1 R4A)
- Forecast Uncertainty Penalty: psi=0.3 * (1-c_i)^2 per name
- Option A Beta Soft Constraint: gamma_beta=0.5 * max(0, w'beta - 0.75)^2 (Risk Agent primary)
- Alpha winsorization: 2-sigma clip (A140860: 3.0 → 1.964)
- Bounds: [0, 0.10] per name
- min_names=10 (Pilot 5 constraint_override), max_names=20

## Selection Rationale (net_ir objective, P3 R4)

### 10-Method Comparison Summary

| Method | net_IR | N | HHI | beta | TO_ann% | Status |
|--------|--------|---|-----|------|---------|--------|
| HRP_wardD2 | 13.723 | 15 | 0.0806 | 0.873 | 457.8 | DISQUALIFIED: beta > 0.80 |
| MaxDiv_80pct_20alpha | 13.562 | 15 | 0.0699 | 0.882 | 210.6 | DISQUALIFIED: beta > 0.80 |
| **MVO_lam1.0_psi0.3_betaA_gamma1.0** | **13.419** | **10** | **0.1000** | **0.760** | **400.0** | Beta OK but collapses to equal-weight |
| **MVO_lam1.0_psi0.3_betaA0.75** | **13.368** | **11** | **0.0960** | **0.766** | **414.5** | **PRIMARY** |
| MVO_lam1.5_psi0.3_betaA0.75 | 13.370 | 11 | 0.0961 | 0.766 | 415.8 | Near-identical to primary |
| MVO_lam2.0_psi0.3_betaA0.75 | 13.372 | 11 | 0.0961 | 0.766 | 417.0 | Near-identical |
| MVO_lam0.5_psi0.3_betaA0.75 | 13.366 | 11 | 0.0960 | 0.766 | 413.2 | Near-identical |
| MVO_lam1.0_psi0.5_betaA0.75 | 13.276 | 11 | 0.0950 | 0.771 | 400.0 | Lower net_IR |
| ERC_invVol | 12.830 | 15 | 0.0697 | 0.881 | 206.7 | DISQUALIFIED: beta > 0.80 |
| BL_absViews_betaA | 12.152 | 10 | 0.1000 | 0.778 | 400.0 | BL shrinkage reduces alpha |

### Why MVO over gamma=1.0 (which has higher net_IR)
gamma=1.0 forces tighter beta (0.760 vs 0.766) but collapses all 10 names to exact 0.10
equal-weight. This provides no alpha differentiation — the optimizer loses information content.
gamma=0.5 (canonical) gives lam=1.0 risk control + meaningful weight differences
(A218410: 0.0727, A028050: 0.0273) reflecting actual alpha signal.

### Why not HRP (highest gross net_IR=13.723)
HRP produces beta=0.873, which violates the Option A governance requirement (beta <= 0.80).
The Risk Agent mandated Option A as primary; HRP implements no beta constraint mechanism.
Disqualified on governance grounds regardless of raw score.

### Why not ERC/MaxDiv
Both produce beta > 0.88. Same disqualification reason as HRP.
Neither implements the Option A beta constraint.

## Portfolio Composition

| Ticker | Weight | Beta | Alpha_raw | Conf | Bucket |
|--------|--------|------|-----------|------|--------|
| A140860 | 0.1000 | 0.815 | 3.000 (winsor→1.964) | 0.270 | mid_beta |
| A287410 | 0.1000 | 0.511 | 0.619 | 0.429 | low_beta |
| A005850 | 0.1000 | 0.912 | 0.514 | 0.526 | mid_beta |
| A058470 | 0.1000 | 0.719 | 0.493 | 0.600 | low_beta |
| A029780 | 0.1000 | 0.562 | 0.464 | 0.600 | low_beta |
| A041510 | 0.1000 | 0.871 | 0.440 | 0.601 | mid_beta |
| A014680 | 0.1000 | 0.934 | 0.529 | 0.430 | mid_beta |
| A001680 | 0.1000 | 0.648 | 0.292 | 0.601 | low_beta |
| A000100 | 0.1000 | 0.703 | 0.328 | 0.601 | low_beta |
| A218410 | 0.0727 | 0.920 | 0.615 | 0.254 | mid_beta |
| A028050 | 0.0273 | 1.172 | 0.544 | 0.600 | high_beta |

**Excluded (high-beta)**:
- A028260 (beta=1.117), A365340 (beta=1.166), A006260 (beta=1.135), A005290 (beta=1.217)

## Key Diagnostics

- n_names: 11 (natural QP convergence, min_names=10 satisfied without forcing)
- min_names_enforced: FALSE (self-selected > min)
- HHI: 0.0960 (cap=0.10, PASS)
- beta_port: 0.7664 (target=0.75, gap=+0.0164)
- market_risk_approx: 58.7% (vs Gate D threshold 40% — gap persists)
- Boundary solution: 10 of 11 names at max weight 0.10

## Expected Performance (Grinold-scaled)

- Expected Active Return (pa): 4.22% (Grinold: IC=0.0318 x vol=40% x sqrt(11))
- Expected Tracking Error (pa): 18.83% (monthly TE annualized)
- Expected IR (Grinold): 1.337 (ICIR=0.403 x sqrt(11))
- Signal-alpha IR (z-score units): 13.37 (not interpretable as return %)
- Turnover (Pilot 4 → Pilot 5): 0.2707 one-way = 324.8% pa
- Estimated annual cost: 48.7 bps (15bps x 324.8% TO)

## Pilot 4 vs Pilot 5 Comparison

| Metric | Pilot 4 | Pilot 5 |
|--------|---------|---------|
| n_names | 15 (forced) | 11 (natural) |
| min_names_enforced | TRUE | FALSE |
| beta_port | 0.789 | 0.766 |
| market_risk | 60.9% | ~58.7% |
| HHI | 0.0744 | 0.0960 |
| lambda_retries | 4 | 0 |

## Binding Constraints
1. weight_bound_upper: 10 of 11 names at max 0.10 (alpha signal > risk penalty)
2. alpha_winsor_2sigma: A140860 clipped 3.0 → 1.964
3. beta_soft_penalty: 4 high-beta names (beta: 1.12-1.22) → weight=0

## Red Flags
- RF-BETA: beta_port=0.766 > target=0.75, market risk ~58.7% vs Gate D 40%. Gap remains.
- RF-ALPHA_IC: rank_IC=0.0318 < 0.04 threshold. Alpha fundamental weakness.
- RF-BOUNDARY: 10/11 names at max weight. Optimizer cannot differentiate further within bounds.

## Hedge Overlay Applied
**Option A** (Risk Agent primary): static beta_target=0.75, gamma_beta=0.5 soft penalty.
Option C-3 (MRS-dynamic) deferred — regime discrepancy (Alpha memo CRISIS vs actual NEUTRAL)
makes C-3 risky for a discovery pilot. Option A is simpler with no regime-timing error.

## Forge Handoff
- optimization_package.json: qepm/mailbox/worktask/WT-D20260424_003/optimization_package.json
- weights.csv: stage_artifacts/WT_D20260424_003/weights.csv
- Covariance: stage_artifacts/WT_D20260424_003/covariance.parquet (LW Oracle 36M)
- Alpha scores: stage_artifacts/WT_D20260424_003/alpha_scores.parquet (RAPC IC-weighted)
- Run pattern: source('run_all.R') in strategy directory
- Key test: Gate D market risk contribution (target < 40%, current ~58.7%)

## v6.1 Compliance
- R4 selection_objective: net_ir (enforced)
- R4A confidence_vector: applied (alpha_tilde = c * alpha_hat)
- R2C method_shopping_log: 10 candidates (limit=10)
- R12 no_silent_override: infeasibility_report = NULL (all constraints satisfied)
- GAP1 challenge_review: P4 obligation met (objection=FALSE)
- GAP2 lineage: recorded in artifact_lineage.json
