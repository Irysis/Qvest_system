# Sleeve-level Σ Design — Path A NAV-level Blend (WT-D20260517_004)

**WT-D20260517_004 risk-research Step 5.1**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: risk-research agent
**Date**: 2026-05-17
**Predecessor inherit**: WT-D20260517_003 risk_package.json (LW Oracle primary + Gerber+RMT backup, T=60 rolling)
**Paradigm reuse**: v3 sleeve-level Σ_comp framework은 Path A NAV-level과 100% 정합. comp sleeve B holdings stock-level Σ는 v3 spec 그대로 재사용.

---

## 0. Executive Summary (1 paragraph)

Path A NAV-level blend은 두 슬리브 NAV의 wealth-weighted 결합(`NAV_blend = (1-a_t)·NAV_1715 + a_t·NAV_comp`)이다. risk 모델은 **두 단계**로 분리: (i) comp sleeve B holdings (top-K=20, 1715 외부 universe) **stock-level Σ_comp**(LW Oracle rolling 60m primary, Gerber+RMT backup) 추정 — comp sleeve 내부 portfolio variance σ²_comp,t 산출 + comp scorer optimization 신호 backbone, (ii) **production STR_1715 5-Layer NAV는 risk model 재구축 X — NAV time-series risk(σ²_1715,t = rolling 60m var of monthly NAV returns)만 측정**. NAV-level Cov(r_1715, r_comp) 결합 분석은 Step 5.2(별도 artifact). 본 step의 핵심은 comp Σ 추정 정합 + 1715 risk re-estimation 금지(production 100% retain).

---

## 1. Two-stage Σ scope clarification

| Sleeve | Σ 모델 | 추정 unit | 출처 |
|---|---|---|---|
| **A. STR_1715 5-Layer (production)** | NAV time-series variance σ²_1715,t | monthly NAV returns scalar series | `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds$nav` READ ONLY |
| **B. comp sleeve (1715 외부)** | stock-level Σ_comp(t) ∈ R^{N×N} | N≤20 holdings × T=60m rolling | feature_db rolling returns (`load_returns_for_universe(comp_universe_t, T=60)`) |
| **Cross-sleeve** | Cov(r_1715, r_comp) scalar | OOS pooled correlation × σ_1715 × σ_comp | Step 5.2 별도 artifact |

**Key principle**: production NAV는 already-portfolioed scalar return series — 추가 Σ 재구축은 (a) production lineage 변경(safety_guard hook 위반) + (b) double-counting (already 5-Layer overlay 거친 결과)이라서 금지. NAV-level variance만 측정.

---

## 2. comp sleeve B Σ_comp — LW Oracle primary

### 2.1 Primary estimator (v3 inherit, paradigm 정합)

```r
source("02_Infrastructure/portfolio/hrp_core.R")  # .get_cor_cov() LW Oracle wrapper
# 또는 직접 Ledoit-Wolf 2003 closed-form:
library(corpcor)
Sigma_comp_t <- corpcor::cov.shrink(returns_60m_N, lambda = NULL)  # α auto-Oracle
```

| Property | Value |
|---|---|
| Estimator | Ledoit-Wolf 2003 JEF §3 Theorem 2 (Oracle target) |
| Window | T=60 months rolling, per-sig_date |
| Universe | comp sleeve B holdings at sig_date t (N≤20, 1715 외부) |
| PSD | theoretical guarantee (Ledoit-Wolf §3 Theorem 2). Empirical per-sig_date verification = Forge cycle |
| Condition number strict target | ≤ 100 (v2/v3 inherit strict) |
| Median condition academic prior | 55 (Ledoit-Wolf 2003 Table 3 S&P 100 analogous, NOT measured) |
| Selection criterion | condition_number minimization within PSD-passed set (R4 P3 정합) |

### 2.2 Backup estimator

```r
# Trigger: LW condition > 100 OR min_eig < 1e-8 OR NA
source("02_Infrastructure/portfolio/hrp_core.R")  # .get_cor_cov_gerber_rmt()
Sigma_comp_t_backup <- cov_gerber_rmt(returns_60m_N, threshold = 0.5, rmt_clip = TRUE)
```

| Property | Value |
|---|---|
| Estimator | Gerber 2015 JPM count-based + Laloux 2000 RMT eigenvalue clipping |
| Trigger | LW fail condition (cond > 100 OR min_eig < 1e-8 OR NA) |
| Rationale | outlier robust + noise eigenvalue removal (KR equity occasional outlier months) |

### 2.3 Rejected estimators (paradigm 정합)

| Name | Rationale rejected |
|---|---|
| sample_pairwise | T=60, N=20, MP eigenvalue ratio ~12.3 → empirical condition 200-800, G2 strict fail |
| DCC-GARCH(1,1) bivariate | T=60 insufficient for stock-level N=20 DCC (대신 sleeve-level Step 5.3 secondary로만 적용) |
| Nonlinear shrinkage (NLS) | v3 Forge cycle 명시 — KR equity small N 이점 작음, LW Oracle 우선 |

**Method shopping cap = 5** (v6.1 R2-C). Tried = 4 (sample, LW Oracle, Gerber+RMT, DCC). Selected = 2 (primary LW + backup Gerber+RMT).

---

## 3. Per-sig_date rolling protocol (L-326 mandate)

