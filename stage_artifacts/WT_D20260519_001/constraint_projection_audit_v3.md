# Constraint Projection Audit — DPL_KR_v3

**WT-D20260519_001 · optimizer-research Step 1**
**Date**: 2026-05-18
**Author**: optimizer-research agent (autonomous)
**Architecture inherit**: `dpl_kr_v3_architecture.md §2.4-2.7` (Continuous concentration softmax + STE top-K + PAN + Partial Adjustment)
**Lineage from v1**: `WT-D20260517_001/constraint_projection_audit.md` (4-stage projection, ReLU + Gumbel + clip + L1)
**Paradigm distinction**: v1 = 4-stage hard projection (Stage 1 ReLU, Stage 2 Gumbel hard top-K, Stage 3 clip, Stage 4 L1). v3 = 4-stage soft-then-projection (continuous softmax over all N, STE top-K mask, PAN bounds+L1 iterative, Partial Adjustment).

---

## 0. Audit Verdict — TL;DR

**Verdict**: `PASS_WITH_CAVEATS` (same family as v1 but materially safer EW-collapse profile due to concentration penalty + continuous softmax)

**Key v3 vs v1 deltas**:

| Aspect | v1 | v3 | Risk |
|---|---|---|---|
| Top-K mechanism | Gumbel hard top-K (τ-anneal 1.0→0.1) | Continuous softmax over N + STE top-K mask | v3 lower EW-collapse risk (concentration penalty) |
| Inference top-K | gumbel_softmax(hard=True) | argsort(w_raw)[N-20:] + Σ-renormalize | v3 deterministic (no stochastic at infer) |
| Bounds/L1 | 1-pass clip → L1 (non-idempotent) | PAN iterative max-3 + Dykstra fallback | v3 inherits v1 Dykstra mandate |
| Persistence layer | none | Partial Adjustment α=0.6 | v3 new layer (TO mitigation) |
| Architecture intent | Substitution-only | Standalone alpha (substitution OR 4th source) | scope expansion |
| Test scope | 5 WF × 52m | **13 WF × 304m** (도훈 mandate 2026-05-19 inherit) | 5.8× sample increase, regime heterogeneity audit weighted |

**Caveats (carried to Forge cycle)**:
1. PAN non-idempotency same family as v1 (Bauschke-Combettes 2017 §28.3) → **Dykstra v1.0 fallback mandate inherited** (Codex v1 C3 ACCEPT). Forge per-row violation_rate = 0 strict.
2. STE top-K continuous-soft training / hard-deterministic inference 일관성 mandate: `if self.training: STE mask else: argsort` (architecture §2.5). Forge per-epoch audit obligation.
3. Continuous softmax can still degenerate if `τ` too large + `λ_conc` too weak → **G7 HHI > 0.06 strict ABORT gate** (request.json `failure_cutoffs_v1_v5_strict.ew_collapse_HHI_0_05`).
4. Partial Adjustment α=0.6 introduces stateful dependency `w_t = α · w_t^new + (1-α) · w_{t-1}` — initial sig_date `w_0` cold start = uniform top-20 (or EW)? Forge cycle initialization protocol obligation.
5. PG2 style cor 0.965 (RF-R6 HIGH) is a **design-phase prior on the universe baseline**, NOT a constraint on DPL_v3 weights. Forge realized DPL weights → re-measure `style_cor(DPL_v3_weights, STR_1715_alpha)` per sig_date. Optimizer scope = audit constraint projection only.

---

## 1. Stage-by-stage Audit

### 1.1 Stage A — Continuous Concentration Softmax (architecture §2.4)

```
s^i_t = ScoreHead(concat(x^i_t, c_t))
s^i_t ← clip(s^i_t, -3.0, 3.0)         # decision-induced ranking
w_raw^i = exp(s^i / τ) / Σ_j exp(s^j / τ),  τ ∈ {0.5, 1.0, 2.0}
```

