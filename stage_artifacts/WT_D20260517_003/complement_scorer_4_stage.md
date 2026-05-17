# Complement Scorer 4-Stage Incremental Design

**WT-D20260517_003 · alpha-research Step 3.4**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Parents**: literature_review_dpl_rc.md §3 Brandt 2009 PPP + §5 AC-M 2023 + §6 Wood 2026 + champion_challenger_comparison_framework.md (v2 inherit)
**Mandate**: 4-stage incremental admission (각 stage 대비 baseline incremental gain 입증 필수) + 도훈 mandate G 8-model comparison framework 정합

---

## 0. Protocol 목적

DPL-RC complement scorer `w_comp(t)`를 학습하는 model을 **4 stages incremental design**:
- Stage 1: Linear PPP (Brandt-Santa-Clara-Valkanov 2009) — interpretable baseline
- Stage 2: Elastic Net — regularized linear
- Stage 3: LightGBM — non-linear + feature interaction
- Stage 4: DPL-RC Neural — Set-Sequence ~30K params (v2 architecture inherit)

각 stage는 직전 stage 대비 **incremental gain (SR / MDD / cor)** 입증해야 진행. 입증 실패 시 **prior stage 채택 + stop**.

이는 도훈 mandate G 8-model comparison framework + Avramov-Cheng-Metzker (2023) "ML이 simpler baseline 대비 incremental gain이 작거나 없는 경우 발생" empirical finding 정합.

---

## 1. Stage 1 — Linear PPP (Brandt-Santa-Clara-Valkanov 2009)

### 1.1. Architecture

```
w_comp_{i,t} = (1/N_t) · θ' · x_{i,t}
where:
  x_{i,t} ∈ R^80 = standardized v2 features (80 PIT-clean)
  θ ∈ R^80 = policy parameter (학습 대상)
  N_t = number of stocks at sig_date t
```

**Constraint enforcement** (DPL-RC framework):
```
Step 1: Linear combination → raw scores s_i = θ' · x_i
Step 2: Z-score normalize per sig_date (cross-section): s_i_norm = (s_i - mean) / std
Step 3: Score-proportional sizing top-K=20: w_raw = softmax(s_top20)
Step 4: Bounds clip [0, 0.20] + L1 renormalize Σ=1
```

### 1.2. Loss function

```
L_stage1 = -E[a_t · r_comp_t | bad_1715] 
        + λ_good · max(0, drag_good) 
        + λ_corr · corr(r_comp, r_1715) 
        + λ_to · turnover(w_comp_t, w_comp_t-1) 
        + λ_tail · CVaR_α(r_comp)
```

**Optimization**: Adam gradient descent (lr=0.001), θ ∈ R^80 학습.

Alternative: closed-form (linear regression) — bad-state subset weighted least squares. PPP original (Brandt 2009 §2.3)에서 closed-form 정합.

### 1.3. Hyperparameters

| Param | Default | Grid (Forge) |
|---|---|---|
| `lr` (Adam) | 0.001 | {0.0005, 0.001, 0.005} |
| `lambda_good` | 2.0 | {1.0, 2.0, 4.0} |
| `lambda_corr` | 1.0 | {0.5, 1.0, 2.0} |
| `lambda_to` | 0.5 | {0.1, 0.5, 1.0} |
| `lambda_tail` | 0.3 | {0.1, 0.3, 0.5} |
| `tau` (softmax temperature) | 1.0 | {0.5, 1.0, 2.0} |
| `top_K` | 20 | fixed (constraint) |

Random search 10 trials per walk-forward window.

### 1.4. Param count + sample ratio

- Params: 80 (θ ∈ R^80)
- Train sample per window: 60m × ~1500-2000 stocks = ~90K-120K observations
- Param-to-data ratio: **~1:1000** (extremely sample-safe)

이는 stage 1 baseline의 sample efficiency 강점 — over-fitting 위험 거의 없음.

### 1.5. Interpretability

θ ∈ R^80의 각 component → 해당 feature가 complement sleeve에서 positive (long) / negative (avoid) weight를 가지는지 직접 보여줌. v2 feature_allowlist 80 features (defensive 55%) → θ pattern은 paradigm validation에 직접 사용.

**Expected outcome (priors)**:
- defensive features (low-beta, low-vol, high-quality) → θ_i > 0 (bad-state에서 long)
- aggressive features (momentum, high-beta) → θ_i < 0 (bad-state에서 avoid)
- 만약 패턴이 random / opposite → paradigm validity 의심

