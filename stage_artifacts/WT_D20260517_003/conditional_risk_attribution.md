# Conditional Risk Attribution — Bad-State vs Good-State Σ Asymmetry

**WT-D20260517_003 · risk-research Step 5.3**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: sigma_estimators_dpl_rc.md + cross_covariance_design.md + alpha_package bad_state_label_3_compare.md + AX-001 v2
**Purpose**: Bad-state subset Σ vs Good-state subset Σ 비대칭 측정 protocol — AX-001 v2 conditional defense evaluation framework backbone

---

## 0. Background — AX-001 v2 conditional defense framework

AX-001 v2 [IMMUTABLE]:
> 방어형 팩터는 **조건부 성과**로 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio). 전기간 SR 기준 적용 금지.

본 risk cycle 은 DPL-RC complement sleeve 가 conditional defense paradigm:
- Bad-state (25-30 sig_dates) 에서 risk profile + alpha 측정
- Good-state (94-99 sig_dates) 에서 risk profile + drag 측정
- **두 state 간 risk asymmetry** = paradigm 효과 정량 입증

→ **AX-001 v2 3-axis (crisis_alpha + MDD + IC ratio) 와 admission 7-axis (axis 4 + axis 2 + axis 7) 1:1 mapping** (alpha_package.json axiom_compliance AX_001_v2 명시).

---

## 1. Bad-state subset identification (alpha-research inherit)

### 1.1. Inherit from alpha cycle

bad_state_label_3_compare.md priors (default expected):
- **Definition 1, x=3% threshold**: 1715 active return < -3% at sig_date t
- Base rate: ~20-25% (124 sig_dates → ~25-30 bad-state sig_dates)

Forge cycle 의무 selection (정확한 label 은 forge cycle empirical 결과).

### 1.2. Bad-state sig_dates (forecast)

**KR 2014-2026 likely bad-state windows** (1715 production retain backtests):
- 2014-Q4 / 2015-Q1 (China shock anticipation)
- 2018-Q2~Q3 (US-China trade)
- 2020-Q1 (COVID-19)
- 2022-Q1~Q3 (rate hike + inflation)
- 2024-Q2 (KR specific stress)

→ 약 25-30 bad-state sig_dates expected.

---

## 2. Bad-state Σ_comp,bad

### 2.1. Estimation protocol

```
bad_sig_dates = {t : bad_state_1715,t = 1}  // ~25-30 sig_dates
good_sig_dates = {t : bad_state_1715,t = 0}  // ~94-99 sig_dates

For complement sleeve stocks (top-K = 20):
  returns_bad = returns matrix [bad_sig_dates, top_K_union]  
  returns_good = returns matrix [good_sig_dates, top_K_union]
  
  Σ_comp_bad = LW_Oracle(returns_bad)
  Σ_comp_good = LW_Oracle(returns_good)
```

**Critical considerations**:
- T_bad = 25-30 → very small sample (N=20 stocks → q=N/T=0.67~0.80, severe high-dim)
- LW Oracle shrinkage 의 α 증가 (sample small → shrink heavy)
- T_good = 94-99 → moderate sample (q=0.20~0.21, well-conditioned)

### 2.2. Top-K membership 합집합 처리

Bad / good 각 subset 의 complement sleeve top-K 가 다를 수 있음 (forge cycle output 의존).

**Protocol**:
- Top-K union: all stocks ever in top-K across 124 sig_dates → universe ~ 30-50 stocks
- Returns matrix 의 column = union universe
- Bad / good subset 마다 returns submatrix
- LW Oracle on submatrix per state

### 2.3. PSD / condition number expectations

| Subset | T | N | q=N/T | Expected LW condition |
|---|---|---|---|---|
| Bad (D=1, x=3) | 27 | 20 (top-K) | 0.74 | ~100-200 (marginal pass, heavy shrinkage) |
| Bad (top-K union) | 27 | 35 (union) | 1.30 | **likely FAIL** (under-determined) |
| Good (D=0) | 97 | 20 (top-K) | 0.21 | ~30-50 (good) |
| Good (top-K union) | 97 | 35 (union) | 0.36 | ~50-80 (acceptable) |

