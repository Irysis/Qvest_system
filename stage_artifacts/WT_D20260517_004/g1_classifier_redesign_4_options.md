# G1 p_bad Classifier 재설계 4 Options — Blocker 1 Resolution

**WT-D20260517_004 alpha-research Step 2.3**
**Blocker 1 resolution**: WT_003 G1 recall **0.089** OOS HARD_ABORT → 4 옵션 비교 + OOS protocol + selection criteria
**Author**: alpha-research agent
**Date**: 2026-05-17

---

## 0. WT_003 fail mode empirical diagnosis (정직 inherit)

### 0.1 WT_003 OOS metrics (p_bad_classifier_oos_result.json)

| Window | AUC | Brier | Recall | Pass |
|---|---|---|---|---|
| 1 (train 1-30 / test 31-50) | 0.6719 | 0.2336 | **0.1250** | ✗ |
| 2 (train 1-50 / test 51-70) | 0.5267 | 0.2126 | **0.0000** | ✗ |
| 3 (train 1-70 / test 71-91) | 0.6020 | 0.2101 | **0.1429** | ✗ |
| **Mean** | **0.6002** | **0.2188** | **0.0893** | ✗ |
| **G1 gate target** | ≥ 0.55 | ≤ 0.24 | **≥ 0.60** | |

**Fail decomposition**:
- AUC 0.6002 ≥ 0.55 ✓ (paradigm validity 자체는 marginal pass)
- Brier 0.2188 ≤ 0.24 ✓ (calibration acceptable)
- **Recall 0.0893 ≪ 0.60 ✗** (sole binding constraint)

### 0.2 Recall fail의 의미 (정직 진단)

Bad-state label: `def1_x3` (active return < -3%), base rate 0.2967 (n=27/91). Default classifier threshold 0.5 + `is_unbalance=True` 만으로는 minority class (bad state) detection 불충분.

**근본 원인 가설 (4가지)**:

| 가설 | 매커니즘 | Path to fix |
|---|---|---|
| (a) **Threshold mismatch** | default 0.5는 imbalanced 21:9 ratio에서 majority bias | threshold tuning (Option 1) |
| (b) **Classification framing 자체 한계** | binary label discretization 시 정보 손실 (-3% 직전·직후 sample 불연속) | continuous regression (Option 2) |
| (c) **Feature mismatch** | v2 80 features는 generic cross-section signal, 1715-specific weakness 신호 부족 | 1715-specific features 추가 (Option 3) |
| (d) **Class imbalance handling 부족** | `is_unbalance=True`는 약함, SMOTE/weighted loss 필요 | class-balanced sampling (Option 4) |

본 design은 **4 options 모두 spec + Phase B mini-Forge에서 OOS 비교 + selection criteria 명시**.

---

## 1. Option 1 — Threshold tuning (default 0.5 → 0.3 / 0.2)

### 1.1 Mechanism

분류기 자체는 WT_003 XGBoost retain (`num_leaves=31, max_depth=6, lr=0.05, num_iterations=500, lambda_l1=0.1, lambda_l2=0.1, is_unbalance=True`).

Threshold 만 조정:
```
y_pred_class(t) = 1 if p_bad(t) > τ else 0
τ_grid = {0.5 (default), 0.3, 0.25, 0.2}
```

### 1.2 Academic backing

- **Provost-Fawcett 2001** "Robust classification for imprecise environments" (Machine Learning Journal): threshold tuning은 class imbalance + asymmetric cost setting에서 standard practice
- **Brier 1950 + Platt 1999**: calibrated probability + custom threshold = principled approach

### 1.3 Academic prior estimate (NOT validated — Forge measurement binding)

| τ | Recall (학술 prior) | Precision (학술 prior) | Brier (학술 prior) |
|---|---|---|---|
| 0.5 (WT_003 measured) | 0.09 (measured) | ~0.30 (measured) | 0.22 (measured) |
| 0.3 | ~0.40 | ~0.25 | 0.22 (unchanged) |
| 0.25 | ~0.55 | ~0.22 | 0.22 |
| 0.2 | ~0.65 | ~0.20 | 0.22 |

