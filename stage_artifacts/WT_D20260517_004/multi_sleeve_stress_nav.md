# Multi-sleeve Stress + Integration — NAV-level (WT-D20260517_004)

**WT-D20260517_004 risk-research Step 5.5**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: risk-research agent
**Date**: 2026-05-17
**Predecessor inherit**: WT-D20260517_003 risk_package.json::stress_scenarios_8 + injection_risk_matrix
**Multi-sleeve precedent**: L-279/280/281 Hybrid 70/15/15 (STR_1715 + TSMOM + KR_10y), AX-007 exemption #1

---

## 0. Executive Summary (1 paragraph)

Path A NAV-level blend stress test는 **8 stress scenarios × 4 a_max = 32 cells** (v3 inherit, 도훈 mandate 8 scenarios retain). NAV-level blend formula는 production 5-Layer 1715 NAV는 stress 기간 그대로 read-only (재구축 X), comp sleeve B는 stress 기간 별도 측정, NAV_blend = (1-a_t)·NAV_1715 + a_t·NAV_comp 결합 손익 cell 별 측정. **Hard abort**: ANY cell의 (cum_r_blend - cum_r_1715) < -5pp at any a_max. **DEFER**: ALL in-sample 5 scenarios negative. **Multi-sleeve admission**: AX-007 exemption #1 (multi-sleeve) + #4 (ML sizing p_bad + a_t) 동시 정합. max_names per-sleeve 20 + union 40 (L-279 precedent + Charter §10 v1.8 multi_sleeve_charter_exception_request 도훈 explicit confirm pending).

---

## 1. 8 stress scenarios (v3 inherit, 도훈 mandate retain)

| # | Name | Start | End | In-sample | Proxy type | Caveat |
|---|---|---|---|---|---|---|
| 1 | GFC_2008 | 2007-10-01 | 2009-03-31 | **No** | global_credit_shock | 1715 architecture pre-sample, universe drift caveat |
| 2 | Euro_Debt | 2011-07-01 | 2011-12-31 | **No** | regional_sovereign | same caveat as GFC |
| 3 | China_Shock | 2015-06-01 | 2016-02-29 | Yes | EM_external | full PIT |
| 4 | US_China_Trade | 2018-03-01 | 2018-12-31 | Yes | trade_policy | full PIT |
| 5 | COVID_2020 | 2020-01-01 | 2020-06-30 | Yes | pandemic_demand | full PIT |
| 6 | Rate_Hike_2022 | 2022-01-01 | 2022-12-31 | Yes | monetary_policy | full PIT |
| 7 | KR_Disinflation_2024 | 2024-01-01 | 2024-09-30 | Yes | domestic_policy | full PIT |
| 8 | Iran_War_2026 | 2026-02-01 | 2026-04-30 | Yes | geopolitical | full PIT recent |

**Pre-2014 proxy caveat** (v3 Codex C9 PARTIAL_ACCEPT 정합):
- GFC_2008 / Euro_Debt → 1715 architecture pre-sample
- Universe drift caveat noted
- **qualitative pattern only, NOT quantitative admission**
- **In-sample 5 scenarios primary**: China_Shock / US_China_Trade / COVID_2020 / Rate_Hike_2022 / KR_Disinflation_2024 / Iran_War_2026 (6 in-sample, 2 proxy)

---

## 2. NAV-level stress matrix (32 cells)

### 2.1 Cell metrics

