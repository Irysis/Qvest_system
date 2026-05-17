# DPL-RC Conditional Loss + 7-Axis Admission Specification

**WT-D20260517_003 · alpha-research Step 3.5**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Parents**: literature_review_dpl_rc.md §0.1 paradigm + §8.1 Insight 3 conditional weighting + bad_state_label_3_compare.md + p_bad_classifier_protocol.md + complement_scorer_4_stage.md
**Mandate (코덱스 핵심 수정)**: Bad month subset learning X — full sample (N=124) + bad-state conditional loss weighting

---

## 0. 본 spec의 목적

본 step은:
1. DPL-RC **conditional loss function**의 explicit mathematical form + λ rationale
2. **7-axis admission criteria** explicit + measurement protocol
3. Decision gates G0-G9 정합 매핑

코덱스 핵심 수정 정합: full 124 sig_dates 학습 + bad-state conditional weighting (subset learning X, under-determined N=25 fail mode 차단).

---

## 1. Conditional loss formulation

### 1.1. Full mathematical specification

```
L(θ) = -E_full[a_t · r_comp_t | bad_1715_t = 1] 
     + λ_good · E_full[max(0, r_drag_t)]
     + λ_corr · |corr(r_comp_·, r_1715_·)|
     + λ_to  · E_full[turnover_comp_t]
     + λ_tail · CVaR_α(r_comp_t)
```

여기서:
- `θ` = scorer parameters (stage 1: θ ∈ R^80, stage 2-3: similar, stage 4: ~30K)
- `r_comp_t` = w_comp_t · r_{t+1}^I — complement sleeve realized return at sig_date t+1
- `r_1715_t` = w_1715_t · r_{t+1}^I — 1715 sleeve realized return at t+1
- `a_t = clip(a_max · p_bad_1715(t+1), 0, a_max)` — bad-state-conditional injection rate
- `bad_1715_t` = binary label (Step 3.2 optimal definition)
- `E_full[·]` = expectation over **full 124 sig_dates** (NOT subset)
- `E_full[·|bad_1715_t = 1]` = **conditional expectation** (sample mask, full N retain)
- `r_drag_t = r_1715_t - r_blend_t` = good-state drag of complement on 1715 alpha (positive when complement reduces 1715 alpha)
- `r_blend_t = (1-a_t) · r_1715_t + a_t · r_comp_t` — blend return
- `turnover_comp_t = ||w_comp_t - w_comp_{t-1}||_1 / 2` — one-way TO
- `CVaR_α(r_comp_t)` = α=0.05 conditional value-at-risk of complement return (tail risk)

### 1.2. Why each term

**Term 1: `-E[a_t · r_comp | bad_1715]`** (negation for minimization)
- 핵심 alpha objective: bad-state subset에서 a_t-weighted complement return maximize
- Conditional expectation: bad_state subset에서만 evaluated (Ferson-Schadt 1996)
- `a_t` 곱셈: small injection (a_max 5-20%) reflects production-stable bound
- **Full sample learning**: gradient 계산은 full sample 124 sig_dates에 대해, 단 bad_state mask로 expectation conditional

**Term 2: `+λ_good · max(0, r_drag_good)`** (good-state drag penalty)
- 1715 alpha core preserve mandate
- `max(0, ·)`: drag positive (complement hurts 1715 in good state) only penalize, drag negative (complement enhances even in good state) no reward
- 강한 penalty (λ_good = 2.0) → admission criteria axis 3 (good_state_drag_SR ≤ 0.05) 직접 enforcement

**Term 3: `+λ_corr · |corr(r_comp, r_1715)|`** (orthogonality regularization)
- 4th sleeve 자격 보장 (cor < 0.3, admission axis 6)
- Absolute value: positive OR negative cor 모두 penalize
- λ_corr = 1.0 → moderate enforcement (G2 hard constraint)

**Term 4: `+λ_to · turnover`** (cost-aware)
- annualized TO ≤ 6 constraint (admission axis 5)
- Research Philosophy P2 (Cost-aware Alpha) 정합 — Jensen-Kelly-Malamud-Pedersen 2022
- λ_to = 0.5 → moderate cost penalty

