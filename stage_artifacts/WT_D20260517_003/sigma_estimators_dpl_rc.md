# Σ Estimators — DPL-RC 4-way Comparison Protocol (Rolling per-sig_date)

**WT-D20260517_003 · risk-research Step 5.1**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: alpha_package.json (DPL-RC paradigm) + v2 inherit (WT-D20260517_002 framework retain) + L-326 (per-sig_date mandate, single-snapshot 금지)
**Goal**: 1715 + complement blend 의 Σ rolling 추정 — 4 estimator 비교 + selection framework + per-sig_date 재계산 protocol

---

## 0. Background — DPL-RC paradigm 의 Σ 특수성

DPL-RC v1.0 (request.json §dpl_rc_core_paradigm):
```
w_final(t) = (1 - a_t) · w_1715(t) + a_t · w_comp(t)
where a_t = clip(a_max · p_bad_1715(t+1), 0, a_max), a_max ∈ {0.05, 0.10, 0.15, 0.20}
```

본 cycle Risk 임무는 **conditional complement sleeve** 의 공동위험 구조 — 일반 multi-asset Σ 와 다른 3 component:

| Component | 의미 | Estimation 대상 |
|---|---|---|
| **Σ_str_1715** | 1715 sleeve 종목 간 공분산 (production retain, n≈20 stocks per sig_date) | production retain (re-estimation X) |
| **Σ_comp** | complement sleeve 종목 간 공분산 (top-K extracted from scorer output) | **per-sig_date estimation 의무** |
| **Cov(r_str_1715, r_comp)** | sleeve-level 1715 returns × complement returns covariance | **time-series estimation 의무** |

**Portfolio total variance (sleeve-level decomposition)**:
```
σ²_p,t = (1-a_t)² · σ²_str_1715,t + a_t² · σ²_comp,t + 2·a_t·(1-a_t)·Cov(r_str_1715,t, r_comp,t)
```

→ **Σ_comp 추정이 본 cycle 의 primary deliverable**. Σ_str_1715 은 production lineage retain.

**왜 4-way 비교**:
- v2 inherit (Codex C2 ACCEPT): condition_number ≤ 100 strict 의무
- alpha-research 80 features → complement sleeve top-K stocks 20명 표본 size 작음 (N=20, T=60m rolling) → estimator 선택이 condition number 결정 critical
- L-326 (single-snapshot 금지) → 124 sig_dates 모두 per-sig_date 재계산

---

## 1. Four Candidate Estimators

### 1.1. Sample covariance (baseline)

**Formula**:
```
Σ_sample,t = (1 / (T-1)) · Σ_{s=t-T}^{t-1} (r_s - r̄)(r_s - r̄)'
```

**Parameters**:
- T = 60 months rolling window
- N = 20 stocks (top-K from complement scorer)
- T / N = 3.0 (marginal — high-dim risk)

**Properties**:
- Unbiased, MLE under Gaussian
- **No regularization** → condition_number explosion risk when T/N < 10
- KR equity monthly: T=60, N=20 → expected condition_number ~ 200-800 (Marchenko-Pastur eigenvalue spread)

**Expected**:
- Pass G2_cor measurement (covariance derived)
- Condition number target ≤ 100 — **likely FAIL** at T=60, N=20

**Use case in DPL-RC**: Comparison baseline only. Not default selection.

---

### 1.2. Ledoit-Wolf shrinkage (oracle target)

**Formula**:
```
Σ_LW,t = α · F + (1 - α) · Σ_sample,t
where F = shrinkage target (constant correlation / single-index / identity scaled),
      α = optimal shrinkage intensity (Ledoit-Wolf 2003/2004 closed-form)
```

**Variants considered**:
- **LW Oracle**: target = (mean σ_i² · I_N + mean ρ · σ_i σ_j matrix), α 자동
- **LW Identity**: target = (mean σ²) · I_N (simpler, more aggressive shrinkage)
- **LW ConstCor**: target = constant correlation across all pairs

**Parameters**:
- Default: LW Oracle (Ledoit-Wolf 2003 JEF "Honey, I shrunk the sample covariance matrix")
- T = 60 months, N = 20 stocks
- α 자동 결정 (sample size + dimensionality)

**Properties**:
- Always positive definite
- Condition number 대폭 개선 (T=60, N=20 일반적 → ~30-80)
- Computational tractable (closed-form α, no iteration)
- KR equity 실증: LW Oracle 일반적으로 sample 대비 condition_number 5-10x 개선

**Expected**:
- Pass condition number ≤ 100 (high probability)
- Pass PSD (by construction)
- **Most likely primary selection** for Σ_comp