---

## 2. Stage 2 — Elastic Net (regularized linear)

### 2.1. Architecture

Stage 1과 동일한 framework + L1 + L2 regularization:
```
w_comp_{i,t} = (1/N_t) · θ' · x_{i,t}
loss: L_stage1 + α · (l1_ratio · ||θ||_1 + (1 - l1_ratio) · ||θ||_2^2)
```

### 2.2. Implementation

sklearn `ElasticNet` 직접 사용:
```python
from sklearn.linear_model import ElasticNet
en = ElasticNet(alpha=α, l1_ratio=l1_ratio, max_iter=1000)
en.fit(X_train, y_train, sample_weight=bad_state_weights)
```

여기서 `bad_state_weights` = conditional loss weighting (bad-state sig_dates에 emphasis).

**Caveat**: ElasticNet은 single-objective MSE loss. DPL-RC 5-term loss를 직접 통합 불가 → **alternative formulation**:
- Predict `y = r_comp_t · 1[bad_state_t]` (bad-state masked target)
- ElasticNet으로 θ 학습 → 학습 후 stage 1 framework에 plug-in
- TO / corr / tail 제약은 **post-hoc constraint enforcement** (학습 후 weight projection)

### 2.3. Hyperparameters

| Param | Default | Grid |
|---|---|---|
| `alpha` (regularization strength) | 0.1 | {0.01, 0.1, 1.0} |
| `l1_ratio` | 0.5 | {0.0 (L2), 0.5, 1.0 (L1)} |
| `max_iter` | 1000 | fixed |
| top_K | 20 | fixed |

### 2.4. Param count + sample ratio

- Params: 80 + sparsity (L1 → 일부 0)
- Effective params: ~30-50 (L1 sparsity 후)
- Sample ratio: ~1:2000-3000 (sample-safe)

### 2.5. Stage 1 vs Stage 2 incremental criterion

Stage 2가 Stage 1 대비 incremental하다면:
- Test SR (OOS aggregate) ≥ Stage 1 + 0.05 (clear improvement)
- OR: Test MDD ≥ Stage 1 + 1pp better (defensive enhancement)
- OR: cor vs 1715 ≤ Stage 1 - 0.05 (better orthogonality)

3 중 1+ 충족 → Stage 2 adopt, Stage 3 진행. 모두 fail → Stage 1 retain, stop.

---

## 3. Stage 3 — LightGBM (non-linear + feature interaction)

### 3.1. Architecture

```python
import lightgbm as lgb

# Stage 3: LightGBM regression
model = lgb.LGBMRegressor(
  objective="regression",
  num_leaves=31,
  max_depth=6,
  learning_rate=0.05,
  num_iterations=500,
  feature_fraction=0.8,
  bagging_fraction=0.8,
  bagging_freq=5,
  lambda_l1=0.1,
  lambda_l2=0.1,
  min_data_in_leaf=10
)

# Conditional loss weighting via sample_weight
sample_weights = bad_state_indicator + good_state_indicator * lambda_good_ratio

model.fit(X_train, y_train, sample_weight=sample_weights, 
          eval_set=[(X_val, y_val)], early_stopping_rounds=50)

# Predict scores → top-K → sizing → constraints
scores = model.predict(X_t)
top_K = argsort(scores)[-20:]
w_raw = softmax(scores[top_K] / tau)
w_clip = clip(w_raw, 0, 0.20)
w_comp = w_clip / sum(w_clip)
```

### 3.2. Loss approximation

LightGBM은 single MSE / objective loss 직접 학습. DPL-RC 5-term loss 통합 방법:

**Method 1: Target engineering**
```
y_target_t = r_comp_t · 1[bad_state_t]                # bad-state masked return
sample_weight_t = bad_state ? 1.0 : lambda_good_inverse  # conditional emphasis
```
LightGBM은 sample-weighted MSE → bad-state subset에 emphasis.

**Method 2: Custom objective**
```python
def dpl_rc_custom_objective(y_true, y_pred):
  # gradient and hessian for DPL-RC composite loss
  ...
  return grad, hess
```
복잡도 ↑, Forge cycle에서 Method 1 우선.

**Method 3: Two-step**
- Step 1: LightGBM으로 score 학습 (MSE / pairwise rank)
- Step 2: post-hoc projection으로 TO / corr / tail 제약 enforce