**Term 5: `+λ_tail · CVaR_α(r_comp)`** (tail risk awareness)
- bad-state complement이지만 자체 tail risk도 controlled
- α=0.05 → worst 5% returns subset의 mean
- λ_tail = 0.3 → moderate tail control

### 1.3. Lambda values rationale

| λ | Value | Rationale |
|---|---|---|
| `λ_good` | **2.0** | Strong penalty — good-state drag = 1715 alpha core 손상이므로 가장 강함. admission axis 3 strict threshold (≤0.05 SR drag). 코덱스 review 요구: "Don't hurt 1715" 정합 |
| `λ_corr` | **1.0** | Moderate — cor 자체는 0-1 bounded, 1.0 weight면 cor 0.3에서 0.3 contribution. Acceptable balance. admission axis 6 (cor ≤ 0.3) |
| `λ_to` | **0.5** | Moderate — TO 자체는 0-12 range (annualized), 0.5 weight면 TO 6에서 3.0 contribution. Cost-aware framework. admission axis 5 (TO ≤ 6) |
| `λ_tail` | **0.3** | Mild — CVaR negative (loss), 0.3 weight면 CVaR -5% (월간 5% 손실)에서 -1.5% contribution. Risk awareness without over-penalize |

**Grid sensitivity** (Forge cycle):
- λ_good: {1.0, 2.0, 4.0} — strong penalty 우선
- λ_corr: {0.5, 1.0, 2.0}
- λ_to: {0.1, 0.5, 1.0}
- λ_tail: {0.1, 0.3, 0.5}

3⁴ = 81 lambda combinations × 5 walk-forward = 405 candidates → Forge cycle 10 random search per window 정합.

### 1.4. Conditional vs unconditional comparison

DPL-RC paradigm validity는 conditional measurement에서만 detect됨 (Ferson-Schadt 1996):

```
Unconditional loss (paradigm 자체 단절):
L_uncond = -E_full[r_comp_t]                # full sample mean
        + ... (same other terms)

→ complement이 bad-state에서만 alpha를 generate → unconditional mean은 small (다소 noise) 
→ 학습 signal weak, paradigm validation 불가
```

```
Conditional loss (paradigm 정합):
L_cond = -E_full[a_t · r_comp_t | bad_1715]  # bad-state subset mean
       + ... 

→ bad-state에서 alpha generate → conditional mean 명확 positive
→ 학습 signal strong, paradigm validation 가능
```

**Sample efficiency 차이**:
- Subset training (bad-state 25 sig_dates only): N=25 × 80 features = under-determined, over-fit
- **Full sample + conditional weighting (본 paradigm)**: N=124 × 80 features = 1.55:1 ratio, 학습 가능

### 1.5. Loss minimization training

```python
# Pseudo-code (stage-agnostic)
for epoch in range(n_epochs):
  for t in walk_forward_window_train_sig_dates:
    # 1. Compute complement weights w_comp_t = scorer_θ(features_t)
    # 2. Realize return r_comp_t = w_comp_t · returns_{t+1}
    # 3. Compute a_t = clip(a_max · p_bad_t+1, 0, a_max)
    # 4. Compute blend r_blend_t = (1-a_t) r_1715_t + a_t r_comp_t
    # 5. Compute conditional alpha term: contrib_alpha = -a_t · r_comp_t if bad_1715_t else 0
    # 6. Compute drag term: r_drag_t = r_1715_t - r_blend_t, drag_penalty = lambda_good · max(0, r_drag_t)
    # 7. Cor / TO / Tail terms aggregated over window
  
  total_loss = mean over t of (contrib_alpha) + drag_penalty + cor_term + to_term + tail_term
  total_loss.backward()
  optimizer.step()

  # early stopping on val_IR_net
```

각 stage는 다른 optimizer (stage 1-2: Adam OR closed-form, stage 3: LightGBM gradient boosting, stage 4: PyTorch Adam).

---

## 2. 7-Axis Admission Criteria

### 2.1. Axis 1 — Overall Sharpe Ratio

