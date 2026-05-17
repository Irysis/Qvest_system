# Active-Weight Neutral Constraint Spec — Σ(w - b) = 0

**WT-D20260517_002 · alpha-research Step 2.2d**
**Date**: 2026-05-17
**Author**: alpha-research agent
**도훈 mandate F.3 (2026-05-17 22:30)**: Active-weight neutral constraint Σ_i (w_{i,t} - b_{i,t}) = 0

---

## 1. Constraint Formal Definition

### 1.1. Mathematical Statement

```
Σ_{i ∈ Universe} (w_{i,t} - b_{i,t}) = 0    ∀ t
```

Where:
- `w_{i,t}` = portfolio weight of stock i at sig_date t (decision variable)
- `b_{i,t}` = benchmark weight of stock i at sig_date t (KOSPI200 cap-weight, fixed)
- Universe = KOSPI200 ∪ KOSDAQ150 ∩ TOP500_LIQ1E8

### 1.2. Long-only universe에서의 의미

Long-only universe: `w_i ≥ 0 ∀ i`, `Σ w_i = 1`.
Benchmark: `b_i ≥ 0 ∀ i`, `Σ b_i = 1` (KOSPI200 cap-weight normalize to 1).

Therefore `Σ (w - b) = Σ w - Σ b = 1 - 1 = 0` **trivially satisfied** in long-only constraint set.

**핵심 insight**: Σ(w-b)=0은 long-only Σw=1 mandate에서 자동 만족. **Non-trivial active control은 TE + sector active + 개별 active weight bounds**로 enforce.

---

## 2. Non-Trivial Active-Risk Constraints

도훈 mandate F의 7 constraints 중 active-risk 관련 4건:

### 2.1. F.3 Active-weight neutral (trivial in long-only)

**자동 만족** — long-only universe.

### 2.2. F.4 Tracking Error TE ≤ 0.08 annualized

```
TE_t = std(w_t^T r_t - b_t^T r_t)    over rolling 12m window
TE_annualized = TE_t · sqrt(12)
Constraint: TE_annualized ≤ 0.08    ∀ t
```

**Implementation in DPL_KR_v2**:
- Loss term: `λ_TE · max(0, TE_realized - 0.08)²` hinge penalty
- λ_TE = 1.0 initial (high weight, strict mandate)
- Computation: validation window 12m std(active return)

**Per-sig_date enforcement**:
1. Post top-K + sizing, compute predicted TE using estimated covariance Σ
2. If predicted TE > 0.08, **scale-shrink active weights** toward benchmark:
   ```
   Δw_scaled = Δw · (0.08 / TE_pred)^0.5
   w_final = b + Δw_scaled (with bounds + L1)
   ```

### 2.3. F.6 Sector Active Risk |Σ_{i ∈ s} (w-b)| ≤ 0.10

```
SectorActive_{s,t} = Σ_{i ∈ sector s} (w_{i,t} - b_{i,t})
Constraint: |SectorActive_{s,t}| ≤ 0.10    ∀ s ∈ {10 KOSPI sectors}, ∀ t
```

**Sectors (KOSPI FnGuide ICS Top)**: 
1. Energy, 2. Materials, 3. Industrials, 4. Consumer Discretionary, 5. Consumer Staples, 
6. Health Care, 7. Financials, 8. Information Technology, 9. Communication Services, 10. Utilities

**Implementation**:
- Post-selection iterative check: if any sector |SectorActive| > 0.10, drop highest-weight stock in offending sector, add next-ranked stock from underweight sector, re-check.
- Max 10 iterations.
- If unable to satisfy, **reduce top-K from 20 to 18 + 2 slot for sector-rebalance**.

### 2.4. F.7 ADV Usage ≤ 0.05 per stock per rebalance

```
TradeVol_{i,t} = |w_{i,t} - w_{i,t-1}| · Portfolio_NAV
ADV_{i,t} = mean(daily_traded_value_{i, t-20 : t-1})
ADVUsage_{i,t} = TradeVol_{i,t} / ADV_{i,t}
Constraint: ADVUsage_{i,t} ≤ 0.05    ∀ i, ∀ t
```

**Implementation**: 
- Pre-rebalance: estimate trade size for each stock
- If `ADVUsage > 0.05`, scale-down trade: 
  ```
  scale_factor = 0.05 · ADV / TradeVol_intended
  Δw_actual = Δw_intended · scale_factor
  carryover_residual = (1 - scale_factor) · Δw_intended  # next rebalance
  ```
- Carryover to next sig_date allowed up to 3 sig_dates (90 days), then expire.

---

## 3. Active-Weight Bounds (DPL_KR_v2 Specific)

### 3.1. Individual stock active weight bound

```
-b_{i,t} ≤ Δw_{i,t} ≤ w_max - b_{i,t}
where w_max = 0.20
```

For top_K stock i: `Δw ∈ [-b_i, 0.20 - b_i]`. Since b_i is small (KOSPI 200 cap-weight: largest 0.30, average 0.005), most stocks: `Δw ∈ [-b, ~0.20]`.

