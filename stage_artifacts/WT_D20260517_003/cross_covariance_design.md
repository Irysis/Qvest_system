# Cross-Covariance Cov(r_str_1715, r_comp) — DPL-RC Sleeve-Level Risk Design

**WT-D20260517_003 · risk-research Step 5.2**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: sigma_estimators_dpl_rc.md + alpha_package.json §dpl_rc_conditional_loss_function (λ_corr term backbone)
**Purpose**: Sleeve-level 1715 × complement covariance backbone — λ_corr loss term enforcement + G2 (|cor| ≤ 0.3) admission axis 6 정합

---

## 0. Background — DPL-RC sleeve decomposition

DPL-RC blend variance (sleeve-level):
```
σ²_p,t = (1-a_t)² · σ²_1715,t + a_t² · σ²_comp,t + 2·a_t·(1-a_t)·Cov(r_1715,t, r_comp,t)
```

여기서 **Cov(r_1715,t, r_comp,t)** = sleeve-level covariance, **NOT** stock-level Σ.

- r_1715,t = sleeve portfolio return at sig_date t
- r_comp,t = complement sleeve portfolio return at sig_date t

→ 두 sleeve 의 **monthly return time series** 간 covariance.

**Connection to G2 admission axis 6**:
```
corr(r_1715, r_comp) = Cov(r_1715, r_comp) / (σ_1715 · σ_comp)
G2_pass = |corr(r_1715, r_comp)| ≤ 0.3
```

→ Cross-covariance design 의 핵심 deliverable: corr 측정 protocol + λ_corr loss term backbone validation.

---

## 1. Time-series covariance estimation

### 1.1. Pooled sample correlation (baseline)

```
Pool all sig_dates t ∈ {2014-01, ..., 2026-04}:
  cov(r_1715, r_comp) = (1/(T-1)) · Σ_t (r_1715,t - r̄_1715)(r_comp,t - r̄_comp)
  cor(r_1715, r_comp) = cov / (σ_1715 · σ_comp)
```

- T = 124 sig_dates (full sample)
- Single scalar correlation (NOT time-varying)

**Pros**: Simple, stable estimate, large N
**Cons**: No regime adaptiveness — bad/good state 의 cor 변동 dilute

### 1.2. Rolling correlation (per sig_date)

```
For each sig_date t:
  cor_t(r_1715, r_comp) = sample correlation over [t-W, t-1]
  W = 24 months default (smaller than Σ_comp T=60 for sleeve-level)
```

- W = 24 monthly rolling window (sleeve-level: smaller window OK because 2 series only, not N=20)
- Time-varying cor_t(r_1715, r_comp) ∈ [-1, 1]

**Pros**: Captures regime shift, decay detection
**Cons**: W=24 → ~5-10% sampling noise per cor estimate

### 1.3. DCC-based dynamic correlation

```
DCC(1,1) applied to (r_1715,t, r_comp,t) bivariate time series:
  σ²_1715,t = GARCH(1,1)_1715
  σ²_comp,t = GARCH(1,1)_comp
  Q_t = (1 - a - b) · Q̄ + a · z_t-1 z_t-1' + b · Q_t-1
  R_t = diag(Q_t)^(-1/2) · Q_t · diag(Q_t)^(-1/2)
```

- T=124 sufficient for bivariate DCC (only 2 series, 5 params total)
- DCC convergence reliable for K=2 (vs K=20)
- Dynamic cor_t with smooth transition

**Pros**: T=124 sufficient for bivariate DCC, smooth dynamic, parametric efficiency
**Cons**: Distributional assumption (Gaussian innovations)

### 1.4. Recommended selection

| Method | Primary use | Backup | Rationale |
|---|---|---|---|
| **Pooled sample** | G2 admission axis 6 enforcement | YES | Stable, large N=124, single number for admission decision |
| **Rolling W=24** | Drift monitoring | NO | Time-varying — useful for diagnostic, NOT admission |
| **DCC bivariate** | Regime-conditional decomposition | NO | Step 5.3 conditional risk attribution primary use |

→ **Primary deliverable for G2 admission**: Pooled sample correlation over 124 sig_dates.
→ **Forge cycle 의무**: pooled + rolling + DCC all 3 computed, primary admission = pooled.

---

## 2. Cov(r_str_1715, r_comp) design considerations

