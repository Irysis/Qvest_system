# DPL_KR_v1 Architecture Specification

**WT-D20260517_001 · alpha-research Step 2.2**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Lineage**: literature_review.md §4 / request.json §model
**Forge implementation 의무**: 본 spec의 정확한 구현 (PyTorch 2.x CUDA)

---

## 0. Architecture Overview

```
                    INPUT                              OUTPUT
features (N × F=1044)  ──[FeatureEmbed]──[Transformer]──[ScoreHead]──[ConstraintProjection]──> weights (N × 1)
                                                                              │
                                                                              ▼
                                                                 Net-Sharpe Utility Loss
                                                                              │
                                                            Backprop ──> gradient ──> param update
```

- **Single function**: f_θ : R^{N × F} → Δ^{N-1}_{top-K, bounded}
- **Output space**: simplex restricted to top-K active weights with [0, w_max] bounds
- **Loss**: portfolio-level utility (Net Sharpe + cost + CVaR penalty)
- **Training**: end-to-end backprop (Adam optimizer)

---

## 1. Input Specification

### 1.1. Feature matrix per sig_date

- **Source**: `stage_artifacts/WT_D20260514_008/features_master.parquet` (long format: sig_date × Ticker × 1047 features + 3 meta)
- **Effective feature count**: 1044 (request.json claim; actual master 1050 cols incl 3 meta; screening 955 KEEP + 58 VARIANT + 8 zero-var + 26 high-miss). 본 cycle은 **955 KEEP only**로 시작 (Forge cycle에서 58 VARIANT는 별도 추가 ablation).
- **Per sig_date matrix**: X_t ∈ R^{N_t × F}, N_t ≈ 1500~2000 (after liquidity LIQ ≥ 2e8 KRW + admin/halt filter).
- **Sector / industry metadata**: Sector_Lv2 (1 col, 65 dummy 인코딩 in `secdum_*` columns).

### 1.2. Preprocessing (per sig_date, PIT-safe)

1. **Filter**: liquidity LIQ_20d ≥ 2e8 KRW, AdminStock=0, TradingHalt=0, UnfaithfulDisc=0
2. **Missing imputation**: cross-section median per feature per sig_date (NA fill, not lookahead — same sig_date only)
3. **Winsorization**: per feature per sig_date, [1st pct, 99th pct] (3std-equivalent)
4. **Normalization**: cross-section Z-score per feature per sig_date (Z_Score_Aligned C13 정합)
5. **Output**: X_t^proc ∈ R^{N_t × 1044}

**PIT compliance**: 모든 preprocessing이 sig_date 내 cross-section. inter-sig-date statistics 사용 금지 (C1 위반).

### 1.3. Target (training signal)

- **t+1 return** (realized return from sig_date_t to sig_date_{t+1}, ~30 days).
- **PIT**: forward-looking but **training-time only** (Lockbox window 외 정상). Test-time evaluation에서는 walk-forward로 봉인.
- **Cost-adjusted**: r_{t+1}^net = r_{t+1}^gross - 0.0015 × |w_t - w_{t-1}| (per asset).

---

## 2. Module Architecture

### 2.1. FeatureEmbed Layer

- **Input**: X_t^proc ∈ R^{N_t × 1044}
- **Operation**: Linear(1044 → 64) + LayerNorm + Dropout(0.3)
- **Output**: H_t^0 ∈ R^{N_t × 64}
- **Parameter count**: 1044 × 64 + 64 = 66,880 (Linear) + 128 (LayerNorm γ + β) ≈ 67K params
- **Rationale**: 1044 raw features를 64-dim dense representation으로 압축. F → d 축소가 Transformer attention complexity (O(N²d))의 d를 제어 (large d ⇒ memory blow).

### 2.2. Transformer Encoder Block

**Architecture** (request.json: heads=2, dim=64, n_layers=2, max_seq=300):

```
H^0 ──> [SelfAttn (h=2)] ──> [LayerNorm + Residual] ──> [FFN (64→256→64)] ──> [LayerNorm + Residual] ──> H^1
H^1 ──> [SelfAttn (h=2)] ──> [LayerNorm + Residual] ──> [FFN (64→256→64)] ──> [LayerNorm + Residual] ──> H^2
```