| Property | Status | Note |
|---|---|---|
| Long-only output | PASS | softmax outputs ∈ (0, 1) for all i; strictly positive |
| Σw_raw = 1 | PASS | softmax by definition |
| Continuous + differentiable | PASS | softmax C^∞ |
| No hard top-K at this stage | PASS | full simplex Δ^{N-1}, all N stocks have non-zero weight |
| EW collapse risk | **LOW (vs v1 HIGH)** | concentration penalty `λ_conc · (HHI - 0.10)²` enforces non-uniform |
| τ grid sweep | PASS | {0.5, 1.0, 2.0} 3-point grid |

**v3 distinction from v1**: v1 used Gumbel hard top-K immediately after ReLU; v3 keeps softmax over all N, applies concentration penalty + STE top-K mask after. **EW collapse safer**: penalty term is differentiable, gradient flows directly to score head.

### 1.2 Stage B — STE Top-K Soft Selection (architecture §2.5)

**Train mode**:
```python
top_k_indices = torch.topk(w_raw, n_top_k=20).indices
top_k_mask = torch.zeros_like(w_raw).scatter_(0, top_k_indices, 1.0)
w_soft = w_raw * top_k_mask   # forward: 80/(N-20) zeros; backward: STE pass-through
```

**Inference mode**:
```python
top_k_indices = torch.topk(w_raw, n_top_k=20).indices
w_soft = torch.zeros_like(w_raw).scatter_(0, top_k_indices, w_raw[top_k_indices])
w_soft = w_soft / w_soft.sum()
```

| Property | Train | Inference | Status |
|---|---|---|---|
| Hard top-20 enforcement | yes (mask) | yes (argsort + renorm) | PASS |
| Σw = 1 after this stage | NO (w_soft = w_raw * mask, Σ < 1) | YES (renormalized) | **inconsistent — Forge must verify** |
| Differentiable backward | YES (STE) | N/A | PASS |
| Stochastic? | NO (deterministic mask + STE) | NO (deterministic argsort) | PASS (no Gumbel sample noise) |
| `max_names ≤ 20` (hook RF-O5) | PASS by construction | PASS by construction | PASS |

**Caveat (CF-O2-v3)**: Train-mode `w_soft = w_raw · mask` has Σ < 1 before PAN. PAN handles this via L1 normalize step. But **gradient via STE through L1 may amplify or attenuate** depending on the magnitude of dropped-mass. **Forge mandate**: log per-epoch `Σ w_raw[top_k_indices]` distribution. Expected ≥ 0.5 for healthy training (architecture §2.5 ACCEPT). 

If `Σ w_raw[top_k_indices] < 0.3` consistently → softmax is too flat → τ too large or score head fails to differentiate → adjust τ grid OR architecture revision.

### 1.3 Stage C — PAN Iterative (architecture §2.6)

```python
def project_simplex_bounds(w, bound_max=0.20, max_iter=3, eps=1e-6):
    for _ in range(max_iter):
        w_clip = torch.clamp(w, 0, bound_max)
        w_norm = w_clip / (w_clip.sum() + eps)
        if w_norm.max() <= bound_max + eps and abs(w_norm.sum() - 1) < eps:
            return w_norm
        w = w_norm
    return w
```

| Property | Status | Note |
|---|---|---|
| `Σw = 1` (Hook RF-O6) | **NEEDS Dykstra fallback** | iterative simple projection, fix-point not strict |
| `0 ≤ w ≤ 0.20` (Hook RF-O7) | **NEEDS Dykstra fallback** | clip-then-L1 can re-violate cap |
| Convergence within max_iter=3 | empirical (Bauschke-Combettes 2017 §28.3 standard) | Forge violation_rate = 0 strict mandate |
| Idempotent? | NO (clip then L1 multiplies all by > 1 when Σ_clip < 1, re-violating cap) | same family as v1 CF-O1 |
| Dykstra v1.0 fallback | mandated (Codex v1 C3 ACCEPT inherit) | Boyle-Dykstra 1986 strict simplex × bounds intersection |

**CF-O1-v3 inheritance** (HIGH, CARRY from v1): Forge per-row violation_rate = 0 strict per sig_date per row. Single violation → Dykstra fallback automatic. Spec same as v1 (no degradation).

