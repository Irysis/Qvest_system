# Decision-Induced Ranking Clipping Audit — NAV-Level (Step 4.2)

**Task**: WT-D20260517_004 — DPL-RC v2.0 Path A NAV-level blend
**Agent**: optimizer-research
**Generated**: 2026-05-17
**Framework**: Wang-Hasuike 2026 KKT + DSPO Zhong 2024 + Epstein 2025 Set-Sequence

---

## 1. NAV-Level Specifics (vs v3 weights-level)

**v3 weights-level audit** (WT-D20260517_003) — score → softmax → rank → weight 직접 매핑.

**v4 NAV-level audit** — score → softmax → comp_sleeve weight (20 names) → comp_NAV → blend NAV.

핵심 차이:
- **Decision induced ranking은 comp sleeve 내부에만 적용**. 1715 NAV 100% retain (변형 X).
- **a_t scalar injection** (NAV-level wealth share) = 추가 ranking clip 차원 NOT direct weight.
- **Smooth transition mandate** = blend NAV `a_t` 변화에 의한 TO 급증 control.

## 2. KKT Parametric Ranking Selection (Wang-Hasuike 2026)

### 2.1 Optimization Problem

```
maximize  Σ w_i · s_i (top-K subset)
subject to  Σ w_i = 1, 0 ≤ w_i ≤ 0.20, |support(w)| ≤ 20
```

KKT necessary conditions (Lagrangian):

```
L = Σ w_i·s_i - λ(Σw_i - 1) - Σ μ_i·(w_i - 0.20) - Σ η_i·(-w_i)
∂L/∂w_i = s_i - λ - μ_i + η_i = 0

Complementary slackness:
  μ_i · (w_i - 0.20) = 0
  η_i · (-w_i) = 0
```

→ active set 분류:
- **w_i = 0.20** (binding upper, μ_i > 0): score s_i 최상위 → w_i clipped at 0.20
- **0 < w_i < 0.20** (interior, μ=η=0): s_i = λ (dual)
- **w_i = 0** (binding lower, η_i > 0): score s_i < λ

### 2.2 R1 Prediction Inflation Risk

**Mechanism**: softmax(s/τ) low τ + outlier score → one name w ≈ 100%, KKT 모두 binding.

**Mitigation 3-layer**:
1. **softmax τ grid** {0.5, 1.0, 2.0} — temperature smoothing
2. **HHI monitoring**: HHI(w_raw) > 0.30 alarm
3. **Concentration cap**: max(w_raw) > 0.30 OR n_active < 10 alarm

**Default**: τ=1.0. R1 inflation 발현 시 τ=2.0 fallback.

## 3. Min-Max Rescaling + Z-Score (R3 mitigation)

### 3.1 Stage 간 Score Scale Variance

**Mechanism**: S1 linear PPP score (raw return space, ~±0.05) vs S3 LightGBM (log-odds space, ~±2.0) → softmax behavior inconsistent.

**Mitigation per-sig_date**:
```
1. Z-score: s_z = (s - mean(s_t)) / sd(s_t)
2. Min-max top-K subset: s_mm = (s_z - min_K) / (max_K - min_K)
3. Softmax: w_raw = exp(s_mm / τ) / Σ exp(s_mm / τ)
```

**Inflation protection by construction**:
- Z-score range ≈ ±3 cross-section (KR equity empirical)
- Min-max top-K → [0, 1] bounded
- τ=1.0 softmax → max(w_raw) ≤ exp(1)/(exp(1) + 19·exp(0)) ≈ 12.5% < 0.20 cap ✓

## 4. Partial Portfolio Adjustment (R2 smooth transition)

### 4.1 Formulation

```
w_t = α · w_t^new + (1-α) · w_{t-1}
```

| α | Behavior | Use case |
|---|---|---|
| 0.30 | Heavy retention | turnover-sensitive scenario |
| 0.50 | Balanced (default) | TO target 6.0/yr 정합 |
| 0.70 | Light retention | alpha-rich scenario |
| 1.00 | No retention | benchmark comparison |

### 4.2 NAV-Level Wealth Share Smoothing

**Critical**: NAV-level `a_t` scalar 변화도 smoothing 적용:

```
a_t_smooth = β_a · a_t^new + (1-β_a) · a_{t-1}
β_a default 0.50 (alignment with α retention)
```

`a_t` 급격 변동 (e.g. 0.20 → 0.05 within 1 month) = blend NAV TO 급증 → A5 violation 가능. β_a smoothing 의무.

