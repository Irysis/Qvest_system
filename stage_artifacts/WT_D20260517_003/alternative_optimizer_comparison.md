# DPL-RC Alternative Optimizer Comparison Framework

**WT-D20260517_003 · optimizer-research Step 4.4**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Parents**:
- alpha_package.json §production_lineage_preserved_explicit + §complement_scorer_4_stage_incremental + §academic_references_5_core_dpl_rc
- risk_package.json §method_shopping_log + §cross_covariance_design
- injection_grid_pareto_admission.md §3 Pareto + §6 expected behavior
- decision_induced_ranking_clipping_audit.md §1 Wang-Hasuike framework
- constraint_projection_validation.md §4 AX-007 exemption + §5 AX-005 EXCLUSION
- complement_scorer_4_stage.md §1-§4 stage definitions
- v2 champion_challenger_comparison_framework.md (8-model 도훈 mandate G inherit)

**Mandate**:
1. 도훈 mandate G inherit — 8-model comparison framework
2. DPL-RC 4-stage × baseline (Linear factor composite / Elastic Net + MVO / LightGBM + MVO / Brandt-Santa-Clara-Valkanov 2009 PPP linear) 비교 protocol
3. DPL-RC value-add 정량화 (You-Zhang §5 정합)
4. **사후 검증용** — admission decision 가 측정 baseline 비교를 통해 paradigm validation 입증

**Academic backbone**:
- You-Zhang (2025) — Direct Portfolio Learning Section 5 incremental value-add framework
- Brandt-Santa-Clara-Valkanov (2009 RFS) — Parametric Portfolio Policy baseline
- Markowitz (1952) — Mean-Variance Optimization baseline
- Avramov-Cheng-Metzker (2023 RFS) — ML conditional vs simple baseline empirical bound
- Mandi-Bharatula-Wilder-Tambe (2024) — End-to-end vs two-stage decision framework

---

## 0. 본 step 핵심 목적

DPL-RC paradigm validation은 **multiple competing methods 비교** 후 incremental value-add 입증 의무.

도훈 mandate G (v2 cycle inherit): 8-model comparison framework. 본 cycle DPL-RC v1.0에 적용:
- DPL-RC paradigm (Stage 1 / 2 / 3 / 4) — 본 cycle subject
- Linear factor composite — single feature averaging baseline
- Elastic Net + MVO — regularized + classical optimizer
- LightGBM + MVO — non-linear scorer + classical optimizer
- Brandt-Santa-Clara-Valkanov 2009 PPP — linear weight policy baseline

비교 결과는 DPL-RC가 marginal / meaningful / strong value-add 보이는지 사후 검증.

---

## 1. Comparison framework — 8 methods

### 1.1. 8 methods specification

| ID | Method | Type | Source |
|---|---|---|---|
| M1 | Naive baseline (no complement) | baseline | w_final = w_1715 (a_t = 0) |
| M2 | Linear factor composite | linear scorer | unweighted average of 80 features → top-K + softmax |
| M3 | Brandt-SCV 2009 PPP | linear policy | w_i = (1/N)·θ' x_i, θ trained on full sample |
| M4 | Elastic Net + classical MVO | two-stage | EN score → mvo with α as μ̂ + sample Σ |
| M5 | LightGBM + classical MVO | two-stage | LightGBM score → mvo with α as μ̂ + Ledoit-Wolf Σ |
| M6 | DPL-RC Stage 1 (Linear PPP) | DPL paradigm | bad-state conditional loss + Linear PPP |
| M7 | DPL-RC Stage 2 (Elastic Net) | DPL paradigm | bad-state conditional loss + EN |
| M8 | DPL-RC Stage 3 (LightGBM) | DPL paradigm | bad-state conditional loss + LightGBM |
| M9 | DPL-RC Stage 4 (Neural) | DPL paradigm | bad-state conditional loss + Set-Sequence Neural |

총 9 methods (도훈 mandate G 8 + Naive baseline M1 추가). M9 (Stage 4)은 incremental admission 통과 후에만 측정 (complement_scorer §5.1 정합).