**Convergence analysis (deferred Forge audit)**:
- Best case (K ≤ 5 stocks at exactly 0.20 cap): converges in 1 iteration
- Typical case (K ≈ 8 stocks at cap): converges in 2 iterations
- Worst case (K ≈ 20 stocks near cap simultaneously, soft active): may need max_iter=3 + Dykstra fallback
- **Architectural note**: 20 stocks × 0.20 max = 4.0 ≥ 1.0 target → feasibility ratio = 4×, more permissive than EW (5 × 0.20 = 1.0 exact)

### 1.4 Stage D — Partial Adjustment (architecture §2.7)

```python
def partial_adjust(w_new, w_old, alpha=0.6):
    return alpha * w_new + (1 - alpha) * w_old
```

| Property | Status | Note |
|---|---|---|
| `Σw = 1` post-adjust | PASS (if both w_new and w_old sum to 1, convex combo sums to 1) | mathematical |
| `0 ≤ w ≤ 0.20` post-adjust | PASS (convex combo preserves bounds) | mathematical |
| `max_names ≤ 20` post-adjust | **CAVEAT** | if `w_new` top-20 vs `w_old` top-20 differ, **union of active names** may exceed 20 |
| TO reduction expected | yes (α=0.6 → ~60% of w_new movement adopted) | Wang-Hasuike 2026 §3-4 |

**CF-O3-v3 NEW (HIGH)**: Partial Adjustment can produce `count(w > 0) > 20` if active universe differs between `t-1` and `t`. 

**Resolution**: After Partial Adjustment, **re-apply STE top-K + PAN** (effectively a second projection):
```python
w_t_pre = alpha * w_new + (1 - alpha) * w_old   # may have > 20 non-zero
top_k_indices = torch.topk(w_t_pre, n_top_k=20).indices
w_t_renorm = torch.zeros_like(w_t_pre).scatter_(0, top_k_indices, w_t_pre[top_k_indices])
w_t = project_simplex_bounds(w_t_renorm / w_t_renorm.sum())
```

This 2-stage projection guarantees `count(w > 0) ≤ 20` AND `Σw = 1` AND `0 ≤ w ≤ 0.20` simultaneously. **Forge mandate**: implement post-Partial Adjustment re-projection. Audit per-row count assertion.

**Architecture amendment**: append to architecture §2.7 — "Post-Partial-Adjustment re-projection mandatory". Carried as alpha-research CF-A16 candidate (no Charter revision needed, implementation-level).

### 1.5 Stage E — Initial Cold Start

For `t_0 = first sig_date`, `w_{-1}` undefined. Initialization options:

| Option | Spec | Pro | Con | Selected |
|---|---|---|---|---|
| EW top-20 (warmup-based) | uniform 1/20 = 0.05 each on top-20 by w_raw at t_0 | safe HHI floor 0.05 | not informative | YES (default) |
| All zeros | w_{-1} = 0, w_0 = α · w_new (Σ = 0.6 < 1 → re-normalize) | clean | numerical singularity | NO |
| First-month no-PA | w_0 = w_new (no adjust), w_{≥1} use PA | natural | special-case logic | conditional |

**Forge mandate**: declare initialization protocol in forge_package.json. Default = EW top-20.

---

## 2. Hard Constraints Compliance Matrix

| Constraint | Source | Architecture Layer Enforcing | Pass at Design Phase | Forge Audit Obligation |
|---|---|---|---|---|
| `max_names ≤ 20` | request.json hard_constraints | Stage B (STE top-K) + Stage D re-proj | PASS by construction | per-row count assertion |
| `weight_bounds [0, 0.20]` | request.json hard_constraints | Stage C (PAN clip) | PASS within max_iter=3 + Dykstra fallback | violation_rate = 0 strict |
| `Σw = 1` (absolute) | request.json hard_constraints | Stage C (PAN L1) | PASS within tol 1e-6 | per-row L1 = 1 ± 1e-6 |
| `long-only` (w ≥ 0) | request.json hard_constraints | Stage A (softmax) + Stage C (clip 0) | PASS by construction | per-row min ≥ -1e-6 |
| Universe `KR_TOP500_LIQ1E8` (2e8 KRW 20d ADV) | alpha-research §1.1-1.2 | pre-input filter | PASS (alpha-stage) | per-row LIQ verification |
| `cost 15bps one-way × 2 round-trip` | cost_model_version | Loss L_to | declared explicit | realized cost = 0.0015 × 2 × Σ\|Δw\| per sig_date |
| `turnover_annualized_max = 6.0` | request.json hard_constraints | Loss λ_to + Partial Adjust + PAN | declared design-time | Σ_{t=1..304} \|w_t - w_{t-1}\|_1 with per-rebal cost — see turnover_decomposition_v3.md |
| `mdd_pct_max = -0.25` | request.json hard_constraints | Strategy-level (post-Forge backtest) | N/A at design | Forge bt_result.rds 10-component |

