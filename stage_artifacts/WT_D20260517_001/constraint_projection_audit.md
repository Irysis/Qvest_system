# DPL_KR_v1 Constraint Projection Audit — Step 4.1

**WT-D20260517_001 · optimizer-research Step 4.1**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Lineage**: alpha_package.json §model.constraint_projection / dpl_architecture.md §2.4 / risk_package.json §risk_constraints_for_optimizer
**Codex Round predecessors**: alpha CF-A6-DPL-PROJECTION (HIGH, Codex C9 ACCEPT) + risk CF-R1 (sample deficit) + risk CF-R2 (FMP attribution paradigm-defense)

---

## 0. Scope (Charter §10 boundary)

본 audit은 **constraint projection design 검토만**. Alpha re-interpretation X / Risk Σ re-definition X. DPL은 features → weights 직접 emission paradigm — optimizer-research 역할 = design audit + alternative comparison + risk integration spec.

**Hard-constraints (사용자 mandate, Hook block)**:

| Constraint | Spec | Verification |
|---|---|---|
| `long_only` | `weights ≥ 0` | Stage 1 ReLU |
| `max_names` | `length(w > 0) ≤ 20` | Stage 2 Gumbel softmax top-K |
| `weight_bounds` | `0 ≤ w_i ≤ 0.20` | Stage 3 clamp |
| `sum_weights` | `Σ w_i = 1` | Stage 4 L1 normalize |
| `universe` | `KR_TOP500_LIQ1E8 (2e8 KRW ADV)` | Forge feature build pipeline (alpha CF-A5 + risk C10 obligation) |

---

## 1. Stage-by-stage audit

### 1.1 Stage 1 — Long-only via ReLU

**spec**: `s^1_t = ReLU(s_t) = max(s_t, 0)`

**Audit points**:

#### (a) Dead neuron risk

ReLU dead neuron 발생 시: 일정 ticker score s_t ≤ 0 → ReLU output = 0 → gradient = 0 → weight update X → 영구 zero state.

**Risk magnitude assessment**:
- DPL의 ScoreHead는 단일 Linear(64 → 1) — saturating function X (raw scalar score).
- Cross-section 내 평균 0 (Z_Score_Aligned 후) → 약 50% ticker가 음수 score → ReLU output = 0.
- 50% dead 비율은 정상 (long-only universe 절반은 underweight zero).
- **그러나** dead neuron 문제는 ticker-specific gradient가 영구 zero인 경우 발생. 본 architecture는 ticker-conditional Linear가 아닌 shared score head → ticker-specific dead state 없음 (cross-section 매 sig_date 새로운 forward pass).

**Verdict**: dead neuron risk **LOW** (shared score head 구조 덕분). Per-ticker ReLU saturate는 단일 sig_date 사건이며, 다음 sig_date에서 re-evaluated.

#### (b) Leaky ReLU 대안 평가

대안: `Leaky_ReLU(s) = max(α·s, s)`, α = 0.01.

| Aspect | ReLU (current) | Leaky ReLU |
|---|---|---|
| Long-only 강제 | ✅ HARD (negative → 0) | ❌ negative score → small negative weight |
| Gradient flow | ✅ inside region | ✅ both regions |
| Numerical stability Stage 2 | ✅ log(s) for s ≥ 0 (with 1e-10 floor) | ❌ log(s<0) undefined |
| Bottom 50% information | ❌ lost | ✅ preserved |

**Decision**: ReLU **RETAIN** — long-only hard-constraint은 architecture-level 강제이며, Leaky ReLU는 Stage 2 Gumbel softmax `log(s)` numerical undefined를 유발 (s<0 처리 불가). bottom 50% information은 Stage 1 ReLU dropout이지만, Stage 2의 top-K=20 selection은 어차피 cross-section 상위 1-2%만 사용 → bottom 50% loss는 information-theoretically irrelevant.

**Caveat**: 만약 alpha source가 short-side에서 alpha 발견 시 → 본 architecture 부적합 → Phase 4 long-short extension 필요. 본 cycle은 long-only mandate (hard constraint) 정합 — Phase 3 paradigm shift first-application scope.

---

### 1.2 Stage 2 — Top-K via Gumbel softmax + STE

**spec**: K=20, τ-anneal 1.0 → 0.1 over 50 epochs.

#### (a) τ→0 hard selection 보장?

τ → 0 시 Gumbel softmax → categorical (one-hot). Top-K via repeated sampling without replacement (Kool-van-Hoof-Welling 2019 Stochastic Beams):

$$y^k = \text{softmax}\left(\frac{\log s^1 + g - \sum_{j<k} \log y^{j,\text{prev}}}{\tau}\right)$$

τ=0.1 final 시 distribution sharpness는 **soft but mostly mass on top-K candidates**.