### 2.1. r_1715,t source: production retain

```
r_1715,t = STR_1715_AR_on_M4_R05_overlay_PG2 monthly return at sig_date t
       (production-admitted, 255m PerfA standard, lineage retain)
```

- production lineage L-307 / L-310~313 retain inheritance
- 본 risk cycle 은 r_1715 series re-compute X
- Forge cycle inherit: `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/r_str1715_monthly.parquet` (or equivalent admitted returns path)

### 2.2. r_comp,t source: Forge cycle output

```
r_comp,t = w_comp,t · realized_returns_{t+1} - cost_15bps · TO_comp,t
```

여기서:
- w_comp,t = complement sleeve weights at sig_date t (top-K, bounds [0, 0.20], Σ=1)
- Cost 15bps one-way (cost_model_version v2.3_kr_retail_15bps)
- 본 risk cycle 은 r_comp series 측정 X (Forge cycle 의무)

### 2.3. Time alignment

```
sig_date alignment:
  r_1715,t: production monthly returns starting 2014-01 (148m, but DPL-RC universe 124 sig_dates)
  r_comp,t: 124 sig_dates 2014-01 ~ 2026-04 (alpha-research training_protocol_v2 inherit)
  
Overlap: 124 sig_dates → cor computation sample size = 124
```

### 2.4. Cost-adjusted vs gross returns

**Cross-cov 계산 시 gross or net returns 사용?**

- **Net returns (cost-adjusted)** 사용 권고 — admission cor 이 production 의 실제 sleeve 결합 risk 반영
- 단, gross cor 도 별도 측정 (Codex audit 의무 — academic literature 정합 gross 기준 학술 backbone)

**Rationale**: Research Philosophy P2 (Cost-aware Alpha, Net > Gross) 정합.

---

## 3. λ_corr loss term backbone validation

### 3.1. Alpha cycle conditional_loss_7axis_admission.md inherit

```
L(θ) = ... + λ_corr · |corr(r_comp_·, r_1715_·)| + ...
```

- λ_corr_initial = 1.0 (moderate enforcement)
- λ_corr_grid = {0.5, 1.0, 2.0} for Forge cycle search

### 3.2. λ_corr value rationale (risk perspective)

**λ_corr = 1.0 의미** (admission axis 6 backbone):
- corr 0.3 → loss contribution 0.3 (1.0 · 0.3)
- corr 0.0 → loss contribution 0.0 (orthogonal)
- corr 1.0 → loss contribution 1.0 (degenerate)

**Risk-side validation**:
- λ_corr 가 너무 작으면 (0.5): G2 (cor ≤ 0.3) hard enforcement 약함 → risk DEFER 가능성
- λ_corr 가 너무 크면 (2.0): comp scorer가 cor 최소화에 치중 → SR alpha-side 손실
- **1.0 = balance**: moderate enforce + alpha objective primary retain

### 3.3. risk-side λ_corr 의 적정성 진단

```
Forge cycle 의무:
  for λ_corr in {0.5, 1.0, 2.0}:
    train complement scorer
    measure final corr(r_comp, r_1715)
    measure final blend SR
  
  Report Pareto frontier (corr vs SR) → optimal λ_corr selection
```

본 risk cycle 은 design-only. Forge cycle 의무 noted.

---

## 4. Cross-covariance impact on portfolio total variance

### 4.1. Decomposition formula

```
σ²_p,t = (1-a_t)² · σ²_1715,t + a_t² · σ²_comp,t + 2·a_t·(1-a_t) · Cov(r_1715,t, r_comp,t)

Define: ρ = corr(r_1715, r_comp), 
        σ_1715, σ_comp = sleeve volatilities
        
σ²_p,t = (1-a_t)² · σ²_1715,t + a_t² · σ²_comp,t + 2·a_t·(1-a_t) · ρ · σ_1715,t · σ_comp,t
```

### 4.2. Sensitivity to ρ at admission baseline

Production baseline:
- σ_1715,annualized ≈ 21.2% (from CAGR 41.5%, SR 1.9536 implied vol)
- σ_comp,annualized estimated ~ 15-25% (typical low-vol complement)
- a_max = 0.10 (mid-grid)

