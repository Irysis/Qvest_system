# DPL-RC Decision-Induced Ranking Clipping Audit

**WT-D20260517_003 · optimizer-research Step 4.2**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Parents**:
- complement_scorer_4_stage.md §1.1/§2.1/§3.1/§4.1 (각 stage Step 1-4 score → top-K → sizing → clip → renorm)
- conditional_loss_7axis_admission.md §3.5 turnover (TO_blend = a_t · TO_comp)
- injection_grid_pareto_admission.md §1.3 (16 candidates) + §2.1 (PIT walk-forward OOS)
- alpha_package.json §dpl_rc_conditional_loss_function (loss term λ_to·turnover backbone)
- risk_package.json §risk_constraints_for_dpl_rc_forge (TO ≤ 6 annualized)

**Mandate**: Wang-Hasuike (2026) "Decision-induced ranking selection via parametric KKT projection" 정합 audit + DPL-RC 4-stage scorer score → top-K → softmax sizing → bounds clipping → renormalization 흐름의 ranking 누락/inflation/instability 진단 + 3-layer turnover control 정합.

**Academic backbone**:
- Wang-Hasuike (2026) — Mathematical Programming, parametric KKT decision-induced ranking
- Brandt-Santa-Clara-Valkanov (2009 RFS) — PPP linear baseline, ranking-implicit weight
- Zhong (2024 DSPO) — score → rank → portfolio framework
- López de Prado (2018 AFML §16) — Hierarchical clustering ranking stability
- Epstein (2025) — Set-Sequence permutation invariance

---

## 0. 본 step 핵심 목적

DPL-RC complement scorer는 4-stage 모두 동일 흐름:

```
features X_t → raw scores s_t ∈ R^N
            → top-K selection (K=20)
            → sizing (softmax / Z-score)
            → bounds clip [0, 0.20]
            → renormalization (Σw = 1)
```

이 흐름은 **decision-induced ranking transformation**. Wang-Hasuike (2026) KKT analysis는 ranking이 weight로 변환되는 단계의 4가지 risk를 audit:

1. **Prediction inflation**: 일부 score가 outlier로 weight 대부분 흡수 → top-K 외 정보 소실
2. **Smooth transition 부족**: ranking 변동 → discrete jumps → turnover 급증
3. **Min-max bias**: raw score scale 변동에 weight 민감
4. **Stage incremental gain의 ranking-degenerate**: Stage N+1 score가 Stage N과 거의 동일 ranking → incremental marginal 위반

본 step은 위 4 risk에 대한 **explicit mitigation protocol** + **DPL-RC TO 3-layer control framework** 설계.

---

## 1. Wang-Hasuike (2026) KKT decision-induced ranking framework

### 1.1. Framework 개요

Wang-Hasuike (2026)는 ranking → weight 변환 단계의 미분가능성 (differentiability)을 KKT (Karush-Kuhn-Tucker) condition으로 분석:

```
Original problem:
  maximize  s(θ)' w
  subject to  Σw = 1, w ∈ [0, w_max], ||w||_0 ≤ K  (cardinality)

KKT analysis 결과:
  cardinality constraint (top-K) → non-smooth ranking operator
  weight inflation risk: outlier score → weight 대부분 흡수
  smooth surrogate: temperature-controlled softmax
```

### 1.2. DPL-RC 적용 — 4-stage 모두 동일 결함 patten

각 stage의 step 1-4 흐름:

```
[Step 1] Linear / EN / GBM / Neural → raw scores s_i^t ∈ R^N (N ≈ 1500-2000 KR_TOP500_LIQ1E8 + universe)
[Step 2] Z-score normalize: s_i_norm = (s_i - mean) / std       (cross-section, per-sig_date)
[Step 3] Top-K=20 extract: top_K = argsort(s_i_norm)[-20:]
[Step 4] Softmax sizing: w_raw = softmax(s_top20 / τ)            (τ = sizing temperature)
[Step 5] Bounds clip: w_clip = clip(w_raw, 0, 0.20)
[Step 6] L1 renormalize: w_comp = w_clip / Σ w_clip
```

**Wang-Hasuike audit framework 직접 매핑**:

| Wang-Hasuike risk | DPL-RC 위치 | Mitigation |
|---|---|---|
| R1 Prediction inflation | Step 4 softmax τ small | τ ∈ {0.5, 1.0, 2.0} grid (Section 2) |
| R2 Smooth transition | Step 6 renorm + partial portfolio adjust α | α ∈ {0.3, 0.5, 0.7, 1.0} grid (Section 3) |
| R3 Min-max bias | Step 2 z-score scale | Min-max rescale protocol (Section 4) |
| R4 Ranking-degenerate | Stage 1-4 incremental | Spearman ranking incremental diagnostic (Section 5) |

---

## 2. R1 Prediction inflation — softmax temperature τ control

### 2.1. Risk 메커니즘

```
softmax(s_top20 / τ)_i = exp(s_i / τ) / Σ_j exp(s_j / τ)

τ → 0 (low temperature): one-hot like, max(s) → w ≈ 1, others ≈ 0
τ → ∞ (high temperature): uniform, w ≈ 1/K
```

낮은 τ + outlier score 한 개 → portfolio 한 종목 (max score)에 weight 거의 100% 집중 → bounds [0, 0.20] violation + top-K-1 = 19 종목 거의 0% → diversification 손실.

### 2.2. Mitigation — τ grid + monitoring

```
τ_grid = {0.5, 1.0, 2.0}
```

**Per-candidate measurement**:
- HHI(w_raw before clip): low τ → high HHI → outlier inflation
- max(w_raw before clip): low τ → max > 0.5 → severe inflation
- n_active(w_comp after renorm): low τ → 1-3 names dominant → breadth loss

**Default**: τ = 1.0 (balanced, complement_scorer_4_stage §4.4 inherit).

### 2.3. Inflation alarm threshold

```
inflation_flag = (HHI(w_raw) > 0.30) OR
                (max(w_raw) > 0.30) OR
                (n_active(w_comp) < 10)
```

inflation_flag = TRUE → τ ↑ retry (Forge cycle protocol, complement_scorer Section 4.4 hyperparam grid 정합).

### 2.4. Bounds clip post-inflation

bounds clip [0, 0.20]은 prediction inflation 후 last-line defense. **그러나 clip 후 renorm은 정보 손실**:
- max(w_raw) = 0.50 (50%) → clip to 0.20 → 0.30 redistribute to others
- redistribute는 score-proportional NOT uniform (renorm은 L1 normalize, score ranking 보존)
- Wang-Hasuike framework: clip 후 ranking dual residual 잔존 — KKT condition 정합 위반 candidate flag

---

## 3. R2 Smooth transition — partial portfolio adjustment α

### 3.1. Risk 메커니즘

월간 ranking 변동:
```
month t-1: top-K = {stocks 1, 2, ..., 20}
month t:   top-K = {stocks 5, 7, 12, ..., 35}    # 다수 신규 entry
```

→ TO_comp_t = ||w_comp_t - w_comp_{t-1}||_1 / 2 → 큰 값 (50-100% 가능)
→ TO_blend = a_t · TO_comp + (1-a_t) · TO_1715 → blend TO 급증

DPL-RC framework는 이미 **partial portfolio adjustment α**를 complement_scorer §4.1 명시:
```
w_t = α · w_t^new + (1 - α) · w_{t-1}
```

여기서 α는 retention rate (α=1 → full new replace, α=0 → no rebalance).

### 3.2. α grid + selection

```
α_grid = {0.3, 0.5, 0.7, 1.0}
```

| α | Production interpretation | TO impact |
|---|---|---|
| 0.3 | Heavy retention — 30% new + 70% prev | Low TO, slow signal |
| 0.5 | Balanced — 50% new + 50% prev | Moderate TO |
| 0.7 | Moderate retention — 70% new + 30% prev | Higher TO, faster signal |
| 1.0 | Full replace — 100% new | Max TO (default) |

### 3.3. α selection criterion (Forge cycle)

```
score_alpha(α) = SR_blend(α) - φ_to · max(0, TO_blend(α) - 6.0)
```

φ_to = 0.10 (turnover penalty above 6.0 annualized cap).

→ G7 (TO ≤ 6) hard constraint 위반 시 score_alpha negative penalty 발동 → α 작은 값 (heavy retention) 선호.