**Risk for bad-state subset**:
- T=27, N=35 (union) → under-determined → 추정 불안정
- **Fallback**: Bad-state Σ 는 admission decision 변수가 아닌 **diagnostic** 으로 약화

---

## 3. Conditional volatility / VaR / CVaR by state

### 3.1. Sleeve-level conditional risk metrics

```
For sleeve s ∈ {1715, comp}:
  σ_s,bad = std(r_s,t for t in bad_sig_dates)
  σ_s,good = std(r_s,t for t in good_sig_dates)
  
  VaR_5_s,bad = empirical 5th percentile of r_s,t in bad subset
  VaR_5_s,good = empirical 5th percentile in good subset
  
  CVaR_5_s,bad = mean of r_s,t below VaR_5 in bad subset
  CVaR_5_s,good = mean of r_s,t below VaR_5 in good subset
```

### 3.2. Comparison protocol

```
Expected pattern:
  σ_1715,bad >> σ_1715,good  (1715 in stress = higher vol)
  σ_comp,bad ≈ σ_1715,bad OR <σ_1715,bad  (complement should NOT amplify bad-state vol)
  
  CVaR_5_blend,bad > CVaR_5_1715,bad  (blend's tail less severe — paradigm value)
  
  Asymmetry index = (σ_bad / σ_good)_1715 vs (σ_bad / σ_good)_comp
  If asymmetry_comp < asymmetry_1715 → complement provides defensive value
  If asymmetry_comp > asymmetry_1715 → complement amplifies bad-state risk → ABORT
```

### 3.3. AX-001 v2 mapping (crisis_alpha)

AX-001 v2 axis 1 (crisis_alpha):
```
crisis_alpha_blend = SR(r_blend in bad_sig_dates) - SR(r_1715 in bad_sig_dates)

Admission axis 4 (bad_state_improvement) ≥ +0.30 SR
↔ crisis_alpha_blend ≥ +0.30

AX-001 v2 axis 1 PASS = admission axis 4 PASS
```

→ **direct 1:1 mapping**.

### 3.4. AX-001 v2 axis 2 (Core 대비 MDD 완화)

```
MDD_blend (full 124 sig_dates) ≥ -24.81% (1715 retain)
↔ admission axis 2 PASS

AX-001 v2 axis 2 PASS = admission axis 2 PASS
```

### 3.5. AX-001 v2 axis 3 (bad/normal IC ratio)

```
For complement scorer:
  IC_bad = rank IC of scorer in bad_state subset
  IC_good = rank IC of scorer in good_state subset
  bad_normal_IC_ratio = IC_bad / IC_good
  
AX-001 v2 axis 3 PASS = bad_normal_IC_ratio ≥ 2.0 (KR empirical L-308 standard, ratio 6.79 정합)
```

**Forge cycle 의무 measurement**: scorer 의 IC by state.

---

## 4. Bad-state subset learning prohibition (코덱스 핵심 수정 정합)

### 4.1. Why subset learning forbidden

Alpha cycle conditional_loss_7axis_admission.md §1.4 explicit:
- **Subset learning** (bad-state 25 sig_dates only): N=25 × 80 features = under-determined, over-fit
- **Full sample + conditional weighting** (본 paradigm): N=124 × 80 features = 1.55:1 ratio

→ 본 risk cycle 도 **bad-state subset 에서 Σ_comp 추정** 시 동일 risk:
- T=25, N=20 → under-determined
- Shrinkage 강하지만 noise inflation 위험

### 4.2. Risk-side protocol 정합