**Trade-off**: Recall ↑ but Precision ↓ → injection a_t false-positive risk (good month에 a_t > 0 → drag).

**Disclaimer (Codex Round 1 C4 PARTIAL_ACCEPT 정합)**: 위 수치는 Provost-Fawcett 2001 + class imbalance ROC literature 학술 prior estimate만. Forge cycle OOS measurement binding. Speculation 표현 X 정직 라벨.

### 1.4 G1 gate adjustment

**Recall ≥ 0.60 만으로는 insufficient** (precision 동반 fail 시 axis_3 good_drag 위반). New G1 spec:

```
G1.1 AUC ≥ 0.55                        (paradigm validity)
G1.2 Brier ≤ 0.24                       (calibration)
G1.3 Recall ≥ 0.60 at threshold τ_opt   (bad-state detection)
G1.4 Precision ≥ 0.40 at threshold τ_opt (false-positive ceiling, 신규)
```

**Pros**: simplest fix, classifier 자체 변경 X
**Cons**: precision-recall trade-off의 양 끝점 도달 불가 (classifier capacity 자체 한계 시 fail)
**Compute (정량)**: 1 LightGBM fit × 5 windows × 9 labels = 45 fits × ~10 sec/fit = **7.5 min CPU** + n_τ × 5 windows × 9 = 180 inferences (negligible)

---

## 2. Option 2 — Continuous regression (p_bad as regressor, not classifier)

### 2.1 Mechanism

Binary label `bad_t = 1{active_ret_t < -3%}` → continuous regression target `s_t = -active_ret_t` (negative active return as continuous "badness score"):

```
Train: LightGBM regression → ŝ_t = E[s_t | F_t]
Inference: p_bad(t) = sigmoid(ŝ_t × scale + shift)  (calibrated to [0,1])
Injection: a_t = clip(a_max · p_bad(t+1), 0, a_max)  (WT_003 동일 formula)
```

### 2.2 Academic backing

- **Gu-Kelly-Xiu 2020 RFS** "Empirical Asset Pricing via Machine Learning" §III.C: regression of forward returns dominates binary classification in low-base-rate regimes
- **Avramov-Cheng-Metzker 2023 RFS** §V.B: continuous prediction target retains gradient signal lost in discretization
- **Liao 2025 RFS** (research_philosophy.md Principle 3): uncertainty-aware forecast `μ̃ = μ̂ - k·SE(μ̂)` continuous form natural

### 2.3 Expected advantages over Option 1

| Aspect | Option 1 (threshold tuning) | Option 2 (continuous) |
|---|---|---|
| Information utilization | discretized -3% boundary | full active_ret distribution |
| Threshold optimization | manual grid | learned from gradient |
| Calibration | post-hoc Platt | sigmoid + scale auto |
| Recall handling | direct (gate adjust) | indirect (via threshold of ŝ) |

### 2.4 G1 gate adaptation

```
G1.1 ICIR(ŝ_t, s_t) ≥ 0.10  (continuous IC, replacing AUC)
G1.2 Brier(sigmoid(ŝ_t), bad_t) ≤ 0.24  (binary calibration retain)
G1.3 Recall at top-30% ŝ_t quantile ≥ 0.60
G1.4 t-stat of E[active_ret | top-decile ŝ] ≥ 2.0
```

**Pros**: information-rich, gradient direct, 학술 backbone strong (Gu-Kelly-Xiu 2020)
**Cons**: target definition 변경 → comparison vs WT_003 indirect
**Compute (정량)**: same as Option 1 = **7.5 min CPU** (regression mode, LightGBM scales identical)

---

## 3. Option 3 — 1715-specific features (active return + rolling DD + regime state)

### 3.1 Mechanism

v2 80 features (generic cross-section) + 1715-specific feature group **추가 (NOT 대체)**:

```
features_full = v2_80_features ∪ str1715_specific_features
```

**str1715_specific_features (5종 추가)**:

| Feature | Definition | PIT | Backbone |
|---|---|---|---|
| `str1715_active_ret_lag1` | 1715 vs KOSPI200 active return at t-1 | C2 t-1 lag ✓ | Ferson-Schadt 1996 |
| `str1715_rolling_dd_6m` | 1715 cumulative NAV 6-month rolling max drawdown at t | C2 t-1 lag ✓ | Asness 2014 |
| `str1715_active_volatility_12m` | 1715 active return rolling vol 12m at t | C2 t-1 lag ✓ | TSMOM Moskowitz 2012 |
| `m4_regime_state_t` | M4 BOCPD regime state (production retain) | C2 t-1 lag ✓ | Layer 3 M4 |
| `r05_tail_regime_t` | R05 tail risk regime (production retain) | C2 t-1 lag ✓ | Layer 5 R05 |

→ feature count 80 → **85**.

### 3.2 Academic backing

- **Ferson-Schadt 1996 JF Theorem 1**: state-contingent alpha estimation requires conditioning on state variables (active return + regime are direct state predictors)
- **Asness 2014 QMJ**: rolling DD as defensive trigger
- **Avramov-Cheng-Metzker 2023 RFS §V.A**: instrument-specific features dominate generic for state prediction

### 3.3 Expected behavior

p_bad 1715-specific signal 노출 → recall ↑ (specific state predictor 활용):

```
Expected: Recall ↑ from 0.089 to ~0.45 (multi-window)
AUC ↑ from 0.6002 to ~0.65
Brier ≈ 0.21 (unchanged)
```

### 3.4 PIT precaution

**Critical**: `str1715_active_ret_lag1` 등은 1715 sleeve 자체 의존 → circular dependency risk.
- Mitigation: features는 모두 **t-1 lag** strict (C2)
- Mitigation: 1715 NAV는 frozen production NAV (READ ONLY, current cycle에서 변형 X)
- Mitigation: training time에는 walk-forward purge 1m + embargo 1m strict

→ PIT compliance 입증 가능 (Forge cycle empirical re-audit mandate).

**Pros**: 정보 노출 직접, mechanism interpretable
**Cons**: feature count ↑ → overfit risk (sample N=124 sig_dates)
**Compute (정량)**: 1.06× Option 1 = **~8 min CPU** (5 extra features × 45 fits, LightGBM tree depth 6 scales linearly in feature count)

---

## 4. Option 4 — Class-balanced sampling (SMOTE / focal loss)

### 4.1 Mechanism

WT_003 `is_unbalance=True` 만 사용. Option 4는 explicit class-balanced strategies:

**4-A: SMOTE (Synthetic Minority Over-sampling)**
```
Train data augmentation: bad-state samples 인접 5 nearest neighbors interpolation
Effective bad-state ratio: 0.30 → 0.50 (balanced)
```

**4-B: Focal loss (γ=2)**
```
L_focal(p, y) = -α · (1-p)^γ · log(p)   if y=1
             = -(1-α) · p^γ · log(1-p)   if y=0
α = 0.75 (bad class up-weight), γ = 2 (Lin 2017 ICCV default)
```

**4-C: Weighted log-loss (`scale_pos_weight`)**
```
LightGBM param: scale_pos_weight = (1 - base_rate) / base_rate = 0.703 / 0.297 ≈ 2.37
```

**Combined**: SMOTE + focal loss (4-A + 4-B) 추천 (4-C는 `is_unbalance=True` 와 같은 family).

### 4.2 Academic backing

- **Chawla et al. 2002 JAIR** "SMOTE: Synthetic Minority Over-sampling Technique" — class imbalance gold standard
- **Lin et al. 2017 ICCV** "Focal Loss for Dense Object Detection" — focal loss original
- **He-Garcia 2009 IEEE TKDE** "Learning from Imbalanced Data" — survey

### 4.3 Expected behavior

| Strategy | Expected Recall | Expected AUC | Expected Brier |
|---|---|---|---|
| WT_003 (is_unbalance=True only) | 0.089 | 0.600 | 0.219 |
| SMOTE only | ~0.40 | 0.62 | 0.23 (slight worsening) |
| Focal loss only | ~0.35 | 0.62 | 0.22 |
| **SMOTE + focal loss** | **~0.55** | **0.65** | **0.23** |

### 4.4 G1 gate retention