Variance decomposition at a = 0.10:
```
ρ = -0.3: σ²_p ≈ (0.81 · 0.045) + (0.01 · 0.04) + (2 · 0.1 · 0.9 · -0.3 · 0.212 · 0.20)
       = 0.03645 + 0.0004 - 0.00229 = 0.0346 → σ_p = 18.6% (vs 1715 21.2%, -2.6pp)

ρ = +0.3: σ²_p ≈ 0.03645 + 0.0004 + 0.00229 = 0.0391 → σ_p = 19.8% (vs 1715 21.2%, -1.4pp)

ρ = 0.0: σ²_p ≈ 0.03685 → σ_p = 19.2% (vs 1715 21.2%, -2.0pp)
```

**Insight**: a = 10% injection 시 ρ 의 ±0.3 변동이 σ_p 에 -2.6pp ~ -1.4pp 차이만 → admission boundary 약함.

→ **G2 cor ≤ 0.3 의 enforcement 가 portfolio total variance 에 marginal 영향**. 그러나 **SR / drag 측면에서는 cor 가 중요** (anti-crowding, complement quality).

### 4.3. Conclusion on cor admission criterion

- Total variance 측면: cor ≤ 0.3 는 marginal (variance reduction modest at a=10%)
- **Anti-crowding 측면**: cor ≤ 0.3 = 4th sleeve 자격, paradigm essence
- **Risk model 정합**: G2 enforce 의 primary purpose = paradigm validity (1715 alpha core + comp orthogonal), NOT variance reduction

---

## 5. Negative correlation 의 가치 (deeper analysis)

### 5.1. Conditional negative cor 의 hedge value

```
If ρ_overall = -0.1 (mildly negative pooled),
But ρ_bad_state = -0.4 (strongly negative in bad state),
ρ_good_state = +0.1 (mildly positive in good state):

→ complement sleeve 가 bad state 에서 hedge property strong
→ paradigm validation maximized
```

이러한 conditional ρ shift 측정은 **Step 5.3 conditional_risk_attribution.md** 에서 explicit handle.

### 5.2. λ_corr 가 cor 의 absolute value vs signed value penalize

Alpha cycle loss: `λ_corr · |corr|` (absolute value)
- Pros: positive OR negative high cor 모두 penalize (4th sleeve 자격 보장)
- Cons: negative cor 가 hedge value 있음에도 push toward 0

**Alternative consideration**:
- `λ_corr · max(0, corr)` (one-sided): negative cor 허용 + positive cor penalize
- 본 cycle 은 absolute value retain (alpha-research conditional_loss_7axis_admission.md 정합)
- Codex 권고 시 Forge cycle exploration retain

---

## 6. Cross-covariance and λ_to (turnover) interaction

### 6.1. TO blend formula

```
TO_blend,t = ||w_blend,t - w_blend,t-1||_1 / 2
          = ||(1-a_t) w_1715,t - (1-a_{t-1}) w_1715,t-1 + a_t w_comp,t - a_{t-1} w_comp,t-1||_1 / 2
```

→ Blend TO 는:
1. 1715 sleeve TO (~ 4-5/yr production baseline)
2. complement sleeve TO (forge cycle measurement)
3. a_t 의 시간적 변동 (p_bad_1715 forecast volatility)

### 6.2. a_t volatility 영향

```
a_t = clip(a_max · p_bad_1715(t+1), 0, a_max)

If p_bad volatile (Brier 큰 경우):
  a_t volatile → 매월 blend mix changes → TO inflation

If p_bad smooth (well-calibrated):
  a_t smooth → blend TO ~ weighted average of 1715 + comp TOs
```

### 6.3. G7 (TO ≤ 6) enforcement 의 risk-side check

본 risk cycle 은 TO 자체는 alpha-research / optimizer-research / forge 영역. 단, **cross-cov 측정 시 net TO-adjusted returns 사용 권고** (Cost-aware Net > Gross).

---

## 7. Diagnostic outputs (Forge cycle 의무)