**Hard verification (post-Codex C10 ACCEPT — assumption → Forge measurement obligation)**:
- τ=0.1 with Gumbel noise g ~ Gumbel(0,1) has range approximately [-2, 3].
- 가장 큰 logit과 두 번째 큰 logit gap이 > 2τ = 0.2 일 때 top-1 sharp peak.
- **Forge measurement obligation**: τ=0.1 final + ScoreHead Z-scored cross-section gap distribution + top-K=20 distribution entropy measurement. Codex C10 ACCEPT — "typically > 0.5" 가정 정량 evidence pending Forge cycle.

#### (b) STE (Straight-Through Estimator) 정합

본 spec은 STE를 명시적으로 우회 안 함 (Gumbel softmax reparameterization 자체로 differentiable — Jang-Gu-Poole 2017 §3.2). 그러나 inference time (production deploy)에서 hard top-K 강제 필요:

**Forge cycle MANDATE**:
```python
# Inference (production weights emission)
y_soft = gumbel_softmax(logits, tau=0.1, hard=False)  # train mode
y_hard = gumbel_softmax(logits, tau=0.1, hard=True)   # inference mode, STE
# 또는
top_k_idx = torch.topk(s_1, k=20).indices  # final selection
w = torch.zeros_like(s_1)
w[top_k_idx] = y_soft[top_k_idx]  # use soft values at hard positions
```

PyTorch `torch.nn.functional.gumbel_softmax(logits, tau, hard=True)` API가 STE 자동 처리 (forward: hard one-hot, backward: soft gradient).

**Verdict**: τ=0.1 + `hard=True` inference mode → top-K=20 strict 강제. STE는 PyTorch built-in으로 충분.

#### (c) Numerical floor issue

`log(s^1_i)` requires `s^1_i > 0`. ReLU output 0 → log(0) = -∞.

**Mitigation spec (dpl_architecture.md §2.4)**: replace 0 with 1e-10 floor.

**Verdict (optimizer-research)**: 1e-10 floor adequate. 추가 권고 — Forge cycle에서 `torch.where(s_1 > 1e-10, torch.log(s_1), torch.tensor(-23.03, device=...))` 명시 (log(1e-10) = -23.03) → consistent floor value across batch.

---

### 1.3 Stage 3 — Bounds clip

**spec**: `s^3 = clamp(y, 0, 0.20)`

#### (a) Order: clip → normalize vs normalize → clip

**현재 spec**: clip (Stage 3) → normalize (Stage 4).

**dpl_architecture.md §2.4 NON-IDEMPOTENCY WARNING 분석**:

Scenario A (sum > 1 after clip):
- Pre-Stage-3: w = [0.30, 0.20, 0.15, 0.05, ...] (Σ = 1.30, max 0.30)
- Post-Stage-3 (clip): w = [0.20, 0.20, 0.15, 0.05, ...] (Σ = 1.20, max 0.20 ✓)
- Post-Stage-4 (L1): w / 1.20 = [0.167, 0.167, 0.125, 0.042, ...] (Σ = 1.0, max 0.167 ✓) → **OK**

Scenario B (sum < 1 after clip with cap violation post-normalize):
- Pre-Stage-3: w = [0.18, 0.15, 0.12, ...] (Σ = 0.50, max 0.18)
- Post-Stage-3: same (no clip)
- Post-Stage-4: w / 0.50 = [0.36, 0.30, 0.24, ...] (Σ = 1.0, max 0.36 ❌ violation)

**Root cause**: Σ < 1.0 일 때 L1 multiplier > 1 → cap 위반 가능.

#### (b) Mitigation: iterative projection vs projection-after-normalize

**Spec mitigation (max 3 iter)**: Stage 3-4 반복.

**Iteration 1 fix-point analysis**:
- Iter 1: clip → normalize
- Iter 2: clip 새 max 후 다시 normalize → 또 cap violation 가능 (재증식)
- Iter N: 수렴 시 정상, 비수렴 시 oscillation

**Mathematical convergence guarantee** (Boyle-Dykstra 1986):
- Two convex sets (cap simplex C1 = {w : w ≤ 0.20} and probability simplex C2 = {w : Σw = 1, w ≥ 0}) intersection projection은 Dykstra projection 알고리즘으로 strict convergence 보장.
- 단순 alternate projection (P_C1 ∘ P_C2) NOT guaranteed to converge to intersection (in general); requires Dykstra correction.