본 cycle default: **Method 1 (sample-weighted regression)** + **Method 3 post-hoc projection**.

### 3.3. Hyperparameters

| Param | Default | Grid (Forge) |
|---|---|---|
| `num_leaves` | 31 | {15, 31, 63} |
| `max_depth` | 6 | {4, 6, 8} |
| `learning_rate` | 0.05 | {0.01, 0.05, 0.1} |
| `num_iterations` | 500 | {200, 500, 1000} (early stopping) |
| `feature_fraction` | 0.8 | {0.5, 0.8, 1.0} |
| `lambda_l1` | 0.1 | {0.0, 0.1, 1.0} |
| `lambda_l2` | 0.1 | {0.0, 0.1, 1.0} |
| `min_data_in_leaf` | 10 | {5, 10, 20} |

Random search 10 trials per walk-forward window.

### 3.4. Param count + sample ratio

- Effective params: ~3-5K (tree-based, depth 6 × 500 iterations ~ leaves count)
- Sample ratio: ~1:20-30 (manageable, comparable to AC-M 2023 ratios)

### 3.5. Feature importance interpretability

LightGBM `feature_importance` → top-20 features ranking. SHAP values → individual prediction interpretation.

**Validation**: Top features는 defensive cluster (Tail_Risk + Risk_Beta_Vol)에 집중되어야 paradigm validation.

### 3.6. Stage 2 vs Stage 3 incremental criterion

Stage 3 incremental:
- Test SR ≥ Stage 2 + 0.05 (clear improvement)
- OR: Test MDD ≥ Stage 2 + 2pp better (non-linear MDD reduction)
- OR: bad-state subset SR ≥ Stage 2 bad-state SR + 0.10 (conditional alpha gain)

3 중 1+ 충족 → Stage 3 adopt, Stage 4 진행. 모두 fail → Stage 2 retain, stop.

---

## 4. Stage 4 — DPL-RC Neural (Set-Sequence ~30K params, v2 inherit)

### 4.1. Architecture (v2 dpl_kr_v2_architecture.md inherit)

```
features X_t (N_t × F=80) + p_bad context (auxiliary)
   │
   ▼
[Set Module: DeepSet permutation-invariant]
   c_t = ρ(Σ_i φ(x^i_t)) ∈ R^{32}        # cross-section summary
   │
   ▼
[Sequence Module: per-stock LSTM with conditioning]
   h^i_t = LSTM(x^i_{t-12:t} || c_{t-12:t}, hidden=32) ∈ R^{32}
   │
   ▼
[Score Head: Linear MLP with bad-state context]
   s^i_t = MLP(h^i_t || p_bad_t) ∈ R       # score conditioned on p_bad
   │
   ▼
[Post-processing — inference time]
   top_K = argsort(s^i_t)[-20:]
   w_raw = softmax(s_top20 / tau)
   w_clip = clip(w_raw, 0, 0.20)
   w_comp = w_clip / sum(w_clip)
   │
   ▼
[Partial portfolio adjustment]
   w_t = α · w_t^new + (1 - α) · w_{t-1}    # α=0.6 retention
```

### 4.2. Params

(v2 architecture inherit + scoring → ~30K):
- Set module: ~9.6K
- Sequence module: ~14.8K (LSTM 2-layer hidden 32)
- Score head: ~3K (32 + 1 p_bad → 1)
- **Total ~30K**

### 4.3. Loss — DPL-RC 5-term composite

```
L_stage4 = -E[a_t · r_comp_t | bad_1715] 
        + λ_good · max(0, drag_good) 
        + λ_corr · corr(r_comp, r_1715) 
        + λ_to · turnover
        + λ_tail · CVaR_α(r_comp) [or EVaR worst-window from DeePM]
        + β_evar · SoftMin_τ(SR_w1, ..., SR_w5) [DeePM Pillar 3 inherit]
```

**Training**: PyTorch 2.x CUDA + Adam optimizer + early stopping val_IR_net.

### 4.4. Hyperparameters

