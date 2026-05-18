# Turnover Decomposition — DPL_KR_v3

**WT-D20260519_001 · optimizer-research Step 3**
**Date**: 2026-05-18
**Author**: optimizer-research agent (autonomous)
**Inherits**: Codex v1 C6 ACCEPT (`cost_convention_codex_c6_explicit` 0.0015 × 2 × |Δw| per rebalance, no annual ×12 multiplier in loss)
**v1 violation reference**: Iter 3 TO ×12 annualization in loss → fail. v3 strict avoid.

---

## 0. Turnover Convention — Single Source of Truth

### 0.1 Per-rebalance One-way TO

```
one_way_TO_t = Σ_i |w_i,t - w_i,t-1|       (L1 distance per rebalance step)
```

- Units: dimensionless ∈ [0, 2] (theoretical max if 100% turnover)
- Typical KR equity strategy: 0.10-0.50 per monthly rebal
- DPL_v3 target: ≤ 0.50 per monthly rebal (Partial Adjust α=0.6 + λ_to × 4.0)

### 0.2 Per-rebalance Cost

```
cost_t = 0.0015 × 2 × one_way_TO_t                (round-trip = buy + sell)
       = 0.003 × one_way_TO_t
```

- `0.0015`: 15bps one-way (cost_model_version v2.3_kr_retail_15bps)
- `× 2`: round-trip multiplier (buy-side + sell-side per rebal)
- **NOT × 12**: annualization is NOT applied at loss term per rebalance (Iter 3 violation avoidance, Codex v1 C6 ACCEPT inherit)

### 0.3 Annual TO Sum (PostBacktest Audit)

```
turnover_annual = Σ_{t=1..n_rebal_per_year} one_way_TO_t        (sum of per-rebal TOs over 12 months)
                ≤ 6.0 hard cap                                   (request.json hard_constraints)
```

- Annual cost: `cost_annual = 0.003 × turnover_annual`
- Pure annual TO sum (NOT × 12 of single rebal) — accumulates monthly rebal differences
- Forge cycle audit: per epoch assert `turnover_annual_estimate < 6.0` during training; per window post-backtest measure realized.

### 0.4 Annual TO Cap = 6.0 Interpretation

For monthly rebalanced strategy:
- `TO_annual = 6.0` means avg `one_way_TO_t = 0.5` per monthly rebal
- 50% portfolio turnover per month, 600% annual
- Equivalent to KOSPI200 reweight ~ 1.5/year (~150% annual TO) is conservative
- v3 target lower than 6.0 via Partial Adjust + concentration penalty

---

## 1. Loss Function — Turnover Term Decomposition

### 1.1 Composite Loss (architecture §3.1)

```
L_total = L_sharpe + λ_to · L_to + λ_conc · L_conc
```

### 1.2 L_to Term (architecture §3.3)

```
L_to(w_t, w_{t-1}) = |w_t - w_{t-1}|_1 · 0.0015 · 2
                   = 0.003 · one_way_TO_t                  (per rebal)
```

- λ_to grid: {1.0, 2.0, 4.0} (v1 1.0 weak → v3 increases to 4.0)
- Gradient: `∂L_to/∂w_i = λ_to · 0.003 · sign(w_i,t - w_i,t-1)` (subgradient of |·|)
- Per rebal — NOT accumulated across rebals during single-batch training (1 sig_date per batch)

### 1.3 Equivalence Forms

```
L_to_per_rebal = γ_cost · one_way_TO_t,    γ_cost = λ_to · 0.003
```

Renaming `γ_cost = λ_to · 0.003 ∈ {0.003, 0.006, 0.012}` to make explicit.

### 1.4 What λ_to ∈ {1.0, 2.0, 4.0} Looks Like in Practice

For a sig_date with `one_way_TO_t = 0.5` (50% turnover):

| λ_to | γ_cost | L_to value | Comparison vs L_sharpe |
|---|---|---|---|
| 1.0 | 0.003 | 0.0015 | weak (assuming \|L_sharpe\| ~ 1.0) |
| 2.0 | 0.006 | 0.003 | moderate |
| 4.0 | 0.012 | 0.006 | strict |

If `L_sharpe ~ -1.0` (good Sharpe), then `L_to ~ 0.006` is 0.6% of signal — small but persistent gradient toward low TO.

**Important caveat**: λ_to is applied **per training batch (per sig_date)**, NOT annually. The optimizer sees ~5 (training set: 60 train months / 12 = 5 years × 12 rebals = 60 rebal events per training sequence) gradient updates per training epoch through the per-rebal cost. Effective annual cost minimization emerges from cumulative gradient over rebals.

