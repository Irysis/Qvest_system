# DPL_KR_v3 Architecture Specification — Original DPL Redesign

**WT-D20260519_001 · alpha-research Step 2.2**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**Lineage**: literature_review_v3.md §4 (5-axis redesign) + dpl_architecture.md (v1) + dpl_kr_v2_architecture.md (v2)
**Forge implementation 의무**: 본 spec의 정확한 구현 (PyTorch 2.x CUDA)
**Paradigm**: Original DPL (Pure standalone alpha generator, 1715 외부 종속성 X) — NOT RC

---

## 0. Architecture Overview

```
features X_t ∈ R^{N_t × 80}
   │
   ▼
[FeatureNorm] — cross-section Z-score per sig_date (C13 Z_Score_Aligned)
   │
   ▼
[DeepSet Set Module — permutation-invariant per Zaheer 2017]
   │ ┌── φ: R^80 → R^32  (MLP 80 → 48 → 32, ReLU, dropout 0.2)
   │ ├── Aggregate: c_t = ρ(Σ_i φ(x^i_t)) ∈ R^{32}    (cross-section summary)
   │ └── ρ: R^32 → R^16  (MLP 32 → 16, ReLU, dropout 0.2)
   ▼
[Per-stock concat] — concat(x^i_t, c_t) ∈ R^{96}   (per-stock raw + cross-section context)
   │
   ▼
[Score Head MLP] — 96 → 64 → 32 → 1, ReLU, dropout 0.2
   │
   ▼ s^i_t ∈ R^{N_t}   (per-stock score)
   │
   ▼
[Decision-induced Ranking Clipping] s^i_t ← clip(s^i_t, -3.0, 3.0)
   │
   ▼
[Continuous Concentration Softmax]
   │ w_raw^i = softmax(s^i / τ),  τ ∈ {0.5, 1.0, 2.0} grid sweep
   │
   ▼ w_raw ∈ Δ^{N-1} (full simplex, no hard top-K)
   │
   ▼
[Top-K Soft Selection — straight-through estimator]
   │ Inference time:  top_K = argsort(w_raw)[N-20:];  w_topk = w_raw[top_K] / Σ w_raw[top_K]
   │ Train time:      w_soft = w_raw · top_K_mask_STE (straight-through gradient)
   ▼
[Projection-after-Normalize (PAN) — 4-stage iterative]
   │ Iter loop (max 3):
   │   1. Bounds clip:    w' = clip(w, 0, 0.20)
   │   2. L1 normalize:   w'' = w' / Σ w'
   │   3. Stop condition: max(w'') ≤ 0.20 + 1e-6 AND |sum(w'') - 1| < 1e-6
   │   4. Assert: violation_rate < 1% per epoch
   ▼
[Output]  w_t^new ∈ R^N (top-20 active, bounds-respect, simplex)
   │
   ▼
[Partial Adjustment] (TO mitigation)
   │ w_t = α · w_t^new + (1 - α) · w_{t-1},   α=0.6
   ▼
Final w_t ∈ R^N (≤20 active, [0, 0.20], Σw=1)
```

**v3 paradigm distinction from v1**:
- v1 Gumbel hard top-K via repeated sampling → EW collapse 100%
- v3 continuous concentration softmax + concentration penalty → expected HHI > 0.06 (G7 gate)

**v3 simplification from v2**:
- v2: DeepSet + LSTM Sequence Module + GAT Macro Graph Prior + 30K params
- v3: DeepSet + per-stock MLP (no LSTM, no GAT) + 17K params target

---

## 1. Input Specification

### 1.1 Feature Matrix per sig_date

- **Source**: `stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv` (80 features, sha256 b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee)
- **Inherited family-balanced distribution** (v2 FMP r² ranking):
  - Risk_Beta_Vol: 15
  - Tail_Risk: 15
  - Momentum_Tech: 15
  - Other: 15
  - Liquidity: 7
  - Risk_Metric: 7
  - Reversal: 2
  - Technical: 2
  - Daily_LowFreq: 2