- **SelfAttn**: 2 heads × 32-dim. Q/K/V Linear (64 → 64 × 3). Output Linear (64 → 64).
- **FFN**: Linear(64 → 256) + GELU + Dropout(0.3) + Linear(256 → 64).
- **LayerNorm + Residual**: standard pre-LN form (more stable than post-LN).

**Cross-section vs Temporal attention** (CRITICAL design choice):

- **Option A (cross-section attention)**: per sig_date, attention 풀 = N_t stocks. Computation O(N_t² × d) = O((2000)² × 64) ≈ 256M ops per sig_date per layer per epoch ≈ 51G ops per epoch × 50 epochs = 2.5T ops per walk-forward window. **Memory**: 2000 × 2000 × 4 bytes (FP32) = 16 MB attention matrix → batch 가능.
- **Option B (temporal attention max_seq=300)**: per ticker, attention 풀 = T (sig_date history). 그러나 본 cycle은 cross-section primary mode이므로 **Option A 채택**.

본 spec **Option A (cross-section attention)** 채택. max_seq=300은 future temporal-aware extension용 placeholder (현 v1.0 unused).

**Parameter count**:
- Per block: Q+K+V Linear 64×64×3 + Out Linear 64×64 + FFN (64×256 + 256×64) = 12,288 + 4,096 + 16,384 + 16,384 = ~49K
- 2 blocks: ~98K params

### 2.3. ScoreHead Layer

- **Input**: H^2 ∈ R^{N_t × 64}
- **Operation**: Linear(64 → 1) — single scalar score per stock
- **Output**: s_t ∈ R^{N_t × 1}
- **Parameter count**: 64 + 1 = 65 params
- **Rationale**: cross-section ranking — s_t는 z-score-like cross-sectional score, 다음 단계 projection의 input.

### 2.4. ConstraintProjection (4-stage)

**Stage 1 — Long-only (ReLU)**:
- s^1_t = ReLU(s_t) = max(s_t, 0)
- 해석: negative score는 zero weight 후보. Risk Agent / Optimizer Agent가 추후 short-side 검토.

**Stage 2 — Top-K via Gumbel softmax τ-anneal**:
- **τ schedule**: linear anneal 1.0 → 0.1 over 50 epochs. Initial τ=1.0 (soft / exploration), final τ=0.1 (hard / exploitation).
- **Gumbel softmax** (Jang-Gu-Poole 2017 ICLR):
  ```
  g_i ~ -log(-log(U_i)), U_i ~ Uniform(0,1)  (Gumbel noise)
  y_i = exp((log(s^1_i) + g_i) / τ) / Σ_j exp((log(s^1_j) + g_j) / τ)
  ```
- **Top-K selection** (K=20): differentiable approximation via repeated Gumbel-softmax sampling without replacement (Kool-van-Hoof-Welling 2019 ICML "Stochastic Beams"):
  ```
  for k = 1..K:
    y^k = softmax((s + g - sum_prev_log_y) / τ)
    mask = (top1(y^k))
    sum_prev_log_y += -inf * mask  (exclude selected)
  ```
- **Output**: y_t ∈ R^{N_t × 1}, with K=20 entries non-zero (soft when τ→0).
- **Numerical stability**: log(s^1_i) requires s^1_i > 0 — Stage 1 ReLU output ≥ 0. log(0) → -inf 처리: replace 0 with 1e-10 floor.

**Stage 3 — Bounds clip**:
- s^3_t,i = clip(y_t,i, 0, 0.20)
- **PyTorch implementation**: `torch.clamp(y_t, min=0.0, max=0.20)`. Gradient는 inside-bounds region에서만 흐름 (STE — Straight-Through Estimator 우회 안 함, 자연 gradient masking).

**Stage 4 — L1 normalize (Σw = 1)**:
- w_t = s^3_t / Σ_i s^3_t,i
- **Critical numerical issue**: Σ s^3_t,i = 0 (e.g., all clipped to zero due to very small Gumbel-softmax outputs) → division by zero. **Floor mechanism**: if Σ s^3 < 1e-8 → fallback EW top-K.

**NON-IDEMPOTENCY WARNING** (literature_review §4.4 R3):

