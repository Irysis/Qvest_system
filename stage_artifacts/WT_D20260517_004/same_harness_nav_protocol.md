# Same-Harness NAV-Level Comparison Protocol — Blocker 3 Resolution

**WT-D20260517_004 alpha-research Step 2.4**
**Blocker 3 resolution**: WT_003 production SR 1.95 vs canonical SR 0.37 cross-base mismatch → NAV-level fair comparison
**Author**: alpha-research agent
**Date**: 2026-05-17

---

## 0. WT_003 Blocker 3 fail mode (정직 inherit)

### 0.1 Cross-base mismatch 증거 (admission_decision.json)

```
STR_1715_standalone in same_harness_comparison_dpl_rc.json:
  SR_ann:    0.6817   (40-month OOS subset, canonical harness)
  CAGR:      0.0345
  MDD:       0.0302
  Sortino:   2.1252
  Calmar:    1.1416

vs production STR_1715 5-Layer admit (book_state v2.3):
  Sharpe:   1.9536   (255-month full backtest)
  CAGR:     0.4150
  MDD:     -0.2481
```

**Discrepancy magnitude**: 1.9536 / 0.6817 = **2.87× ratio**. Cross-base mismatch quantified.

### 0.2 Root cause (정직 진단)

| Cause | Impact |
|---|---|
| (a) **Time period mismatch** | production 255m (full backtest) vs canonical 40m (WT_003 OOS subset only). 40m has fewer crisis recoveries → lower SR. |
| (b) **Measurement basis** | canonical = `forge_realized_share_based` (WT_003 admission_decision Line 27), production = PerformanceAnalytics + Backtest Contract v1.0 (5-Layer admit) |
| (c) **Cost basis** | canonical = "15bps one-way × Σ|Δw|" (WT_003 same_harness_comparison Line 5), production = same 15bps inherit (consistency 확인 필요) |
| (d) **Universe basis** | canonical may differ in feature_build LIQ 5e7 vs production 2e8 |

### 0.3 Why this matters for admission

WT_003 admission rule: `axis_1_overall_SR ≥ 1.97` (= 1715 SR 1.9536 + 0.0164 margin).
- 1.97 target은 **production SR 1.95 baseline**에 anchored
- 그러나 WT_003 same-harness measurement은 canonical SR 0.68만 보고
- → 1715의 "real" SR baseline 무엇? Admission decision impossible without resolved baseline.

본 cycle은 NAV-level same-harness comparison으로 이 문제를 근본 해소.

---

## 1. NAV-level fair comparison core principle

### 1.1 단일 측정 단위 = NAV (sleeve cumulative wealth)

```
NAV_1715_5Layer(t):  production frozen NAV time-series, monthly, 2014-01 ~ 2026-04
                     net of 15 bps × turnover × 2 (round-trip) cost
                     PerformanceAnalytics Return.portfolio() standard

NAV_comp(t):         sleeve B (comp universe, 1715 외부) cumulative NAV
                     net of 25 bps × turnover × 2 cost
                     same PerformanceAnalytics standard

NAV_blend(t):        (1 - a_t) · NAV_1715(t) + a_t · NAV_comp(t)
```

→ **모든 sleeve가 동일 measurement basis**: PerformanceAnalytics + Backtest Contract v1.0.

### 1.2 Comparison set (3 NAV time-series)

| NAV | Definition | Period |
|---|---|---|
| **NAV_1715_5Layer** | production frozen (READ ONLY) | 2014-01 ~ 2026-04 (255m + 17m extension) |
| **NAV_comp** | new sleeve B (Forge cycle 생성) | 2014-01 ~ 2026-04 (same period) |
| **NAV_blend** | blend (1-a_t)·1715 + a_t·comp | 2014-01 ~ 2026-04 (same period) |

→ 3개 모두 동일 period + 동일 measurement basis → **fair comparison**.

### 1.3 Sub-period comparison (PIT-clean)

| Sub-period | Months | Purpose |
|---|---|---|
| **Full backtest** | 2014-01 ~ 2026-04 (148m) | overall comparison |
| **In-sample (training)** | 2014-01 ~ 2018-12 (60m) | training period 비교 |
| **Validation** | 2019-01 ~ 2019-12 (12m) | hyperparam selection 비교 |
| **OOS test (combined)** | 2020-01 ~ 2026-04 (76m, 5 windows 합집합) | **decision-binding fair comparison** |
| Crisis 1: COVID 2020 | 2020-02 ~ 2020-06 (5m) | conditional defense audit |
| Crisis 2: 2022 inflation/war | 2022-01 ~ 2022-12 (12m) | conditional defense audit |
| Bull regime | 2020-07 ~ 2021-12 (18m) | good_state drag audit |