### 1.2. Comparison dimensions

각 method는 동일 walk-forward purged + embargo + 동일 universe + 동일 cost 15bps + 동일 alpha cycle inherit (full 124 sig_dates + 5-window OOS aggregation 52m).

**Common evaluation** (admission 7-axis A1-A7 + supplementary):

| Dimension | A1 SR | A2 MDD | A3 drag | A4 bad_imp | A5 TO | A6 cor | A7 AUC | DSR |
|---|---|---|---|---|---|---|---|---|
| M1 baseline | 1.9536 (1715) | -24.81% | 0 | 0 | ~3 (1715 inherit) | 0 (self) | N/A | (1715 inherit) |
| M2 Linear comp | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M3 PPP | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M4 EN+MVO | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M5 GBM+MVO | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M6 DPL-RC S1 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M7 DPL-RC S2 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M8 DPL-RC S3 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| M9 DPL-RC S4 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

(TBD = Forge cycle measurement, 학술 prior NOT measured)

### 1.3. v6.1 R2-C method shopping log cap

```
Total candidates_tried = 9 (M1-M9)
v6.1 R2-C cap = 10
→ 정합 (9 ≤ 10)
```

본 cycle은 paradigm comparison (도훈 mandate G 8-model + Naive). traditional MVO/HRP/CVaR/ERC/BL/PPO_RL 비교 사용 X (DPL-RC paradigm 본질이 score-based optimizer + injection-based blend이므로 stock-level optimizer 직접 적용 의미 적음).

---

## 2. Baseline method specifications

### 2.1. M1 — Naive baseline (no complement)

```
w_final = w_1715
a_t = 0 ∀ t (no injection)
```

**Purpose**: DPL-RC paradigm 자체 marginal value 입증 baseline. DPL-RC가 M1 대비 SR + 0.02 미만 → ABORT cycle (complement_scorer §5.1 + §8.1).

**Compute**: trivial (1715 lineage retain).

### 2.2. M2 — Linear factor composite (unweighted)

```
Step 1: For each sig_date t, compute s_i^t = mean of 80 z-scored features for stock i
Step 2: Top-K=20 + softmax + clip + renorm → w_comp_t
Step 3: a_t = clip(0.10 · 1[r_1715,t < 0], 0, 0.10)  # naive: a_max=0.10 + bad_indicator binary
Step 4: w_final = (1-a_t) · w_1715 + a_t · w_comp
```

**Purpose**: Simplest possible complement scorer. Feature interaction 없음, parameter 없음, learning 없음.

**Compute**: ~30s CPU (no training).

### 2.3. M3 — Brandt-SCV 2009 PPP (classical baseline)

```
Step 1: w_i^t = (1/N_t) · θ' · x_{i,t} where θ ∈ R^80 학습
Step 2: Loss = -E_full[a_t · r_t] + λ_to · TO  (NO bad-state conditional, NO good-state drag penalty)
Step 3: Adam train θ on full 124 sig_dates × 1500-2000 stocks
Step 4: top-K + softmax + clip + renorm + injection same as DPL-RC
```

**Purpose**: Original Brandt-SCV 2009 RFS framework. unconditional alpha objective (NOT bad-state conditional).

**Difference vs DPL-RC Stage 1 (M6)**:
- M3: unconditional E_full[a_t · r_t], no λ_good drag penalty, no λ_corr orthogonality
- M6: conditional E_full[a_t · r_t | bad_state_1715], 5-term composite loss

→ M3 vs M6 비교는 **conditional learning value-add 정량화** 직접 enable.

**Compute**: ~10 min CPU (Adam train 80 params, similar to Stage 1 DPL-RC).

### 2.4. M4 — Elastic Net + classical MVO (two-stage)