4-stage sequence는 Stage 4 (L1 normalize) 후 Stage 3 (bounds) 위반 가능:
```
Example: w_pre = [0.30, 0.20, 0.15, 0.05, ...]  (after Stage 1-2-3 with K=20)
         Σ = 0.30 + 0.20 + 0.15 + 0.05 + ... = 1.30
         w_post = w_pre / 1.30 = [0.231, 0.154, 0.115, 0.038, ...]  → OK (bounds satisfied)
```

But:
```
Example: w_pre after Stage 1-2 = [0.50, 0.30, ...] (Gumbel softmax soft)
         Stage 3 clip → [0.20, 0.20, ...]  (clipped)
         Stage 4 L1 → [0.20/0.70 × 0.20 ≈ 0.057, ...]  (sum was 0.70, < 1.0)
         → after normalize, max weight = 0.057. Bound NOT violated, but max bound not utilized.

OR (worse):
Example: w_pre after Stage 1-2 = [0.18, 0.15, 0.12, ...] (already < 0.20, sum < 1.0)
         Stage 3 clip → same (no clip)
         Stage 4 L1 → re-scale by 1/Σ. If Σ=0.50 → multiply by 2.0 → [0.36, 0.30, 0.24, ...] → bound VIOLATION 발생
```

**Mitigation (FORGE MANDATE)**:
1. **Post-projection audit per epoch**: `assert torch.all(w_t <= 0.20 + 1e-6) and torch.all(w_t >= 0) and abs(w_t.sum() - 1.0) < 1e-6`. Violation > 0 시 batch abort + log.
2. **Iterative projection**: Stage 3-4 반복 적용 (max 3 iter). 수렴 시 break. (단순 fix-point iteration; 수학적 수렴 보장은 Dykstra projection — Boyle-Dykstra 1986, deferred to Phase 4).
3. **Sinkhorn alternative**: full feasibility 보장 시 Sinkhorn-Knopp + bounded simplex projection (Bauschke-Combettes 2017 Section 28.3) — deferred.

본 v1.0 spec은 **iterative projection (max 3 iter)** 채택. Forge cycle에서 violation count audit + violation rate > 1% 시 v1.1 architecture 재설계.

### 2.5. Total parameter count

- FeatureEmbed: 67K
- Transformer 2 blocks: 98K
- ScoreHead: 65
- ConstraintProjection: 0 (no trainable params)
- **Total: ~165K params**

매우 작은 model (vs Wei-Dai-Lin E2EAI 1M+ params). Sample efficiency 우선 — 148 sig_dates × ~2000 stocks ≈ 300K observation으로 over-parametrize 회피. **Param/data ratio ≈ 1/2 — 충분히 conservative**.

### 2.6. Total memory footprint estimate

- Params (FP32): 165K × 4 bytes = 660 KB
- Adam state (m, v per param FP32): 2 × 660 KB = 1.3 MB
- Activation per sig_date (FP32): 2000 × 64 (Embed) + 2000 × 64 × 4 (Transformer) + 2000 × 1 (Score) + ~3K (projection) ≈ 0.5 MB
- Attention matrix (FP32): 2000 × 2000 × 4 bytes × 2 heads × 2 layers = 64 MB
- **Total per batch (1 sig_date)**: ~70 MB
- **RTX 4080 SUPER 16 GB**: 200+ sig_dates batch 가능 (memory-bound 아님)
- **Bottleneck**: compute (attention FLOPS, not memory)

---

## 3. Loss Function

### 3.1. Net-Sharpe utility loss

```
loss(w, r_{t+1}) = -E[r_p,t+1] + γ_cost · TO_penalty + λ_cvar · CVaR_penalty
```

**Component 1 — Negative expected portfolio return**:
- `r_p,t+1 = Σ_i w_i × r_i,t+1`
- E[r_p] approximated by sample mean over training batch (1 batch = 1 sig_date in single-batch mode, or T sig_dates in multi-batch).
- **CRITICAL**: Sharpe ratio annualized로 변환할 때 분모 σ_p가 필요. 본 cycle은 **per-batch -E[r_p] loss + 별도 cumulative Sharpe 추적**. Sharpe loss 자체 (-E[r_p] / σ_p)는 vanishing variance 시 numerical instability — 본 cycle은 -E[r_p] + variance penalty hybrid.

**Component 2 — Turnover penalty (Net cost)**:
- `TO = Σ_i |w_i,t - w_i,t-1|`
- Cost: 15bps one-way = 0.0015 = c
- Penalty: `γ_cost × TO × c`
- **γ_cost ∈ {0.5, 1.0, 2.0}** grid sweep (training_protocol.md).
- **PIT note**: w_{t-1} accessed at t — fully within sig_date_t-1 information set.

