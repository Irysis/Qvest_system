# DPL_KR_v2 Architecture Spec — Sorted Portfolio Learning + Set-Sequence

**WT-D20260517_002 · alpha-research Step 2.2**
**Date**: 2026-05-17
**Author**: alpha-research agent
**Parent**: literature_review_v2.md (≥3950 words, 14 citations, 5 core papers)

---

## 1. Architecture Overview

DPL_KR_v2 = **5-axis redesigned paradigm** for KR equity Direct Portfolio Learning. 5축 axis_redesign 정합:

```
features X_t (N_t × F=80)
   │
   ▼
[Axis 5.3: m4 regime auxiliary feature inject] → X'_t ∈ R^{N_t × 81}
   │
   ▼
[Axis 2: Set-Sequence permutation-invariant architecture, ~30K params]
   │
   ├── Set Module (DeepSet, permutation-invariant)
   │   c_t = ρ(Σ_i φ(x'^i_t)) ∈ R^{32}        // cross-section summary
   │
   ├── Sequence Module (per-stock LSTM)
   │   h^i_t = LSTM(x'^i_{t-12:t}, c_{t-12:t}) ∈ R^{64}
   │
   ├── [Axis 5.2: Macro Graph Prior GAT (sector-restricted attention)]
   │   h̃^i_t = GAT(h^i_t, neighbors A) ∈ R^{64}
   │
   └── Score Head (Linear MLP)
        s^i_t = MLP(h̃^i_t) ∈ R                // ranking score
   │
   ▼
[Axis 1: Sorted Portfolio Output]
   │
   ├── [Axis 4.1: Decision-induced ranking clipping]
   │   s^i_t ← clip(s^i_t, -3.0, 3.0)
   │
   ├── [Axis 4.2: Min-max rescaling per sig_date]
   │   s^i_t ← (s^i_t - min) / (max - min + 1e-6)
   │
   ├── Top-K extraction (inference time)
   │   top_K = argsort(s^i_t)[N-K:]  K=20
   │
   ├── Score-proportional sizing (DSPO §3.4 inherit)
   │   w_i^new = softmax_τ(s^i) / Σ_{j ∈ top_K} softmax_τ(s^j)   τ=1.0
   │
   ├── Bounds clip [0, 0.20] + L1 renormalize  (constraint projection)
   │
   └── [Axis 4.3: Partial portfolio adjustment]
        w_t = α · w_t^new + (1 - α) · w_{t-1}    α=0.6
```

---

## 2. Module Spec

### 2.1. m4 Regime Inheritance (Axis 5.3)

- Source: STR_1715_AR_on_M4_R05_overlay_PG2 (Session 80 admit, Layer 5)
- Regime feature: r_t ∈ {NORMAL=1.0, CAUTION=0.7, CRISIS=0.3}
- Injection: append as auxiliary feature to **all stocks at sig_date t**
- Resulting input: X_t ∈ R^{N_t × 81} (80 PIT-clean features + 1 regime scalar)

### 2.2. Set Module — DeepSet Aggregator (Axis 2)

Permutation-invariant per Zaheer et al. (2017) DeepSet theorem:
```
c_t = ρ(Σ_i φ(x'^i_t)) where:
  φ: R^81 → R^32  is 2-layer MLP (81 → 64 → 32, ReLU, dropout 0.2)
  ρ: R^32 → R^32  is 2-layer MLP (32 → 32 → 32, ReLU, dropout 0.2)
```

**Params**: φ has (81·64 + 64) + (64·32 + 32) ≈ 7.4K. ρ has (32·32 + 32) × 2 ≈ 2.2K. **Total Set Module ≈ 9.6K**.

Alternative: attention pooling (Lee et al. 2019 Set Transformer) deferred — DeepSet baseline simpler + permutation invariance guaranteed.

### 2.3. Sequence Module — Per-stock LSTM (Axis 2)

