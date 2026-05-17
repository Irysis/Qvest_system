# Champion vs Challenger Comparison Framework

**WT-D20260517_002 · alpha-research Step 2.2b**
**Date**: 2026-05-17
**Author**: alpha-research agent (도훈 mandate 2026-05-17 22:30 직접 통합)

---

## 1. Paradigm Comparison Framing (도훈 mandate A)

### 1.1. Champion (Conventional 2-stage)

```
X_{i,t}  →  μ̂_{i,t}  →  Optimizer (MVO/CVaR/HRP/etc.)  →  w_{i,t}  →  R^net_{p,t+1}
        prediction              optimization              portfolio        net return
```

**구조**: Prediction model이 expected return / volatility를 estimate → standalone optimizer가 weights 도출.

**대표 prior art**:
- Markowitz (1952) MVO
- Black-Litterman (1992)
- Lopez de Prado (2016) HRP
- ML prediction (Gu-Kelly-Xiu 2020) + downstream MVO

**KR 실무 기준 (현 STR_1715 baseline)**: Z-score factor composite → Score 기반 top-K + bounds + L1 → effectively prediction → simple optimizer (top-K equal-tilt).

### 1.2. Challenger (Direct Active Weight Policy)

```
X_{i,t}  →  Δw_{i,t}  →  w_{i,t} = b_{i,t} + Δw_{i,t}  →  R^net_{p,t+1}
        active weight       active position (benchmark relative)
        직접 학습
```

**구조**: Neural network가 features → **active weight deviation** Δw 직접 학습. 최종 weight = benchmark weight + active weight.

**대표 prior art**:
- Brandt-Santa-Clara-Valkanov (2009) Parametric Portfolio Policy (linear baseline)
- Zhang-Zhang-Roberts-Zohren (2020) Deep Learning for Portfolio Optimization
- You-Zhang (2025) Direct Portfolio Learning
- Wood-Roberts-Zohren (2026) DeePM (50 futures)

**KR 적용**: KOSPI200 benchmark weight b_{i,t} (cap-weight). Active weight Δw_{i,t} 학습 → w_{i,t} = b + Δw. **Active-weight neutral Σ_i Δw = 0** 자동 (도훈 mandate F.3).

### 1.3. v1 → v2 Framework Integration

기존 v2 mandate (sorted portfolio + Set-Sequence + 3-term loss)는 **Challenger family의 한 instance**. 도훈 mandate는 이를 **8-model Champion/Challenger comparison framework**의 한 candidate로 위치시킨다.

본 alpha-research cycle은 **8 모델의 spec design + protocol 정의**만. 실제 학습/비교는 **Forge cycle**.

---

## 2. 8 Comparison Models (도훈 mandate G)

### Model 1: Linear Factor Composite (Baseline Champion)

**Type**: Champion (2-stage trivial). Prediction = factor composite Z-score. Optimizer = top-K + bounds (effectively rank-based).

**Spec**:
```
μ̂_i = Σ_k w_k · Z_k(x_{i,t})    # equal-weight or learned factor weights
top_K = argsort(μ̂)[N-20:]
w_i = (1/20) for i ∈ top_K else 0
clip [0, 0.20] + L1 renormalize
```

**Inheritance**: STR_1715 H1 base architecture. KR實證 SR 1.50-1.65 baseline.

**Hyperparams**: factor weights via cross-validation (or equal-weight).

---

### Model 2: Elastic Net Prediction + Optimizer (Champion)

**Type**: Champion. ElasticNet penalty regression → predict next-month return → MVO optimizer.

**Spec**:
```
μ̂_i = ElasticNet(α=0.5, l1_ratio=0.5).predict(x_{i,t})
Σ̂ = LedoitWolf shrinkage covariance
w = argmax (μ̂^T w - λ · w^T Σ̂ w) s.t. long-only, max 20, [0, 0.20], Σ=1, |w-b|^T 1 = 0
```

**Hyperparams**: α / l1_ratio cross-validated. λ risk-aversion grid.

---

### Model 3: GBM Prediction + Optimizer (Champion)

**Type**: Champion. LightGBM regression → predict next-month return → MVO optimizer.

**Spec**:
```
μ̂_i = LightGBM(num_leaves=31, lr=0.05).predict(x_{i,t})
Σ̂ = LedoitWolf shrinkage
w = MVO same as Model 2 constraints
```

**Hyperparams**: GBM grid (lr / num_leaves / depth / subsample) via purged WF CV.

---

### Model 4: Linear Parametric Portfolio Policy (Challenger Baseline)

**Type**: Challenger. Brandt-Santa-Clara-Valkanov (2009).

**Spec**:
```
Δw_{i,t} = θ^T x_{i,t}    # linear in features, θ ∈ R^F
w_{i,t} = clip(b_{i,t} + Δw_{i,t}, 0, w_max)
Σw=1 renormalize
```