```r
for (s in stress_scenarios_8) {
  for (a_max in c(0.05, 0.10, 0.15, 0.20)) {
    
    # 1715 stress retain (production READ ONLY)
    period_idx <- which(date(NAV_1715) %in% s$start:s$end)
    NAV_1715_stress <- bt_1715$nav[period_idx]
    cum_r_1715 <- last(NAV_1715_stress) / first(NAV_1715_stress) - 1
    mdd_1715 <- PerformanceAnalytics::maxDrawdown(NAV_1715_stress)
    
    # comp sleeve stress measurement
    NAV_comp_stress <- compute_comp_nav_stress(comp_holdings, s)
    cum_r_comp <- last(NAV_comp_stress) / first(NAV_comp_stress) - 1
    
    # blend
    NAV_blend_stress <- (1 - a_max) * NAV_1715_stress + a_max * NAV_comp_stress
    cum_r_blend <- last(NAV_blend_stress) / first(NAV_blend_stress) - 1
    mdd_blend <- PerformanceAnalytics::maxDrawdown(NAV_blend_stress)
    
    cell[s, a_max] <- list(
      cum_return_1715 = cum_r_1715,
      cum_return_blend = cum_r_blend,
      stress_alpha = cum_r_blend - cum_r_1715,
      mdd_1715 = mdd_1715,
      mdd_blend = mdd_blend,
      sr_1715 = compute_sr(NAV_1715_stress),
      sr_blend = compute_sr(NAV_blend_stress),
      var_5_blend = quantile(returns_blend, 0.05)
    )
  }
}
```

### 2.2 Cell schema

```json
{
  "scenario": "COVID_2020",
  "a_max": 0.10,
  "in_sample": true,
  "cum_return_1715": -0.082,
  "cum_return_blend": -0.045,
  "stress_alpha": +0.037,
  "mdd_1715": -0.115,
  "mdd_blend": -0.094,
  "sr_1715": -0.42,
  "sr_blend": -0.18,
  "var_5_blend": -0.052
}
```

---

## 3. Hard abort / DEFER criteria

### 3.1 Hard abort

```
ANY cell: stress_alpha < -5pp at any (scenario, a_max) → ABORT
```

### 3.2 DEFER

```
ALL in-sample 5 scenarios: avg stress_alpha < 0 → DEFER (complement provides no stress hedge)
```

### 3.3 Soft criteria (admission preference, NOT block)

- Avg stress alpha (blend - 1715) > 0 across 5 in-sample scenarios
- Stress SR_blend > Stress SR_1715 majority scenarios
- Worst-stress cum_r_blend > -25%

### 3.4 Single-period loss test (RF-R4)

```
worst single-month loss in any stress period at any a_max < -25% → RF-R4 alert
```

---

## 4. Pareto frontier (a_max optimization)

### 4.1 4 a_max grid Pareto

```r
a_max_grid <- c(0.05, 0.10, 0.15, 0.20)
pareto_data <- data.frame()
for (a_max in a_max_grid) {
  cells <- stress_matrix[, a_max]
  worst_stress_alpha <- min(cells$stress_alpha)
  avg_stress_alpha <- mean(cells$stress_alpha)
  pareto_data <- rbind(pareto_data, list(
    a_max = a_max,
    worst = worst_stress_alpha,
    avg = avg_stress_alpha
  ))
}
# Construct (worst, avg) Pareto frontier
```

### 4.2 Optimal a_max (admission candidate)

Optimizer agent 영역. risk-side는 stress matrix raw cells 제공 + Pareto frontier 시각화 + abort/DEFER trigger evaluation.

---

## 5. NAV-level multi-sleeve stress 정합성

### 5.1 production 1715 stress retain mandate

```r
# bt_result_layer5_R05.rds READ ONLY
production_nav_rds <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds"
bt_1715 <- readRDS(production_nav_rds)
NAV_1715_full <- bt_1715$nav  # production 267m timeseries

# stress 기간 read only — re-backtest 금지 (safety_guard hook PreToolUse[W/E])
```

### 5.2 comp sleeve stress measurement

```r
# Forge cycle 의무
for (s in stress_scenarios_8) {
  comp_holdings_s <- comp_scorer_predict(s$start:s$end, comp_universe_t_per_sig_date)
  NAV_comp_s <- compute_nav_from_holdings(comp_holdings_s, cost = 25bps, rebalance = monthly)
  store(NAV_comp_s, scenario = s$name)
}
```

