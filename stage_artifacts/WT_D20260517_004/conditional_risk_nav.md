# Conditional Risk Attribution — NAV-level Bad/Good State (WT-D20260517_004)

**WT-D20260517_004 risk-research Step 5.3**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: risk-research agent
**Date**: 2026-05-17
**Predecessor inherit**: WT-D20260517_003 risk_package.json::conditional_risk_attribution (AX-001 v2 3-axis mapping + bad/good state Σ asymmetry)

---

## 0. Executive Summary (1 paragraph)

Path A NAV-level blend의 conditional risk는 (a) **bad_state subset** (1715 active return < -3%, base rate ~20-25%, 27/91 obs prior)에서 σ_1715,bad / σ_comp,bad / σ_blend,bad + VaR/CVaR by state 측정, (b) **good_state subset**에서 drag asymmetry measurement, (c) **M4 4-regime decomposition** (BULL/NORMAL/CAUTION/CRISIS) cor + σ by regime, (d) **AX-001 v2 3-axis ↔ admission 7-axis 1:1 mapping** (axis 1 crisis_alpha ↔ axis 4 bad_state_improvement / axis 2 MDD ↔ axis 2 / axis 3 bad/normal IC ratio ↔ axis 7 p_bad OOS AUC). Thin-sample (n=25-30 bad, n=≤10 CRISIS) 의무 **Politis-Romano 1994 stationary bootstrap CI B=1000**. Subset Σ는 **diagnostic only NOT admission variable** (T=25-30, N=20 under-determined). Admission Σ는 full 124 LW Oracle.

---

## 1. Bad/good state definition (alpha cycle inherit)

### 1.1 Default: Definition 1 (`def1_x3`)

```r
bad_state_t <- (active_return_1715[t] < -0.03)
# base_rate ≈ 0.2967, expected n_bad ≈ 27 / 91 OOS
```

alpha cycle `bad_state_label_3_compare.md` 산출(v3 inherit `bad_state_label_selected.json`).

### 1.2 Alternative definitions (Forge cycle sensitivity)

| Label | Definition | Base rate prior |
|---|---|---|
| def1_x3 ★ default | 1715 active ret < -3% | 0.2967 |
| def2_x5 | 1715 active ret < -5% | 0.1467 |
| def3_quartile | 1715 active ret < q25 | 0.25 |
| def4_dd_5m | 1715 rolling 5m DD < -5% | 0.20 |

**사후 label tuning 차단** (Charter §8 No Silent Override). default = def1_x3 retain.

---

## 2. Conditional risk measurement protocol

### 2.1 Subset Σ by state

```r
# bad state subset Σ
bad_idx <- which(active_return_1715 < -0.03)  # length ≈ 27/91 prior
returns_comp_bad <- returns_comp[bad_idx, ]  # T_bad × N

Sigma_comp_bad <- corpcor::cov.shrink(returns_comp_bad)  # LW Oracle subset
# T_bad ≈ 27, N=20 → ratio 1.35 — under-determined → heavy LW shrinkage

# good state subset (T_good ≈ 94)
good_idx <- which(active_return_1715 >= -0.03)
Sigma_comp_good <- corpcor::cov.shrink(returns_comp[good_idx, ])
```

**Subset Σ role**: **diagnostic only NOT admission variable** (v3 Codex C5 정합 — subset learning fail mode 차단). Admission Σ는 full 124 LW Oracle.

### 2.2 Conditional metrics protocol

| Metric | Computation | Role |
|---|---|---|
| σ_1715,bad / σ_1715,good | bad/good subset std dev of monthly returns | diagnostic |
| σ_comp,bad / σ_comp,good | sqrt(diag(Σ_comp_bad)) avg | diagnostic |
| σ_blend,bad / σ_blend,good | (1-a)²·σ²_1715,bad + a²·σ²_comp,bad + 2a(1-a)ρ_bad·σ_1715,bad·σ_comp,bad sqrt | diagnostic |
| VaR_5,blend,bad | empirical 5% quantile of blend returns bad subset | diagnostic |
| CVaR_5,blend,bad | mean of bottom 5% blend returns bad subset | **alpha cycle loss term** |
| CVaR_95,blend,bad | mean of bottom 5% blend returns bad subset (alarm) | **admission alarm RF-R6** |
| cor_bad / cor_good / cor_pooled | bad/good subset cor + difference | diagnostic |
| asymmetry_index | log(trace(Σ_comp_bad) / trace(Σ_comp_good)) | diagnostic |