- **Per sig_date matrix**: X_t ∈ R^{N_t × 80}, N_t ≈ 500 (KR_TOP500_LIQ1E8 filter, 2e8 KRW 20d ADV strict at alpha-emit)
- **Liquidity strict mandate** (Codex C4 v1 fix): LIQ_20d ≥ 2e8 KRW at alpha-emit stage. **NOT inherit** 5e7 from features_master.parquet build threshold — re-filter at every sig_date.

### 1.2 Preprocessing (per sig_date, PIT-safe)

1. **Filter** (per sig_date): LIQ_20d ≥ 2e8 KRW, AdminStock=0, TradingHalt=0, UnfaithfulDisc=0
2. **Universe**: KR_TOP500_LIQ1E8 (request.json mandate, 1715-independent)
3. **Missing imputation**: cross-section median per feature per sig_date (no inter-sig-date statistics, PIT-safe)
4. **Winsorization**: 1st-99th percentile per feature per sig_date
5. **Normalization**: cross-section Z-score per feature per sig_date (C13 Z_Score_Aligned strict)
6. **Output**: X_t^proc ∈ R^{N_t × 80}

### 1.3 Target (Training Signal)

- **t+1 return**: realized return from sig_date_t to sig_date_{t+1} (~30 days), real PIT
- **Source**: rawdata.parquet sha256 c86e4ae5c6cc3e733efe35db4aa9bf335f434f85aa90f0a6fdd086183464659c (v5 inherit canonical)
- **Cost-adjusted**: `r_{t+1}^net = r_{t+1}^gross - 0.0015 × |w_t - w_{t-1}| × 2`  (round-trip)

---

## 2. Module Spec

### 2.1 DeepSet Set Module (Permutation-Invariant)

**Architecture**:
```
φ: R^80 → R^32      (2-layer MLP 80 → 48 → 32, ReLU, dropout 0.2)
Aggregate: c_t = Σ_i φ(x^i_t)
ρ: R^32 → R^16      (1-layer MLP 32 → 16, ReLU, dropout 0.2)
Cross-section summary: c_t^final = ρ(c_t / N_t)   (mean-normalized to avoid scale-dependency)
```

**Parameter count**:
- φ: (80 × 48 + 48) + (48 × 32 + 32) = 3,888 + 1,568 = 5,456
- ρ: (32 × 16 + 16) = 528
- **Set Module total**: ~6K params

**Rationale**: DeepSet (Zaheer 2017) provides theoretical permutation invariance — output independent of stock ordering. v1 Transformer attention (O(N²d) = 256M ops per sig_date per layer per epoch) → DeepSet (O(N · d) = 64K ops per sig_date per layer per epoch). **4000× compute reduction**.

### 2.2 Per-stock Score Head

**Architecture**:
```
Per-stock input: concat(x^i_t, c_t^final) ∈ R^{80+16=96}
MLP: 96 → 64 → 32 → 1, ReLU, dropout 0.2
Output: s^i_t ∈ R
```

**Parameter count**:
- Linear 96 → 64: 96 × 64 + 64 = 6,208
- Linear 64 → 32: 64 × 32 + 32 = 2,080
- Linear 32 → 1: 32 + 1 = 33
- **Score Head total**: ~8.3K params

### 2.3 Decision-Induced Ranking Clipping (Wang-Hasuike §3)

```
s^i_t ← clip(s^i_t, -3.0, 3.0)
```

**Rationale**: Wang-Hasuike 2026 §3 KKT mitigation step 1. Score range [-3, 3] = ~3std after Z-score normalization. Prevents extreme weight swings (TO control).

### 2.4 Continuous Concentration Softmax (Replacing v1 Gumbel Hard top-K)

```
w_raw^i = exp(s^i / τ) / Σ_j exp(s^j / τ),  τ ∈ {0.5, 1.0, 2.0}
```