```
For each stock i, sequence length T_seq = 12 (12 months lookback):
  h^i_t = LSTM_2layer(input_seq = [x'^i_{t-11:t} || c_{t-11:t}],  // 81 + 32 = 113 dim
                       hidden = 64,
                       dropout = 0.2)
```

**Params**: LSTM 2-layer 64-hidden: 4 · (113 + 64 + 1) · 64 ≈ 14.5K per layer × 2 ≈ 29K... too many.

**Revision**: Reduce hidden to 32:
- LSTM 2-layer 32-hidden: 4 · (113 + 32 + 1) · 32 ≈ 7.4K per layer × 2 ≈ 14.8K
- **Sequence Module ≈ 15K params** ✓

### 2.4. Macro Graph Prior — GAT (Axis 5.2)

DeePM Wood 2026 §4 inherit:
```
Adjacency A_{ij} = 1 if stocks i, j share KOSPI 10-sector (GICS top), else 0
α_{ij} = softmax_{j ∈ N(i)} (LeakyReLU(a^T [W h_i || W h_j]))
h̃_i = σ(Σ_{j ∈ N(i)} α_{ij} · W h_j)
```

- Single GAT layer (1 head)
- W: 32 × 32 = 1024 params + a: 64 params ≈ 1.1K
- **GAT layer ≈ 1.1K params** (sparse-attention efficient)

Sector mapping (KR-specific):
- Sector codes from FnGuide ICS classification (10 sectors)
- adjacency sparse, average degree ~5-10 per sector

### 2.5. Score Head (Axis 1)

```
s^i_t = MLP(h̃^i_t, hidden = [32, 16, 1], ReLU, dropout 0.2)
```

**Params**: 32·16 + 16·1 + 16 + 1 ≈ 0.5K (intentionally minimal — over-fit risk avoidance).

### 2.6. Parameter Budget Summary

| Module | Params | % |
|---|---|---|
| Set Module (DeepSet) | 9.6K | 32% |
| Sequence Module (LSTM 2-layer 32-hidden) | 15K | 50% |
| Macro Graph Prior (GAT 1-layer) | 1.1K | 4% |
| Score Head | 0.5K | 2% |
| Buffer / norm / bias | 4K | 12% |
| **TOTAL** | **~30K** | 100% |

**Compare**: v1 165K (5.5× reduction). Param-to-data ratio 5-7:1 (under-param regime, Lu-Yang-Zhang 2024 double-descent 회피).

---

## 3. Loss Function — 3-Term Composite (Axis 3)

### 3.1. ListMLE Listwise Ranking Loss (Term 1)

Per sig_date t, given predicted scores s_t ∈ R^{N_t} and observed return ranks r_t (descending):

```
L_listwise(t) = -Σ_{i=1}^{N_t} log(exp(s_{r_t(i)}) / Σ_{j=i}^{N_t} exp(s_{r_t(j)}))
```

Plackett-Luce model (Xia et al. 2008 ListMLE consistency proof). Top-down decomposition: rank 1 stock 선택 확률 + 잔여 rank 2 stock 선택 확률... 

**Variance reduction**: per sig_date subsample 200 stocks (top + bottom 100) for stability (DSPO §3.5 sub-sampling 정합).

**Aggregated**: `L_listwise = (1/T) · Σ_t L_listwise(t)`

### 3.2. EVaR Worst-Window Penalty (Term 2)

DeePM Wood 2026 §5 SoftMin EVaR (App. D.2 dual form equivalence):

```
SR_b = (mean(r_p^{w_b}) - r_f) / std(r_p^{w_b})    for each walk-forward window w_b ∈ {1..5}
SoftMin_τ(SR_1, ..., SR_5) = -τ · log(Σ_{b=1}^{5} exp(-SR_b / τ))    τ_softmin = 0.1

L_evar = -SoftMin_τ(SR_1, ..., SR_5)    # negative because we want to MAXIMIZE worst SR
```