```r
sig_dates <- seq.Date(as.Date("2014-01-01"), as.Date("2026-04-30"), by = "month") - 1
# n_sig_dates_total = 148 (full sample) / 124 (walk-forward post-purge/embargo)

for (t in sig_dates) {
  comp_universe_t <- setdiff(load_kr_top500_liq1e8(t), get_str1715_top20(t))
  # comp_holdings_t <- comp scorer top-K=20 (Forge cycle, alpha cycle 영역)
  
  returns_60m_N <- load_returns_for_universe(comp_holdings_t, end = t, T = 60)  
  # 60m rolling, end ≤ t, PIT strict
  
  Sigma_LW_t <- cov.shrink(returns_60m_N)
  cond_LW_t <- kappa(Sigma_LW_t)
  min_eig_LW_t <- min(eigen(Sigma_LW_t, only.values = TRUE)$values)
  
  if (cond_LW_t <= 100 && min_eig_LW_t > 1e-8) {
    Sigma_t <- Sigma_LW_t
    estimator_selected_t <- "ledoit_wolf_oracle"
  } else {
    Sigma_t <- cov_gerber_rmt(returns_60m_N)
    estimator_selected_t <- "gerber_rmt"
  }
  
  # persist: covariance_t.parquet
  write_per_sig_date(Sigma_t, estimator_selected_t, cond_t, min_eig_t, alpha_shrinkage_t)
}
```

**Output (Forge cycle)**: `stage_artifacts/WT_D20260517_004/covariance.parquet` (124 sig_dates × Σ_comp).

**Method shopping log per-sig_date**:
```json
{
  "sig_date": "2018-06-30",
  "candidates_tried": 2,
  "method_log": [
    {"name": "ledoit_wolf_oracle", "cond": 47.3, "min_eig": 0.0023, "selected": true},
    {"name": "gerber_rmt", "cond": 62.1, "min_eig": 0.0019, "selected": false}
  ]
}
```

---

## 4. Σ_comp covariance freshness SLA (R6 v6.1)

`.cache/covariance/*.parquet` 사용 시:
- `covariance_asof` > 30일 → stale → 재계산
- `regime_tag` (M4 BULL/NORMAL/CAUTION/CRISIS) vs `.cache/regime_current.json` 불일치 → stale

본 cycle은 design-only. `compute_and_cache_covariance()` Forge cycle 호출 의무.

---

## 5. STR_1715 5-Layer NAV time-series risk — production retain

### 5.1 Scope

production NAV는 already-portfolioed monthly return series. 추가 Σ 모델 X.

```r
production_nav_rds <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds"
bt_1715 <- readRDS(production_nav_rds)
ret_1715 <- bt_1715$period_returns  # monthly returns scalar series
sigma_1715_t <- zoo::rollapply(ret_1715, width = 60, FUN = sd, align = "right")  
# rolling 60m std dev
```

| Property | Value |
|---|---|
| Source | `bt_result_layer5_R05.rds$period_returns` (Backtest Contract v1.0 nav field-derived) |
| Aggregation | rolling 60m sd of monthly returns × √12 (annualized) |
| PIT | end ≤ t strict (period_returns timestamps) |
| READ ONLY | mandate (safety_guard hook PreToolUse[W/E]) |
| Re-estimation | FORBIDDEN |

### 5.2 σ_1715 academic prior (NOT measured)

- production SR 1.9536 / CAGR 41.50% (L-313) → implied σ ≈ CAGR / SR ≈ 21.2% annualized
- 본 cycle은 학술 prior 21.2% retain. Forge cycle empirical re-measure (rolling).

---

## 6. Codex C3 PARTIAL_ACCEPT (v3 inherit) — factor BΩB'+D 불채택 rationale

WT_003 v3 risk cycle Codex C3 ACCEPT:
- comp scorer = 80 features composite weight (단순 factor 직접 노출 X)
- comp top-K N=20 small → factor model rank deficiency risk
- Stock-level LW = practical + interpretable
- factor_coverage_r2 = supplementary check (regress Σ_comp returns on 80 features → 1 - var(resid)/var(total) ≥ 30% target), **NOT admission gate**

Path A NAV-level은 이 boundary 그대로 inherit. (Forge cycle factor_coverage_r2 mandate retain.)

---

## 7. Output (design-only, Forge cycle measurement mandate)

| Forge cycle 의무 산출물 | 경로 |
|---|---|
| Σ_comp per-sig_date | `stage_artifacts/WT_D20260517_004/covariance.parquet` (124 × N×N) |
| Method shopping log | `stage_artifacts/WT_D20260517_004/sigma_method_shopping_log.json` |
| Condition number diagnostic | per-sig_date kappa + min_eig + alpha_shrinkage report |
| factor_coverage_r2 | supplementary check (admission X) |
| Cache meta | `.cache/covariance/*.meta.json` (covariance_asof, regime_tag) |
| σ_1715 NAV time-series | rolling 60m std dev of `bt_1715$period_returns` |

---

## 8. Charter 정합

- **AX-002 PIT**: per-sig_date rolling (C1 정합) + end ≤ t (C2) + load_month_factors (C15)
- **R4 P3 selection_objective**: condition_number (return-based X)
- **R6 covariance_freshness_sla**: 30 days
- **R2-C method_shopping_log**: cap=5, tried=4 (sample + LW + Gerber+RMT + DCC)
- **Common Charter Principle 8 (No Silent Override)**: Σ rebuild 의무 자제 (1715 retain), method shopping log explicit
- **L-326**: per-sig_date rolling (single snapshot 금지)
- **v3 inherit retain**: LW Oracle primary + Gerber+RMT backup + T=60 + cond ≤ 100 strict

---

## 9. Forge cycle compute estimate

| Step | Compute |
|---|---|
| Σ_comp per-sig_date × 124 sig_dates × 4 estimator parallel | ~1.5h CPU (future_lapply 5 workers) |
| factor_coverage_r2 supplementary | ~0.5h CPU |
| Cache meta write | trivial |
| σ_1715 NAV rolling | trivial (production read) |
| **Total** | **~2h CPU** |

---

**End of artifact**. Step 5.2 (NAV-level cross-covariance) 작성 진행.
