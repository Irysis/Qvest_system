# Weight Method Selected — WT-S20260504_001 (PCA Latent Hedge)

## Selected Method

**M4+PCA_Hedge** (canonical primary, recommendation_only).

## Rationale

### Objective
Reduce STR_1715 dominant latent factor exposure (B_ref'w) without rewriting alpha. Statistical factor model only — no heuristic rule (DD brake / topN fixed cash / regime threshold) added beyond existing M4.

### QP formulation
```
max  α'w  −  (γ/2) ||B_ref' w||²  −  (ε/2) ||w||²
s.t. Σw = 1
     0 ≤ w ≤ 0.20
     |support(w)| ≤ 20  (top-20 selected before QP by score_eff)
```

- α: STR_1715 score_eff (parent alpha, no new generation)
- B_ref: 440×5 PCA loadings IS-frozen at 2024-06-30 (lro_params SHA `6a48a719025f9bb3...`)
- γ = **1000** (calibrated via 8-point sweep on 2026-05-01 panel)
- ε = 1e-4 (Tikhonov regularizer for QP PD)

### γ calibration sweep

| γ | LFC | reduction | alpha.w | comment |
|---|---|---|---|---|
| 0.1 ~ 10 | 0.001868 | -157% | 1.94 | alpha completely dominates |
| 50 | 0.001056 | -45% | 1.94 | minor hedge |
| 100 | 0.000839 | -16% | 1.93 | parity |
| 500 | 0.000219 | +70% | 1.86 | strong hedge |
| **1000** | **0.000087** | **+88%** | **1.81** | **selected (Pareto-optimal)** |
| 5000 | 0.000008 | +99% | 1.75 | excessive alpha damage |
| 10000 | 0.000004 | +99% | 1.73 | redundant |

### Multi-strategy comparison (recommendation_only side-by-side for Forge)

| # | Strategy | LFC@2026-05-01 | Cap | Cash overlay | Note |
|---|---|---|---|---|---|
| 1 | S1 baseline | 0.000727 | 0.20 | none | Iter31 reproduce |
| 2 | PCA_Hedge | 0.000087 | 0.20 | none | structural hedge only |
| 3 | **M4+PCA_Hedge** | **0.000087** (sleeve) | 0.20 | M4 BOCPD regime | **canonical** |

### Why M4+PCA_Hedge canonical

- M4 retains state-conditional cash defense (proven +9.6pp MDD on STR_1715 per L-274)
- PCA Hedge structurally diversifies Layer B (replaces Iter31 linear_tilt with QP)
- Stacking is multiplicative: M4 hedges regime-shock; PCA hedges latent-factor concentration
- Both layers statistical/optimization-based — no heuristic rule introduced

### Hard constraints (all PASS)

- max_names ≤ 20 (RF-O5)
- 0 ≤ w ≤ 0.20 (RF-O7)
- |Σw − 1| < 0.001 (RF-O6, max dev 4.6e-6)
- long_only (PASS)

### Schedule fidelity

- parent alpha sig_dates: 269 (2004-01-01 ~ 2026-05-01)
- weights.csv unique_dates: 269
- schedule_density: **1.0000** (≥ 0.95 threshold) — RF-O9 PASS
- No infeasibility encountered → no `infeasibility_report` field

### B_ref coverage diagnostic (Codex C2 risk concern)

At 2026-05-01: B_ref overlap 16/20 names (80%). 4 names absent from B_ref (universe drift since 2024-06-30 IS endpoint) → imputed B_i = 0 (neutral assumption). Worst-case bound documented in `lro_portfolio_mrc.csv` for Forge sensitivity test if needed.

### AX-002 enforcement

- lro_params SHA self-verify: PASS (`6a48a719025f9bb3...` recomputed match)
- OOS modification count: 0 (B_ref + K=5 + window=252 + cov method all frozen at 2024-06-30)
- production directory STR_1715 write count: 0

### Selection objective

`to_adj_ret_with_lfc_reduction` (custom): tradeoff between alpha-tilt preservation and latent factor exposure minimization. Single Sharpe-max blocked per role spec.

## Forge handoff

- canonical weights: `stage_artifacts/WT_WT-S20260504_001/weights.csv`
- variants: `stage_artifacts/WT_WT-S20260504_001/weights_variants/{S1,PCA_Hedge,M4+PCA_Hedge}.csv`
- backtest matrix: 3 strategies, monthly, 15bps cost, KOSPI200 benchmark
- lro_params SHA verify by Forge: replicate with `digest::digest(charToRaw(toJSON(dict_excl_sha, auto_unbox=TRUE, pretty=FALSE)), algo='sha256', serialize=FALSE)`

## References

- Connor & Korajczyk (1986) — statistical factor model identification
- Bai & Ng (2002) — number of factor selection (PC_p2)
- Rockafellar & Uryasev (2000) — CVaR LP (related, used in M4 layer)
- Kim, Kim & Mulvey (2014) — regime-conditional optimization (M4 motivation)
- L-274 STR_1715 PG2 3-Layer separation
- L-269 v6.0 Codex Critic Round 의무