---

## 2. Production STR_1715 5-Layer NAV measurement

### 2.1 NAV source (READ ONLY)

```r
nav_1715_path <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds"
bt_result_1715 <- readRDS(nav_1715_path)
nav_1715 <- bt_result_1715$nav   # monthly NAV, length 255+
returns_1715 <- bt_result_1715$period_returns  # monthly returns
```

**Audit prerequisites**:
- `bt_result_1715$audit$integrity == "PASS"` (Backtest Contract v1.0)
- `bt_result_1715$manifest$cost_model_version == "v2.3_kr_retail_15bps"` (cost consistency)
- `bt_result_1715$strategy_spec$weight_bounds == c(0, 0.20)` (production constraint)
- `length(nav_1715) >= 255` (full backtest coverage)

만일 audit fail 시 → STOP + Q-Lead escalate (Forge cycle 위임).

### 2.2 Full-period metrics (PerformanceAnalytics standard)

```r
library(PerformanceAnalytics)
sr_1715_full <- table.AnnualizedReturns(returns_1715, Rf = 0)["Annualized Sharpe (Rf=0%)", ]
mdd_1715_full <- maxDrawdown(returns_1715)
cagr_1715_full <- (last(nav_1715) / first(nav_1715))^(12 / length(nav_1715)) - 1
```

**Expected (admit-time, L-308~L-313)**:
- SR 1.9536, MDD -24.81%, CAGR 41.50%

### 2.3 OOS-subset metrics (76m, decision-binding)

```r
oos_idx <- which(month_dates %in% seq.Date("2020-01-01", "2026-04-01", by = "month"))
returns_1715_oos <- returns_1715[oos_idx]
sr_1715_oos <- table.AnnualizedReturns(returns_1715_oos)["Annualized Sharpe (Rf=0%)", ]
```

→ Production 1715 OOS-only SR가 WT_003 canonical 0.68과 같은 period에서 측정. 이 값이 **same-harness baseline**.

**Critical**: 본 cycle은 production NAV의 "OOS subset SR"이 admission decision baseline. Full-period 1.9536은 reference only (publicized achievement). NOT used for admission gating.

---

## 3. Comp sleeve NAV measurement (Forge cycle spec)

### 3.1 Forge build pipeline

```r
# Phase B mini-Forge (next cycle):
sig_dates <- seq.Date("2014-01-31", "2026-04-30", by = "month")

for (t in sig_dates) {
  comp_universe_t <- build_comp_universe_t(t)  # KR_TOP500_LIQ1E8 \ STR_1715_top_20
  features_t <- load_month_factors_v2(t, universe = comp_universe_t, allowlist_v2_80)
  # → C15 strict: load_month_factors_v2() 경유
  
  scorer_t <- fit_complement_scorer_stage1_linear_ppp(features_t, ...)
  weights_comp_t <- top_k_extract(scorer_t, K = 20, liq_floor_2e8 = TRUE, bounds = c(0, 0.20))
}

returns_comp_monthly <- compute_returns_panel(weights_comp_t, sig_dates)
bt_result_comp <- build_bt_result(returns_comp_monthly, cost_bps = 25, ...)  # Backtest Contract v1.0
nav_comp <- bt_result_comp$nav
```

### 3.2 Cost basis (25 bps for comp sleeve, mandate-conditional)

```
cost_comp_per_round_trip = 25 bps × |Δw_comp(t)| × 1
                       (one-way × 1, sleeve 회전율 자체 적용)
                       
Expected annualized comp cost = 25 × annualized_TO_comp / 100
                              ≈ 25 × 4.5 / 100 = 1.125 pp (≈ 1715 production cost annualized 0.9 pp)
```

### 3.3 Cost validation (Backtest Contract v1.0 audit)

`audit_bt_result(bt_result_comp)` 의 10 checks:
- nav_strict_monotonic, period_returns_PerformanceAnalytics_standard, cost_basis_audit, ...
- audit FAIL 시 `metric_type='unavailable'` + `integrity='FAIL'` → **admission 차단**

---

## 4. NAV_blend measurement (PerformanceAnalytics standard)

### 4.1 Blend formula (per-month)

```r
# For each month t:
a_t <- clip(a_max * p_bad_1715_t, 0, a_max)  # a_t from G1 classifier forecast
nav_blend_t <- (1 - a_t) * nav_1715_t + a_t * nav_comp_t

# Returns (PerformanceAnalytics derivation):
r_blend_t <- nav_blend_t / nav_blend_{t-1} - 1
```