```
Axis 1: Blend SR (1715 + complement) ≥ 1.97

Measurement:
  blend_returns = (1 - a_t_series) ⊙ r_1715_series + a_t_series ⊙ r_comp_series
  blend_SR = PerformanceAnalytics::SharpeRatio.annualized(blend_returns, scale=12)
  
Pass: blend_SR ≥ 1.97
```

**Rationale**: 1715 baseline SR 1.9536, milestone closure 97.9% (gap 0.0464). +0.02 margin → +0.02 incremental gain (modest but meaningful).

### 2.2. Axis 2 — Overall MDD

```
Axis 2: Blend MDD ≥ -24.81% (1715 retain, 악화 금지 — 코덱스 보수적)

Measurement:
  blend_NAV = cumprod(1 + blend_returns)
  blend_MDD = PerformanceAnalytics::maxDrawdown(blend_returns)
  
Pass: blend_MDD ≥ -24.81% (less negative or equal)
```

**Rationale**: 1715 MDD -24.81% — admission baseline. "no worse" 코덱스 보수적. 악화 시 HARD ABORT (failure_cutoffs: blend_MDD_worse_than_1715).

### 2.3. Axis 3 — Good-state drag SR

```
Axis 3: Good-state drag SR ≤ 0.05

Measurement:
  good_state_sig_dates = sig_dates where bad_1715_t = 0
  good_drag_t = r_1715_t - r_blend_t  (for t in good_state_sig_dates)
  good_drag_SR_loss = SharpeRatio(r_1715[good]) - SharpeRatio(r_blend[good])
  
Pass: good_drag_SR_loss ≤ 0.05
```

**Rationale**: 1715 alpha core preservation strict. Good-state에서 complement가 1715 alpha를 0.05 SR points 이상 손상하면 paradigm 손상. λ_good = 2.0 directly enforces.

### 2.4. Axis 4 — Bad-state improvement

```
Axis 4: Bad-state subset SR ≥ 1715 bad-state SR + 0.30

Measurement:
  bad_state_sig_dates = sig_dates where bad_1715_t = 1
  bad_1715_SR = SharpeRatio(r_1715[bad_state])
  bad_blend_SR = SharpeRatio(r_blend[bad_state])
  
Pass: bad_blend_SR - bad_1715_SR ≥ 0.30
```

**Rationale**: paradigm의 핵심 differentiator. Bad-state SR이 clearly improve해야 complement가 paradigm validation. +0.30 SR threshold = clear improvement (Ferson-Schadt 1996 conditional alpha framework 정합).

### 2.5. Axis 5 — Turnover

```
Axis 5: Annualized TO ≤ 6.0

Measurement:
  TO_comp_annualized = mean(monthly TO) × 12
  TO_blend_annualized = mean(blend TO) × 12 (factoring 1715 TO + complement TO + a_t fluctuation)
  
Pass: TO_blend_annualized ≤ 6.0
```

**Rationale**: implementation discipline (Research Philosophy P6). 1715 TO ~4-5 baseline + complement TO contribution.

### 2.6. Axis 6 — Correlation vs 1715

```
Axis 6: |corr(r_comp, r_1715)| ≤ 0.3

Measurement:
  monthly_returns_overlap = sig_dates with both r_comp_t and r_1715_t known
  cor_comp_1715 = cor(r_comp_overlap, r_1715_overlap)
  
Pass: |cor_comp_1715| ≤ 0.3
```

**Rationale**: 4th sleeve 자격 (complement essence). λ_corr = 1.0 directly enforces. G2 decision gate.

### 2.7. Axis 7 — p_bad OOS AUC

```
Axis 7: p_bad classifier aggregate OOS AUC ≥ 0.55

Measurement:
  See p_bad_classifier_protocol.md §2 (G1 hard gate already enforces)
  Aggregate AUC across 5 walk-forward windows
  
Pass: aggregate_AUC ≥ 0.55
```

**Rationale**: state predictability 입증. Without p_bad valid forecast, conditional injection a_t = 0 → paradigm degenerate. G1 / G8 gates.

### 2.8. Composite admission decision