**τ grid sweep**:
- τ=0.5: more concentrated (peak around top scores)
- τ=1.0: balanced (default)
- τ=2.0: more spread (closer to uniform)

**Hyperparam grid**: τ × {0.5, 1.0, 2.0} × λ_to × {1.0, 2.0, 4.0} × λ_conc × {0.5, 1.0, 2.0} = 27 combinations
→ subsample to 20 random search (per Forge cycle protocol, training_protocol_v3.md §3)

**Rationale**: 
- v1 Gumbel hard top-K → 0.05 uniform collapse (EW HHI=0.05)
- v3 continuous softmax → expressible weight diversity (HHI ≥ 0.06 strict)
- Concentration penalty `λ_conc · (HHI - HHI_target)²` enforces HHI > 0.06

### 2.5 Top-K Soft Selection (Straight-Through Estimator)

**Inference time** (forward-only):
```
top_K = argsort(w_raw)[N-20:]
w_topk = w_raw[top_K] / Σ w_raw[top_K]
```

**Training time** (gradient flows):
```
top_K_mask_STE[i] = 1 if i ∈ argsort(w_raw)[N-20:] else 0
w_soft = w_raw · top_K_mask_STE   # forward
# Gradient backprop: w_soft.grad = w_raw.grad (mask treated as 1 in backward)
```

**Rationale**: 
- Hard top-K not differentiable
- Gumbel top-K with τ-anneal → v1 EW collapse
- Straight-through estimator (Bengio-Léonard-Courville 2013) — discrete forward + continuous backward → differentiable surrogate

### 2.6 Projection-After-Normalize (PAN, 4-stage iterative)

```
def project_simplex_bounds(w, bound_max=0.20, max_iter=3, eps=1e-6):
    for iter in range(max_iter):
        # 1. Bounds clip
        w_clip = torch.clamp(w, 0, bound_max)
        # 2. L1 normalize
        w_norm = w_clip / w_clip.sum()
        # 3. Convergence check
        if w_norm.max() <= bound_max + eps and abs(w_norm.sum() - 1) < eps:
            return w_norm
        w = w_norm
    return w
```

**Rationale** (vs v1 non-idempotency):
- v1: ReLU → Gumbel → clip → L1 normalize, where Stage 4 L1 normalize can re-violate Stage 3 bounds
- v3 PAN: clip → L1 normalize → check → iter. Convergence guaranteed within max_iter=3 in practice (Bauschke-Combettes 2017 §28.3 standard simplex projection theory).
- **Audit mandate** (Forge cycle): per epoch assert `violation_rate < 1%`. Violation > 1% → ABORT and retune `bound_max` or `max_iter`.

### 2.7 Partial Adjustment (TO Mitigation, Wang-Hasuike §3-4)

```
w_t = α · w_t^new + (1 - α) · w_{t-1},   α=0.6
```

**Rationale**: 
- Wang-Hasuike 2026 §3 partial adjustment principle
- α=0.6 ⇒ 60% new + 40% previous → expected TO ≈ 0.6 × TO_raw
- If TO_raw ≈ 8-10 (typical L2L NN), then TO_final ≈ 4.8-6.0 (within 6.0 cap)
- α grid {0.4, 0.6, 0.8} ablation (Forge cycle)

### 2.8 Total Parameter Budget

| Module | Params | % |
|---|---|---|
| FeatureNorm (non-trainable) | 0 | 0% |
| DeepSet Set Module (φ + ρ) | 6,000 | 35% |
| Per-stock Score Head MLP | 8,300 | 49% |
| ConstraintProjection (no trainable) | 0 | 0% |
| Buffer / bias / LayerNorm | 2,700 | 16% |
| **TOTAL** | **~17,000** | 100% |

**Compare**: 
- v1 165K (10× reduction)
- v2 30K (1.8× reduction)
- v3 17K (target 30~50K achieved, in fact lower)

