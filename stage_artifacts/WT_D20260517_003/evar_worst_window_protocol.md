# EVaR Worst-Window Protocol — DPL-RC Tail Risk Design

**WT-D20260517_003 · risk-research Step 5.4**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: alpha_package conditional_loss_7axis_admission.md §7.4 (CVaR α=0.05 ↔ EVaR Step 4 Neural)
**Backbone**: Wood-Roberts-Zohren (2026 arxiv:2601.05975) DeePM SoftMin EVaR + Ahmadi-Javid (2012) Entropic Value at Risk
**Purpose**: λ_tail loss term backbone validation + Stage 4 DPL-RC Neural EVaR variant design

---

## 0. Background — Why EVaR for DPL-RC

### 0.1. CVaR (alpha cycle default) vs EVaR (this protocol)

Alpha cycle conditional_loss_7axis_admission.md §1.1 loss:
```
L(θ) = ... + λ_tail · CVaR_α(r_comp)
```
- CVaR_α (Conditional Value-at-Risk, Rockafellar-Uryasev 2002): mean of worst α-quantile returns
- α = 0.05 default → bottom 5% returns 평균
- Stage 1-3 (Linear / EN / LightGBM) 에서 표준 사용

Stage 4 (DPL-RC Neural) 에서 **EVaR worst-window** explicit variant 권고:

### 0.2. EVaR mathematical definition

```
EVaR_α(X) = inf_z>0 (1/z) · log(E[exp(z · (-X))] / α)
       = entropic upper bound of CVaR_α
       
Properties:
- EVaR_α(X) ≥ CVaR_α(X) (always tighter upper bound)
- Coherent risk measure (Artzner et al. 1999)
- Strictly convex in α (CVaR not strict)
- Closed under maximization with smooth surrogate (Wood 2026 SoftMin EVaR)
```

→ **EVaR 의 worst-window 변형** = sliding window 최악 손실 시점에 explicit penalty.

### 0.3. Worst-window 정의

```
worst_window_EVaR(window_size=k):
  For each rolling window [t, t+k]:
    window_loss = sum(r_comp_t to r_comp_t+k)
  
  worst_k_loss = min_window window_loss
  EVaR_α(worst_window_distribution)
```

- k = 1 → single-period worst (= traditional CVaR)
- k = 3 → 3-month sustained worst (more conservative, captures persistence)
- k = 6 → 6-month worst (drawdown 인식)

---

## 1. DeePM Wood 2026 SoftMin EVaR

### 1.1. Smooth approximation (Wood et al. 2026 Pillar 3)

Hard min over window losses is non-differentiable. SoftMin variant:
```
SoftMin_β(losses) = -1/β · log(Σ_w exp(-β · loss_w))

As β → ∞, SoftMin → min
At β = finite, SoftMin smooth + differentiable (gradient-based training)
```

→ NN training 에서 backprop 가능. λ_tail loss term 에 explicit penalty.

### 1.2. SoftMin EVaR for DPL-RC Stage 4

```
L_tail_neural = λ_tail · SoftMin_β EVaR_α(r_comp,t-k+1:t+1 across rolling windows)
where:
  α ∈ {0.1, 0.2}  (worst 10% or 20% of windows)
  k ∈ {1, 3, 6}  (window size)
  β = 10-100 (smoothing parameter)
```

**Hyperparameter grid for Forge cycle Stage 4**:
- α: {0.1, 0.2}
- k: {1, 3, 6}
- β: {10, 50, 100}
- → 18 EVaR variant combinations
- Pareto frontier search: SR vs worst-window EVaR

---

## 2. α-grid rationale (worst-window quantile)

### 2.1. Why α ∈ (0.1, 0.2) for EVaR

alpha cycle CVaR α = 0.05 (worst 5%). 본 EVaR worst-window 에서는 더 넓은 α:
- α = 0.05: 24 sig_dates × 0.05 = 1.2 obs → single-window noise, unstable
- **α = 0.10**: 12 obs → moderate, robust EVaR estimate
- **α = 0.20**: 25 obs → conservative, wide enough sample

124 sig_dates × 0.10 = 12.4 obs / α=0.20 → 25 obs → bootstrap CI feasible.

### 2.2. Comparison: CVaR vs EVaR at same α

```
At α = 0.05 (24 sig_dates × 0.05 ≈ 1.2 obs):
  CVaR_5 = mean of worst ~1 obs → unstable (single outlier dominates)
  EVaR_5 = entropic upper bound → less unstable but high penalty

At α = 0.10:
  CVaR_10 = mean of worst ~12 obs → moderate stable
  EVaR_10 = entropic bound, smoother gradient

At α = 0.20:
  CVaR_20 = mean of worst ~25 obs → most stable
  EVaR_20 = wide quantile, less conservative penalty
```

→ **α = 0.10 for primary, α = 0.20 for diagnostic**.