**그러나 본 DPL spec의 specific case**:
- C1 ∩ C2 = {w : Σw=1, 0 ≤ w_i ≤ 0.20}
- min(K × max_w, 1) = min(20 × 0.20, 1) = 1.0 ⇒ K=20 × max=0.20 = 1.0 exactly → C1 ∩ C2 non-empty이지만 boundary case.
- 만약 top-K=20 모두 max bound 0.20 시 Σ = 4.0 ≠ 1 — only feasible 시 K=5 (5 × 0.20 = 1.0).
- 본 K=20 × cap 0.20은 K_active 분포에 의존 — 일부 weight < 0.20 (가능) + 일부 = 0.20 (가능).

**Verdict**: iterative max-3-iter는 **실험적 충분조건**이지만 strict guarantee X. Forge cycle violation rate audit 의무.

#### (c) Alternative: projection-after-normalize (Bregman / Dykstra)

**Dykstra-corrected projection (Boyle-Dykstra 1986 §3.2)**:

```
init: w^0 = raw_score, p^0 = 0, q^0 = 0
for k = 0..max_iter:
  y^k = P_simplex(w^k + p^k)       # project onto {Σ=1, w≥0}
  p^{k+1} = w^k + p^k - y^k
  w^{k+1} = P_cap(y^k + q^k)        # project onto {w ≤ 0.20}
  q^{k+1} = y^k + q^k - w^{k+1}
  if ||w^{k+1} - w^k|| < tol: break
return w^{k+1}
```

**Pros**: strict convergence to C1 ∩ C2 projection.
**Cons**: differentiability 복잡 (Jacobian computation each iteration). PyTorch autograd 호환되지만 backward computation 5-10× slower.

**Verdict**: Phase 4 deferred. **Phase 3 v1.0 = iterative max-3-iter retain** with Forge violation rate ≤ 1% audit. v1.0 ≥ 1% rate 시 → v1.1 redesign (Dykstra adoption).

#### (d) Risk_package C2 정합 — gradient explosion

`risk_package.json::condition_number_max_strict = 100`. Σ_stocks LW oracle cond ≤ 100 (Codex C2 ACCEPT strict).

**Question**: cond(Σ) ≤ 100 시 DPL backward pass gradient explosion risk?

**Analysis**:
- DPL gradient는 ScoreHead → ConstraintProjection → loss flow.
- ConstraintProjection 내 L1 normalize ∂w/∂s Jacobian 안정성은 Σs 분모 → s_i 0에 가까울 때 explosion. Stage 4 floor 1e-8 fallback EW (dpl_architecture.md §2.4 Stage 4)으로 처리.
- Σ_stocks는 **loss function variance penalty 외** weight emission에 직접 미관여 — DPL은 features → weights 직접, Σ는 사후 측정 (risk attribution).
- 그러나 만약 future v1.1에서 loss에 `λ · w'Σw` 추가 시 → cond(Σ) high 시 quadratic form gradient sensitivity 증가 → cond 100 strict는 적절.

**Verdict**: **risk_package cond ≤ 100 정합** → DPL Forge cycle backward pass 안정성 확보. cond > 100 시 Gerber+RMT fallback (risk_package C4) → DPL 정합 유지.

**Forge measurement protocol**:
```python
# Per-window gradient norm monitoring
grad_norm_per_step = torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
# Track grad_norm_per_step; if mean(grad_norm) > 10 across last 50 steps → cond(Σ) audit + early stop
```

---

### 1.4 Stage 4 — L1 normalize (Σw=1)

**spec**: `w = s^3 / Σ_i s^3_i`

#### (a) Σw=1 strict vs tolerance

**현재 spec**: Σw=1 strict (tolerance 1e-6).

**alternatives**:

| Tolerance | Pros | Cons |
|---|---|---|
| Strict (1e-6) | Hard-constraint 정합 (Hook block). Forge constraint_enforcer.sh 통과. | Numerical edge cases (Σ ≈ 1.0000001) Hook reject risk |
| [0.95, 1.05] | Soft allowance | Long-only + max_names + bounds 모두 strict일 때 Σ=1 free variable 인정 안 됨 — over-determined system |
| [0.99, 1.01] | Practical | Same as above |

**Decision**: **Strict 1e-6 RETAIN**. 이유:
1. Hook `worktask_constraint_enforcer.sh`는 `|sum(weights) - 1| > 0.001` 시 hard block. 1e-6 floor는 hook 안전 margin.
2. Stage 4 L1 normalize는 deterministic (math 연산) — numerical floor 외 deviation 없음.
3. Long-only + bounds [0, 0.20] + Σw=1은 K=20 hard cap 동시 충족 가능 (feasibility check §2).

#### (b) Floor case (Σs^3 → 0)

dpl_architecture.md §2.4 Stage 4: `Σ s^3 < 1e-8 → fallback EW top-K`.

**Audit verdict**: 적절. EW top-K=20 = 1/20 = 0.05 each (Σ=1.0, max=0.05 ✓). EW fallback은 cap 위반 risk 0%.