```
Step 1: Train ElasticNet on full 124 sig_dates × 1500-2000 stocks
  X = 80 features, y = next-month r_{t+1}
  L1 + L2 regularization
Step 2: μ̂_i = EN.predict(X_i^t) for each i  # expected return forecast
Step 3: Σ = Ledoit-Wolf Oracle (risk_package primary)
Step 4: MVO: w* = argmax μ̂' w - λ/2 · w'Σw subject to constraints
Step 5: a_t same as DPL-RC, w_final = (1-a_t)·w_1715 + a_t·w_comp_MVO
```

**Purpose**: Two-stage paradigm (forecast then optimize). End-to-end vs two-stage 비교 (Mandi 2024).

**Compute**: ~5 min CPU (EN + MVO quadprog Fortran).

### 2.5. M5 — LightGBM + classical MVO (two-stage)

```
Step 1: Train LightGBM on full 124 sig_dates × 1500-2000 stocks
  X = 80 features, y = next-month r_{t+1}
  Standard regression objective
Step 2: μ̂_i = LightGBM.predict(X_i^t) for each i
Step 3: Σ = Ledoit-Wolf Oracle
Step 4: MVO: w* = argmax μ̂' w - λ/2 · w'Σw subject to constraints
Step 5: a_t same as DPL-RC, w_final = (1-a_t)·w_1715 + a_t·w_comp_MVO
```

**Purpose**: Two-stage with non-linear forecast. Mandi 2024 + Avramov 2023 정합 baseline.

**Compute**: ~15 min CPU (LightGBM + MVO).

---

## 3. DPL-RC value-add quantification (You-Zhang §5 정합)

### 3.1. Value-add framework

You-Zhang (2025) Section 5는 Direct Portfolio Learning value-add를 다음과 같이 분해:

```
ΔSR_DPL = SR_DPL - SR_baseline
       = (SR_DPL - SR_two_stage_MVO) +     # DPL paradigm value-add
         (SR_DPL_conditional - SR_DPL_uncond) +  # Conditional learning value-add
         (SR_DPL_4stage - SR_DPL_1stage)    # Complexity value-add
```

### 3.2. DPL-RC 적용 — 3 value-add components

#### Component 1: DPL paradigm value-add (vs two-stage)
```
ΔSR_paradigm = SR_M6 (DPL Stage 1) - SR_M4 (EN+MVO)
             OR SR_M8 (DPL Stage 3) - SR_M5 (GBM+MVO)
```
→ End-to-end learning이 forecast-then-optimize 대비 incremental SR 측정.

#### Component 2: Conditional learning value-add
```
ΔSR_conditional = SR_M6 (DPL Stage 1, bad-state conditional) - SR_M3 (PPP, unconditional)
```
→ Ferson-Schadt 1996 conditional alpha framework value-add 정량화.

#### Component 3: Complexity value-add
```
ΔSR_complexity_S2 = SR_M7 - SR_M6  # Elastic Net 추가
ΔSR_complexity_S3 = SR_M8 - SR_M7  # LightGBM 추가
ΔSR_complexity_S4 = SR_M9 - SR_M8  # Neural 추가
```
→ Avramov 2023 §V.B "ML이 simpler baseline 대비 incremental gain이 작거나 없는 경우" 직접 검증.

### 3.3. Forge cycle value-add report

```json
{
  "value_add_quantification": {
    "delta_sr_paradigm_dpl_vs_two_stage": {
      "ppp_vs_dplrc_s1": "SR_M6 - SR_M3 (학술 prior estimate ~0.05-0.10)",
      "en_mvo_vs_dplrc_s2": "SR_M7 - SR_M4 (학술 prior estimate ~0.05-0.10)",
      "gbm_mvo_vs_dplrc_s3": "SR_M8 - SR_M5 (학술 prior estimate ~0.05-0.10)"
    },
    "delta_sr_conditional_vs_uncond": {
      "dplrc_s1_vs_ppp": "SR_M6 - SR_M3 (학술 prior estimate ~0.10-0.20, Ferson 1996 핵심 prediction)"
    },
    "delta_sr_complexity_stage": {
      "s2_vs_s1": "학술 prior estimate ~0.05",
      "s3_vs_s2": "학술 prior estimate ~0.05",
      "s4_vs_s3": "학술 prior estimate -0.02 to +0.05 (Avramov 2023 marginal value)"
    },
    "expected_dominant_method": "DPL-RC S2 or S3 (학술 prior, NOT measured)",
    "expected_marginal_method": "DPL-RC S4 (over-param risk despite GPU compute)"
  }
}
```