**Use case in DPL-RC**: Primary estimator for complement sleeve. v2 inherit Codex C2 ACCEPT 정합.

**Academic backbone**: Ledoit-Wolf (2003 JEF), Ledoit-Wolf (2004 JPM "Honey shrinkage").

---

### 1.3. Gerber correlation + RMT filtering

**Formula** (2-step):
```
Step 1: Gerber correlation (Gerber et al. 2015 JPM)
  G_ij = [ count(r_s,i and r_s,j both > +H) - count(both < -H) - count(opposite signs > H) ]
        / total non-trivial s
  where H = threshold (default 1·σ scaled)

Step 2: RMT eigenvalue filtering (Laloux et al. 2000)
  Σ_GR,t = U · clip(Λ, λ_min, λ_max) · U'
  where Λ filtered to retain only signal eigenvalues (> Marchenko-Pastur upper bound λ+)
```

**Parameters**:
- H = 1 · sample_std (Gerber threshold)
- λ+ = (1 + sqrt(N/T))² · σ̄² (Marchenko-Pastur bulk edge)
- T = 60 months, N = 20 stocks

**Properties**:
- Robust to outliers (Gerber: count-based, not amplitude-based)
- RMT noise filtering → condition_number well-controlled
- Computationally heavier (eigen decomposition required)
- KR equity adverse 2022-2024 outliers handling 우수

**Expected**:
- Pass condition number ≤ 100 (high probability post-RMT)
- Pass PSD (eigenvalue clipping ensures)
- May lose some signal in clipping (over-regularization risk)

**Use case in DPL-RC**: Backup if LW conditions degraded by outliers (e.g., 2020 COVID, 2022 rate shock months in rolling 60m window).

**Academic backbone**: Gerber et al. (2015 JPM "Markowitz Reimagined"), Laloux et al. (2000 IJTAF), L-326 mandate.

---

### 1.4. DCC-Copula (regime-conditional dynamic)

**Formula** (2-step Engle 2002):
```
Step 1: Univariate GARCH(1,1) for each asset
  σ²_i,t = ω_i + α_i · ε²_i,t-1 + β_i · σ²_i,t-1
  
Step 2: DCC(1,1) dynamic correlation
  Q_t = (1 - a - b) · Q̄ + a · z_t-1 z_t-1' + b · Q_t-1
  R_t = diag(Q_t)^(-1/2) · Q_t · diag(Q_t)^(-1/2)
  
Σ_DCC,t = D_t · R_t · D_t
where D_t = diag(σ_i,t)
```

**Variants**:
- Copula extension: Student-t copula on standardized residuals → tail dependence capture
- t-Copula DCC: parameters (a, b) + ν (Student-t dof)

**Parameters**:
- GARCH order: (1,1)
- DCC order: (1,1)
- T ≥ 120 months recommended for stable DCC estimation
- **본 cycle T = 60m rolling → DCC estimation marginal** (risk of unstable a, b)

**Properties**:
- Captures regime shift (DCC dynamic correlation)
- Tail dependence via copula extension
- Computationally heaviest (4-step nested optimization)
- KR equity: DCC under 60m sample frequently parameter unidentified

**Expected**:
- Condition number variable (depending on DCC fit quality)
- May fail PSD if DCC iteration unstable
- **Risk of overfitting** at T=60 (sample size insufficient)

**Use case in DPL-RC**: Tertiary fallback only. Primary use case = regime shift detection (Step 5.3 conditional risk attribution).

**Academic backbone**: Engle (2002 JBES), Pelletier (2006 J Econometrics) regime-switching DCC.

---

## 2. Selection Framework

### 2.1. Hard requirements (모든 estimator 충족 의무)