**Component 3 — CVaR_5% penalty (tail risk)**:
- `CVaR_5% = E[r_p | r_p ≤ q_5]` where q_5 = 5th percentile of {r_p,τ}_{τ in training history}
- **Implementation**: in-batch, computed over batch returns (B = batch_size_months × 1 returns per sig_date). Note: per-stock return correlation structure NOT modeled — Risk Agent's domain.
- Penalty: `-λ_cvar × CVaR_5%` (CVaR is negative, multiplying by -1 makes it positive penalty)
- **λ_cvar ∈ {0.25, 0.5, 1.0}** grid sweep.

### 3.2. Total loss

```
L_total = -mean(r_p) + γ_cost · 0.0015 · mean(TO) - λ_cvar · CVaR_5%
       = -mean_t( Σ_i w_i,t × r_i,t+1 ) 
         + γ_cost · 0.0015 · mean_t( Σ_i |w_i,t - w_i,t-1| ) 
         - λ_cvar · (1/0.05) × mean( r_p | r_p ≤ q_5 )
```

**Initial setting (request.json default)**:
- γ_cost = 1.0
- λ_cvar = 0.5

### 3.3. Gradient flow

- ∂L/∂w gradient는 ScoreHead (s_t) → Transformer → FeatureEmbed로 backprop.
- ConstraintProjection 내 Gumbel softmax는 **reparameterization**으로 differentiable (Jang-Gu-Poole 2017 §3.2).
- Clip (Stage 3)은 inside-bounds region에서만 gradient — outside-bounds region gradient = 0 (자연 gradient masking, STE 우회 불요).
- L1 normalize (Stage 4)는 Σ에 의존 — `∂w/∂s` Jacobian이 N×N dense이지만 sparse top-K로 sparse 효율 가능.

---

## 4. Training Algorithm

### 4.1. Optimizer

- **Algorithm**: Adam (Kingma-Ba 2015)
- **lr ∈ {1e-4, 5e-5, 1e-5}** grid sweep (request.json default 1e-4)
- **β1=0.9, β2=0.999, eps=1e-8** (default)
- **L2 weight decay**: 1e-4 (request.json)

### 4.2. Batch construction

- **1 batch = B sig_dates** (B = batch_size_months from request.json, default 12)
- **Sampling**: chronological (NO shuffling within training window — important: walk-forward integrity)
- **Multiple batches per epoch**: |train_window| / B = 60/12 = 5 batches per epoch
- **Total updates per training window**: 5 batches × 50 epochs = 250 gradient updates

### 4.3. Epoch logic

```
for epoch in 1..max_epochs:
  for batch in train_window_batches:
    1. Forward: features → ... → weights
    2. Compute loss: L_total
    3. Backprop: ∂L/∂params
    4. Adam step
  Compute val_window loss (no gradient)
  Early stop: if val_loss doesn't improve for 5 epochs (patience), stop
  τ-anneal: τ = max(0.1, 1.0 - 0.9 × epoch/max_epochs)
```

### 4.4. Early stopping

- **Patience**: 5 epochs (request.json)
- **Metric**: val_window loss
- **Restore best weights**: track best val_loss, restore params from that epoch

### 4.5. Total training time estimate

- 5 batches × 50 epochs × ~2000 attention FLOPS × 50 × 50 ≈ 5 × 10⁹ FLOPS per walk-forward window
- RTX 4080 SUPER 31 TFLOPS FP32 → ~3 seconds compute + ~30 minutes I/O / Python overhead
- **5 walk-forward windows × 30 minutes = 2.5 hours** (estimate, GPU-bound 아닌 I/O-bound on parquet read)

---

## 5. Hyperparameter Grid

| Hyperparam | Grid values | Default | Rationale |
|---|---|---|---|
| lr | 1e-4, 5e-5, 1e-5 | 1e-4 | Adam standard range |
| dropout | 0.2, 0.3, 0.4 | 0.3 | Sample-bias prone — high dropout |
| γ_cost | 0.5, 1.0, 2.0 | 1.0 | Wang-Hasuike 2026 §5 range |
| λ_cvar | 0.25, 0.5, 1.0 | 0.5 | Tail penalty sensitivity |
| τ_anneal_min | 0.05, 0.1, 0.2 | 0.1 | Numerical stability vs hard top-K |