본 risk cycle 의 **subset Σ 측정 목적 = diagnostic only** (admission 변수 X):
- Σ_comp,bad / Σ_comp,good 의 **eigenvalue ratio** diagnostic
- **NOT** 사용 to compute admission Σ (admission Σ = full 124 LW Oracle)

### 4.3. Conditional asymmetry index

```
asymmetry_index = log(trace(Σ_comp_bad) / trace(Σ_comp_good))
  Positive → bad-state higher variance (typical, expected)
  Negative → complement actively reduces variance in bad-state (강한 defensive)
  Near zero → no state asymmetry (paradigm questionable)

Forge cycle measurement.
```

---

## 5. Regime correlation table (1715 vs complement state-dependent)

### 5.1. Conditional cor measurement

```
cor_bad = corr(r_1715, r_comp, sig_dates ∈ bad_state)
cor_good = corr(r_1715, r_comp, sig_dates ∈ good_state)
cor_all = corr(r_1715, r_comp, sig_dates ∈ all)

If cor_bad << cor_all (e.g., cor_bad = -0.2, cor_all = +0.1):
  → strong conditional hedge property in bad state ✓
If cor_bad >> cor_all (e.g., cor_bad = +0.5, cor_all = +0.1):
  → complement amplifies 1715 risk in bad state ✗ (ABORT)
If cor_bad ≈ cor_all:
  → no conditional benefit, simple weighted average ?
```

### 5.2. Regime correlation reporting

```json
{
  "regime_correlation": {
    "cor_pooled_124": "Forge measurement",
    "cor_bad_state": "Forge measurement",
    "cor_good_state": "Forge measurement",
    "cor_bad_minus_good": "Forge measurement (asymmetry, expected negative)",
    "cor_g2_admission": "based on cor_pooled, OOS sample"
  }
}
```

### 5.3. Cor by macro regime (M4 layer)

Beyond bad/good state, 1715 production lineage uses M4 regime engine (BULL/NORMAL/CAUTION/CRISIS):
```
cor_by_m4_regime = {
  "BULL": corr(r_1715, r_comp in m4=BULL sig_dates),
  "NORMAL": corr(r_1715, r_comp in m4=NORMAL sig_dates),
  "CAUTION": corr(r_1715, r_comp in m4=CAUTION sig_dates),
  "CRISIS": corr(r_1715, r_comp in m4=CRISIS sig_dates)
}
```

→ 4-regime correlation matrix 정밀 진단. Forge cycle 의무.

---

## 6. Output protocol

### 6.1. regime_correlation.parquet schema (Forge cycle)

```
schema: data.table
  sig_date | bad_state | m4_regime | r_1715 | r_comp | a_t | r_blend | cor_rolling_24m
  
N rows: 124 sig_dates × 1 = 124
```

### 6.2. conditional_risk_table.json

```json
{
  "conditional_risk_attribution_table": {
    "bad_state": {
      "n_sig_dates": "Forge measurement",
      "sigma_1715_annualized": "Forge measurement",
      "sigma_comp_annualized": "Forge measurement",
      "sigma_blend_annualized": "Forge measurement",
      "var_5_1715_monthly": "Forge measurement",
      "var_5_comp_monthly": "Forge measurement",
      "var_5_blend_monthly": "Forge measurement",
      "cvar_5_1715_monthly": "Forge measurement",
      "cvar_5_comp_monthly": "Forge measurement",
      "cvar_5_blend_monthly": "Forge measurement",
      "cor_1715_comp": "Forge measurement",
      "sigma_comp_subset_lw": {
        "condition_number": "Forge measurement (T=27 N=20 LW heavy shrink)",
        "warning": "subset Σ diagnostic only, NOT admission variable"
      }
    },
    "good_state": {"...similar..."},
    "asymmetry_metrics": {
      "sigma_ratio_1715_bad_good": "...",
      "sigma_ratio_comp_bad_good": "...",
      "cvar_ratio_1715_bad_good": "...",
      "cvar_ratio_comp_bad_good": "...",
      "asymmetry_index_log_trace_ratio": "..."
    },
    "ax_001_v2_mapping": {
      "axis_1_crisis_alpha": "admission axis 4 mapped",
      "axis_2_mdd_alleviation": "admission axis 2 mapped",
      "axis_3_bad_normal_ic_ratio": "Forge IC by state measure"
    }
  }
}
```