(학술 prior estimate는 NOT measured, Forge cycle 측정 mandate)

---

## 4. Decision criteria — DPL-RC primary candidate validation

### 4.1. Primary candidate validity criteria

DPL-RC가 primary 선정되려면:

| Criterion | Condition | Forge cycle measurement |
|---|---|---|
| C1 vs M1 baseline | SR_DPL ≥ SR_M1 + 0.02 (paradigm marginal value) | required |
| C2 vs M2 naive composite | SR_DPL ≥ SR_M2 + 0.05 (learning value-add) | required |
| C3 vs M3 PPP unconditional | SR_DPL ≥ SR_M3 + 0.05 (conditional learning value) | required |
| C4 vs M4 EN+MVO | SR_DPL ≥ SR_M4 + 0.05 (paradigm vs two-stage) | required |
| C5 vs M5 GBM+MVO | SR_DPL ≥ SR_M5 + 0.05 (paradigm vs two-stage, non-linear) | required |

**4 criteria 동시 만족 시**: DPL-RC primary 선정 + admit candidate.
**1+ criteria 미달**: DPL-RC marginal value-add → DEFER 또는 alternative method 채택 검토.

### 4.2. Stage selection within DPL-RC

각 stage 간 incremental admission (complement_scorer §5.1):
- Stage 2 vs Stage 1: ΔSR_complexity_S2 ≥ +0.05 → Stage 2 adopt
- Stage 3 vs Stage 2: ΔSR_complexity_S3 ≥ +0.05 → Stage 3 adopt
- Stage 4 vs Stage 3: ΔSR_complexity_S4 ≥ +0.05 → Stage 4 adopt

Else: prior stage retain final.

### 4.3. a_max selection (injection grid Pareto)

injection_grid_pareto_admission §3 Pareto + §4.1 tiebreaker `crowding_adj_ret` 적용.

선정 stage_X에 대해 a_max ∈ {0.05, 0.10, 0.15, 0.20} 중 Pareto-optimal a_max 선택. 도훈 explicit selection 시 도훈 mandate retain.

---

## 5. Fairness — same-harness compliance (v1/v2 Codex C5 learning)

### 5.1. Codex C5 (v1/v2) 학습 정합

v1 (WT-D20260517_001) + v2 (WT-D20260517_002) Codex Round에서 Codex C5: **"comparison baseline same-harness PerformanceAnalytics + same cost + 1715 same-period overlap"** 학습 inherit.

본 cycle 정합:

| Fairness item | 정합 |
|---|---|
| same-harness PerformanceAnalytics | ✅ Charter §13 + Backtest Contract v1.0 (PerfA standard functions only, manual arithmetic prohibited) |
| same cost 15bps one-way | ✅ cost_model_version v2.3_kr_retail_15bps inherit |
| 1715 same-period overlap | ✅ walk-forward OOS 52m (5 windows × 12m - purge), 1715 admit 255m PerfA standard subset |
| same universe | ✅ KR_TOP500_LIQ1E8 + LIQ ≥ 2e8 + max_names 20 + bounds [0, 0.20] |
| same training protocol | ✅ purged_walk_forward_protocol v2 inherit (5 windows × 60m train + 12m val + 12m test + 1m purge + 1m embargo) |
| same feature pool | ✅ feature_allowlist_v2.csv (sha256 b3d667517a..., 80 features) |
| same DSR n_trials | ✅ n_trials = 7200 conservative (alpha cycle inherit) |

→ same-harness fairness 100% 정합. cross-cycle DSR convention drift L-309 (Session 80) 재발 차단.

### 5.2. Same-harness specific protocol