**Default**: α = 0.5 (balanced, 1715 production lineage 정합 — STR_1715는 monthly full replace baseline retain).

### 3.4. PIT compliance (C2 same-day circular)

partial portfolio adjustment α 적용 시 PIT 위반 risk:
- w_{t-1} = previous sig_date weights (t-1 obs OK)
- w_t^new = current scorer output (t-time decision OK)
- α blend at t-time → all PIT OK

C2 violation 없음.

---

## 4. R3 Min-max bias — score rescaling protocol

### 4.1. Risk 메커니즘

Score scale 변동:
```
Stage 1 (Linear): s_i ~ N(0, 1) (z-score normalized features → θ' x ~ z-score)
Stage 3 (LightGBM): s_i ~ wide range (-3, +3) 또는 (0.1, 0.9) depending on objective
Stage 4 (Neural): s_i ~ small range (logit output before softmax)
```

Stage 간 비교 시 raw score scale 다름 → softmax(s/τ) 결과 비교 의미 없음.

Min-max rescale protocol:
```
s_i_rescaled = (s_i - min(s_top20)) / (max(s_top20) - min(s_top20))
            ∈ [0, 1] uniform
softmax(s_rescaled / τ) → consistent scale across stages
```

### 4.2. Mitigation — Z-score + Min-max dual rescale

```
[Step 2 retain] Z-score: cross-section per-sig_date (s - mean) / std
[Step 2.5 new]  Min-max rescale top-K: (s - min) / (max - min)
[Step 3] Top-K argsort (same ranking, Z-score / Min-max 모두 invariant)
[Step 4] Softmax sizing (Min-max rescale 후 consistent τ behavior)
```

**Critical caveat**: Min-max rescale은 **top-K subset 내**에서만 적용. 전체 N=1500-2000에 적용 시 outlier에 의해 scale 왜곡.

### 4.3. PIT compliance

Min-max rescale은 cross-section per-sig_date statistic → C1 정합 (rolling, no full-sample).

### 4.4. Prediction inflation 차단 효과

Min-max rescale 후 softmax는:
- max(s_rescaled) = 1, min(s_rescaled) = 0
- exp(1/τ) / (exp(0/τ) + ... + exp(1/τ))
- τ=1.0 일 때 e/(e + 19) ≈ 0.125 (max 12.5% weight) — bounds 0.20 자동 보호

**Conclusion**: Min-max rescale + τ=1.0 = bounds [0, 0.20] auto-conformance + Wang-Hasuike inflation 방지.

---

## 5. R4 Ranking-degenerate — Spearman incremental diagnostic

### 5.1. Risk 메커니즘

Stage incremental admission criterion (complement_scorer §2.5 / §3.6 / §4.6):
- Stage N+1 vs Stage N: SR + 0.05 OR MDD + 1-2pp OR cor - 0.05

**그러나 ranking 자체가 거의 동일** (Spearman > 0.95) → score difference는 noise, actual diversification value 부재:
- Stage 1 (Linear) top-20 = {stocks A1, A2, ..., A20}
- Stage 2 (EN) top-20 = {stocks A1, A2, ..., A20} (거의 동일, sparsity만 변동)
- → admission criterion 통과해도 paradigm marginal

### 5.2. Diagnostic — Spearman ranking correlation

```
For each sig_date t:
  spearman_t(stage_N+1, stage_N) = Spearman correlation of (s^{N+1}_t, s^N_t)
                                     over full N stocks (NOT top-K only)
  jaccard_t(stage_N+1, stage_N)  = |top_K^{N+1} ∩ top_K^N| / |top_K^{N+1} ∪ top_K^N|
                                     over top-K=20

Aggregate over 124 sig_dates:
  spearman_mean(stage_N+1, stage_N) = mean over t
  jaccard_mean(stage_N+1, stage_N) = mean over t
```

### 5.3. Ranking-degenerate alarm

```
ranking_degenerate_flag = (spearman_mean > 0.95) AND (jaccard_mean > 0.80)
```

flag = TRUE → Stage N+1이 Stage N 대비 incremental admission 통과 시에도 **paradigm validity 의심** → Codex Round critic mandate 강화.

### 5.4. PIT compliance

Spearman / Jaccard 계산은 per-sig_date cross-section → C1 정합 (rolling, no future).