```
Admission_Decision = ALL([
  axis_1_PASS,   # blend SR ≥ 1.97
  axis_2_PASS,   # blend MDD ≥ -24.81%
  axis_3_PASS,   # good_state_drag_SR ≤ 0.05
  axis_4_PASS,   # bad_state_improvement ≥ +0.30
  axis_5_PASS,   # TO ≤ 6
  axis_6_PASS,   # |cor| ≤ 0.3
  axis_7_PASS,   # p_bad AUC ≥ 0.55
])

if Admission_Decision:
  if AX008_2_3_PASS (Forge + Codex + Architect):
    → ADMIT
  else:
    → DEFER (AX-008 weak)
else:
  → DEFER (axis fail count = N, specifics)
```

### 2.9. Hierarchy of axes

7 axes 중 가장 critical (failure_cutoffs):
1. **Axis 2 (blend_MDD_worse_than_1715)** → HARD ABORT (1715 production retain absolute)
2. **Axis 3 (good_state_drag exceeded)** → ABORT (1715 alpha core 손상)
3. **Axis 7 (p_bad AUC fail)** → already HARD ABORT via G1 (Step 3.3)

다음 critical:
4. **Axis 4 (bad_state_improvement < +0.30)** → paradigm value 약함, DEFER
5. **Axis 1 (blend SR < 1.95)** → 1715 보다 못함, ABORT
6. **Axis 6 (cor > 0.3)** → 4th sleeve 자격 X, DEFER
7. **Axis 5 (TO > 6)** → cost concern, DEFER (재학습 with stronger λ_to)

---

## 3. Decision gates G0-G9 매핑

WT-D20260517_003 request.json `decision_gates` 매핑:

| Gate | Spec | 매핑 |
|---|---|---|
| **G0_PIT** | Usable_Date <= sig_date + t-1 lag + p_bad classifier t-feature only | All artifacts (literature §0.4, bad_state §6, p_bad §5, scorer §6) + PIT C1-C15 strict |
| **G1_p_bad_classifier_oos** | AUC ≥ 0.55 + Brier < 0.24 + recall ≥ 0.60 | Step 3.3 p_bad_classifier_protocol.md §2 HARD ABORT gate |
| **G2_cor_vs_str1715** | |cor| ≤ 0.3 | admission axis 6 |
| **G3_overall_sr** | blend SR ≥ 1.97 | admission axis 1 |
| **G4_mdd_no_worse** | blend MDD ≥ -24.81% | admission axis 2 |
| **G5_good_state_drag** | good_state_drag_SR ≤ 0.05 | admission axis 3 |
| **G6_bad_state_improvement** | bad_state SR ≥ 1715 + 0.30 | admission axis 4 |
| **G7_turnover_hurdle** | blend TO ≤ 6.0 | admission axis 5 |
| **G8_p_bad_state_predictability** | 3 sub-period AUC PASS | Step 3.3 §3 G8 sub-period stability |
| **G9_AX008** | Forge + Codex + Architect 2/3 PASS | Cycle-level AX-008 verification triangulation |

---

## 4. Measurement protocol

### 4.1. Per walk-forward window measurement

각 window (W1-W5) test period에서 다음 측정:

```python
test_metrics_window_w = {
  "sr_blend": ...,           # axis 1 candidate
  "mdd_blend": ...,           # axis 2 candidate
  "good_state_drag_sr": ...,  # axis 3 candidate
  "bad_state_improvement": ...,  # axis 4 candidate
  "to_annualized": ...,       # axis 5 candidate
  "cor_comp_1715": ...,       # axis 6 candidate
  "p_bad_auc": ...,           # axis 7 candidate
  
  # Reproducibility
  "n_obs": len(test_sig_dates),
  "n_bad_state": sum(bad_state_t for t in test_sig_dates),
  "n_good_state": ...,
  "test_period": (start, end),
}
```

### 4.2. Aggregate across windows

```python
aggregate_metrics = {
  "sr_blend_pooled": SharpeRatio(concat(window_returns) over all windows),
  "mdd_blend_pooled": maxDrawdown(concat(window_returns)),
  "good_state_drag_sr_pooled": ...,
  "bad_state_improvement_pooled": ...,
  "to_annualized_pooled": ...,
  "cor_comp_1715_pooled": cor(concat(r_comp), concat(r_1715)),
  "p_bad_auc_pooled": AUC(concat(predictions), concat(targets)),
  
  # Sub-period stability (G8)
  "sr_blend_window_std": std(sr_window_1, ..., sr_window_5),
  "auc_window_min": min(auc_window_1, ..., auc_window_5),
}
```