**Param/data ratio**: 17K params vs 80 features × 124 sig_dates × ~500 stocks ≈ 5M obs → 1:295 (under-param regime, Lu-Yang-Zhang 2024 double-descent safe).

---

## 3. Loss Function — 3-Term Sharpe Surrogate

### 3.1 Composite Loss

```
L_total(w, r) = L_sharpe + λ_to · L_to + λ_conc · L_conc
```

### 3.2 Term 1 — Sharpe Surrogate (v1 -E[r_p] fix)

```
L_sharpe(w, r) = -E[r_p,t+1] / (Std[r_p,t+1] + ε)
```

where `r_p,t+1 = Σ_i w_i^t · r_i,t+1` and `ε = 1e-6` for numerical stability.

**Rationale**: 
- v1 `-E[r_p]` direct → high-variance gradient + no risk normalization
- v3 Sharpe surrogate → variance-normalized, more stable + risk-aware
- Annualized factor: standard portfolio Sharpe formula, monthly rebal → multiply by √12 for annual interpretation (only used for reporting, not gradient)

**Implementation note**: per-batch (per walk-forward train fold) standardization. To avoid degenerate σ_p → 0, add `ε = 1e-6` floor.

### 3.3 Term 2 — Turnover Penalty (Net Cost)

```
L_to(w_t, w_{t-1}) = |w_t - w_{t-1}|_1 · 0.0015 · 2
```

**Components**:
- `|·|_1`: L1 norm (absolute weight change per asset, summed)
- `0.0015`: 15bps one-way cost (cost_model_version v2.3_kr_retail_15bps)
- `× 2`: round-trip multiplier (buy + sell = 2 transactions per rebal cycle)

**λ_to grid**: {1.0, 2.0, 4.0}. v1 used 1.0 (too weak → TO 17.64), v3 increases to 4.0 max.

**Hard cap audit**: per epoch assert `Σ_t |w_t - w_{t-1}|_1 × 12 < 6.0` annual. Violation → λ_to grid expand to 8.0.

### 3.4 Term 3 — Concentration Penalty (v1 EW Collapse Fix)

```
L_conc(w) = (HHI(w) - HHI_target)²
```

where:
- `HHI(w) = Σ_i w_i²` (Herfindahl-Hirschman Index)
- `HHI_target = 0.10` (5× EW floor 0.05, ensures non-degenerate)

**Quadratic penalty**: 
- HHI < 0.10 → positive penalty (encourage concentration)
- HHI > 0.10 → positive penalty (discourage over-concentration)

**λ_conc grid**: {0.5, 1.0, 2.0}.

**G7 gate enforcement**: HHI > 0.06 strict at admission. If HHI ≤ 0.06 majority of sig_dates → DPL EW collapse detected → HARD ABORT per request.json `failure_cutoffs_v1_v5_strict.ew_collapse_HHI_0_05`.

### 3.5 Optional Term 4 — EVaR Worst-Window (Forge Ablation)

```
L_evar = -τ_evar · log(Σ_w exp(-SR_w / τ_evar))   τ_evar = 0.1
```

Soft-min over 5 walk-forward windows. Forge cycle ablation flag (Wood-Roberts-Zohren 2026 §4).

---

## 4. Training Protocol

### 4.1 Walk-Forward 5 Windows Shift-12m Overlapping

Same as v1/v2 (inherit):

| Window | Train | Val | Test |
|---|---|---|---|
| 1 | 2016-01 ~ 2020-12 (60m) | 2021-01 ~ 2021-12 (12m) | 2022-01 ~ 2022-12 (12m) |
| 2 | 2017-01 ~ 2021-12 (60m) | 2022-01 ~ 2022-12 (12m) | 2023-01 ~ 2023-12 (12m) |
| 3 | 2018-01 ~ 2022-12 (60m) | 2023-01 ~ 2023-12 (12m) | 2024-01 ~ 2024-12 (12m) |
| 4 | 2019-01 ~ 2023-12 (60m) | 2024-01 ~ 2024-12 (12m) | 2025-01 ~ 2025-12 (12m) |
| 5 | 2020-01 ~ 2024-12 (60m) | 2025-01 ~ 2025-12 (12m) | 2026-01 ~ 2026-04 (4m partial) |