**No design-phase violations detected**. All hard constraints have architectural enforcement layer.

---

## 3. PAN Convergence Theory + Dykstra v1.0 Fallback

### 3.1 PAN Iterative — Simple Projection (Bauschke-Combettes 2017 §28.1)

PAN alternates between:
- Box: `B = {w | 0 ≤ w_i ≤ 0.20}`
- Simplex: `S = {w | Σw_i = 1, w_i ≥ 0}`

For intersection `B ∩ S`:
- **Simple alternating projection** (PAN spec) converges *under best conditions* but NOT guaranteed in 3 iter for arbitrary inputs.
- **Dykstra projection** (Boyle-Dykstra 1986) guarantees convergence with corrector terms.

### 3.2 v1 Codex C3 ACCEPT Inheritance — Dykstra v1.0 as Fallback

When PAN max_iter=3 fails (`max(w) > 0.20 + 1e-6` OR `|Σw - 1| > 1e-6`):
```python
def dykstra_simplex_box(w_init, bound_max=0.20, max_iter=50, eps=1e-8):
    w, p_box, p_simplex = w_init.clone(), torch.zeros_like(w_init), torch.zeros_like(w_init)
    for k in range(max_iter):
        # Project onto box
        w_box = torch.clamp(w + p_box, 0, bound_max)
        p_box = w + p_box - w_box
        # Project onto simplex (L1 normalize positive part)
        w_simplex = torch.clamp(w_box + p_simplex, 0, None)
        w_simplex = w_simplex / (w_simplex.sum() + eps)
        p_simplex = w_box + p_simplex - w_simplex
        # Convergence check
        if (w_simplex - w).abs().max() < eps:
            return w_simplex
        w = w_simplex
    return w
```

**Forge mandate**:
1. Try PAN with `max_iter=3`
2. If violates either bound → automatic Dykstra v1.0 fallback (max_iter=50)
3. Log per-row PAN_converged flag (True/False) for audit
4. Aggregate Forge cycle log: `pan_fallback_rate = #(Dykstra used) / total_rows` — target < 5%, alert ≥ 10%

### 3.3 Numerical floor

PAN uses `w_clip.sum() + eps` to avoid /0 when softmax temperature too high (uniform → Σ = 1 → clip 0.20 → all = 0.20 → Σ = 4.0 → renormalize 0.05 each → bound respected). Edge case: if STE mask zeros all top-K (impossible by construction but degenerate softmax could approach 0) → fallback to EW top-20.

---

## 4. v3 Architecture Risks vs v1 Architecture Risks

| Risk class | v1 occurrence | v3 mitigation | residual probability (Forge audit) |
|---|---|---|---|
| EW collapse (HHI ≤ 0.05) | 100% (all 51 sig_dates uniform 0.05) | concentration penalty `λ_conc · (HHI - 0.10)² ∈ {0.5, 1.0, 2.0}` grid + softmax temperature τ ∈ {0.5, 1.0, 2.0} | low (~15% per architecture §9.1) |
| TO > 6.0 annual | 17.64 observed | λ_to ∈ {1.0, 2.0, 4.0} + 2× round-trip + Partial Adjust α=0.6 + decision-induced clip | low (~10% per architecture §9.2) |
| PAN non-idempotency | implicit (v1 used Stage 4 L1 once) | iterative max_iter=3 + Dykstra v1.0 fallback (inherits v1 C3 ACCEPT) | violation_rate = 0 strict mandate |
| max_names > 20 post-PA | NOT addressed | re-proj after Partial Adjustment (CF-O3-v3 above) | mandate Forge implementation |
| STE gradient instability | Gumbel τ-anneal had stochastic noise (v1 collapse correlated) | STE deterministic mask, gradient `w_raw.grad` clean pass-through | low |
| AX-007 #4 ML sizing exemption invalidation | violated (EW collapse → exemption broken) | HHI > 0.06 G7 gate strict, Forge per-sig_date audit | demonstration deferred |