**Total grid size**: 3 × 3 × 3 × 3 × 3 = **243 combinations**. **Cost-aware reduction**: random search 20 trials per walk-forward window (Bergstra-Bengio 2012). Total 20 × 5 = **100 GPU minutes per WT cycle**.

**Method shopping log mandate** (R2-C v6.1 alpha init prompt): Stage 1 hyperparameter search는 single architecture choice이므로 method_shopping_log.candidates_tried ≤ 5 hard cap 의무. **본 v1.0은 single architecture (Transformer-lite) + hyperparam grid → method_shopping_log.candidates_tried = 1 (architecture-level) — hard cap 정합**.

---

## 6. Output Specification

### 6.1. Per sig_date output

- **w_t ∈ R^{N_t × 1}**: portfolio weights (long-only, top-K=20, bounds [0, 0.20], Σw=1)
- **Alpha vector ∝ w_t** (for cor measurement vs STR_1715)
- **Confidence vector**: derived from y_t (Stage 2 output) magnitude — sharper Gumbel-softmax peak = higher confidence

### 6.2. alpha_scores.parquet schema

```
sig_date    | Ticker  | alpha_score   | confidence | w_dpl
date32[day] | string  | double        | double     | double
```

- **alpha_score**: ScoreHead output s_t (post-ReLU). Z-scored within sig_date.
- **w_dpl**: final 4-stage projection output (top-K=20 long-only weights).
- **confidence**: Stage 2 Gumbel softmax max-peak value, scaled [0, 1].

### 6.3. ic_history.parquet schema

```
sig_date    | rank_ic  | icir_5y_trailing | n_stocks
date32[day] | double   | double           | int
```

- **rank_ic**: Spearman corr(alpha_score_t, r_t+1) cross-sectional per sig_date.
- **icir_5y_trailing**: rolling 60-month IC mean / IC std.
- **n_stocks**: cross-section size at sig_date.

---

## 7. Forge Implementation Mandate

본 spec은 alpha-research deliverable. **실제 training은 Forge agent 책임** (request.json `agent_lineage.forge`):

1. Forge가 PyTorch 2.x 코드 작성 (`forge_dpl_v1.py` 또는 R-Python bridge).
2. PIT C1~C15 strict — features_master.parquet의 모든 feature는 sig_date 시점에 known.
3. Walk-forward 5 windows (Option B per literature_review §5 권고 — Forge agent 정합 의무).
4. Per-window train/val/test split + early stop + restore best.
5. Cost-inclusive loss (γ_cost · 0.0015 · TO).
6. **Post-projection audit** (constraint violation count 출력 의무).
7. Output: `alpha_scores.parquet` + `ic_history.parquet` + `bt_result.rds` (Backtest Contract v1.0 10-component).

---

## 8. Open architecture decisions (Codex Round disposition)

1. **Stage 2 differentiable top-K choice**: Gumbel softmax τ-anneal (본 spec) vs SoftSort (Prillo-Eisenschlos 2020) vs Sinkhorn (Mena et al. 2018) vs Sparsemax (Martins-Astudillo 2016). **본 v1.0 = Gumbel softmax**. Codex가 alternative 권고 시 disposition.
2. **Non-idempotent projection**: iterative max-3-iter (본 v1.0) vs full Dykstra (Boyle-Dykstra 1986) vs Bregman (Bauschke-Combettes 2017). **본 v1.0 = iterative max-3, audit-driven**. Codex가 strict guarantee 권고 시 disposition.
3. **Attention scope**: cross-section (본 spec) vs temporal vs hybrid. **본 v1.0 = cross-section only**. Cross-section information sharing 강조.
4. **Single architecture vs ensemble**: DSL 2025 paper는 ensemble을 핵심 contribution으로 명시. 본 v1.0 = single architecture (Phase 3 첫 application). Ensemble은 Forge cycle ablation.

---

**Submitted**: 2026-05-17 alpha-research Step 2.2 deliverable. PyTorch 2.x 정확한 구현은 Forge agent 책임. 본 spec의 architecture choice (4-stage projection + Transformer-lite + Adam + Net-Sharpe loss)가 Forge implementation의 reference.