**Loss**: SR maximization on `(w-b)^T r - cost · TO - λ · TE²`.

**θ learned via gradient descent OR closed-form regression**.

---

### Model 5: GBM Direct Active Weight Policy (Challenger)

**Type**: Challenger. LightGBM regression to predict active weight Δw directly.

**Spec**:
```
Δw_{i,t} = LightGBM.predict(x_{i,t}, target=optimal_Δw_post-hoc)
   OR train via gradient descent through differentiable downstream
```

**Caveat**: GBM은 non-differentiable → either pre-compute optimal Δw target (less ideal) OR use surrogate gradient.

---

### Model 6: Neural Direct Active Weight Policy ⭐ CORE (Challenger)

**Type**: Challenger. **본 v2 DPL_KR_v2 핵심 모델**.

**Spec**: 기존 dpl_kr_v2_architecture.md spec 완전 inherit:
- Set-Sequence ~30K params
- ListMLE + EVaR + TO 3-term loss
- 3-layer TO mitigation
- 3-layer regime robustness

**Output revision (도훈 mandate F.3)**: 
- Original spec: scores → sorted top-K → score-proportional sizing (absolute weight)
- **Revised spec**: scores → Δw active weight relative to benchmark `b_{i,t}`
- `w_{i,t} = clip(b_{i,t} + softmax_τ(scores_top_K), 0, 0.20)` + L1 renormalize
- `Σ_i Δw_{i,t} = 0` constraint enforced (active-neutral)

**Note**: top_K선택 후 active weight reallocation은 KOSPI200 ∪ KOSDAQ150 ∩ TOP500_LIQ1E8 universe 내에서, 선택된 20 stocks의 active weight 양음으로 reallocate. Benchmark weight outside top_K는 0 (full active short = -b).

**실제 implementation 보강 필요** (Forge cycle 진입 전 Q-Lead confirm):
- `w_i = b_i + Δw_i` for i ∈ top_K
- `w_i = 0` for i ∉ top_K  → 자동 active = -b_i (full short benchmark exposure)
- Σ_i w_i = 1 자동 (top_K outside는 0, top_K inside는 b + Δw, Σ Δw = -Σ_{outside} b = -(1 - Σ_{inside} b))
- Σ(w - b) = 0 자동 만족 (Σ_inside (b+Δw) + Σ_outside 0 - Σ_all b = Σ_inside Δw - Σ_outside b = -Σ_outside b + Σ_outside b... 사실은 = 0 만 long-only equiv. 정확한 Σ(w-b)=0 enforce 필요).

**Active-neutral constraint enforcement**:
```
After top_K selection:
  Δw_raw_i = softmax_τ(scores_top_K_i) - benchmark_share_top_K
  w_i = b_i + Δw_raw_i
  Adjust: subtract mean(Δw_raw) so Σ Δw = 0
  Re-clip [0, w_max=0.20] + L1 renormalize → re-derive Δw
  Verify Σ(w - b) = 0 ± 1e-4
```

---

### Model 7: Differentiable Optimizer Layer (Challenger Advanced)

**Type**: Challenger. CvxpyLayer (Agrawal et al. 2019) 또는 qpth (Amos-Kolter 2017) differentiable QP layer.

**Spec**:
```
μ̂ = NN.predict(x_{i,t})
Σ̂ = LedoitWolf
w = CvxpyLayer(μ̂, Σ̂, constraints_C-fG)   # differentiable QP optimal w
Loss = SR(w^T r)
∇_NN = autograd through CvxpyLayer
```

**Caveat**: O(N^3) QP per training step → GPU memory + time intensive. KR N=1500-2000 → top-K filter 후 N=20 QP만 differentiate (manageable).

**Hyperparams**: λ risk aversion, NN backbone same as Model 6 (Set-Sequence).

---

### Model 8: Cost-aware Direct Portfolio Learning (Challenger + Explicit Cost)

**Type**: Challenger. Model 6 + explicit cost term in objective.

**Spec**: Model 6 + 도훈 mandate E objective:
```
L_dpl = -E_t [(w_t - b_t)^⊤ r_{t+1} - C(w_t - w_{t-1}) - λ·TE_t² - ρ·Concentration_t]
        where:
          (w_t - b_t)^⊤ r_{t+1}  = active return
          C(Δw_t = w_t - w_{t-1}) = cost · |Δw| · 0.0015  (15bps)
          TE_t² = var(active return) over training window
          Concentration_t = HHI(w) - 1/20 (deviation from EW)
```