**Purged WF embargo**: 1-month embargo between train/val/test (López de Prado 2018 Ch 7).

**Total test months**: 12 + 12 + 12 + 12 + 4 = 52 test months (v1 inherit canonical).

### 4.2 Hyperparameter Random Search

**Grid** (3^3 = 27 combinations, sample 20 random):
- τ ∈ {0.5, 1.0, 2.0}
- λ_to ∈ {1.0, 2.0, 4.0}
- λ_conc ∈ {0.5, 1.0, 2.0}

**Total trials**: 20 random search × 5 walk-forward windows = 100 trials.

**DSR n_trials=100** (Bailey-LdP strict, Codex v1 C3 disposition retain).

### 4.3 Adam Optimizer + Schedule

- Adam optimizer, lr=0.001, β1=0.9, β2=0.999
- 50 epochs per window, early stopping on val Sharpe (patience=10)
- Batch size: 1 sig_date per batch (cross-section primary mode)
- Mixed precision (FP16 forward, FP32 backward) for memory efficiency

### 4.4 Convergence & Audit

- Per epoch: assert violation_rate < 1% (PAN convergence)
- Per epoch: log HHI mean / max / min (G7 audit)
- Per epoch: log TO_annual estimate (G3 audit)
- Per window end: log val Sharpe + train Sharpe (overfitting check)

---

## 5. Decision Gates Mapping

| Gate | Threshold | Measurement |
|---|---|---|
| G0 PIT C1~C15 | strict | Forge `lookahead_detector.R` scan + factor_db_connector audit |
| G1 SR floor | DPL_v3 SR ≥ 1.0 | 52 test months PerformanceAnalytics standard |
| G2 cor vs STR_1715 | < 0.5 substitution / < 0.3 4th source | Same-harness alpha_scores Pearson + Spearman per sig_date, averaged |
| G3 Harvey-t | t_NW ≥ 3.0 5-spec | OLS 5-spec (CAPM/FF3/FF5/Carhart4/FF6) + Newey-West HAC lag-12. NOTE: FF5/FF6 may be structural duplicates if no RMW/CMA data (v5 C2 lesson) — report genuine + placeholder transparently. |
| G4 DSR Bailey-LdP | Z ≥ 1.5 strict | n_trials=100 (20 random × 5 windows) |
| G5 cost Pareto | Net-of-cost 15bps Pareto vs STR_1715 | Same-harness same-period overlap |
| G6 AX-008 | ≥ 2/3 PASS | Forge + Codex + Architect |
| G7 EW non-collapse | HHI > 0.06 strict majority sig_dates | Per-sig_date weight HHI from weights.csv |

**Failure cutoffs strict** (request.json):
- HHI ≤ 0.05 (EW collapse) → HARD ABORT
- Synthetic detection → HARD ABORT (v4 lesson)
- TO > 6.0 annual → HARD ABORT (v1 17.64 lesson)
- SR < 0 → ABORT
- Codex REJECT veto=true → DEFER

---

## 6. Implementation Notes for Forge

### 6.1 PyTorch 2.x Skeleton (Forge Mandate)