```
For each method M_i:
  Train + predict using same walk-forward windows
  Apply same top-K=20 + bounds [0, 0.20] + renorm
  Apply same injection formula a_t = clip(a_max·p_bad, 0, a_max) (M2-M9)
  Apply same cost 15bps one-way
  Compute PerformanceAnalytics SR_NW, MDD, etc.
```

→ **Forge cycle 의무**: 모든 method 동일 harness, identical compute protocol.

---

## 6. Compute budget — fair comparison

각 method 측정 budget:

| Method | Compute | Note |
|---|---|---|
| M1 baseline | ~1 min | 1715 retain |
| M2 Linear comp | ~30s | no train |
| M3 PPP | ~10 min CPU | Adam 80 params |
| M4 EN+MVO | ~5 min CPU | sklearn + quadprog |
| M5 GBM+MVO | ~15 min CPU | LightGBM + quadprog |
| M6 DPL-RC S1 | ~8 min CPU | complement_scorer Section 5.2 |
| M7 DPL-RC S2 | ~25 min CPU | complement_scorer Section 5.2 |
| M8 DPL-RC S3 | ~50 min CPU | complement_scorer Section 5.2 |
| M9 DPL-RC S4 | ~4h 10min GPU | complement_scorer Section 5.2 |
| p_bad classifier | ~25 min CPU | 모든 method 공통 |
| **Total** | ~5.5h CPU + 4h GPU = ~9.5h | Forge cycle compute budget |

총 ~9.5h compute (alpha cycle estimate 6h + risk cycle 3.5h CPU 정합).

---

## 7. Expected outcome (학술 prior, NOT measured)

### 7.1. Expected SR ranking

```
학술 prior (Ferson-Schadt + Brandt + AFP + Avramov + You-Zhang):

SR_M9 (DPL-RC S4 Neural) ~ 2.00 (학술 prior)
SR_M8 (DPL-RC S3 LightGBM) ~ 2.02 (학술 prior)    ← expected dominant
SR_M7 (DPL-RC S2 Elastic Net) ~ 1.98
SR_M5 (GBM + MVO two-stage) ~ 1.95
SR_M6 (DPL-RC S1 Linear PPP) ~ 1.96
SR_M4 (EN + MVO two-stage) ~ 1.93
SR_M3 (PPP unconditional) ~ 1.92
SR_M2 (Linear comp naive) ~ 1.92
SR_M1 (Naive baseline) = 1.9536 (1715 retain)
```

→ Expected dominant: **DPL-RC S3 LightGBM** (학술 prior, NOT measured).
→ Expected primary candidate: M8 (DPL-RC S3) + a_max=0.10 or 0.15 (Pareto sweet spot).

### 7.2. Expected value-add components

```
ΔSR_paradigm (DPL vs two-stage):    +0.05 to +0.07  (M8 - M5)
ΔSR_conditional (cond vs uncond):   +0.10 to +0.20  (M6 - M3) - Ferson 1996 핵심
ΔSR_complexity_S2_S1:               +0.05
ΔSR_complexity_S3_S2:               +0.05 (LightGBM non-linear gain)
ΔSR_complexity_S4_S3:               +0.00 to +0.02 (Avramov 2023 marginal)
```

### 7.3. Avramov 2023 §V.B empirical bound 정합

Avramov-Cheng-Metzker (2023 RFS) §V.B: "ML이 simpler baseline 대비 incremental gain은 종종 작거나 없음".

→ DPL-RC S4 (Neural) 대 S3 (LightGBM) marginal value (+0.00 to +0.02) 정합 expected. complement_scorer §7.3 "stop early at stage N" mandate 정합 (S3 final 채택 가능성 학술 prior).

---

## 8. ABORT triggers (cycle abort vs candidate abort)

| Trigger | Type | Action |
|---|---|---|
| All 9 methods SR < 1.9536 | CYCLE ABORT | DPL-RC paradigm 자체 marginal |
| M8/M9 ΔSR vs M5 < +0.02 | CANDIDATE DEFER | paradigm value-add 부재 |
| ANY method MDD < -24.81% | CANDIDATE DEFER | Codex 보수적 admission rule |
| G1 p_bad fail | CYCLE ABORT | already (alpha cycle G1) |
| Stage incremental fail at S1 | CYCLE ABORT | already (complement_scorer §8.1) |