**중요**: 기존 v2 ListMLE + EVaR + TO loss는 **3-term composite**, 본 도훈 objective는 **active-return + cost + TE + concentration 4-term**. **두 form 모두 retain**:
- Primary: 도훈 mandate E objective (active-return based)
- Secondary: v2 ListMLE + EVaR + TO (sorted portfolio paradigm)
- Forge cycle에서 두 loss 모두 ablation 가능 (objective는 직접 학습 신호, listwise는 ranking signal — 결합 형태로 시너지 검증)

---

## 3. 12 Mandatory Evaluation Metrics (도훈 mandate H)

모든 8 모델에 대해 다음 12 metric 산출 의무. **gross + net 분리 보고** (도훈 mandate B.7):

| # | Metric | Definition | Target / Threshold |
|---|---|---|---|
| 1 | **CAGR_net** | (1+net_return)^(12/n_months) - 1 | > KOSPI200 CAGR |
| 2 | **IR_net** | active_return / TE | > Champion IR (mandate I.1) |
| 3 | **Sharpe_net** | (mean_net_return - r_f) / std | > 1.0 G1 floor |
| 4 | **MDD** | max drawdown peak-to-trough | ≤ 25% (G8) |
| 5 | **TE** | std(w - b)^T r annualized | ≤ 8% (constraint F.4) |
| 6 | **Turnover** | Σ_t Σ_i |Δw| / T · 12 | ≤ 6.0/yr (G7) |
| 7 | **ADVUsage** | per stock daily trade / 20d ADV | ≤ 5% per stock (constraint F.7) |
| 8 | **FactorAdjustedAlpha** | residual α after FF5/Carhart4 regression | > 0 strictly (mandate I.3) |
| 9 | **SectorActiveRisk** | std(Σ_{i ∈ sector} (w_i - b_i)) | ≤ 10% (constraint F.6) |
| 10 | **HitRatio** | % months active return > 0 | > 50% |
| 11 | **RollingIR_12m** | IR over rolling 12-month windows | min > -0.5 |
| 12 | **RollingDrawdown_12m** | max DD over rolling 12-month | < 30% in any window |

**Gross/Net 분리**: gross = before transaction cost, net = after 15bps. 둘 다 보고.

---

## 4. 6 Rejection Criteria (도훈 mandate I)

DPL_KR_v2 (Model 6) **폐기 / 보류 trigger** (1개라도 해당 시):

| # | Criterion | Quantitative Threshold |
|---|---|---|
| 1 | IR_net_DPL ≤ IR_net_Champion | DPL_IR < max(Model1~3 IR) |
| 2 | MDD_DPL > MDD_Champion AND CAGR insufficient | DPL_MDD > Champion_MDD AND DPL_CAGR < Champion_CAGR + 5pp |
| 3 | FactorAdjustedAlpha_DPL ≤ 0 | FF5/Carhart4 residual α t-stat < 1.96 (5% significance) OR α < 0 |
| 4 | Period/Universe/Sector dependence | If perf in any 12-m subperiod < -1.0 SR OR any single sector > 50% of active risk → REJECT |
| 5 | Risk Exposure 설명력 | If size/liquidity/beta regression R² > 0.7 → ALPHA NOT INDEPENDENT |
| 6 | Explainability 부재 | Risk-driver attribution 불가능 (model interpretability test 실패) → REJECT |

**구체 measurement** (Forge cycle 의무):
- (1) IR comparison: DPL_IR_net per 51-month period vs all 5 Champion models max IR
- (2) DD/CAGR Pareto: 2D dominance check
- (3) FF5 / Carhart4 regression: Newey-West HAC t-stat
- (4) Subperiod test: 2022 / 2023 / 2024 / 2025 / 2026 5 분기-rolling SR + sector active risk decomposition
- (5) Style exposure: regress DPL active return on (Size_Z + LIQ + Beta) → R²
- (6) SHAP value test: top 10 features contribution to weight decisions, must explain ≥ 50% variance

---

## 5. Champion vs Challenger Comparison Protocol

### 5.1. Same-harness rule

**모든 8 모델 동일 조건**:
- Universe: KR_TOP500_LIQ1E8 (2e8 KRW 20d ADV)
- Period: 2022-01 ~ 2026-04 (51 months net test post 5-window walk-forward)
- Cost model: v2.3_kr_retail_15bps (15 bps one-way)
- Benchmark: KOSPI200 total return
- Constraint set: F.1~F.7 7건 동일 적용
- Walk-forward: purged WF + embargo (다음 section)

### 5.2. Pareto Dominance Test

DPL_KR_v2 admit 자격:
- **Substitution**: DPL outperforms BEST Champion on IR_net + MDD + FactorAdjustedAlpha simultaneously (Pareto dominance)
- **4th orthogonal**: DPL + best Champion blend Pareto dominates EITHER alone (positive interaction)
- **Reject**: DPL fails any 6 rejection criteria