### 2.3 Bootstrap CI mandate (Politis-Romano 1994 JASA)

```r
ci_sigma_bad <- politis_romano_bootstrap(returns_comp_bad, FUN = "std_dev", B = 1000, level = 0.95)
ci_cvar_bad <- politis_romano_bootstrap(returns_comp_bad, FUN = "cvar_5", B = 1000, level = 0.95)
# ...
```

**DEFER trigger**: `if (ci_width > 1.5 × point_estimate) DEFER` (sample-size insufficient for admission).

---

## 3. AX-001 v2 3-axis ↔ admission 7-axis mapping

### 3.1 AX-001 v2 (from `qepm/memory/axioms/active/AX-001.json`)

**Conditional defense factor evaluation** (3 axes):
1. **Crisis alpha** (bad-state outperform Core)
2. **MDD alleviation** (lower max drawdown vs Core)
3. **Bad/normal IC ratio** (≥ 2.0 standard, KR L-308 ratio 6.79)

### 3.2 Path A NAV-level mapping (1:1)

| AX-001 v2 axis | Admission 7-axis (alpha cycle) | Risk-side computation |
|---|---|---|
| axis 1 crisis_alpha | **axis 4** (bad_state_improvement ≥ +0.30 SR) | r_blend in bad_state vs r_1715 in bad_state, SR diff ≥ +0.30 |
| axis 2 mdd_alleviation | **axis 2** (MDD ≥ -24.81% no worse) | NAV_blend MDD vs NAV_1715 MDD |
| axis 3 bad/normal_IC_ratio | **axis 7** (p_bad OOS AUC ≥ 0.55) + Forge cycle IC by state | scorer IC by state, target ≥ 2.0 |

### 3.3 KR L-308 정합 인용

L-308 Layer 5 R05 sequential overlay admit: bad/normal IC ratio = **6.79** (well over 2.0 standard). Path A NAV-level 신청 시 동급 expectation (≥ 2.0 minimum).

---

## 4. M4 4-regime decomposition

### 4.1 M4 regime engine inherit (production)

```r
m4_regime_t <- bocpd_m4_engine(t)  # ∈ {BULL, NORMAL, CAUTION, CRISIS}
```

production 1715 5-Layer는 M4 BOCPD regime engine 기반(L-274). DPL-RC paradigm은 추가 M4 4-regime cor decomposition diagnostic 측정.

### 4.2 Per-regime metrics

```r
for (regime in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  idx <- which(m4_regime == regime)
  cor_regime[regime] <- cor(r_1715[idx], r_comp[idx])
  sigma_blend_regime[regime] <- compute_blend_sigma(a, idx)
  evar_regime[regime] <- compute_evar(r_blend[idx], alpha = 0.10)
}
```

### 4.3 CRISIS regime sample-size caveat

**CRISIS regime n typical ≤ 10 sig_dates** (production L-308 evidence). Bootstrap CI 의무 + `if (n_regime < 5) UNAVAILABLE flag` (v3 RF_R8 inherit).

### 4.4 Regime transition matrix (Hamilton 1989 Econometrica)

```r
trans_mat <- table(m4_regime[-length(m4_regime)], m4_regime[-1])
trans_mat_prob <- trans_mat / rowSums(trans_mat)
# Persistence diagnostic: P(state_t+1 == state_t)
```

---

## 5. Thin-sample handling

### 5.1 Expected sample sizes (학술 prior, NOT measured)

| State / Regime | n estimated | Subset Σ stability |
|---|---|---|
| bad_state def1_x3 | 25-30 / 124 | T/N ≈ 1.3-1.5, heavy LW shrinkage |
| good_state def1_x3 | 94-99 / 124 | T/N ≈ 4.7-5.0, stable |
| CRISIS regime | ≤ 10 / 124 | T/N ≈ 0.5, **UNAVAILABLE** likely |
| CAUTION regime | 10-20 / 124 | T/N ≈ 0.5-1.0, heavy shrinkage |
| NORMAL regime | 60-80 / 124 | T/N ≈ 3-4, stable |
| BULL regime | 20-30 / 124 | T/N ≈ 1-1.5, moderate |

### 5.2 Fail action protocol

```
if (n_subset / N < 1.0) → subset Σ UNAVAILABLE flag
if (1.0 ≤ n_subset / N < 2.0) → heavy LW + bootstrap CI mandate
if (n_subset / N ≥ 2.0) → standard LW
```