### 4.3 Effective Turnover Decomposition

```
TO_blend_monthly_t
  = (1-a_t)·TO_1715_monthly_t  [Layer 1: 1715 internal]
  + a_t·TO_comp_monthly_t      [Layer 2: comp internal]
  + |a_t - a_{t-1}|·(NAV_comp - NAV_1715)/NAV_blend  [Layer 3: cross-sleeve rebalance]

TO_blend_annualized = Σ_{t=1..12 over rolling year} TO_blend_monthly_t × 2
(round-trip ×2, NOT ×12 annualization — Iter 3 violation 사례 차단)
```

## 5. R4 Ranking Degenerate (incremental admission)

### 5.1 Diagnostic (Spearman + Jaccard)

stage N+1 vs N pair에 대해:

```r
spearman_t = cor(rank(s_N1_t), rank(s_N_t), method = "spearman")
jaccard_t = |top20(s_N1_t) ∩ top20(s_N_t)| / |top20(s_N1_t) ∪ top20(s_N_t)|
```

→ `spearman_mean, jaccard_mean` over walk-forward OOS test windows.

### 5.2 Alarm Thresholds

```
ALARM: spearman_mean > 0.95 AND jaccard_mean > 0.80
→ Stage N+1은 Stage N과 ranking degenerate (incremental gain 미미)
→ admission re-evaluation + Codex Round critic mandate 강화
```

**Default decision**: degenerate stage REJECT — Occam razor + L-326 over-param mandate.

## 6. 3-Layer TO Control Hierarchy

| Layer | Mechanism | Default | Grid |
|---|---|---|---|
| L1 Loss term | λ_to · turnover training loss | 0.5 | {0.1, 0.5, 1.0} |
| L2 Partial adjust | α retention | 0.5 | {0.3, 0.5, 0.7, 1.0} |
| L3 Admission gate | A5 ≤ 6.0 hard cap | hard | none |
| L4 (NAV-level) **NEW** | β_a smoothing | 0.5 | {0.3, 0.5, 0.7, 1.0} |

**Cumulative annualization**:
```
TO_target_annualized ≤ 6.0
  Layer 1+2+4 design-time enforce
  Layer 3 hard admission
```

## 7. Long-Only Compliance Audit (risk C7 PARTIAL_ACCEPT)

### 7.1 β Neutralization DEFERRED Audit Path

risk_package C7 PARTIAL_ACCEPT: β neutralization fallback = `r_comp_residual = r_comp - β·r_1715` 차감.

**Optimizer audit**:
- portfolio holdings = comp_sleeve weights ≥ 0 (long-only retain) ✓
- blend NAV time-series = `(1-a)·NAV_1715 + a·NAV_comp` (NO subtraction at NAV level) ✓
- BUT residualization 적용 시 `r_comp_residual` ≈ `r_comp - β·r_1715` → implicit -β·r_1715 short exposure at return-level

### 7.2 Decision

**β neutralization fallback = OPTIMIZER design-only deferred** (governor + execution agent long-only compliance audit binding).

Primary path = **λ_corr training-side grid** (Section 5 injection_grid_nav_pareto.md):
- training-side cor anchor via L_total loss term
- no NAV-level shorting
- long-only holdings strictly retain

## 8. KKT Diagnostic per Pareto Candidate (Forge cycle binding)

각 16 candidate에 대해 measurement 시:

```
1. Solve QP/MILP → w_t per sig_date
2. KKT dual variables (λ, μ_i, η_i) extract
3. binding_constraints (max upper / cardinality) count
4. dual sensitivity: ∂SR/∂λ via finite difference
```

Output: `stage_artifacts/WT_D20260517_004/kkt_diagnostics_per_cell.csv`

## 9. Design-Only Scope Statement

**본 audit framework은 design-only**. 16 candidate KKT diagnostic + λ_corr grid sweep + R4 degenerate diagnostic = **Forge cycle 의무 measurement**.

optimizer-research cycle 산출 = **audit framework + risk decomposition + decision rules**. measurement responsibility = forge agent.

---

## References

- Wang-Hasuike 2026 — KKT parametric ranking selection
- Zhong 2024 DSPO — score → rank → portfolio framework
- Epstein 2025 — Set-Sequence permutation
- Politis-Romano 1994 — stationary bootstrap
- López de Prado 2018 AFML §7 — walk-forward OOS
- WT-D20260517_003 v3 clipping_audit_v3.md inherit