```json
{
  "cross_covariance_diagnostics": {
    "pooled_correlation": {
      "value": "Forge measurement",
      "sample_size": 124,
      "ci_95": ["measurement", "measurement"],
      "g2_admission": "PASS|FAIL based on |value| <= 0.3"
    },
    "rolling_correlation_w24": {
      "min": "Forge measurement",
      "median": "Forge measurement",
      "max": "Forge measurement",
      "regime_drift_detected": "boolean"
    },
    "dcc_correlation": {
      "smooth_path": "stage_artifacts/WT_D20260517_003/dcc_cor_path.parquet",
      "convergence_status": "PASS|FAIL"
    },
    "sleeve_volatilities": {
      "sigma_1715_annualized": "production retain",
      "sigma_comp_annualized": "Forge measurement"
    },
    "blend_variance_reduction": {
      "at_a_0_05": "Forge measurement",
      "at_a_0_10": "Forge measurement",
      "at_a_0_15": "Forge measurement",
      "at_a_0_20": "Forge measurement"
    },
    "method_shopping_log": {
      "candidates_tried": ["pooled_sample", "rolling_24m", "dcc_bivariate"],
      "primary_admission": "pooled_sample"
    }
  }
}
```

---

## 8. PIT compliance audit

### 8.1. C1 (full-sample 통계 금지)

**Critical**: cor 측정에서 full-sample 사용?
- **pooled_sample**: T=124 전체 sample 사용 = full-sample correlation
- **본 cycle 의 정당화**: cor 은 **admission decision** 변수, NOT signal. 단, **Forge cycle 측정 시 OOS 부분만 사용** 의무 (5 walk-forward windows OOS aggregation).

**Corrected protocol** (Codex pre-rebuttal):
```
For Forge cycle:
  Walk-forward 5 windows × OOS cor measurement per window
  Aggregate OOS cor = pool OOS sig_dates 의 cor
  → 124 sig_dates 중 OOS portion (52 net test months) 만 사용
  → admission decision = OOS-based cor
```

### 8.2. C2 (same-day circular)

r_1715,t × r_comp,t cor 측정에 사용된 returns 모두 realized (t close 시 알 수 없음, t+1 close 후 known). cor measurement 는 **lookback** → no circular.

### 8.3. C9 (DD/VT lag)

Sleeve returns r_1715,t / r_comp,t 는 t-1 close based weights × t close return → t close 에 known. cor measurement 는 past returns only. **Compliant**.

---

## 9. Codex Round audit points (예상 challenge)

1. **C-RC1: "Pooled sample T=124 cor 은 full-sample statistic 위반"**
   - 정당화: Admission decision variable, NOT signal. Forge cycle 의무: walk-forward OOS cor only (52m net test sample). admission 기반 = OOS cor.

2. **C-RC2: "DCC bivariate 은 distribution assumption (Gaussian)"**
   - 정당화: t-Copula DCC variant 우선 explore (Step 5.3). Pooled sample cor 은 distribution-free.

3. **C-RC3: "λ_corr = 1.0 의 sensitivity formal study 부재"**
   - 정당화: Forge cycle 의무 grid {0.5, 1.0, 2.0} × 5 windows → Pareto frontier (corr vs SR) selection.

4. **C-RC4: "Cov(r_1715, r_comp) measurement 가 0 인 sig_dates 가 있을 수 있음 (comp scorer 가 1715 stocks 와 동일 top-K selected 경우)"**
   - 정당화: Top-K disjoint 의무 X (orthogonal weights, NOT orthogonal stocks). 종목 overlap 있어도 weight 다르면 cor 다름. Forge cycle 측정 의무.

5. **C-RC5: "negative correlation 의 hedge value 무시"**
   - 정당화: alpha-research conditional_loss_7axis_admission.md §1.2 absolute value retain. 단 Forge cycle exploration: one-sided λ_corr · max(0, corr) variant retain.

---

## 10. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.2 cross_covariance_design.md.

**Key deliverables**:
- 3 cross-cov methods (pooled / rolling / DCC bivariate) — primary admission = pooled OOS
- λ_corr backbone validation (1.0 moderate, grid {0.5, 1.0, 2.0})
- Portfolio total variance decomposition + ρ sensitivity (a=10% : ρ ±0.3 → σ_p ±0.6pp)
- G2 admission axis 6 의 paradigm-essence vs variance-reduction distinction
- Cost-aware net returns 사용 권고 (P2 정합)
- Walk-forward OOS cor only (C1 정합)

**Forge cycle handoff**:
- r_1715,t production retain inherit path
- r_comp,t 124 sig_dates Forge cycle measure
- pooled + rolling + DCC all 3 measure, admission = pooled OOS

**다음 step**: 5.3 conditional_risk_attribution.md (bad vs good state Σ asymmetry)
