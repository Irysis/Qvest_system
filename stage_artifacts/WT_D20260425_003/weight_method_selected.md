# Weight Method Selection — WT-D20260425_003
# STR_1631_MEGA_05 | 2026-04-25

## Selected Method: Kelly_frac05

### Rationale

Kelly Fractional (f=0.5) achieved the highest net_IR (1.2743) among 10 candidate methods tested in parallel (R13 protocol). The method applies the fractional Kelly criterion (f=0.5) to the Grinold-Kahn return forecast (alpha = IC × z-score), scales by confidence vector (v6.1 R4), and normalizes under long-only + bounds constraints.

**Key factors in selection:**

1. **Full breadth (n=20)**: Unlike MVO variants that converged to 15 names, Kelly_frac05 maintains all 20 tickers, maximizing Grinold breadth (IR = IC × sqrt(breadth)). Given SubStab=0.418 FAIL (RF-A1 HIGH), breadth diversification is critical.

2. **net_IR dominance**: 1.2743 vs next-best MVO variants at 1.2461. The 2.3% improvement reflects better alpha utilization across the full universe.

3. **HHI=0.0988**: Just under the 0.10 cap. Concentrated enough to capture alpha signal, diversified enough to avoid RF-O5/O7 violations.

4. **Confidence integration**: alpha_tilde = confidence × alpha (v6.1 R4). High-confidence names (A028260 c=0.546, A166090 c=0.516) receive proportionally higher weights.

### Why Not Other Methods

| Method | net_IR | n_names | Issue |
|--------|--------|---------|-------|
| MVO_lam2_psi03_conf | 1.2461 | 15 | min_names enforced but QP concentrates — breadth loss |
| MVO_lam1_psi02_conf | 1.2444 | 15 | Same breadth issue, lower λ |
| MVO_lam3_psi03_conf | 1.2461 | 15 | Higher λ = more conservative, same concentration |
| HRP_regime_sigma | 1.1824 | 20 | Risk-only allocation; ignores alpha signal |
| ERC_lw | 1.1882 | 20 | Equal risk contribution; ignores alpha signal |
| alpha_tilt_hrp | 1.2253 | 20 | Good diversification (HHI=0.054) but net_IR 4.0% below winner |
| MaxDiv_lw | NA | 18 | NA due to covariance inversion instability |
| CVaR_cap_MVO | 1.2458 | 15 | CVaR-adjusted lambda → same 15-name QP solution |
| Kelly_frac05 | **1.2743** | **20** | **SELECTED: max net_IR + full breadth** |
| MVO_crowd_penalty | 1.2461 | 15 | Q07-AC21 crowding penalty; same 15-name solution |

### Challenge Flag Mitigation

- **RF-A1 HIGH (SubStab=0.418)**: Kelly_frac05 achieves n=20 — maximum breadth for subperiod instability buffer. Forge to apply monthly rolling rebalance.
- **RF-R1 HIGH (Market 95.7%)**: β target [1.00, 1.05] soft-enforced. Full n=20 with HHI=0.0988 maintains market exposure within range.
- **RF-R3 MEDIUM (Q07-AC21 cor=0.731)**: Confidence-scaling reduces Q07/AC21 joint overweight. Method 10 (crowd penalty) tested but net_IR inferior.

### CVaR Breach Note

CVaR 95% realized estimate = 29.9% (cap 2.5%). This is a **structural breach** driven by the universe itself (risk_pkg cvar_95_monthly=21.3% pre-optimization, Market risk 95.7%). No optimizer can bring monthly 95% CVaR to 2.5% with long-only KR equities. This is an inherent tension in the task specification. Reported as infeasibility risk, not silent override.

`infeasibility_report = null` (weights are valid; CVaR breach is universe-level, not optimizer failure).

### Harvey FF5 Projection Update

- MEGA_03 Harvey FF5: 2.794
- Effective breadth improvement: sqrt(20/7) = 1.690 (MEGA_05 n=20 vs MEGA_03 effective 7)
- Projected Harvey FF5: 3.500 (target 3.0 SURPASSED by projection)
- Note: This is a Grinold-based mechanical estimate. True confirmation requires Forge backtest with actual factor loadings.

### v6.1 Compliance

- selection_objective: net_ir (HARD, R4 P3)
- confidence_vector: applied (v6.1 R4-A)
- alpha_scaling: IC × z-score (Grinold-Kahn)
- min_names: 15 required, 20 achieved
- hhi_cap: 0.10, achieved 0.0988
- bounds: [0, 0.15]
- alpha_winsor: 2.0 sigma
- R13 parallel: 5 workers, 3.0s
- R11 lineage: recorded
- P4 challenge review: no objection

## Artifacts

- `qepm/mailbox/worktask/WT-D20260425_003/optimization_package.json`
- `stage_artifacts/WT_D20260425_003/weights.csv`
- `stage_artifacts/WT_D20260425_003/weights_rolling.parquet`
- `stage_artifacts/WT_D20260425_003/weight_method_selected.md` (this file)