| Param | Default | Grid (Forge) |
|---|---|---|
| `lr` | 0.001 | {0.0001, 0.001, 0.01} |
| `dropout` | 0.2 | {0.1, 0.2, 0.3} |
| `lambda_good` | 2.0 | {1.0, 2.0, 4.0} |
| `lambda_corr` | 1.0 | {0.5, 1.0, 2.0} |
| `lambda_to` | 0.5 | {0.1, 0.5, 1.0} |
| `lambda_tail` | 0.3 | {0.1, 0.3, 0.5} |
| `beta_evar` (DeePM SoftMin) | 0.3 | {0.0 (no DeePM), 0.3, 0.5} |
| `tau` (SoftMin temperature) | 0.5 | {0.3, 0.5, 1.0} |
| `alpha` (partial portfolio retention) | 0.6 | {0.5, 0.6, 0.8} |
| `tau_softmax` (sizing temperature) | 1.0 | {0.5, 1.0, 2.0} |
| top_K | 20 | fixed |

Random search 10 trials per walk-forward window × 5 windows = 50 trials per stage.

### 4.5. Param count + sample ratio

- Params: ~30K
- Train sample per window: 60m × ~1500-2000 stocks = ~90K-120K observations
- Param-to-data ratio: ~1:3-4 (manageable, double-descent regime entry mitigated by ensemble + early stopping)

v1 33:1 대비 8-10× 감소. v2 dpl_kr_v2_architecture analysis 직접 inherit.

### 4.6. Stage 3 vs Stage 4 incremental criterion

Stage 4 incremental:
- Test SR ≥ Stage 3 + 0.05 (clear)
- OR: Test MDD ≥ Stage 3 + 2pp better
- OR: bad-state SR ≥ Stage 3 bad-state SR + 0.10
- AND: param ratio increase justified (cost-benefit)

만족 + Codex Round PASS → Stage 4 final adopt. 그렇지 않으면 stage 3 retain.

---

## 5. Incremental admission decision protocol

### 5.1. Per-stage admission flow

```
Stage 1 admission:
  - Pre-validation gate: G1 (p_bad classifier) PASS (Step 3.3 mandate)
  - Train Stage 1 × 5 walk-forward windows × 10 hyperparam trials
  - Aggregate test metrics
  - Check: SR / MDD / cor vs baseline (no complement, w_final = w_1715)?
  - Pass condition: blend (1-a_max)·1715 + a_max·complement SR ≥ 1715 SR + 0.02 (margin)
  - If FAIL: paradigm marginal, ABORT cycle. If PASS: proceed Stage 2.

Stage 2 admission (only if Stage 1 PASS):
  - Train Stage 2 × 5 windows × 10 trials
  - Compare Stage 2 vs Stage 1: incremental criterion (Section 2.5)
  - If FAIL: Stage 1 retain final. If PASS: proceed Stage 3.

Stage 3 admission (only if Stage 2 PASS):
  - Train Stage 3 LightGBM × 5 windows × 10 trials
  - Compare Stage 3 vs Stage 2: incremental criterion (Section 3.6)
  - If FAIL: Stage 2 retain final. If PASS: proceed Stage 4.

Stage 4 admission (only if Stage 3 PASS):
  - Train Stage 4 DPL-RC Neural × 5 windows × 10 trials (GPU 의무)
  - Compare Stage 4 vs Stage 3: incremental criterion (Section 4.6)
  - If FAIL: Stage 3 retain final. If PASS: Stage 4 final.
```

### 5.2. Total Forge cycle compute

| Stage | Trials | Compute |
|---|---|---|
| Stage 1 (Linear PPP) | 10 × 5 windows = 50 | CPU 10s × 50 = 8min |
| Stage 2 (Elastic Net) | 10 × 5 windows = 50 | CPU 30s × 50 = 25min |
| Stage 3 (LightGBM) | 10 × 5 windows = 50 | CPU 60s × 50 = 50min |
| Stage 4 (DPL-RC Neural) | 10 × 5 windows = 50 | GPU 5min × 50 = 4h 10min |
| p_bad classifier (Step 3.3) | 10 × 5 windows = 50 | CPU 30s × 50 = 25min |
| **Total** | 250 | ~6h |

**DSR n_trials**: 250 (5 stages × 5 windows × 10 trials = 250, but admission이 incremental하므로 effective n_trials는 각 stage 50). Bailey-LdP DSR deflation에 250 사용 (conservative).

### 5.3. Stop early at Stage N

도훈 mandate: "simpler stage가 충분히 incremental하면 그 stage에서 stop" → DPL-RC paradigm은 사실상 stage 1-2가 더 production-friendly:
- interpretable + sample-safe + Codex audit pass 용이
- 도훈 mandate 정합: "production retain + small complement" framework은 **complex model 불필요**