---

## 7. PIT compliance audit

### 7.1. C1 (full-sample 통계 금지)

**Critical**: bad/good state subset 추정은 full-sample sig_dates 의 partition.
- **정당화**: state label 은 t-time information 만 사용 (PIT-compliant from alpha cycle)
- Σ_comp,bad estimation 은 historical bad_state sig_dates 만 사용 → no future
- **Admission decision** Σ = full 124 LW Oracle (NOT subset) — proper PIT
- **Diagnostic Σ subset** = bad-state historical patterns, NOT predictive
- Forge cycle 의무: walk-forward purged subset Σ (OOS bad-state sig_dates only per window)

### 7.2. C2 / C9

State label 측정 사용 returns 는 past 또는 t (sig_date close) → no future use.

### 7.3. C14 / C15

IC by state measurement (AX-001 v2 axis 3) 는 Usable_Date <= sig_date strict 의무 (Forge cycle).

---

## 8. Codex Round audit points (예상 challenge)

1. **C-CR1: "Bad-state subset Σ (T=25-30, N=20) 는 under-determined"**
   - 정당화: 본 risk cycle 에서 subset Σ 는 **diagnostic only**, admission Σ X. Admission Σ = full 124 LW Oracle. Codex pre-rebuttal mandate 정합.

2. **C-CR2: "AX-001 v2 axis 3 (bad/normal IC ratio) 측정 protocol 부재"**
   - 정당화: 본 risk cycle design-only. Forge cycle 의무 (scorer IC by state, 5 walk-forward × bad/good aggregated). admission axis 7 (p_bad AUC) 와 별개 metric.

3. **C-CR3: "Bad-state sig_dates 25-30 은 sample insufficient for CVaR estimation"**
   - 정당화: CVaR_5 at 5% percentile → bottom 5% × 25 sig_dates = 1.25 obs → 단일 observation 의 mean. **Sample-size limitation noted**. Forge cycle 의무: bootstrap CI for bad-state CVaR (Pfaff Ch 4 + FRM textbook precedent).

4. **C-CR4: "M4 4-regime cor decomposition 은 sample 더욱 작음"**
   - 정당화: CRISIS regime 일반적으로 ≤ 10 sig_dates → diagnostic only, NOT admission. Forge cycle 의무 report with explicit sample size flag.

5. **C-CR5: "Asymmetry index log(trace ratio) 의 admission threshold 부재"**
   - 정당화: Asymmetry index 는 diagnostic — 본 cycle 명시 threshold X. AX-001 v2 axis 1 (crisis_alpha) 와 axis 2 (MDD) 가 admission. Asymmetry index 는 paradigm validity diagnostic.

---

## 9. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.3 conditional_risk_attribution.md.

**Key deliverables**:
- Bad-state subset Σ_comp,bad protocol (T=25-30, N=20 under-determined caveat noted)
- AX-001 v2 3-axis ↔ admission 7-axis (axis 4 + 2 + 7) 1:1 mapping
- Conditional volatility / VaR / CVaR / cor protocol
- Subset Σ = diagnostic only (admission Σ = full 124 LW Oracle)
- M4 4-regime cor decomposition (Forge cycle, sample-size flag mandate)
- regime_correlation.parquet schema

**Critical principle**: **Subset Σ_bad/good = diagnostic only, NOT admission variable**. Admission Σ = full 124 LW Oracle. Codex 핵심 수정 정합 (under-determined fail mode 차단).

**다음 step**: 5.4 evar_worst_window_protocol.md (DeePM EVaR 정합)