### 5.3 NAV-level blend integration

```r
# At each sig_date t in stress period
NAV_blend_t <- (1 - a_t) * NAV_1715_t + a_t * NAV_comp_t
# Where a_t = clip(a_max · p_bad_1715(t+1|F_t), 0, a_max)
```

**Path A NAV-level 본질**: production 1715 NAV는 stress 기간 그대로 inherit, comp sleeve는 별도 측정, NAV_blend는 wealth-weighted 결합 — **production lineage 변경 X**.

---

## 6. AX-007 exemption #1 + #4 정합 (multi-sleeve)

### 6.1 AX-007 (single_sleeve_top20_mechanism_break)

WT_003 v3 risk_package + alpha_package에서 AX-007 본문:
- `single_sleeve_long_only_top20` 신호-포트폴리오 변환 메커니즘 단절
- 예외 4종: multi-sleeve / long-short / 50+ 분산 / ML sizing

### 6.2 Path A NAV-level 정합

| Exemption | Path A 정합 |
|---|---|
| **#1 multi-sleeve** | NAV_1715 (sleeve A) + NAV_comp (sleeve B) 물리적 분리 + universe 0% overlap |
| **#4 ML sizing** | p_bad classifier (G1 4-options) + a_t = clip(a_max · p_bad, 0, a_max) |

**Both exemptions 동시 활성** (alpha cycle AX_007 axiom_compliance "EXCLUSION_via_AX007_exemption_1_PLUS_4_by_construction" 정합).

### 6.3 L-279~L-281 Hybrid precedent

L-279 Session 76: Hybrid 70/15/15 (STR_1715 + TSMOM + KR_10y bond) 3-source multi-sleeve admit. Effective 2026-06-01.

Path A는 **2-sleeve** 변형 (STR_1715 + comp_complement)이지만 same paradigm + L-279 admit precedent direct 정합.

---

## 7. max_names per-sleeve 20 + union 40 (multi_sleeve_charter_exception)

### 7.1 Hard constraint extension request

Charter v1.8 §10 (multi_sleeve_charter_exception_request, alpha cycle inherit):
- Base: single-sleeve max 20 (CLAUDE.md Production Constraints, v53 hook 강제)
- Requested: multi-sleeve union ≤ 40 (sleeve A NAV_1715 ≤ 20 + sleeve B NAV_comp ≤ 20)

### 7.2 Precedent basis

- L-279/280/281 Hybrid 70/15/15 admit (3 sleeves, union ≤ 60 in theory)
- AX-007 exemption #1

### 7.3 Approval pending

- 도훈 explicit confirm + governor agent admission gate audit (Charter §10 v1.8)
- 본 risk cycle은 design only — admission decision은 governor agent post-Forge

### 7.4 Risk-side compliance

Risk model 자체는 **stock-level Σ_comp N=20 + production NAV scalar** 구조 — max_names extension은 weights-level admission decision (optimizer/governor 영역). risk-side는 sleeve-level Σ + cross-cov + stress matrix raw cell만 제공.

---

## 8. Stress scenarios proxy / in-sample explicit

### 8.1 In-sample 6 scenarios (1715 architecture sample post-2014)

China_Shock / US_China_Trade / COVID_2020 / Rate_Hike_2022 / KR_Disinflation_2024 / Iran_War_2026

→ quantitative admission contribute.

### 8.2 Proxy 2 scenarios (pre-2014)

GFC_2008 / Euro_Debt

→ **qualitative pattern only, NOT quantitative admission** (v3 Codex C9 PARTIAL_ACCEPT). 1715 architecture / universe drift caveat 명시.

---

## 9. Integration with risk model layers

### 9.1 Stress matrix consumer

- **alpha cycle**: alpha confidence by stress (bad_state extension)
- **risk cycle**: cross-cov by stress + tail risk by stress (Step 5.3 conditional)
- **optimizer cycle**: a_max optimal selection + admission curve
- **forge cycle**: 9 artifacts integration + AX-008 verification
- **judge cycle**: Gate G3 (mdd_no_worse) + Gate G4 (mdd_no_worse) verification
- **governor cycle**: admission decision based on Pareto frontier + AX-001 v2 mapping