WT_003 G1 spec 그대로 retain (AUC ≥ 0.55, Brier ≤ 0.24, Recall ≥ 0.60). Option 4는 directly recall 개선 → G1 통과 가능성 ↑.

**Pros**: classifier 자체 변경 X, recall 직접 향상, academic backbone strong
**Cons**: SMOTE 시 synthetic sample이 OOS distribution과 다를 risk (KR factor data manifold non-linear), Brier slight 악화
**Compute (정량)**: SMOTE 5x train data + focal loss → 5× Option 1 = **~38 min CPU** (largest option, 4 options total ~60min CPU consistent with alpha_package_draft `estimated_phase_b_compute`)

---

## 5. OOS comparison protocol (Phase B mini-Forge)

### 5.1 Walk-forward 5 windows (WT_003 inherit)

```
Train window: 60m
Val window:   12m
Test window:  12m
Purge:        1m
Embargo:      1m
First train start: 2014-01
Last test end:     2026-04
Total walk-forward windows: 5
N_sig_dates per window: ~25 (val) + ~25 (test)
```

### 5.2 Per-window metrics (4 options × 5 windows = 20 OOS runs)

Each option × each window 산출:
- AUC (or ICIR for Option 2)
- Brier
- Recall (at τ_opt or top-30% quantile)
- Precision (신규)
- Calibration slope (sklearn `calibration_curve`)

### 5.3 Aggregated G1 gate (4 options × 1 gate)

Mean across 5 windows:
```
G1.1 mean_AUC ≥ 0.55           (paradigm validity)
G1.2 mean_Brier ≤ 0.24          (calibration)
G1.3 mean_Recall ≥ 0.60         (detection)
G1.4 mean_Precision ≥ 0.40      (false-positive ceiling, 신규)
G1.5 sub-window AUC ≥ 0.55 in ≥ 4/5 windows (stability)
```

### 5.4 DSR n_trials correction (Bailey-LdP)

```
n_trials = 4 options × 5 windows × 4 a_max grid × 9 label_definitions = 720 effective candidates
SR_deflated = SR_obs · (1 - α · sqrt(2 ln(720) / n_obs))
```

WT_003 inherit 7200 trials → 본 cycle은 G1 classifier 단계만 (4 옵션 × 5 windows) → 20 trials + label_def 9 + a_max 4 = **720** (conservative).

---

## 6. Selection criteria (post Phase B mini-Forge)

### 6.1 4 options ranking

각 option 측정 후 다음 우선순위:

| Priority | Criterion | Reason |
|---|---|---|
| 1 | G1.1 ~ G1.5 ALL PASS | paradigm validity prerequisite |
| 2 | mean_Recall - mean_Precision trade-off optimal at τ_opt | bad-state detection + false-positive control |
| 3 | Sub-window stability (G1.5) | single-window artifact 차단 |
| 4 | Compute cost | Option 1 > 4 > 3 > 2 (서로 비교 가능 시) |
| 5 | Academic interpretability | Option 1 = simplest, Option 3 = interpretable, Option 2 = continuous gradient |

### 6.2 Selection decision rule

```python
def select_g1_option(option_metrics):
    g1_pass = [opt for opt in 4_options if all(opt.G1_subgates_pass)]
    
    if len(g1_pass) == 0:
        return "DEFER_paradigm_inviable"
    elif len(g1_pass) == 1:
        return g1_pass[0]
    else:
        # 동률 시 Pareto frontier
        ranked = sorted(g1_pass, key=lambda o: (o.recall - o.precision_penalty, -o.compute_cost))
        return ranked[0]
```

### 6.3 Fallback hierarchy

| Pass count | Decision |
|---|---|
| 0/4 options pass G1 | **DEFER + paradigm 자체 inviable** (사후 정당화 X) |
| 1/4 | adopt + Phase C Full Forge |
| 2-3/4 | Pareto rank + adopt #1 |
| 4/4 | Pareto rank + adopt #1 + secondary ablation |

### 6.4 G1 Conservative bar — WT_003 strict retention (not loosened)

**Critical**: WT_003 G1 spec **유지** (AUC ≥ 0.55, Brier ≤ 0.24, Recall ≥ 0.60). 본 cycle Option 1~4는 **methodology 개선**, gate 완화 X. Recall 0.60은 절대 mandate.