---

## 2. Realized Turnover Decomposition (Post-Forge Measurement)

### 2.1 Three-source Decomposition

```
TO_annual = TO_signal_change + TO_membership_change + TO_partial_adjust_smoothing
```

| Source | Formula | DPL_v3 Expected |
|---|---|---|
| Signal change | `Σ_{i ∈ persistent top-20} |w_i,t - w_i,t-1|` (same name, weight changes) | LOW (continuous softmax + concentration penalty stabilizes) |
| Membership change | `Σ_{i ∈ entered \ exited at t} max(w_i,t, w_i,t-1)` (entry/exit events) | MEDIUM (cross-section ranking can shift) |
| Partial Adjust smoothing | reduces both above by factor (1-α) = 0.4 absorbing prior weights | HIGH absorption (40% prior carry) |

### 2.2 Theoretical TO Bound — Top-K Stability

With Partial Adjust α=0.6, if `w_new` is *completely different* set of top-20 from `w_old`:
- `Σ_i |α·w_new_i + (1-α)·w_old_i - w_old_i|` = `α · Σ_i |w_new_i - w_old_i|`
- For uniform 20×0.05 swap: TO_raw = 2.0 (max possible), TO_PA = 1.2
- For partial overlap (50% retained): TO_raw ≈ 1.0, TO_PA ≈ 0.6

Annual: 12 × 0.6 = 7.2 (if every month full swap with PA). Still above 6.0 cap.

**Conclusion**: Partial Adjust alone insufficient if signal churns heavily. Concentration penalty + decision-induced ranking clip + λ_to grid must work together.

### 2.3 Stability Inducer Layers

| Layer | Mechanism | Expected TO Reduction |
|---|---|---|
| Decision-induced ranking clip [-3, 3] | Limits extreme score swings between sig_dates | Modest (~20%) |
| Concentration penalty `λ_conc · (HHI - 0.10)²` | Prefers persistent top stocks (high score persistence → lower HHI variance) | Modest (~15%) |
| Continuous softmax + STE top-K (vs Gumbel hard sampling) | Deterministic at inference (no stochastic noise re-sampling between sig_dates) | LARGE (~40%) — v1 Gumbel τ=0.1 caused independent sampling each sig_date |
| Partial Adjustment α=0.6 | 40% prior weight carry forward | LARGE (~30-40%) by construction |
| Per-epoch λ_to penalty | Direct gradient toward low TO | calibrated by grid |

**Estimated combined effect**: from worst-case TO_raw ~ 12 (uniform top-20 swap monthly w/o any mitigation) → DPL_v3 expected ~ 3-5 (50-60% reduction). Within 6.0 cap.

---

## 3. Per-window Turnover Schedule

For each of 13 walk-forward test windows:

| Window | Test months | Expected rebals | Expected TO_window | Annualized TO |
|---|---|---|---|---|
| 1-12 | 24 | 24 | n × avg_TO_per_rebal | n × avg_TO × 12 / 24 |
| 13 | 16 (partial) | 16 | n × avg_TO_per_rebal | n × avg_TO × 12 / 16 |

**Hard cap**: per-window annualized TO < 6.0. If any window > 6.0 → λ_to grid expand to 8.0 (architecture §3.3 mandate).

**Forge measurement obligation**:
- `realized_TO_per_rebal[1..304]` array
- `mean_TO_per_rebal` aggregate (target ≤ 0.5)
- `annual_TO_per_window` × 13 (target all ≤ 6.0)
- `pct_rebal_with_TO_gt_1` (target ≤ 5%)

---

## 4. Cost vs Net Sharpe Pareto Frontier

### 4.1 Net SR Formula

```
net_SR = (mean_gross_return - cost_realized) / std_gross_return  
       ≈ gross_SR - cost_term / σ_p
```

For monthly: `cost_term = 0.003 · turnover_per_rebal · 12 = 0.036 · turnover_per_rebal`.

For typical KR equity vol σ_p_monthly ≈ 0.05-0.07 (~6% monthly), σ_p_annual ≈ 0.20:
- TO_per_rebal = 0.5 → cost_annual = 1.8% → Δ_SR ≈ 0.09 (gross SR penalty ~ 0.09)
- TO_per_rebal = 1.0 → cost_annual = 3.6% → Δ_SR ≈ 0.18

DPL_v3 target `net_SR ≥ 1.0` (G1 gate) implies `gross_SR ≥ 1.18 + cost_drag` ≈ 1.18-1.3 depending on TO.

### 4.2 Pareto Frontier — λ_to vs SR_net