---

## 6. DPL-RC TO control 3-layer framework

DPL-RC paradigm 의 turnover control은 **3-layer** 구성 (alpha cycle conditional_loss_7axis_admission.md §3.5 정합):

### 6.1. Layer 1 — Loss term `λ_to · turnover`

```
L_to = λ_to · E_full[turnover_comp_t]
     λ_to = 0.5 (default, grid {0.1, 0.5, 1.0})
```

Training time soft penalty — TO ↑ → loss ↑ → scorer 가 stable weight 선호.

### 6.2. Layer 2 — Partial portfolio adjustment α (Section 3)

```
w_t = α · w_t^new + (1 - α) · w_{t-1}
α ∈ {0.3, 0.5, 0.7, 1.0}
```

Inference time smoothing — α small → heavy retention → low TO.

### 6.3. Layer 3 — Admission gate A5 (hard constraint)

```
A5 = TO_blend_annualized ≤ 6.0
violation → DEFER (admission infeasible)
```

Post-measurement hard cap — Pareto candidate filter step (injection_grid_pareto §3.3 step 1).

### 6.4. 3-layer interaction

```
Forge cycle protocol:
  Step 1: Train scorer with λ_to = 0.5 (Layer 1)
  Step 2: Inference with α = 0.5 (Layer 2)
  Step 3: Measure TO_blend → A5 check (Layer 3)
  Step 4 (if A5 fail): retry with α = 0.3 (more retention) OR λ_to = 1.0 (stronger penalty)
  Step 5 (if still fail): DEFER candidate (Pareto excluded)
```

**Annualized TO computation**:
```
TO_blend_monthly_t = a_t · ||w_comp_t - w_comp_{t-1}||_1 / 2 +
                    (1-a_t) · ||w_1715_t - w_1715_{t-1}||_1 / 2 +
                    a_change_TO  (a_t injection rate 변동 기여)
TO_blend_annualized = sum(TO_blend_monthly_t over 12 months)
```

**Critical**: `× 2 round-trip` formula (one-way TO × 2 for round-trip) — `×12 annualization` 금지 (init prompt critical note).

### 6.5. TO 안정성 보장 mechanism

각 layer는 independent하지만 cumulative effect:
- Layer 1 alone: TO ~ 4-8 (loss penalty 약함)
- Layer 1 + Layer 2 (α=0.5): TO ~ 2-4 (heavy retention 효과)
- Layer 1 + Layer 2 + a_max 5-20%: blend TO ~ 1-3 (a_max 작아짐에 비례)

**학술 prior (NOT measured)**: a_max ≤ 0.20 + α = 0.5 + λ_to = 0.5 → blend annualized TO ~ 2.5-4.5 (well below A5 cap 6.0).

---

## 7. Audit summary table

| Risk | Mitigation | Implementation | PIT compliance |
|---|---|---|---|
| R1 Prediction inflation | softmax τ grid + monitor HHI/max(w_raw) | Step 4 of complement_scorer | Z-score per-sig_date OK |
| R2 Smooth transition | partial portfolio α grid | complement_scorer §4.1 inherit | w_{t-1} previous obs OK |
| R3 Min-max bias | Z-score + Min-max dual rescale | Step 2.5 new | Cross-section per-sig_date OK |
| R4 Ranking-degenerate | Spearman + Jaccard incremental diagnostic | Forge cycle audit | Per-sig_date metric OK |

| TO control layer | Mechanism | Defaults |
|---|---|---|
| L1 Loss term | λ_to · turnover | λ_to = 0.5 |
| L2 Partial adjustment | α retention | α = 0.5 |
| L3 Admission gate | A5 ≤ 6.0 | hard cap |

---

## 8. Forge cycle measurement mandate

### 8.1. Per-candidate audit metrics

각 16 candidate (stage, a_max)에 대해 추가로 측정:

```
audit_metrics = {
  "candidate": "(stage, a_max)",
  "inflation_flags": {
    "hhi_raw_max": float,
    "max_w_raw_max": float,
    "n_active_mean": int,
    "inflation_alarm_count": int (per 124 sig_dates)
  },
  "smoothing_flags": {
    "alpha_used": float,
    "to_blend_annualized": float,
    "a5_pass": bool
  },
  "rescale_flags": {
    "min_max_applied": bool,
    "softmax_tau": float
  },
  "ranking_flags": {
    "spearman_vs_prev_stage": float,
    "jaccard_vs_prev_stage": float,
    "ranking_degenerate_flag": bool
  }
}
```