### 4.2 Blend rebalance cost (sleeve wealth-share rebalancing)

```r
# Per-month sleeve weight at decision time (NAV-derived):
w_1715_t <- (1 - a_t) * nav_1715_{t-1} / nav_blend_{t-1}
w_comp_t <- a_t * nav_comp_{t-1} / nav_blend_{t-1}
# Note: nav_{t-1} 사용 (PIT C2 t-1 lag strict)

# Cross-sleeve turnover cost (15 bps × 2 = 30 bps round-trip):
sleeve_rebal_turnover_t <- abs(w_1715_t - w_1715_{t-1})
cost_rebal_t <- sleeve_rebal_turnover_t * 0.0015  # 15 bps base

r_blend_net_t <- r_blend_t - cost_rebal_t
```

### 4.3 Aggregate metrics (5 metrics primary)

```r
sr_blend <- table.AnnualizedReturns(r_blend_net)["Annualized Sharpe (Rf=0%)", ]
mdd_blend <- maxDrawdown(r_blend_net)
cagr_blend <- Return.cumulative(r_blend_net, geometric = TRUE)^(12 / length(r_blend_net)) - 1
sortino_blend <- SortinoRatio(r_blend_net, MAR = 0) * sqrt(12)
calmar_blend <- cagr_blend / abs(mdd_blend)
```

---

## 5. 3-way fair comparison protocol

### 5.1 Comparison table (decision-binding)

본 protocol Phase B/C에서 산출:

| Metric | NAV_1715 (production) | NAV_comp (sleeve B alone) | NAV_blend (a_max optimal) |
|---|---|---|---|
| SR_ann (full backtest) | 1.95 (target retain) | TBD | ≥ 1.97 (axis_1) |
| SR_ann (OOS 76m) | TBD (production OOS-subset) | TBD | ≥ 1.715 (margin retained) |
| MDD | -24.81% | TBD | ≥ -24.81% (axis_2) |
| CAGR | 41.50% | TBD | TBD |
| TO (annualized) | (production retain) | ≤ 6.0 | ≤ 6.0 (axis_5) |
| Cost (bps annualized) | 15 bps × TO | 25 bps × TO | net 17 bps ≤ 20 bps |
| cor vs NAV_1715 | 1.000 | ≤ 0.3 (axis_6) | NA (auto-derived) |

→ 모든 metric **PerformanceAnalytics standard 단일**. Cross-base mismatch 해소.

### 5.2 Sub-period decomposition (conditional alpha audit)

```
Good months (bad_state = 0):
  SR_good_1715, SR_good_blend → drag audit (axis_3)

Bad months (bad_state = 1, n ≈ 27 in WT_003):
  SR_bad_1715, SR_bad_blend → improvement audit (axis_4)
  Expected: SR_bad_blend ≥ SR_bad_1715 + 0.30

Crisis windows (COVID 2020 + inflation 2022):
  cumulative drawdown 비교 → AX-001 v2 conditional defense audit
```

### 5.3 Statistical significance (Harvey-t + DSR)

```
5 Harvey-t specs: CAPM / FF3 / FF5 / Carhart4 / FF6 (WT_003 spec inherit)
  t-stat target: |t_NW| > 3.0 (Harvey 2016 multiple-testing)
  
DSR (Bailey-LdP):
  n_trials = 720 (label_def 9 × a_max 4 × G1_options 4 × walk_forward 5)
  SR_deflated = SR_obs · (1 - α · sqrt(2·ln(720) / n_obs))
  
Combined: 5 Harvey-t 모두 |t_NW| > 3.0 + DSR_deflated SR ≥ admission target ≥ 1.97
```

---

## 6. Decision rules — what counts as PASS

### 6.1 Strict ALL-pass criteria (admission)

```
DECISION = ADMIT iff:
  1. axis_1: NAV_blend full_backtest SR ≥ 1.97
  2. axis_2: NAV_blend MDD ≥ -24.81%
  3. axis_3: good-state drag SR ≤ 0.05
  4. axis_4: bad-state SR improvement ≥ +0.30
  5. axis_5: NAV_blend annualized TO ≤ 6.0
  6. axis_6: cor(NAV_comp, NAV_1715) ≤ 0.3
  7. axis_7: p_bad classifier OOS AUC ≥ 0.55
  AND
  G1 4-subgate ALL PASS (Step 2.3 spec)
  AND
  AX-008: Forge + Codex + Architect ≥ 2/3 PASS
  AND
  Harvey 5 t-spec |t_NW| > 3.0 all
  AND
  DSR Bailey-LdP deflated SR ≥ 1.97
```