### 9.2 Stress matrix output schema

```json
{
  "stress_matrix_32_cells": {
    "COVID_2020_a005": {/* metrics */},
    "COVID_2020_a010": {/* metrics */},
    /* ... 32 cells total ... */
  },
  "pareto_frontier": {
    "a005": {"worst_stress_alpha": -0.02, "avg_stress_alpha": +0.012},
    "a010": {"worst_stress_alpha": -0.045, "avg_stress_alpha": +0.025},
    "a015": {"worst_stress_alpha": -0.07, "avg_stress_alpha": +0.032},
    "a020": {"worst_stress_alpha": -0.10, "avg_stress_alpha": +0.038}
  },
  "abort_triggers_fired": [],
  "defer_triggers_fired": [],
  "rf_r4_alerts": [],
  "in_sample_avg_stress_alpha": +0.025,
  "in_sample_majority_sr_blend_gt_sr_1715": true
}
```

---

## 10. Forge cycle measurement mandate

| Output | Path |
|---|---|
| 32 cell stress matrix | `stage_artifacts/WT_D20260517_004/stress_matrix_32_cells.parquet` |
| Pareto frontier 4 a_max | `stage_artifacts/WT_D20260517_004/stress_pareto.json` |
| Abort/DEFER trigger eval | embedded in matrix |
| Single-period -25% loss alarm | RF-R4 alert log |
| In-sample 5 scenarios summary | aggregate stress_alpha + SR diff |

---

## 11. Charter 정합

- **AX-002 PIT**: comp scorer는 stress 기간 walk-forward (in-sample only), 1715 NAV는 production READ ONLY
- **AX-007 exemption #1 + #4**: multi-sleeve + ML sizing 동시 정합
- **L-279~L-281**: Hybrid multi-sleeve admit precedent direct 정합
- **Common Charter Principle 5 (Data Mining 방지)**: stress scenarios pre-defined (사후 cherry-pick 차단), 8 retain
- **Common Charter Principle 8 (No Silent Override)**: pre-2014 proxy caveat 명시 + qualitative pattern only declaration

---

## 12. Codex round (v3) C7/C9 PARTIAL_ACCEPT 정합

v3 Codex C7 (4 scenarios → 8 scenarios extension, 도훈 mandate) + C9 (pre-2014 proxy caveat):
- 8 scenarios retain
- GFC/Euro pre-2014 proxy caveat noted
- in-sample 6 primary

Path A inherit 100%.

---

## 13. Multi-sleeve admission decision flow (post-Forge)

```
1. risk-side: 32 cell stress matrix + Pareto frontier + abort/DEFER eval
2. optimizer-side: a_max optimal (Pareto + axis 1 SR ≥ 1.97 / axis 2 MDD ≥ -24.81%)
3. forge-side: 9 artifacts integration + AX-008 verification (Forge + Codex + Architect 2/3)
4. judge-side: Gate G0-G9 + 7-axis + 5b cost ≤ 20bps + multi_sleeve_charter_exception audit
5. governor-side: admit decision + book_state v2.3 → v3 mutation (도훈 explicit confirm multi_sleeve_charter_exception 필요)
```

risk-side 책임: stress matrix raw cell + Pareto + abort/DEFER trigger. **Weight 결정 X (optimizer 영역)**.

---

## 14. Forge cycle compute estimate

| Step | Compute |
|---|---|
| 8 stress scenarios × 4 a_max comp sleeve NAV measurement | ~1h CPU |
| Pareto frontier construction | trivial |
| Abort/DEFER trigger evaluation | trivial |
| **Total** | **~1h CPU** |

---

**End of artifact**. Step 5.6 (Codex Critic Round) 진행 — draft package 작성 후 spawn.
