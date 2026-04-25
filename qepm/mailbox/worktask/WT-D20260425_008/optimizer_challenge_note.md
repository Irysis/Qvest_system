# Optimizer Challenge Note — WT-D20260425_008 (Iter 3)

**Round**: 1  | **Objection**: FALSE  | **From**: optimizer  | **To**: alpha+risk
**Created**: 2026-04-25T14:27:48+0900

## P4 Audit — targets reviewed

1. `alpha_vector` (20 tickers, range 1.51 ~ 2.90, RoleBias_Core)
2. `confidence_vector` (range 0.24 ~ 0.52, mean 0.37)
3. `risk_sigma` (LW_oracle, cond 197.47, market 70.4%)
4. `bound_feasibility` (max_names 20, min_names 15, weight_ub 0.15 < user 0.20)
5. `L_219_caveat_resolution` (panel cor 0.0021 vs top-20 -0.290 — resolved by metric type)
6. `M08_decay_recommendation` (RF-R7 채택 → m08_decay_overlay conditional spec)
7. `Q07_M08_joint_exposure` (RF-R6 채택 → q07_m08_joint_monitor enabled)
8. `heavy_tail_handling` (Hill α=0.46 → Student-t df=4 simulation + tie-breaker)

## Observations (informational, no formal objection)

### OBS-O1: M08 standalone-IC sign instability
- Risk Agent measured monthly recompute -0.043 vs Alpha panel +0.082
- Resolution: M08 weight_theta = 0.040 (smallest among 6 factors). Standalone signal NOT used. Cross-family diversifier role honoured by alpha composite design.
- Action: no_change. Optimizer respects alpha_package allocation; no factor re-weighting.

### OBS-O2: Heavy-tail M08 (Hill α=0.46)
- Daniel-Moskowitz (2016) momentum crash exposure structurally present
- Resolution: Returns history simulated under Student-t (df=4) for CVaR. Heavy-tail tie-breaker rule applied if top-3 methods within 5% net_ir.
- Action: heavy-tail-aware method (CVaR/HRP/Kelly_frac025) preferred when within 5% of optimum.

### OBS-O3: M08 SubStab 0.188 (P3 IC decay 0.062 → 0.012)
- Risk Agent recommended Risk_Management overlay if Forge OOS P3 < baseline
- Resolution: m08_decay_overlay conditional spec emitted (vol_target 18%, lookback 60d).
- Action: Forge engages overlay ONLY if backtest confirms P3 IC decay materializes OOS.

### OBS-O4: Q07-M08 top-20 cor = -0.290 (currently negative diversifier)
- Risk Agent recommendation: monitor dynamically
- Resolution: q07_m08_joint_monitor enabled with 3-metric schema
  - portfolio-level cor (alert if > 0.50)
  - joint top-5 weight share (alert if > 0.50)
  - max single-name weight where both factors > +1σ (alert if > 0.10)
- Action: monitoring layer active in deployment WT (post-graduation).

## Selected method

- **method_selected**: HRP_lw
- **net_IR**: 12.2905
- **IR**: 12.3633
- **TE**: 0.1560
- **n_names**: 20
- **HHI**: 0.0843
- **max_w**: 0.1500 (≤ 0.20 user hard)
- **turnover (vs EW)**: 0.6308

## No silent override

- alpha_vector / weight_theta unchanged from alpha_package
- Σ unchanged from risk_package (LW_oracle preserved)
- All Risk Agent challenge_flags addressed without alpha or Σ re-interpretation
- Heavy-tail handling implemented via simulation + tie-breaker, NOT via factor re-weighting
- m08_decay_overlay is CONDITIONAL (Forge stage trigger), NOT pre-applied

## Verdict

**OPTIMIZER_DONE — selected=HRP_lw, max_w=0.1500, expected SR=12.3633, M08 weight=4.0100%, joint Q07-M08 weight=0.5614**