**Forge mandate**: fallback EW 발생 시 audit log + violation_count.

---

## 2. Feasibility pre-check

**Hard constraint feasibility 확인**:
- max_names = 20 × max_weight = 0.20 = 4.0
- Σw_target = 1.0
- → **4.0 ≥ 1.0** → feasible (multiple 해 존재).

**Boundary cases**:
- All-equal top-K=20: w_i = 0.05 (i=1..20), Σ=1.0 ✓
- All-max top-5: w_i = 0.20 (i=1..5), Σ=1.0 ✓ (max_names=5 < 20, OK)
- Asymmetric: top-3 at 0.20, top-4 at 0.15, top-13 at 0.0231 → Σ=1.0, max=0.20 ✓

**Infeasible only if**: ML output completely degenerate (all w → 0) → Stage 4 floor → EW fallback 자동 처리.

---

## 3. Verdict summary

| Stage | Component | Verdict | Caveats |
|---|---|---|---|
| 1 | ReLU long-only | ✅ PASS | Dead neuron LOW risk. Leaky ReLU 대안 부적합 (log(s<0) issue) |
| 2 | Gumbel softmax top-K | ✅ PASS | τ=0.1 + hard=True inference 의무. Numerical floor 1e-10 → log(1e-10)=-23.03 const |
| 3 | Bounds clip | ⚠️ PASS_WITH_CAVEAT | Non-idempotent (Σ<1 normalize 시 cap re-violation). Iterative max-3 retain. Violation rate ≤ 1% audit 의무 |
| 4 | L1 normalize | ✅ PASS | Floor 1e-8 → EW fallback 안전 |
| Overall | 4-stage projection | ⚠️ **PASS_WITH_CAVEATS** | (a) **violation_rate = 0 strict per row** Forge mandate (Codex C3 ACCEPT, was ≤ 1%) (b) **Dykstra v1.0 fallback** mandatory if simple iterative fails (Phase 4 deferred 폐기, Codex C3 ACCEPT) (c) inference mode hard=True 의무 |

---

## 4. Forge cycle implementation mandate

본 audit deliverable은 Forge cycle implementation의 reference. Forge agent 의무:

1. **Per-epoch post-projection assert** (dpl_architecture.md §2.4 mitigation 1):
   ```python
   def audit_weights(w_t):
       n_active = (w_t > 1e-6).sum()
       max_w = w_t.max()
       sum_w = w_t.sum()
       min_w = w_t.min()
       violation = (n_active > 20) or (max_w > 0.20 + 1e-6) or \
                   (abs(sum_w - 1.0) > 1e-6) or (min_w < -1e-6)
       return {"violation": violation, "n_active": n_active, "max_w": max_w, "sum_w": sum_w}
   ```

2. **Violation rate aggregate (post-Codex C3 ACCEPT — strict 0 per row)**: per-sig_date violation count → 124 sig_dates 누계 → `violation_rate = violation_sig_dates / 124`.
   - Rate > 0 (any single row violation) → **즉시 Dykstra v1.0 fallback** (Boyle-Dykstra 1986 §3.2)
   - Phase 4 deferred 폐기. Phase 3 v1.0 = simple iterative max-3 + Dykstra fallback (single fallback architecture).
   - Production weights.csv every row strict pass 의무 (Hook block 정합).

3. **Inference mode strict**: production weights.csv emission 시 `gumbel_softmax(..., hard=True)` 의무.

4. **Numerical floor consistency**: `torch.where(s_1 > 1e-10, torch.log(s_1), -23.03)` 명시.

5. **Gradient norm tracking**: `clip_grad_norm_(max_norm=1.0)` + 50-step mean > 10 시 warn.

6. **Σ_stocks cond ≤ 100 audit**: risk_package C2 mandate inherit. Forge per-window Σ_estimators.parquet emit + max(cond) check.

---

## 5. Open architecture decisions (Codex Round disposition)

본 audit이 Codex Critic Round (optimizer stage) 입력:

1. **Iterative max-3 vs Dykstra**: 본 v1.0 = max-3 retain + audit-driven escalation. Codex 권고 시 disposition.
2. **STE explicit vs Gumbel reparameterization implicit**: PyTorch `gumbel_softmax(hard=True)` 내장 STE 사용. Codex 권고 시 disposition.
3. **Σw=1 strict vs tolerance**: strict 1e-6 (Hook block 정합) retain. Codex 권고 시 disposition.
4. **Stage 1 ReLU vs Leaky ReLU**: ReLU retain (log(s<0) issue + long-only hard). Codex 권고 시 disposition.

---

**Submitted**: 2026-05-17 optimizer-research Step 4.1 deliverable. Forge implementation은 본 audit + dpl_architecture.md §2.4 + risk_package §risk_constraints_for_optimizer 통합 reference.