Stage 4 (Neural) 도달 시: Codex critic이 "stage 3 LightGBM enough, stage 4 marginal" 권고 시 stage 3 final.

---

## 6. PIT compliance audit

### 6.1. Stage 1-2 (Linear)

- θ closed-form: bad-state subset weighted regression. Train data 모두 t-1 lag features + t target return.
- Cross-section normalization (Z-score): per-sig_date, t close까지 observable.
- No forward look.

### 6.2. Stage 3 (LightGBM)

- Tree-based: features at t → target at t+1. Walk-forward purge + embargo (purged_walk_forward_protocol.md).
- Sample weight (bad_state_indicator): t-time observable label (Step 3.2 definition).
- No leakage.

### 6.3. Stage 4 (Neural)

- LSTM sequence: stocks i의 features at t-11:t (12-month lookback). All past data, no forward look.
- p_bad context: p_bad_classifier output at t (t-1 features → t+1 prediction). Strictly PIT.
- Set module summary c_t: aggregated over t-time cross-section, no future.

### 6.4. Walk-forward purge consistency

All 4 stages use same walk-forward windows (purged_walk_forward_protocol.md inherit):
- W1: Train 2016-01 ~ 2020-11 (59m, purged) | Val 2021-01 ~ 2021-11 | Test 2022-01 ~ 2022-12
- W2-W5: 12m shift

Embargo: 1m between train/val and val/test.

---

## 7. Risk mitigation

### 7.1. Over-fitting risk per stage

- Stage 1 / 2 (Linear): low risk (sample ratio 1:1000-2000). No special mitigation.
- Stage 3 (LightGBM): medium risk. early stopping + bagging + L1/L2 regularization.
- Stage 4 (Neural): high risk. dropout + early stopping + ensemble (5 windows ensemble) + small param budget (30K).

### 7.2. Conditional loss subset under-determination

bad-state subset ~25-30 sig_dates × 1500-2000 stocks = ~37K-60K observations per window. **Adequate for 80-features regression**. Stage 4 Neural with 30K params는 sample ratio borderline.

Mitigation: **full sample training** (124 sig_dates × all stocks) + conditional loss weighting (NOT subset training). 코덱스 핵심 수정 정합.

### 7.3. Stage 4 GPU compute

Forge cycle compute spec confirmed via mandate: GPU 사용 명시 confirm. Stage 4 deferred until Q-Lead explicit confirm (도훈 mandate B.2 정합 — design only이고 코드 작성 X, GPU 코드는 Forge cycle).

---

## 8. ABORT criteria summary

### 8.1. Stage 1 fail → ABORT cycle

Stage 1 PPP가 baseline (no complement) 대비 marginal (SR + 0.02 미만) → DPL-RC paradigm 자체 marginal value → ABORT.

### 8.2. p_bad classifier G1 fail → already HARD ABORT (Step 3.3)

Stage 1-4 모두 시작 안 함.

### 8.3. Incremental admission fail → prior stage final

Stage N+1이 Stage N 대비 incremental fail → Stage N final (paradigm valid, complexity escalation 부재).

---

## 9. Forge cycle artifacts

각 stage trained model + metrics:

```
stage_artifacts/WT_D20260517_003/
├── stage1_ppp_models.pkl
├── stage1_ppp_predictions.parquet
├── stage1_ppp_metrics.json
├── stage2_elasticnet_models.pkl
├── stage2_elasticnet_predictions.parquet
├── stage2_elasticnet_metrics.json
├── stage3_lightgbm_models.pkl
├── stage3_lightgbm_predictions.parquet
├── stage3_lightgbm_metrics.json
├── stage4_dpl_rc_neural_models.pt (PyTorch)
├── stage4_dpl_rc_neural_predictions.parquet
├── stage4_dpl_rc_neural_metrics.json
├── incremental_admission_decisions.json
└── final_complement_scorer_choice.json
```

---

## 10. Submission summary

**Submitted**: 2026-05-17 alpha-research Step 3.4 complement_scorer_4_stage.md. 4-stage incremental design (Linear PPP → Elastic Net → LightGBM → DPL-RC Neural) + per-stage hyperparam grids + incremental admission criteria + PIT compliance + ABORT criteria + Forge cycle artifacts.

**Critical mandate**: Stage 4 Neural은 GPU 의무 + 도훈 명시 confirm 후 Forge cycle 진행. design only.

**다음 step**: 3.5 conditional_loss_7axis_admission.md