τ_softmin = 0.1 → adversarial reweighting Q over 5 windows concentrates on worst 1-2 windows. Wood 2026 §5 ablation 결과 τ=0.1이 stable.

### 3.3. Turnover-Adjusted IR Penalty (Term 3)

Zhang-Wang-Cao 2021 inherit + hinge form:

```
TO_t = Σ_i |w^i_t - w^i_{t-1}|
TO_annualized = (1/T) · Σ_t TO_t · 12      # monthly × 12

L_to_penalty = max(0, TO_annualized - TO_target)    TO_target = 5.0/yr
```

Hinge function: only penalize TO above target (5.0 < 6.0 hard cap → 1.0/yr margin buffer).

### 3.4. Total Loss

```
L_total = L_listwise + κ_evar · L_evar + λ_to · L_to_penalty
```

**Initial hyperparams**:
- κ_evar = 0.3 (EVaR weight)
- λ_to = 0.5 (TO penalty weight)
- τ_softmin = 0.1 (EVaR concentration)

**Ablation grid (Step 2.5 training_protocol)**:
- κ_evar ∈ {0.1, 0.3, 0.5, 1.0}
- λ_to ∈ {0.2, 0.5, 1.0, 2.0}
- τ_softmin ∈ {0.05, 0.1, 0.2}
- 4 × 4 × 3 = 48 configs, 20 random subsample × 5 windows = 100 trials (DSR n_trials 정합)

---

## 4. Constraint Projection (Inference Time)

### 4.1. Top-K Selection

```
top_K_indices = argsort(s_t)[N_t - 20 : N_t]     # top 20 by descending score
```

### 4.2. Score-Proportional Sizing (DSPO §3.4 Inherit)

```
softmax_τ(s_i) = exp(s_i / τ) / Σ_{j ∈ top_K} exp(s_j / τ)    τ_size = 1.0
w_i = softmax_τ(s_i)    for i ∈ top_K
w_i = 0                  for i ∉ top_K
```

τ_size = 1.0 baseline. Alternative: τ_size = 0.5 (more concentrated) or 2.0 (more uniform).

### 4.3. Bounds Clip [0, 0.20] + L1 Renormalize

```
w_i ← clip(w_i, 0.0, 0.20)
w_i ← w_i / Σ_j w_j
```

Iterative Dykstra projection (Bauschke-Combettes 2017 §28.3) max 3 iterations until ||Σw - 1|| < 1e-6 AND max(w) ≤ 0.20 + 1e-6. **v1 4-stage non-idempotency 문제는 v2에서 inference-time projection (training은 ranking loss, weights는 derived) → 학습 안정성과 분리**.

### 4.4. Partial Portfolio Adjustment (Axis 4.3)

```
w_t = α · w_t^new + (1 - α) · w_{t-1}     α = 0.6
```

After blend, **re-apply** bounds clip + L1 renormalize (idempotent fixed point).

---

## 5. Training Protocol Summary (detail in training_protocol_v2.md)

| Aspect | Spec |
|---|---|
| Walk-forward | 5-overlap shift-12m (v1 정합) |
| Train window | 60m |
| Val window | 12m |
| Test window | 12m (W5 = 4m partial 2026-01~04) |
| Optimizer | AdamW lr=1e-4, weight_decay=1e-4 |
| Batch | 12 months (per epoch) |
| Epochs | 50 with early stop patience 5 |
| Dropout | 0.2 throughout |
| Hyperparam grid | 20 random subsample × 5 windows = 100 trials (DSR n_trials=100) |
| Sub-sampling per sig_date | top+bottom 100 stocks (DSPO §3.5) |
| Framework | PyTorch 2.x CUDA (RTX 4080 SUPER 16GB) |

---

## 6. AX-007 Exemption Strategy

### 6.1. v1 학습

v1 AX-007 exemption #4 (ML sizing): architecture claim했으나 Forge에서 HHI ≈ 0.05 (EW collapse) → exemption INVALIDATED.

### 6.2. v2 Strategy