### 4.3. Statistical robustness

- **Harvey-t**: t-statistic of pooled blend Sharpe (deflated by n_trials = 250)
- **DSR Z**: Bailey-LdP DSR formula
- **Lo 2002 SR confidence interval**: SR ± 1.96 × sqrt((1 + 0.5·SR²) / n)

각 stage scorer 결과에 대해 위 statistical robustness checks 적용. Multiple testing correction (Bonferroni: 4 stages × 4 a_max grid × 5 windows = 80 multiple comparisons).

---

## 5. Code skeleton (Forge cycle reference)

```python
# Forge cycle reference (alpha-research design-only, NOT implementation)

def compute_admission_metrics(
  scorer_predictions: pd.DataFrame,    # sig_date × stock × predicted score
  p_bad_predictions: pd.Series,         # sig_date × p_bad probability
  a_max: float,                          # 0.05, 0.10, 0.15, 0.20
  realized_returns: pd.DataFrame,        # sig_date × stock × realized return
  str1715_weights: pd.DataFrame,        # sig_date × stock × 1715 weight
  str1715_returns: pd.Series,           # sig_date × 1715 sleeve return
  bad_state_labels: pd.Series,          # sig_date × binary
  kospi200_returns: pd.Series,          # sig_date × benchmark return
  cost_bps: float = 15,                  # PIT 15bps
) -> dict:
  
  # 1. Compute complement weights from scorer (top-K + sizing)
  w_comp = sizing_pipeline(scorer_predictions, top_K=20, bounds=(0, 0.20), Σ=1)
  
  # 2. Compute injection rate
  a_t = (a_max * p_bad_predictions).clip(0, a_max)
  
  # 3. Compute blend returns
  r_1715 = str1715_returns
  r_comp = (w_comp * realized_returns).sum(axis=1) - cost_bps_one_way(w_comp)
  r_blend = (1 - a_t) * r_1715 + a_t * r_comp
  
  # 4. Compute 7 axes
  sr_blend = PerformanceAnalytics.SharpeRatio_annualized(r_blend)
  mdd_blend = PerformanceAnalytics.maxDrawdown(r_blend)
  
  good_mask = (bad_state_labels == 0)
  bad_mask = (bad_state_labels == 1)
  sr_1715_good = SharpeRatio(r_1715[good_mask])
  sr_blend_good = SharpeRatio(r_blend[good_mask])
  good_drag = sr_1715_good - sr_blend_good
  
  sr_1715_bad = SharpeRatio(r_1715[bad_mask])
  sr_blend_bad = SharpeRatio(r_blend[bad_mask])
  bad_improve = sr_blend_bad - sr_1715_bad
  
  to_blend = compute_annualized_turnover(blend_weights_series)
  cor_comp_1715 = correlation(r_comp, r_1715)
  
  p_bad_auc = sklearn.metrics.roc_auc_score(bad_state_labels.shift(-1).dropna(), 
                                            p_bad_predictions.shift(-1).dropna())
  
  return {
    "axis_1_sr_blend": sr_blend,
    "axis_2_mdd_blend": mdd_blend,
    "axis_3_good_drag": good_drag,
    "axis_4_bad_improvement": bad_improve,
    "axis_5_to_annualized": to_blend,
    "axis_6_cor_vs_1715": cor_comp_1715,
    "axis_7_p_bad_auc": p_bad_auc,
    
    "passes": {
      "axis_1": sr_blend >= 1.97,
      "axis_2": mdd_blend >= -0.2481,
      "axis_3": good_drag <= 0.05,
      "axis_4": bad_improve >= 0.30,
      "axis_5": to_blend <= 6.0,
      "axis_6": abs(cor_comp_1715) <= 0.3,
      "axis_7": p_bad_auc >= 0.55,
    },
    
    "admission_decision": all(...)
  }
```

---

## 6. ABORT decision flowchart