---

## 3. EVaR computation protocol

### 3.1. Empirical EVaR (sample-based)

```r
empirical_evar = function(losses, alpha) {
  # losses: vector of period losses (negative returns)
  z_grid = exp(seq(log(0.1), log(100), length=200))   # search z>0
  
  evar_candidates = sapply(z_grid, function(z) {
    (1/z) * log(mean(exp(z * losses)) / alpha)
  })
  
  evar = min(evar_candidates)   # inf z>0
  optimal_z = z_grid[which.min(evar_candidates)]
  return(list(evar = evar, z = optimal_z))
}
```

### 3.2. Worst-window EVaR

```r
worst_window_evar = function(returns, alpha = 0.10, window_size = 3) {
  T = length(returns)
  n_windows = T - window_size + 1
  
  window_losses = sapply(1:n_windows, function(t) {
    -sum(returns[t:(t+window_size-1)])  # cumulative loss
  })
  
  evar_result = empirical_evar(window_losses, alpha)
  return(evar_result)
}
```

### 3.3. SoftMin EVaR (Stage 4 Neural)

```python
# PyTorch differentiable EVaR
def softmin_evar_neural(returns, alpha=0.10, window_size=3, beta=50, z=1.0):
    """
    returns: torch tensor of returns time series
    
    Returns differentiable EVaR estimate for backprop.
    """
    losses = torch.stack([-(returns[t:t+window_size].sum())  
                          for t in range(len(returns) - window_size + 1)])
    
    # SoftMin instead of hard min
    softmin_loss = -1.0/beta * torch.logsumexp(-beta * losses, dim=0)
    
    # EVaR with optimization over z (or fixed z)
    evar = (1/z) * torch.log(torch.exp(z * softmin_loss) / alpha)
    
    return evar
```

→ Forge cycle Stage 4 의무 implementation.

---

## 4. λ_tail value and grid

### 4.1. λ_tail = 0.3 (initial) rationale

CVaR_5 typically -3% to -8% monthly for KR equity strategies.
- λ_tail · CVaR contribution: 0.3 · (-0.05) = -0.015 (loss minimization → +0.015 penalty)
- Relative to alpha primary term (E[r_comp | bad]): ~0.02 monthly → 75% relative penalty
- **Moderate** — risk aware but not dominating

### 4.2. EVaR vs CVaR magnitude

EVaR_α typically 1.5-2.5x CVaR_α at same α:
- λ_tail (CVaR) = 0.3 → equivalent λ_tail (EVaR) ~ 0.15-0.20 (smaller because EVaR larger)
- **Stage 4 Neural λ_tail (EVaR) = 0.15** initial recommendation
- Grid: {0.05, 0.15, 0.30}

### 4.3. Forge cycle grid search

```
λ_tail × tail_metric grid:
  Stage 1-3 (CVaR α=0.05): λ_tail ∈ {0.1, 0.3, 0.5}
  Stage 4 (EVaR worst-window α=0.10 k=3): λ_tail ∈ {0.05, 0.15, 0.30}
  
→ Pareto frontier (alpha primary vs tail penalty) per stage
```

---

## 5. Tail risk infrastructure (existing leverage)

### 5.1. tail_risk_engine.R inheritance

`02_Infrastructure/portfolio/tail_risk_engine.R` (438 LoC) provides:
- EVT (Extreme Value Theory) GPD fit (POT 80/90/95%)
- Cornish-Fisher VaR adjustment (skew/kurt)
- CDaR (Conditional Drawdown at Risk)
- Hill α estimator for tail decay

**Risk-side opportunity**:
- GPD tail fit on r_comp losses → semi-parametric EVaR estimate (Pfaff Ch 7 FRM)
- Tail decay α comparison: 1715 tail vs complement tail
- CDaR_blend vs CDaR_1715 → drawdown-based tail measure (CVaR alternative)

**Forge cycle 의무**: tail_risk_engine.R 호출 → EVaR / GPD / CF-VaR / CDaR 4-way tail diagnostic.

### 5.2. FRM Pfaff Ch 7 EVT alternative

GPD (Generalized Pareto Distribution) fit on exceedances:
```
For losses L > threshold u:
  P(L - u > x | L > u) ≈ GPD(ξ, σ_u)
  
  ξ (tail index): tail thickness — KR equity typical ξ ≈ 0.2-0.4 (heavy tail)
  σ_u: scale parameter
  
  EVaR_α (GPD-based) = u + (σ_u/ξ) · ((α/p_exceed)^(-ξ) - 1)
```

→ Semi-parametric EVaR, robust to small sample tails.

**Comparison protocol** (Forge cycle):
- Empirical EVaR (sample-based, Step 3.1) vs GPD EVaR (parametric, Step 5.2)
- Convergence check: if both estimates within 20% → robust
- Divergence → small-sample concern, GPD prior