- **Architectural**: sorted portfolio paradigm은 score-proportional sizing이 본질. EW collapse는 expressible failure mode 아님 (모든 score가 numerical zero일 때만 발생 — FP32 noise > 1e-7으로 불가능)
- **Demonstration**: Forge cycle weights.csv에서 HHI > 0.05 demonstrate 의무 (Codex C7 학습)
- **Pre-Forge advisory**: `AX-007 exemption #4 (ML sizing) advisory_pending_forge_demonstration` retain

### 6.3. Verification Criteria

Forge cycle weights.csv 51 sig_dates에 대해:
- mean(HHI) > 0.07 expected (sorted paradigm + score-proportional)
- max(weight per sig_date) > 0.05 + 0.01 = 0.06 expected (NOT uniform 0.05)
- 5/51 sig_dates → HHI = 0.05 ± 0.001 tolerance (numerical edge case 허용)
- 5+/51 sig_dates EW collapse → AX-007 exemption invalidated, WT ABORT

---

## 7. v1 5축 fail 직접 대응 매트릭스

| v1 Axis | v1 fail | v2 redesign | v2 expected mitigation | Academic backbone |
|---|---|---|---|---|
| 1 Output | EW collapse HHI 0.05 51/51 | Sorted portfolio → score-proportional sizing | EW collapse 표현 불가능 | DSPO Zhong 2024 + Zhang 2021 |
| 2 Architecture | 165K params, double-descent risk | Set-Sequence 30K params (1/5) | Param-to-data 33:1 → 5-7:1 | Epstein 2025 + Lu-Yang-Zhang 2024 |
| 3 Loss | -E[r_p] high variance | ListMLE + EVaR + TO 3-term | Ranking gradient bounded, EVaR worst-window | Zhang 2021 + Wood 2026 + Zhang-Wang-Cao 2021 |
| 4 Turnover | TO 17.64 vs 6.0 | 3-layer: clipping + rescaling + partial adjustment | TO target 4-6/yr expected | Wang-Hasuike 2026 KKT |
| 5 Regime | MDD 65%, all-negative 2022-2026 | EVaR + GAT + m4 regime | MDD target ≤ 25%, regime-adaptive | Wood 2026 DeePM |

---

## 8. Forge Cycle Mandate (Step 2.7 Implementation Guide)

다음 의무는 Forge agent에 전달:

1. **PyTorch 2.x + CUDA**: forge_dpl_v2.py 신규 작성 (v1 forge_dpl_v1.py 참조하되 axis 1-5 redesign)
2. **Data**: features_master.parquet (1044 features × 292595 rows) → v2 feature_allowlist_v2.csv 80 features × Usable_Date filter
3. **Training**: 5 walk-forward windows × 20 random hyperparam trials = 100 trials. DSR n_trials=100 strict.
4. **Constraint audit**: per sig_date assert max(w) ≤ 0.20 + 1e-6, Σw = 1 ± 1e-6, count(w > 0) ≤ 20.
5. **EW collapse check**: per sig_date HHI computation → write to forge_run_log. Majority sig_date HHI ≈ 0.05 → ABORT.
6. **TO audit**: per sig_date Σ|Δw| → annualized. Target < 6.0/yr.
7. **Metrics output**: bt_result_summary.json with SR / CAGR / MDD / Sortino / IR. PerformanceAnalytics standard.
8. **Harvey-t 5-spec**: CAPM / FF3 / FF5 / Carhart4 / FF6 정식 regression (v1 placeholder fail 학습 — Newey-West HAC lag=12).
9. **Codex Round 5단계**: forge_package_draft → codex critic → challenge_note → forge_package final.

---

**Submitted**: 2026-05-17 alpha-research Step 2.2 v2 architecture spec. v1 5축 fail 5건 모두 학술 backbone과 정합한 axis redesign으로 대응. ~30K params + 80 features × 1500-2000 stocks panel × 124 sig_dates 학습 ready.