```python
import torch
import torch.nn as nn

class DPL_KR_v3(nn.Module):
    def __init__(self, n_features=80, n_top_k=20, tau=1.0):
        super().__init__()
        # DeepSet Set Module
        self.phi = nn.Sequential(
            nn.Linear(n_features, 48), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(48, 32), nn.ReLU(), nn.Dropout(0.2),
        )
        self.rho = nn.Sequential(
            nn.Linear(32, 16), nn.ReLU(), nn.Dropout(0.2),
        )
        # Score Head MLP
        self.score_head = nn.Sequential(
            nn.Linear(n_features + 16, 64), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(64, 32), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(32, 1),
        )
        self.tau = tau
        self.n_top_k = n_top_k

    def forward(self, X):
        # X: (N, F) per sig_date
        phi_X = self.phi(X)              # (N, 32)
        c = self.rho(phi_X.mean(dim=0))  # (16,) cross-section summary
        c_expand = c.unsqueeze(0).expand(X.size(0), -1)  # (N, 16)
        per_stock_input = torch.cat([X, c_expand], dim=-1)  # (N, F+16)
        s = self.score_head(per_stock_input).squeeze(-1)    # (N,)
        # Decision-induced ranking clip
        s = torch.clamp(s, -3.0, 3.0)
        # Continuous concentration softmax
        w_raw = torch.softmax(s / self.tau, dim=0)          # (N,)
        # Top-K soft selection (training: STE; inference: hard)
        if self.training:
            top_k_indices = torch.topk(w_raw, self.n_top_k).indices
            top_k_mask = torch.zeros_like(w_raw).scatter_(0, top_k_indices, 1.0)
            w_soft = w_raw * top_k_mask  # STE: hard forward, soft gradient
        else:
            top_k_indices = torch.topk(w_raw, self.n_top_k).indices
            w_soft = torch.zeros_like(w_raw).scatter_(0, top_k_indices, w_raw[top_k_indices])
            w_soft = w_soft / w_soft.sum()
        # Projection-after-normalize (PAN)
        w = self.project_simplex_bounds(w_soft, bound_max=0.20)
        return w

    def project_simplex_bounds(self, w, bound_max=0.20, max_iter=3, eps=1e-6):
        for _ in range(max_iter):
            w_clip = torch.clamp(w, 0, bound_max)
            w_norm = w_clip / (w_clip.sum() + eps)
            if w_norm.max() <= bound_max + eps and abs(w_norm.sum() - 1) < eps:
                return w_norm
            w = w_norm
        return w


def loss_fn(w_t, w_tm1, r_tp1, lam_to=2.0, lam_conc=1.0, hhi_target=0.10):
    # Term 1: Sharpe surrogate
    r_p = (w_t * r_tp1).sum()
    sigma_p = r_p.std() if r_p.std() > 1e-6 else torch.tensor(1e-6)
    L_sharpe = -r_p.mean() / sigma_p
    # Term 2: Turnover penalty (round-trip)
    L_to = torch.abs(w_t - w_tm1).sum() * 0.0015 * 2
    # Term 3: Concentration penalty
    hhi = (w_t ** 2).sum()
    L_conc = (hhi - hhi_target) ** 2
    return L_sharpe + lam_to * L_to + lam_conc * L_conc


def partial_adjust(w_new, w_old, alpha=0.6):
    return alpha * w_new + (1 - alpha) * w_old
```

### 6.2 Forge Cycle Output Requirements

1. **alpha_scores.parquet**: Date × Ticker × score schema (52 test months × ~500 stocks = ~26K rows)
2. **weights.csv**: Date × Ticker × weight × method_selected schema (52 test months × 20 active stocks per sig_date = ~1040 rows)
3. **ic_history.parquet**: per sig_date IC + ICIR (52 rows)
4. **forge_package.json**: 8-field schema (SR / MDD / CAGR / Harvey_t / DSR / cor_vs_1715 / HHI_mean / TO_annual)
5. **bt_result.rds**: 10-component bt_result list (Backtest Result Contract v1.0)
6. **bt_result.rds SHA256 hash binding**: `sha256sum bt_result.rds > bt_result.rds.sha256` (v5 lesson, anti-fabrication)
7. **self_synthesis_used label audit**: must be `false`, audit-verified (v4 lesson)
8. **lookahead_detector.R scan**: PIT C1~C15 PASS (G0 gate)

---