---

## 6. EVaR integration with admission criteria

### 6.1. EVaR 는 admission axis 직접 X

7-axis admission 의 어느 axis 와도 EVaR direct mapping X:
- Axis 1 (SR), Axis 2 (MDD), Axis 3 (good_drag), Axis 4 (bad_improve), Axis 5 (TO), Axis 6 (cor), Axis 7 (p_bad AUC)
- EVaR worst-window = **loss term internal** (training objective), NOT admission gate

### 6.2. EVaR 의 risk-side admission interaction

EVaR 의 영향은 다음 axis 에 indirect:
- **Axis 2 (MDD)**: worst-window EVaR penalty → 강한 drawdown 회피 → MDD 개선 효과
- **Axis 4 (bad_state_improvement)**: tail-aware training → bad-state outlier hedge → bad_state SR 안정

### 6.3. EVaR diagnostic reporting

```json
{
  "evar_diagnostics_forge_cycle": {
    "empirical_evar_alpha_010_k_1": "Forge measurement",
    "empirical_evar_alpha_010_k_3": "Forge measurement",
    "empirical_evar_alpha_020_k_3": "Forge measurement",
    "softmin_evar_neural_alpha_010_k_3_beta_50": "Forge measurement (Stage 4 only)",
    "gpd_evar_alpha_010_k_3": "Forge measurement",
    "evar_vs_cvar_ratio": "validation 1.5-2.5x expected",
    "evar_1715_vs_evar_comp_relative": "Forge measurement"
  }
}
```

---

## 7. PIT compliance audit

### 7.1. C1 (full-sample 통계 금지)

EVaR estimation 은 historical losses 만 사용 (forward look 없음).
- Empirical EVaR: past returns
- GPD EVaR: past exceedances over threshold
- SoftMin EVaR (Stage 4 Neural): training window의 returns
- **All compliant** at design level

Forge cycle 의무: walk-forward purged window 내에서만 EVaR 계산 → OOS validation.

### 7.2. C9 / C14

Returns 사용은 t-1 close based → no future use.

---

## 8. Codex Round audit points (예상 challenge)

1. **C-EV1: "EVaR 는 admission axis 직접 X — paradigm value 명확 X"**
   - 정당화: EVaR = loss term internal (training objective). Direct admission impact 없음, 단 indirect (Axis 2 MDD + Axis 4 bad_improve) 효과. Wood 2026 DeePM Pillar 3 backbone 정합.

2. **C-EV2: "α=0.10 vs α=0.05 (alpha cycle CVaR) 차이"**
   - 정당화: CVaR (alpha cycle) = α=0.05 (worst 5% 단일 quantile). EVaR worst-window = α=0.10 (12 obs, 더 robust). Each different tail metric purpose.

3. **C-EV3: "GPD EVT 추정은 KR small sample 에서 unstable"**
   - 정당화: 124 sig_dates × tail threshold POT 80% → 25 exceedances. GPD MLE convergence stable at n≥20. Pfaff Ch 7 FRM precedent.

4. **C-EV4: "SoftMin EVaR β hyperparameter 추가 search burden"**
   - 정당화: β grid 3 values (10, 50, 100) → 18 EVaR variant combinations per Stage 4. Forge cycle Stage 4 GPU 단계 의무. Stage 1-3 은 traditional CVaR only.

5. **C-EV5: "λ_tail (EVaR) = 0.15 의 sensitivity 부재"**
   - 정당화: Forge cycle 의무 grid {0.05, 0.15, 0.30} × walk-forward 5 windows → Pareto frontier selection.

---

## 9. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.4 evar_worst_window_protocol.md.

**Key deliverables**:
- EVaR (Ahmadi-Javid 2012) + SoftMin variant (Wood 2026 DeePM Pillar 3) backbone
- α ∈ (0.1, 0.2) for EVaR worst-window (alpha cycle CVaR α=0.05 보다 robust)
- Window size k ∈ {1, 3, 6} grid (single → sustained)
- β smoothing for SoftMin (Stage 4 Neural backprop)
- λ_tail (EVaR) = 0.15 initial, grid {0.05, 0.15, 0.30}
- Empirical / GPD / SoftMin 3 estimators (Forge cycle 의무)
- tail_risk_engine.R existing infra leverage (Pfaff Ch 7 FRM)
- EVaR = loss term (training) NOT admission gate (indirect impact Axis 2 + Axis 4)

**Forge cycle handoff**:
- Stage 1-3: λ_tail · CVaR_5 (alpha cycle inherit)
- Stage 4 Neural: λ_tail · SoftMin EVaR worst-window α=0.10 k=3 β=50
- 18 EVaR variant Pareto Stage 4 only
- empirical vs GPD 2 estimator convergence check

**다음 step**: 5.5 crowding_score_dpl_rc.md (Acadian 2026 per-factor crowding)