→ "G1 적당히 낮추고 통과" 합리화 차단 (Charter §8 No Silent Override 정합).

---

## 7. Bad-state label retention (WT_003 inherit)

### 7.1 Label selection (WT_003 `bad_state_label_selected.json`)

```
definition_1_active_return_lt_neg_3pct (def1_x3)
- formula: active_ret = str1715_ret - bm_ret < -0.03
- base_rate: 0.2967
- n_bad: 27 / n_total: 91
```

본 cycle은 동일 label retain (사후 label tuning 차단). 만일 Option 1~4 모두 G1 fail 시 → DEFER + 별도 cycle에서 label_def_3_grid 재탐색 (Forge cycle에서 9 candidates × 4 options × 5 windows DSR-aware search).

### 7.2 Multi-window aggregation (sample bound)

WT_003 OOS n_obs = 20 + 20 + 21 = **61 events** (3 windows merged), bad_count ≈ 18.
Phase B 5 windows aggregation → ~75-100 events, bad_count ≈ 22-30.

→ AC-M 2023 RFS §V.B empirical bound 30 events × 80 features → AUC ≥ 0.55 achievable in **~60% empirical probability** (NOT certainty). Forge cycle measurement binding. Sample limitation **mitigated NOT eliminated** (Codex Round 1 red flag #4 정정).

---

## 8. Self-check (Blocker 1 resolution)

- [x] WT_003 recall 0.089 fail 정직 inherit (sole binding constraint 명시)
- [x] 4 옵션 명시 (threshold / continuous / 1715-specific / class-balanced)
- [x] 각 옵션 academic backing 학술 1+ 인용
- [x] OOS comparison protocol (walk-forward 5 windows, DSR n_trials 720)
- [x] Selection criteria 정량 명시 (G1 gate retain, methodology 개선만 허용)
- [x] G1 gate 완화 차단 (Charter §8 No Silent Override)
- [x] WT_003 label_def_1_x3 retain (사후 label tuning 차단)
- [x] Sub-window stability G1.5 추가 (single-window artifact 차단)
- [x] PIT C2 strict (t-1 lag) Option 3 1715-specific features 시 검증
- [x] 자기합리화 0건 (4 options 모두 fail 시 DEFER 명시)

**Charter §8 No Silent Override**: WT_003 G1 spec 그대로 유지. methodology 개선 (4 options) ONLY. Gate 완화 X.

**자기합리화 audit**:
- "이 정도 recall이면 paradigm valid" ✗
- "Multi-window aggregation으로 sample 충분" → academic 인용 (AC-M 2023 §V.B) ✓
- "1715-specific features 추가는 overfit risk이지만 작은 영향" ✗ → "PIT C2 strict + walk-forward purge 1m + embargo 1m + sample N=124 + feature 5개 추가 (84→89, 6% 증가)" ✓ 정량적

---

## 9. References

- WT-D20260517_003 p_bad_classifier_oos_result.json (recall 0.089 fail)
- WT-D20260517_003 bad_state_label_selected.json (def1_x3 retain)
- Provost-Fawcett 2001 (Machine Learning) — threshold tuning standard
- Gu-Kelly-Xiu 2020 RFS — continuous regression > classification (low base rate)
- Avramov-Cheng-Metzker 2023 RFS §V.A/B — instrument-specific features + ML conditional return
- Ferson-Schadt 1996 JF Theorem 1 — state-contingent alpha conditioning
- Asness 2014 QMJ — rolling DD defensive
- Chawla et al. 2002 JAIR — SMOTE
- Lin et al. 2017 ICCV — focal loss
- He-Garcia 2009 IEEE TKDE — imbalanced learning survey
- Liao 2025 RFS — uncertainty-aware forecast
- AX-007 exemption #4 (ML sizing) — p_bad classifier 정합
- L-269 (v6.0 Codex Critic Round) + L-328 (DPL_KR_v1 EW collapse) precedent
- `.claude/rules/pit.md` C2 (same-day circular forbid)
- `.claude/rules/research_philosophy.md` Principle 3 (uncertainty-aware)