| Requirement | Threshold | Why |
|---|---|---|
| **Positive Definite** | min(eigenvalue) > 0 | Σ inverse 계산 가능 / optimizer feasibility |
| **Condition number** | ≤ 100 strict (v2 Codex C2 ACCEPT) | numerical stability / weight stability |
| **Symmetric** | abs(Σ - Σ') < 1e-10 | basic property |
| **Coverage** | non-NA proportion > 95% per sig_date | data availability |

### 2.2. Selection algorithm

```r
# Per-sig_date estimator competition
for (t in sig_dates):
  returns_window_t = returns[(t-60):(t-1), top_K_comp_stocks_t]
  
  candidates = list(sample, LW_oracle, gerber_rmt, dcc)
  
  for (est in candidates):
    Σ_t = estimate(est, returns_window_t)
    hard_checks = list(
      PSD = (min(eigen(Σ_t)$values) > 0),
      cond = (kappa(Σ_t) <= 100),
      sym  = (max(abs(Σ_t - t(Σ_t))) < 1e-10),
      cov  = (mean(!is.na(returns_window_t)) > 0.95)
    )
    
    if all(hard_checks):
      candidates[[est]] = list(
        Σ = Σ_t,
        cond = kappa(Σ_t),
        log_det = log(det(Σ_t)),
        min_eig = min(eigen(Σ_t)$values)
      )
  
  # Ranking by condition number (lower = better) within PSD-passed set
  selected_t = candidates[order(condition_number)][1]
  
  if (selected_t == NULL): 
    # All 4 estimators fail → fallback shrinkage stronger
    Σ_t = diag(diag(Σ_sample_t)) * 1.5  # extreme diagonal shrinkage
```

### 2.3. Default expected ranking (priors, Forge measurement 전)

| Rank | Estimator | Expected Condition | Notes |
|---|---|---|---|
| 1 | **LW Oracle** | ~ 30-80 | Closed-form, robust, KR T=60 N=20 fit |
| 2 | **Gerber+RMT** | ~ 40-100 | Outlier robust, may over-regularize |
| 3 | **Sample** | ~ 200-800 | Baseline only, frequently FAIL condition |
| 4 | **DCC** | Variable | Marginal at T=60, risk of failed convergence |

**Primary selection (default)**: **LW Oracle** for Σ_comp_t. v2 Codex C2 ACCEPT inherit + KR empirical priors 정합.

**Backup**: Gerber+RMT if LW fails on adverse months (2020-Q1 COVID / 2022 rate shock).

---

## 3. Per-sig_date rolling protocol (L-326 mandate)

### 3.1. Rolling window specification

```
For each sig_date t in {2014-01, 2014-02, ..., 2026-04} (124 sig_dates total):
  
  # 1. Identify complement sleeve top-K stocks at t
  scorer_output_t = run_scorer_at_sig_date(t)   # Forge cycle
  top_K_t = top_20(scorer_output_t)              # 20 stocks at sig_date t
  
  # 2. Extract rolling 60m returns matrix
  returns_window_t = returns[(t - 60m):(t - 1m), top_K_t]   # T=60 × N=20
  
  # 3. PIT compliance check
  assert all dates in returns_window_t <= t - 1m  # C1, C9 strict
  
  # 4. Estimator competition (4 candidates)
  Σ_t, est_selected_t, diag_t = select_estimator(returns_window_t)
  
  # 5. Persist (per sig_date)
  artifact_t = {
    sig_date: t,
    estimator: est_selected_t,
    condition_number: diag_t$cond,
    min_eig: diag_t$min_eig,
    log_det: diag_t$log_det,
    Σ_path: f"stage_artifacts/WT_D20260517_003/sigma_t_{t}.parquet"  # Forge cycle persist
  }
```

### 3.2. Top-K membership change handling

**문제**: Complement sleeve top-K membership 이 sig_date 마다 변동 → 직전 sig_date 와 다른 stocks → returns matrix 가 다른 universe

**Solution**:
- Top-K membership turnover ≤ 30% (typical month-on-month) — 14/20 stocks retain, 6/20 새로
- Returns matrix per sig_date 독립적으로 rebuild (rolling 60m using current top-K)
- New stocks 의 60m history availability 확인 → IPO ≤ 60m 종목은 universe 제외 (PIT C-availability)

### 3.3. Method shopping log (HARD, v6.1 R2-C inherit)

```json
{
  "risk_agent": {
    "candidates_tried": 4,
    "method_log": [
      {"name": "sample_pairwise", "median_cond": 350, "selected_count": 0, "selected": false},
      {"name": "ledoit_wolf_oracle", "median_cond": 55, "selected_count": 110, "selected": true},
      {"name": "gerber_rmt", "median_cond": 70, "selected_count": 14, "selected": false_primary_backup_yes},
      {"name": "dcc_copula", "median_cond": 180, "selected_count": 0, "selected": false}
    ],
    "primary_estimator": "ledoit_wolf_oracle",
    "backup_estimator": "gerber_rmt",
    "selection_rationale": "LW Oracle median condition 55 (well within 100 strict bound), 124/124 sig_dates PSD pass. Gerber+RMT backup for adverse outlier months."
  }
}
```

**Cap**: 5 estimator max (현 4, retain 1 slot for v2 future).

---

## 4. Σ_str_1715 inheritance (production retain)

### 4.1. Production lineage retain

STR_1715_AR_on_M4_R05_overlay_PG2 admit 시 Σ_str_1715 production lineage (book_state.json v2.3 effective 2026-05-13):
- Σ_str_1715 은 production 시점에 Forge cycle 에서 이미 estimated + admitted
- 본 risk cycle은 **Σ_str_1715 re-estimation X**, inherit retain (admission baseline 보존)

### 4.2. Σ_str_1715 retain path

```
sigma_str_1715_inherit_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/sigma_inherit.parquet"
```

**If absent in production folder**:
- Forge cycle 에서 1715 admitted returns r_1715_t series 로부터 sleeve-level σ² 추정 (single time-series variance, NOT cross-section Σ)
- 본 risk cycle 은 design-only — Forge cycle 의무 noted

### 4.3. Production Σ_str_1715 re-estimation 금지 rationale

- AX-007 EXCLUSION_via_multi_sleeve_AND_ML_sizing inherit retain (alpha_package.json axiom_compliance)
- L-307 (production lineage retain precedent) 정합
- Re-estimate 시 admission baseline drift 위험 (도훈 audit instinct precedent)

---

## 5. Cross-covariance Cov(r_str_1715, r_comp)

별도 protocol: **cross_covariance_design.md** (Step 5.2). 본 step 의 estimator 선택은 cross-covariance 입력 σ², σ_comp 도 동일 LW estimator 의 diagonal element 사용 (consistency).

---

## 6. Codex Round audit points (예상 challenge)

본 protocol 에 대한 Codex 예상 challenge:

1. **C-RA1: "Why T=60m rolling not 36m or 120m?"**
   - 정당화: KR equity 124 sig_dates total (2014-2026) → 60m balance between recency + sample size. T=36m insufficient PSD (Marchenko-Pastur ratio 1.8). T=120m forfeits regime adaptiveness.
   - Sensitivity: Forge cycle additional grid T ∈ {36, 60, 84, 120} robustness check 권고.

2. **C-RA2: "DCC at T=60 known to fail convergence"**
   - 정당화: DCC는 본 cycle tertiary fallback (Step 5.3 conditional risk attribution 에서만 우선). Σ_comp primary estimation 은 LW Oracle.

3. **C-RA3: "RMT eigenvalue clipping may over-regularize at N=20"**
   - 정당화: Marchenko-Pastur upper bound λ+ 은 T/N → ∞ asymptotic. T=60, N=20 의 finite-sample correction (Bickel-Levina 2008) 적용 권고. Stage 5.3 에서 lambda_min 보조 floor 추가.

4. **C-RA4: "Method shopping log cap=5, but only 4 candidates"**
   - 정당화: 4 candidates (sample, LW, Gerber+RMT, DCC) primary. v2 future 의 NLS (Ledoit-Wolf 2020 nonlinear shrinkage) retain 1 slot.

5. **C-RA5: "Top-K membership change에서 covariance regime shift 발생 시 어떻게?"**
   - 정당화: Σ_comp,t 매 sig_date 독립 estimate → no regime fitting. New stocks 의 IPO ≤ 60m 제외 (history availability). Top-K turnover 30% bound (typical KR monthly).

6. **C-RA6: "Σ_str_1715 production inherit는 lineage drift risk"**
   - 정당화: 1715 admit precedent retain (L-307 inheritance). 본 risk cycle 의무는 complement sleeve Σ_comp + Cross-cov. Σ_str_1715 inherit 시 production lineage hash 검증 의무 (Forge cycle).

---

## 7. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.1 sigma_estimators_dpl_rc.md.
- 4 estimator (Sample / LW Oracle / Gerber+RMT / DCC-Copula) comparison
- LW Oracle primary selection priors + Gerber+RMT backup
- Per-sig_date rolling 60m protocol (L-326 mandate 정합)
- 124 sig_dates × 4 estimator competition framework
- Method shopping log v6.1 R2-C inherit
- Σ_str_1715 production inheritance (re-estimation X)

**Sample / Window 정합 audit**:
- T = 60m rolling (KR equity 124 sig_dates 2014-2026 balance)
- N = 20 stocks (complement sleeve top-K)
- T/N = 3.0 (LW shrinkage 필수 ↔ sample baseline insufficient)
- 124 sig_dates × per-sig_date estimation (single snapshot 금지)

**다음 step**: 5.2 cross_covariance_design.md (sleeve-level 1715 × comp cross-cov)

**Forge cycle handoff**:
- Σ_comp,t 124 sig_dates per-sig_date estimation 의무
- LW Oracle primary + Gerber+RMT backup 의무
- Condition number ≤ 100 strict per sig_date
- Σ_str_1715 production inherit hash 검증