### 6.2 Partial-pass → DEFER (정직)

- 7 axes 중 1-2 fail → DEFER + 사후 Forge tuning
- 3+ axes fail → REJECT (paradigm marginal)
- G1 ALL options fail → REJECT (paradigm inviable)
- AX-008 < 2/3 → DEFER + verification triangulation

### 6.3 Self-improvement decision rule (NOT loosened)

WT_003 admission_criteria **strict retain**. Phase B/C에서 measurement 개선만, gate 완화 X.

**Charter §8 No Silent Override**: "이 정도면 괜찮다" 합리화 차단. PASS 조건 ALL strict mandate.

---

## 7. Cross-base mismatch 완전 해소 audit

### 7.1 단일 measurement standard

| Item | Standard |
|---|---|
| NAV calculation | PerformanceAnalytics `Return.portfolio()` |
| Cost basis | 15bps (1715) + 25bps (comp) × |Δw| × round-trip |
| Time period | identical (2014-01 ~ 2026-04 full + 76m OOS subset) |
| Universe basis | production (2e8 LIQ floor) at sleeve B holdings extraction |
| Backtest Contract | v1.0 audit_bt_result() ≥ 9/10 checks PASS |

### 7.2 No more "forge_realized_share_based vs production"

WT_003 admission_decision Line 27: `"measurement_basis_primary": "forge_realized_share_based"`.
본 cycle: `"measurement_basis_primary": "performance_analytics_standard_with_bt_result_audit_v1"` (단일).

### 7.3 Backtest Contract v1.0 audit mandate

`audit_bt_result(bt_result_blend)` 10 checks PASS 의무:
- nav_strict_monotonic, period_returns_PerformanceAnalytics_standard, cost_basis_audit, ...

audit FAIL 시 `metric_type='unavailable'` + admission **차단**.

→ measurement coherence Hook 정합 (HEALTHY 100/100 retain).

---

## 8. Self-check (Blocker 3 resolution)

- [x] WT_003 cross-base mismatch (1.95 vs 0.68) 정직 inherit
- [x] NAV-level fair comparison single measurement basis 명시
- [x] PerformanceAnalytics standard 단일 적용
- [x] 3-way comparison protocol (NAV_1715 / NAV_comp / NAV_blend)
- [x] Sub-period decomposition (good / bad / crisis)
- [x] Statistical significance (Harvey-t + DSR n_trials 720)
- [x] Decision rule strict retention (WT_003 7-axis admit gate 완화 X)
- [x] Backtest Contract v1.0 audit mandate
- [x] 자기합리화 0건 (1.95 retain claim 폐기 — OOS subset SR이 binding)

**Charter §8 No Silent Override**: production full SR 1.95는 reference (admit-time achievement), admission decision은 **same-harness OOS 76m measurement** 이 binding. Forge cycle empirical measurement 의무.

**자기합리화 audit**:
- "Production SR 1.95이 baseline이므로 blend도 1.95 회복하면 OK" ✗ → "OOS 76m fair comparison baseline 사용 의무" ✓
- "Sample size sufficient" ✗ → "Walk-forward 5 windows aggregation + Harvey 5 spec |t_NW|>3 + DSR n_trials 720" ✓ 정량
- "측정 기준 통일은 cosmetic 변경" ✗ → "WT_003 cross-base mismatch 2.87× ratio → admission decision impossible without resolution" ✓ 정량

---

## 9. References

- WT-D20260517_003 admission_decision.json (cross-base mismatch evidence)
- WT-D20260517_003 same_harness_comparison_dpl_rc.json (canonical SR 0.6817 vs production SR 1.9536)
- `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds` (READ ONLY)
- `02_Infrastructure/contracts/build_bt_result.R` + `audit_bt_result.R` (Backtest Contract v1.0)
- `.claude/rules/backtest-contract.md` (10-component bt_result list)
- `.claude/rules/answer-principles.md` (PerformanceAnalytics standard functions only)
- PerformanceAnalytics: Carl-Peterson R package (`Return.portfolio`, `Return.cumulative`, `maxDrawdown`, `SortinoRatio`, `table.AnnualizedReturns`)
- Harvey-Liu-Zhu 2016 RFS (`t_NW > 3.0` multiple-testing correction)
- Bailey-Lopez de Prado 2014 JoPM (DSR formula)
- L-282 (PerformanceAnalytics convention reconcile manual vs PerfA +0.19 SR drift) — measurement coherence precedent
- L-313 (STR_1715 5-Layer R05 production promotion)