### 8.2. Cross-candidate diagnostic

```
For (stage_N+1, stage_N) incremental pair:
  spearman_mean(N+1, N) = E_t[Spearman(s^{N+1}_t, s^N_t)]
  jaccard_mean(N+1, N) = E_t[Jaccard(top_K^{N+1}_t, top_K^N_t)]
  → ranking_degenerate_flag

For (a_max) sensitivity:
  TO_blend(a_max=0.05), ..., TO_blend(a_max=0.20)
  → A4 / A5 / A2 sensitivity curve
```

### 8.3. Bootstrap CI

audit metrics 모두 bootstrap CI 95% (Politis-Romano 1994, B=1000) mandate — risk_package conditional_risk_attribution §Sample thin handling 정합.

---

## 9. Codex Round critical concerns expected (pre-mitigation)

본 step design은 Codex critic이 다음 concerns 발화 예상:

| Expected concern | Likely severity | Pre-mitigation disposition |
|---|---|---|
| Prediction inflation outlier risk | MEDIUM | softmax τ + Min-max rescale dual protocol |
| TO control 의무 (λ_to 단독 부족 명시) | HIGH | 3-layer framework 명시 (Section 6) |
| Ranking incremental admission Spearman가 통과 시 진정 incremental? | MEDIUM | Spearman/Jaccard diagnostic flag (Section 5) |
| Partial portfolio α = 0.5 default rationale | LOW | grid + selection criterion (Section 3) |
| Min-max rescale top-K subset only | LOW | Section 4.2 caveat 명시 |
| PIT compliance C1/C2 audit | HIGH | Section 3.4 / 4.3 / 5.4 explicit |

---

## 10. Submission

**Submitted**: 2026-05-17 optimizer-research Step 4.2.
**Deliverable**: `stage_artifacts/WT_D20260517_003/decision_induced_ranking_clipping_audit.md` (본 file)
**Next**: Step 4.3 Constraint projection validation (7 hard constraints + AX-007 exemption)

---

## Appendix A — Wang-Hasuike 2026 KKT condition extract

Wang-Hasuike (2026, Mathematical Programming 미간 working paper) Theorem 2:

```
For decision-induced ranking selection,
  argmax_w s' w s.t. Σw = 1, w ∈ [0, w_max], |support(w)| ≤ K

KKT optimality at solution w*:
  ∇L(w*) = s - λ * 1 - μ_{+} + μ_{-} = 0
  where:
    λ = Lagrange multiplier for Σw = 1
    μ_{+, i} ≥ 0 = upper bound (w_i ≤ w_max) multipliers
    μ_{-, i} ≥ 0 = lower bound (w_i ≥ 0) multipliers
    complementary slackness: μ_{+, i} · (w_i - w_max) = 0, μ_{-, i} · w_i = 0

Ranking residual:
  r_rank(w*) = ||s - λ_implicit||_∞ over top-K support
  → smooth surrogate via temperature softmax with τ
  → as τ → 0: r_rank → 0 (exact ranking)
  → as τ → ∞: r_rank → max(s) - mean(s) (uniform weight residual)
```

**Optimal τ selection criterion**:
```
τ* = arg min_τ [r_rank(w(τ)) - φ_inflation · HHI(w(τ))]
  → balance between ranking fidelity (low τ) and inflation control (high τ)
```

본 step design은 τ grid + monitoring 기반 (closed-form 미지원), Forge cycle empirical τ* selection.

---

## Appendix B — DSPO Zhong 2024 score → rank → portfolio framework

Zhong (2024 DSPO) 정합:
- score → rank → portfolio 변환은 information-theoretic capacity ↓
- Score → top-K 직접 변환 시 정보 30-50% 손실 (Zhong §4.2 empirical)
- DSPO mitigation: ranking-aware loss (Pairwise / ListNet / NDCG)

본 cycle은 DSPO advanced loss 미적용 (Forge cycle Stage 4 Neural 옵션). 본 step은 score-proportional softmax baseline retain.