### 5.3 Admission variable rules

- **Admission Σ**: full 124 LW Oracle (T=60 rolling × 124 sig_dates) — sample size 충분
- **Subset Σ**: diagnostic only, bootstrap CI mandate
- **Subset SR/CVaR**: admission contribute only with bootstrap CI within DEFER threshold

---

## 6. Conditional metrics output schema

```json
{
  "bad_state_def1_x3": {
    "n_obs": 27,
    "sigma_1715_bad": 0.305,
    "sigma_comp_bad": 0.34,
    "sigma_blend_bad_a010": 0.288,
    "cor_bad_pooled": 0.42,
    "cvar_5_blend_bad": -0.085,
    "cvar_95_blend_bad": -0.062,
    "bootstrap_ci_95_sigma_1715_bad": [0.27, 0.34],
    "bootstrap_ci_95_cvar_5_blend_bad": [-0.11, -0.06]
  },
  "good_state": { /* ... */ },
  "m4_regime_decomp": {
    "BULL": {"n": 28, "cor": 0.32, "sigma_blend": 0.18, "evar_010": -0.054},
    "NORMAL": {"n": 71, "cor": 0.45, "sigma_blend": 0.19, "evar_010": -0.062},
    "CAUTION": {"n": 17, "cor": 0.51, "sigma_blend": 0.24, "evar_010": -0.092},
    "CRISIS": {"n": 8, "cor": "UNAVAILABLE_n<10", "sigma_blend": "UNAVAILABLE", "evar_010": "UNAVAILABLE"}
  },
  "asymmetry_index_comp": 0.31,
  "ax_001_v2_three_axis_mapping": {
    "axis_1_crisis_alpha_sr_diff": 0.34,
    "axis_2_mdd_alleviation_pct": -0.225,
    "axis_3_bad_normal_ic_ratio": 2.4
  }
}
```

---

## 7. Forge cycle measurement mandate

| Metric | Output |
|---|---|
| bad/good state subset Σ + CVaR + EVaR by sleeve | per-state JSON + bootstrap CI |
| M4 4-regime cor + σ + EVaR | 4-regime JSON + caveat for n<10 |
| asymmetry_index | scalar |
| transition matrix Hamilton 1989 | 4×4 prob matrix + persistence |
| AX-001 v2 3-axis empirical | 1:1 admission mapping report |
| bad/normal IC ratio (scorer) | Forge cycle Stage 1-4 incremental |

---

## 8. Codex round (v3) C5 PARTIAL_ACCEPT 정합

v3 Codex C5:
- thin-sample bootstrap CI mandate
- subset Σ → diagnostic only NOT admission variable

Path A inherit. + alpha cycle bad_state_label inherit (def1_x3 default, 사후 tuning 차단).

---

## 9. Charter 정합

- **AX-001 v2**: 3-axis ↔ admission 7-axis 1:1 mapping (axis 1↔4, axis 2↔2, axis 3↔7)
- **AX-002 PIT**: subset Σ는 t-1 lag returns 사용 (C2), purge/embargo 정합
- **Common Charter Principle 5 (Data Mining 방지)**: 사후 label tuning 차단, default def1_x3 retain
- **Common Charter Principle 8 (No Silent Override)**: 모든 subset metric bootstrap CI 의무, UNAVAILABLE flag explicit

---

## 10. RF-R8 regime monitoring (v3 inherit)

```json
{
  "regime_n_by_state": "BULL n? / NORMAL n? / CAUTION n? / CRISIS n? + bootstrap CI per state",
  "regime_switch_rate": "transition matrix + persistence Hamilton 1989",
  "fail_action": "if any state n < 5 → regime-specific risk diagnostic UNAVAILABLE flag",
  "design_only_note": "Forge cycle measurement mandate"
}
```

---

## 11. Forge cycle compute estimate

| Step | Compute |
|---|---|
| Subset Σ bad/good × LW Oracle | ~0.3h CPU |
| Bootstrap CI B=1000 per metric (10 metrics) | ~1h CPU |
| M4 4-regime decomposition | ~0.5h CPU |
| Asymmetry index + transition matrix | trivial |
| **Total** | **~2h CPU** |

---

**End of artifact**. Step 5.4 (EVaR worst-window + crowding NAV-level) 작성 진행.