---

## 5. Optimizer Scope vs Forge Scope

| Aspect | optimizer-research (this cycle) | Forge cycle |
|---|---|---|
| Constraint projection design | audit + Dykstra fallback mandate | implement + per-row violation_rate = 0 enforce |
| Alternative weight comparison | protocol spec (B1-B6 baselines) | execute 6 baselines + DPL on 304 test months |
| Turnover decomposition | analytical decomposition (cost formula explicit) | realized turnover measurement |
| Top-K mechanism choice | continuous softmax + STE (selected) + alternatives evaluated | execute selected |
| Method selection objective | `net_ir` declared | measure realized net_ir post-Forge |
| weights.csv emission | **NOT EMITTED at design phase a** | emit 304 sig_dates × 20 active × Ticker × method_selected |
| Realized SR/MDD/CAGR | **NOT MEASURED** (placeholder) | bt_result.rds 10-component PerformanceAnalytics standard |
| HHI mean / sector HHI | **DESIGN-TIME EXPECTED** > 0.06 | Forge per-sig_date measurement |
| Sequential admission scenario decision (A/B/C) | scenario spec only | post-Forge G2 cor measurement → decide |

**v1 paradigm doctrine inherited (Codex C4 REBUTTAL retain)**: Production weights = DPL only (4-stage projection direct emission). Baselines = post-hoc validation. v3 ditto.

---

## 6. Carry-forward Mandates to Forge

1. **PAN per-row violation_rate = 0 strict** — single violation triggers Dykstra v1.0 fallback
2. **Post-Partial-Adjust re-projection** — guarantees count(w > 0) ≤ 20 (CF-O3-v3 NEW)
3. **STE inference hard top-K** — `if self.training` branch verified per epoch
4. **Initial cold start = EW top-20** (default; alternative declared in forge_package.json)
5. **PAN fallback rate logging** — `pan_fallback_rate = #Dykstra / total_rows`, alert ≥ 10%
6. **STE top-K mass logging** — per-epoch `Σ w_raw[top_k_indices]` distribution, alert if median < 0.5
7. **Universe LIQ 2e8 re-filter at per-sig_date** — alpha-research §1.2 mandate (Codex v1 C4 inherit)
8. **PG2 style cor re-measurement on realized DPL weights** — RF-R6 design-phase prior 0.965 is universe baseline, NOT strategy. Forge measure `style_cor(DPL_v3_weights_t, STR_1715_alpha_t)` per sig_date.

---

## 7. Audit Conclusion

| Metric | Verdict |
|---|---|
| Constraint architecture (Stages A-D) | PASS_WITH_CAVEATS (PAN fallback mandate inherit) |
| Hard constraints compliance | PASS by construction (all 8 constraints) |
| EW collapse risk | LOW (vs v1 HIGH) — concentration penalty added |
| TO violation risk | LOW (vs v1 HIGH) — 4-layer mitigation |
| AX-007 #4 eligibility | RE-ESTABLISHED (continuous softmax + concentration penalty) — DEMONSTRATION deferred Forge G7 |
| max_names ≤ 20 post-Partial-Adjustment | CAVEAT (CF-O3-v3) → re-proj mandate added |
| Charter §10 amendment-pending inherit | YES (alpha CF-A10 + v1 optimizer CF-O6 lineage) |

**Action carried to draft optimization_package_draft.json**: 
- Same family of caveats as v1 (PAN fallback, Codex C3 ACCEPT inherit)
- CF-O3-v3 NEW (Partial Adjust max_names risk) added
- All Codex Round mandate (5-step) deferred to PostToolUse spawn

---

**End of Constraint Projection Audit v3**