---

## 9. Codex Round expected critic concerns

| Expected concern | Likely severity | Pre-mitigation |
|---|---|---|
| M5 (LightGBM+MVO) covariance estimation matters more than scorer? | MEDIUM | Same Σ = Ledoit-Wolf Oracle (risk_package) used in M4/M5 |
| M3 (PPP) unconditional vs M6 (DPL-RC S1) conditional fair comparison? | HIGH | Same harness Section 5, same parameter budget (θ ∈ R^80 both) |
| 9 methods over-search → DSR over-correction? | MEDIUM | n_trials = 7200 (alpha cycle inherit), DSR Bailey-LdP deflation applied |
| Value-add quantification 학술 prior NOT measured 라벨? | LOW | §3.3 + §7.2 명시 라벨 |
| Avramov 2023 marginal S4 / S3 fallback explicit? | LOW | §7.3 명시 + complement_scorer §7.3 stop early |
| M2/M3 cross-comparison harness coverage? | MEDIUM | §5.2 same-harness protocol |
| 8-model 도훈 mandate G complete inheritance? | LOW | Section 1.1 매핑 |
| Method shopping log cap (9 ≤ 10) v6.1 R2-C compliance? | LOW | Section 1.3 명시 |

---

## 10. Forge cycle deliverables

```
stage_artifacts/WT_D20260517_003/
├── method_comparison_table_9_methods.parquet     # M1-M9 × A1-A7 + DSR
├── value_add_decomposition.json                  # 3 components quantified
├── pareto_with_baselines.parquet                 # 9 methods × 4 a_max = 36 candidates Pareto
├── primary_candidate_validation.json             # C1-C5 criteria evaluation
├── same_harness_compliance_audit.json            # cost + universe + windows + DSR n_trials log
└── alternative_method_diagnostic.md              # Forge cycle artifacts summary
```

---

## 11. Submission

**Submitted**: 2026-05-17 optimizer-research Step 4.4.
**Deliverable**: `stage_artifacts/WT_D20260517_003/alternative_optimizer_comparison.md` (본 file)
**Next**: Step 4.5 Codex Critic Round 5단계 mandate.

---

## Appendix A — Mandi 2024 end-to-end vs two-stage framework

Mandi-Bharatula-Wilder-Tambe (2024) "Decision-Focused Learning" (NeurIPS / AAAI variants):
- Two-stage: predict y → optimize w (loss = MSE on y) — sub-optimal for decision quality
- End-to-end: loss directly on decision quality (regret / portfolio Sharpe) — superior

DPL-RC는 end-to-end (loss는 직접 portfolio return-based) → DPL paradigm value-add 학술 backbone.

M4/M5 two-stage baseline은 Mandi 2024 framework의 sub-optimal class. DPL-RC vs M4/M5 비교는 paradigm 정량 입증.

---

## Appendix B — Brandt 2009 PPP 핵심 차이점

Brandt-Santa-Clara-Valkanov (2009 RFS §2):
- w_i^t = w_b_i + (1/N) · θ' · x_{i,t}    # PPP formula (active weight from benchmark)
- L = -E[CRRA_utility(r_p)]                # full-sample utility maximization
- θ trained on full sample, unconditional

**DPL-RC Stage 1 (M6) 차이점**:
- w_i^t = (1/N) · θ' · x_{i,t} (active weight without benchmark explicit, complement = pure overlay)
- L = -E_full[a_t · r_comp | bad_state_1715] + 4 penalty terms
- θ trained on full sample, **bad-state conditional**

→ M3 vs M6 = "conditional learning value-add" 직접 정량화 가능.

PPP framework는 30+ years 학술 backbone (Brandt 2009 + extensions in Lin-Yu-Zhao 2024 등). M3은 DPL-RC value-add 입증 baseline 직접 backbone.