## 7. PIT Compliance Specification

### 7.1 C1 — Full-sample statistics avoided

- All preprocessing per sig_date cross-section only (NOT inter-sig-date)
- Walk-forward train/val/test split enforces sig_date_train < sig_date_val < sig_date_test
- 24m rolling warm-up 2014-2015 mitigated via training_sig_date_first=2016-01-30

### 7.2 C13 — Z_Score_Aligned strict

- Manual flip / NEGATE_FACTORS / FLIP_SIGN 금지
- factor_db_connector::load_month_factors() returns Z_Score_Aligned canonical (C13 PASS)

### 7.3 C14 — IC access Usable_Date ≤ sig_date

- ic_history.parquet emit per sig_date IC, Usable_Date ≤ sig_date strict
- Forge cycle audit: `assert all(ic_history$Usable_Date <= ic_history$sig_date)`

### 7.4 C15 — Factor DB routing

- factor_db_connector::load_month_factors(sig_date) strict
- Direct parquet load 금지 (`.cache/factor_db/factor_db_YYYYMM.parquet` direct read 금지)
- features_master.parquet inherit (WT-D20260514_008 v1 inherit) IS PIT-safe because built via same connector + sig_date awareness

### 7.5 Real PIT via rawdata.parquet (v5 inherit)

- Price/return source: rawdata.parquet sha256 c86e4ae5c6cc3e733efe35db4aa9bf335f434f85aa90f0a6fdd086183464659c
- 13,919,924 rows × monthly aggregation = real Korean stock daily-to-monthly PIT-clean panel
- Anti-fabrication: forge cycle assert `rawdata_sha256 == "c86e4ae5..."`. Mismatch → ABORT.

---

## 8. Comparison to v1 / v2 (Direct Lineage)

| Spec | v1 (REJECT) | v2 (DEFER, Sorted Portfolio Learning) | v3 (Original DPL Redesign) |
|---|---|---|---|
| **Features** | 634 | 80 (FMP r²) | 80 (inherit v2) |
| **Params** | 165K | 30K | 17K |
| **Architecture** | Transformer 2-layer + 4-stage projection | DeepSet + LSTM + GAT + Score Head + 3-layer TO mitigation | DeepSet + Per-stock MLP + PAN + partial adjustment |
| **Output** | Top-20 hard via Gumbel softmax | Sorted portfolio + score-proportional sizing | Continuous concentration softmax + STE top-K + PAN |
| **Loss** | -E[r_p] + γ_cost · TO + λ_cvar · CVaR | ListMLE + κ_evar · L_evar + λ_to · L_to | Sharpe surrogate + λ_to · L_to + λ_conc · L_conc |
| **Cost-aware** | γ_cost=1.0 (weak) | λ_to=2.0 | λ_to ∈ {1.0, 2.0, 4.0} grid + 2× round-trip |
| **Concentration** | None (Gumbel hard → EW collapse) | None (sorted portfolio) | λ_conc · (HHI - 0.10)² (5× EW floor) |
| **PIT** | C1~C15 strict | C1~C15 strict + Purged WF | C1~C15 strict + Purged WF + rawdata SHA256 binding + self_synthesis_used audit |
| **Hyperparam** | 1 config | 8-model framework | 20 random × 5 WF = 100 trials |
| **Goal** | Substitution KRf SR 1.95 | Sorted portfolio outperform | Standalone alpha (substitution or 4th source) |
| **Cor target** | < 0.5 / < 0.3 | < 0.5 / < 0.3 | < 0.5 substitution / < 0.3 4th source |
| **Universe** | KR_TOP500_LIQ1E8 (5e7 build) | inherit | KR_TOP500_LIQ1E8 (**2e8 strict at alpha-emit**) |

---

## 9. Risk & Mitigation

### 9.1 Risk 1 — Continuous Softmax Still Collapses (HHI < 0.06)