For non-top_K stock i: `w = 0` → `Δw = -b_i`. Effectively full active short of benchmark exposure (long-only equivalent of "underweight").

### 3.2. Top_K constraint

```
|{i : w_{i,t} > 0}| ≤ 20    ∀ t
```

Max 20 stocks with positive weight. All others w = 0 (active = -b).

### 3.3. Implementation flow in DPL_KR_v2 (revised)

Post-Model 6 architecture (Set-Sequence + scores):
```
1. scores = NN.forward(x_t)  → R^{N_t}
2. scores_clip = clip(scores, -3.0, 3.0)
3. scores_normalized = (scores_clip - min) / (max - min + 1e-6)
4. top_K_idx = argsort(scores_normalized)[N_t - 20 : N_t]
5. # Score-proportional sizing within top_K
   raw_weights_top_K = softmax_{τ=1.0}(scores_normalized[top_K_idx])  # Σ = 1
6. # Convert to active weight relative to benchmark in top_K
   benchmark_share_top_K = b[top_K_idx]
   benchmark_total_top_K = Σ benchmark_share_top_K
   # Effective benchmark for top_K-only portfolio
   effective_target_top_K = raw_weights_top_K  # absolute weight in 20-stock portfolio
7. # Constraint: w_final must satisfy:
   #   - w_i = effective_target_i for i ∈ top_K
   #   - w_i = 0 for i ∉ top_K
   #   - Σ w_i = 1 (trivially satisfied by softmax)
   w_top_K = effective_target_top_K
8. # Bounds clip [0, 0.20] + L1 renormalize (Dykstra projection)
   w_top_K = clip(w_top_K, 0, 0.20)
   w_top_K = w_top_K / Σ w_top_K
9. # TE check + shrinkage if needed
   TE_pred = predicted_TE(w_top_K, b)
   if TE_pred > 0.08:
       w_top_K = b[top_K_idx] + (w_top_K - b[top_K_idx]) · (0.08 / TE_pred)^0.5
       # re-apply bounds + renormalize
10. # Sector active check + rebalance if violated (max 10 iter)
11. # Partial portfolio adjustment (Axis 4.3)
    w_t = α · w_t^new + (1-α) · w_{t-1}    α = 0.6
12. # ADV usage scale-down if needed
13. # Return w_t (full universe, 0 for non-top_K)
```

---

## 4. Comparison with v1

| Aspect | v1 | v2 (도훈 mandate 통합) |
|---|---|---|
| Σw=1 | ✓ L1 normalize | ✓ retain |
| Long-only | ✓ ReLU | ✓ score-proportional > 0 |
| Max 20 | ✓ Gumbel top-K | ✓ argsort top-K |
| Bounds [0, 0.20] | ✓ clip | ✓ Dykstra clip |
| **Σ(w-b)=0** | implicit (long-only Σw=1) | **explicit constraint (trivial), TE ≤ 0.08 binding** |
| **TE ≤ 0.08** | NOT enforced | **explicit penalty + shrinkage** |
| **Sector active ≤ 0.10** | NOT enforced | **iterative rebalance** |
| **ADV usage ≤ 0.05** | NOT enforced | **scale-down + carryover** |
| Turnover ≤ 6.0 | loss penalty γ=1.0 (weak) | 3-layer mitigation (mandate) |

**Net effect**: v2 constraint set is **strictly tighter**. v1 unbounded TE → KOSPI200 underperform 가능 (실제 v1 IR -1.14 입증). v2 TE ≤ 0.08 enforce → IR floor 통제.

---

## 5. Forge Cycle Implementation Mandate

본 alpha cycle = design only. Forge cycle 의무:

1. Constraint enforcement code: `forge_dpl_v2_constraint_enforcer.py` (Q-Lead confirm 후 작성)
2. Per-sig_date constraint audit log
3. TE / Sector active / ADV usage 모두 forge_run_log_v2.json 기록
4. Constraint violation rate per sig_date ≤ 1% target
5. If violation rate > 5%, **architecture re-design or constraint relaxation**.

---

## 6. Open Questions for Codex Round

1. **TE ≤ 0.08 strict vs adaptive**: 8% annualized는 KR active equity benchmark에서 modest. Codex 권고 시 12%까지 relaxation.
2. **Sector classification source**: FnGuide ICS (10 sectors) vs MSCI GICS (11 sectors). KOSPI 분류는 FnGuide가 더 정합 (KR-specific).
3. **ADV usage 5% strict vs adaptive**: 5%는 retail-scale (5억 KRW NAV). 더 큰 capacity 가정 시 relaxation.
4. **Carryover residual 3 sig_date**: 90 days 후 expire. Codex 권고 시 1 sig_date만 retain.
5. **Iterative rebalance 10 iter**: Convergence guarantee 없음. Bauschke-Combettes Dykstra (1986) strict iteration. Forge cycle convergence audit 의무.

---

**Submitted**: 2026-05-17 alpha-research Step 2.2d. Active-weight neutral + TE + sector active + ADV usage constraints 모두 정합. 도훈 mandate F.3~F.7 완전 통합.