### 5.3. Probabilistic admit estimate

8 모델 비교 framework 후 DPL_KR_v2 admit 확률 reassess (v2 5축 redesign + active-neutral + Champion benchmark):

| Outcome | Pre-framework prob | Post-framework prob (도훈 mandate 통합 후) |
|---|---|---|
| G1 SR ≥ 1.0 | 0.55-0.70 | 0.50-0.65 (Champion baseline 강화로 floor 시험 더 strict) |
| Pareto vs Champion BEST | n/a (new) | 0.25-0.40 (real Champion models 8개와 직접 비교 — 어려움) |
| FactorAdjustedAlpha > 0 strict | n/a (new) | 0.30-0.45 (size/liquidity/beta 설명력 차감 후 residual α 입증 필요) |
| Substitution admit | 0.30-0.45 | 0.15-0.25 (Pareto 다중 metric 동시 통과 strict) |
| 4th orthogonal admit | 0.15-0.25 | 0.10-0.20 (blend 시너지 입증 별도 필요) |

**도훈 mandate 통합 후 admit probability**: 0.20-0.30 (5축 redesign + Champion comparison strict 통과 시).

---

## 6. Active-Weight Neutral Constraint 통합 (도훈 mandate F.3)

### 6.1. Constraint formula

```
Σ_i (w_{i,t} - b_{i,t}) = 0    ∀ t
```

즉 `Σ w = Σ b = 1` (benchmark KOSPI200 cap-weight Σ = 1 정의). Long-only universe에서 자동 만족 (이미 Σw = 1, Σb = 1).

**핵심 의미**: long-only Σw=1 trivially satisfies active-neutral. **non-trivial constraint는 active **risk** (TE) 제한**으로 enforcement:
- `TE_t = std(w_t^T r - b_t^T r)` annualized
- Constraint: TE_t ≤ 8% (mandate F.4)

### 6.2. Sector Active Weight Constraint (mandate F.6)

```
|Σ_{i ∈ sector s} (w_{i,t} - b_{i,t})| ≤ 0.10    ∀ s, ∀ t
```

10 GICS sectors (KOSPI 분류) → 10 constraints per sig_date. Energy / Financials / Tech 같은 큰 sector에서 active over-weight 10% 한도. 

**Implementation in Forge**: top-K=20 selection 후, sector active weight check. Violation 시 가장 큰 sector active의 stocks 중 1개 drop + 다음 ranked stock add. Iterative 5 max iter.

### 6.3. ADV Usage Constraint (mandate F.7)

```
trade_volume_{i,t} = |w_{i,t} - w_{i,t-1}| × portfolio_NAV
ADV_{i,t} = mean(daily_traded_value_{i, t-20:t-1})
ADVUsage_{i,t} = trade_volume_{i,t} / ADV_{i,t} ≤ 0.05    ∀ i, ∀ t
```

5% of 20-day ADV per stock per rebalance. Implementation: if violation, scale down trade size + carry forward residual to next rebalance.

---

## 7. Forge Cycle Mandate (post Q-Lead confirm)

본 alpha cycle = design only. Forge cycle 진입 전 다음 의무:

1. **Code 작성 Q-Lead confirm** (도훈 mandate B.2)
2. 8 모델 모두 same-harness 구현
3. Purged walk-forward CV (다음 산출물 spec) 의무
4. 12 metric × 8 model = 96 metric values 산출
5. 6 rejection criteria check 의무
6. Codex Round 5단계 (Forge stage)

---

## 8. Open Questions for Codex Round

1. **8 모델 모두 alpha cycle에서 spec design**: 본 design phase에서 8 모델 모두 spec? 또는 DPL_KR_v2 (Model 6) only? — 본 file은 8 모델 모두 spec 정의. Forge cycle implementation 의무.
2. **Active-neutral Σ(w-b)=0의 long-only 의미**: trivial (Σw=Σb=1) 또는 enforce 의미? — TE constraint (≤8%)가 실질 binding으로 해석.
3. **Differentiable optimizer (Model 7)의 KR N=1500-2000 적용 가능성**: top-K 후 QP만 differentiate → manageable.
4. **GBM Direct Policy (Model 5)의 surrogate target generation**: post-hoc optimal Δw 또는 surrogate gradient — Forge cycle decision.
5. **Cost-aware DPL (Model 8)의 objective E 4-term vs v2 3-term composite**: 두 form 모두 ablation 필요? 또는 통합? — Model 8 = E (mandate 직접), Model 6 = 3-term v2. 두 가지 진행.

---

**Submitted**: 2026-05-17 alpha-research Step 2.2b. 도훈 mandate 2026-05-17 22:30 8 모델 비교 framework + 12 metric + 6 rejection + 7 constraint 모두 통합. 본 cycle = design only, code 작성 X.