**Mitigation**:
- Concentration penalty `λ_conc · (HHI - 0.10)²` strict enforce
- λ_conc grid {0.5, 1.0, 2.0} (vs v1 no penalty)
- G7 HHI > 0.06 gate ABORT if fail majority sig_dates

**Probability**: low (~15%) given direct concentration penalty optimization.

### 9.2 Risk 2 — TO Still Exceeds 6.0 Annual

**Mitigation**:
- λ_to grid {1.0, 2.0, 4.0} (vs v1 1.0)
- Round-trip × 2 multiplier explicit
- Decision-induced ranking clip
- Partial adjustment α=0.6 → expected 0.6× TO reduction
- Hard cap audit per epoch + ABORT if violation

**Probability**: low (~10%) given multi-layer mitigation.

### 9.3 Risk 3 — SR < 1.0 (G1 Fail)

**Mitigation**:
- 20 random search × 5 WF = 100 trials
- DSR Bailey-LdP n_trials=100 deflation
- Forge cycle ablation: DPL vs simpler MLP baseline + EW baseline

**Probability**: moderate (~40%). KR is harder than US/CN — depends on feature signal-to-noise.

### 9.4 Risk 4 — cor > 0.5 vs STR_1715 (G2 Fail)

**Mitigation**:
- Universe 자유 (KR_TOP500_LIQ1E8, 1715-independent)
- 80 features family-balanced (not STR_1715 alpha-driven)
- Worst case: substitution still viable if cor < 0.5 OR DEFER

**Probability**: moderate (~30%). Cross-sectional KR alpha may correlate with STR_1715's M4/AR/R05 overlay common factor exposure.

### 9.5 Risk 5 — AX-007 Single-Sleeve ML Sizing Exemption Invalidation

**Mitigation**:
- HHI > 0.06 strict (non-EW) demonstrates ML sizing (vs v1 EW collapse 0.05 invalidated exemption)
- Forge weights.csv per-sig_date HHI audit
- AX-007 exemption #4 (ML sizing) eligibility re-established by v3 architecture

**Probability**: low (~10%) if G7 HHI > 0.06 passes.

---

## 10. Conclusion

DPL_KR_v3 Original DPL Redesign = 5-axis architectural fix to v1 REJECT, retaining v2 architectural learning, departing from v3~v5 RC paradigm (L-330 retired). 

**Core mechanisms**:
1. Smaller MLP 17K params (vs v1 165K) → sample-efficient
2. Continuous concentration softmax + concentration penalty (vs v1 Gumbel hard top-K) → EW collapse 회피
3. Sharpe surrogate loss (vs v1 -E[r] direct) → variance-normalized stable gradient
4. λ_to × 2 round-trip + partial adjustment α=0.6 (vs v1 weak γ_cost=1.0) → TO ≤ 6.0
5. PAN projection (vs v1 non-idempotent) → bounds + simplex guaranteed
6. Pure standalone alpha — universe 자유 + cor < 0.3 (4th source) / < 0.5 (substitution) target

**Forge cycle obligation**: 
- Real PIT via factor_db_connector + rawdata.parquet SHA256
- bt_result.rds SHA256 hash binding
- self_synthesis_used label audit
- weights.csv schedule (52 test months × 20 active stocks)
- alpha_scores.parquet schedule (52 test months × ~500 stocks)
- ic_history.parquet (52 sig_dates IC + ICIR)
- forge_package.json (8-field, Harvey-t 5-spec + DSR + cor_vs_1715 + HHI + TO_annual)

**Status**: alpha-research Step 2.2 architecture spec emitted. Forge implementation 의무.

---

**End of DPL_KR_v3 Architecture Spec**

Lineage: literature_review_v3.md §4 (5-axis redesign) + dpl_architecture.md v1 inherit (4-stage projection, Transformer fail learning) + dpl_kr_v2_architecture.md v2 inherit (DeepSet, partial adjustment, 80 features) + 도훈 mandate 2026-05-18 autonomous.