```
Forge cycle:
  1. Step 3.2 bad_state definition selection
  2. Step 3.3 p_bad classifier 학습
     → if G1 FAIL: HARD ABORT (paradigm inviable)
  3. Stage 1 PPP 학습 + admission test
     → if axis 1-7 fail majority: ABORT cycle (paradigm marginal value)
  4. Stage 2 EN 학습 + admission test + incremental check vs Stage 1
     → if no incremental: Stage 1 final, proceed to admission
  5. Stage 3 LightGBM 학습 + admission + incremental check vs Stage 2
     → if no incremental: Stage 2 final
  6. Stage 4 DPL-RC Neural 학습 (GPU 의무, Q-Lead confirm 후) + admission + incremental
     → if no incremental: Stage 3 final
  7. Final stage scorer × a_max grid (4 values: 0.05, 0.10, 0.15, 0.20)
     → 4 candidates × admission 7-axis
     → admission PASS candidates → Pareto curve construction
     → 도훈 select among Pareto optimal
  8. Codex Round 5단계
  9. Judge gate G0-G9 verification
  10. Governor admission → book_state mutation (if PASS)
```

각 step에서 ABORT triggers:
- G1 fail (p_bad classifier inviable)
- Axis 2 fail (MDD worse than -24.81%)
- Axis 3 fail (good-state drag)
- Codex REJECT veto=true

---

## 7. Codex Round audit points

본 spec에 대한 Codex 예상 challenge:

1. **λ values overlooked sensitivity** → λ_good = 2.0 is "strong", but no formal sensitivity study. 정당화: Forge cycle 10 random search per window with λ grid → empirical sensitivity. axis 3 strict threshold 직접 enforce.

2. **Conditional loss with full sample training is methodologically novel** → 정당화: Ferson-Schadt (1996) framework + AC-M (2023) sample weighting + LightGBM `is_unbalance` + sklearn `sample_weight` 표준 framework. 학술 backbone explicit.

3. **`bad_state_improvement ≥ +0.30` threshold sourcing?** → 정당화: Frazzini-Pedersen 2014 BAB conditional SR improvement bound (~+0.3 to +0.5 in stress vs normal). 본 cycle은 conservative end 사용. Codex 추가 sensitivity 권고 시 grid 검증.

4. **CVaR α=0.05 vs EVaR worst-window (DeePM Pillar 3)** → 정당화: Stage 1-3 (Linear/EN/LightGBM)에는 CVaR_α 단순 + tractable. Stage 4 Neural에서 DeePM SoftMin EVaR 추가 (선택 hyperparam β_evar). 4-stage paradigm 정합.

5. **Multiple testing correction** — 4 stages × 4 a_max × 5 windows × 10 trials = 800 trials. DSR n_trials = 800? → 250-800 range, Bailey-LdP DSR conservative bound 적용. Harvey-t 3.0 threshold 정합 + DSR Z ≥ 0 strict.

6. **`a_t = clip(a_max · p_bad, 0, a_max)` linear function may amplify noise** → 정당화: linear is simplest, interpretable. p_bad calibrated (Brier < 0.24 통과) → clipping noise mitigated. Alternative: sigmoid (1 / (1 + exp(-k(p_bad - 0.5)))) 가능, Forge cycle exploration retain.

7. **What if p_bad_classifier과 complement scorer가 동일 features 사용 → leakage / multicollinearity?** → 정당화: 두 모델 별개 학습 (separate train), features overlap (80 same)이지만 target 다름 (p_bad target = bad_state binary; complement target = realized return). 직접 leakage 없음. Walk-forward purge 동일 정합.

---

## 8. Submission summary

**Submitted**: 2026-05-17 alpha-research Step 3.5 conditional_loss_7axis_admission.md. DPL-RC 5-term conditional loss explicit form + λ values rationale + 7-axis admission criteria explicit + decision gates G0-G9 매핑 + measurement protocol + Codex audit points.

**Critical mandate**: full sample training (N=124) + bad-state conditional weighting (NOT subset learning). 코덱스 핵심 수정 정합. Step 3.6 Codex Round 5단계 mandate 진행.

**다음 step**: Codex Round 5단계 (Step 3.6) → alpha_package.json final (Step 3.7).