Forge cycle Pareto sweep:

| λ_to | Expected TO_annual | Expected Δ_SR_net | Expected SR_net |
|---|---|---|---|
| 1.0 (weak) | ~5.5 | -0.07 | ~ 1.0 |
| 2.0 (moderate) | ~4.0 | -0.05 | ~ 1.1 |
| 4.0 (strict) | ~2.8 | -0.03 | ~ 1.05 (signal might attenuate) |

**Selection**: Forge selects λ_to maximizing net_ir (NOT gross SR). Codex v1 C6 ACCEPT — cost-aware selection objective.

---

## 5. Iter 3 Annual ×12 Violation Avoidance

### 5.1 Violation Pattern (Forbidden)

```python
# WRONG — Iter 3 violation
L_to = (|w_t - w_{t-1}|_1 * 0.0015 * 12)   # ×12 inside loss
```

Reason: loss term × 12 multiplier inflates gradient artificially. Per-rebal training does not see annualized aggregation.

### 5.2 Correct Form (DPL_v3 spec)

```python
# CORRECT — v3 spec
L_to_per_batch = (|w_t - w_{t-1}|_1 * 0.0015 * 2)   # per rebal, ×2 round-trip
loss = L_sharpe + lam_to * L_to_per_batch + lam_conc * L_conc
```

### 5.3 Forge Audit Mandate

- Per-epoch log L_to value distribution
- If `mean(L_to) > 0.05` consistently → λ_to too low or signal churning
- If `L_to ≈ 12 × per_rebal_expected` → violation detected → ABORT

---

## 6. Realized Cost Reconciliation (Backtest Contract v1.0)

```
cost_realized = Σ_{t=1..n_rebal} 0.0015 × 2 × |w_t - w_{t-1}|_1
              = 0.003 × Σ_{t=1..n_rebal} one_way_TO_t
              = 0.003 × TO_annual                              (if 1 year period)
```

Backtest Contract v1.0 audit field: `bt_result$audit$cost_realized` matches `0.003 × turnover_annual` within 1e-6.

PerformanceAnalytics input: returns are net (`r_net = r_gross - per_rebal_cost / vol_share`).

---

## 7. Cost-Aware Loss Term Net Effect on Gradient

### 7.1 Gradient Form

```
∂L_to/∂w_i = λ_to · 0.003 · sign(w_i,t - w_i,t-1)
```

Where `sign(·)` is the subgradient of |·| at zero. PyTorch `torch.sign` gives 0 at exactly 0 (smoothed via differentiable surrogates if needed).

### 7.2 Combined Gradient (Sharpe + TO)

```
∂L_total/∂w_i = ∂L_sharpe/∂w_i + λ_to · 0.003 · sign(Δw_i) + 2 · λ_conc · (HHI - 0.10) · w_i
```

For top-K stocks with positive (Δw_i > 0, increasing weight): TO gradient is positive (push back DOWN); Sharpe gradient depends on direction. Net effect: TO term provides damping.

### 7.3 Empirical Tuning Strategy (Forge cycle)

```
1. Start with λ_to = 1.0 (v1 baseline)
2. If realized TO_annual > 6.0 → λ_to *= 2.0 (escalate)
3. If λ_to = 4.0 still TO > 6.0 → expand grid to {4.0, 8.0, 16.0}
4. If λ_to = 16.0 still TO > 6.0 → architectural issue, signal too volatile → REJECT
```

---

## 8. Conclusions

1. **Cost convention strict explicit**: per-rebal `0.0015 × 2 × |Δw|`, NO ×12 in loss (Codex v1 C6 ACCEPT)
2. **Three-source decomposition**: signal change + membership change + Partial Adjust smoothing
3. **5-layer mitigation stack**: decision-induced clip + concentration penalty + continuous softmax (vs Gumbel stochastic) + Partial Adjustment + λ_to grid
4. **Expected DPL_v3 TO_annual**: 3-5 (within 6.0 cap), depending on grid sweep result
5. **Forge audit**: per-rebal TO logging + per-window TO_annual + Pareto frontier sweep
6. **Net SR penalty**: ~0.03-0.09 SR points from cost drag → target G1 net_SR ≥ 1.0 implies gross_SR ≥ 1.1+

**Forge mandate**:
- Per-epoch L_to value distribution log
- Per-window realized TO_annual measurement
- Pareto sweep λ_to grid selection by net_ir (Codex v1 C6 + R4 P3 selection_objective)
- Realized cost reconciliation with Backtest Contract v1.0 `bt_result$audit$cost_realized`

---

**End of Turnover Decomposition v3**
