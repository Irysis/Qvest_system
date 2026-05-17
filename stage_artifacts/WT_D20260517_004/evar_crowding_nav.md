# EVaR Worst-window + Crowding (NAV-level) — WT-D20260517_004

**WT-D20260517_004 risk-research Step 5.4**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: risk-research agent
**Date**: 2026-05-17
**Predecessor inherit**: WT-D20260517_003 risk_package.json::evar_worst_window_protocol + crowding_audit_extended

---

## 0. Executive Summary (1 paragraph)

NAV-level blend의 tail risk는 **EVaR (Ahmadi-Javid 2012) + SoftMin variant (Wood-Roberts-Zohren 2026 DeePM)** + 표준 CVaR/CDaR/Hill α/VaR_99/EVT-GPD 통합. λ_tail = 0.15 (v3 inherit, CVaR λ=0.3의 0.5x because EVaR ~1.5-2.5x CVaR). α ∈ (0.10, 0.20) softplus + log-sum-exp. Window size k ∈ {1, 3, 6}. **Crowding** 측정은 80 features (Acadian 2026 framework) sha256 `b3d667...8fb6ee` (v2 inherit) 기준 + comp universe(1715 외부) 적용 + 1715 vs comp 차이 diagnostic + role checklist standard 4-metric (TDC vs PG2 / HHI / style cor / family saturation L-219). **Path A NAV-level 특수성**: production 1715 NAV는 이미 5-Layer 통과한 already-crowding-audited (L-313 admit). comp sleeve crowding 자체 측정 + 1715 외부 universe로 sleeve overlap 자연 차단.

---

## 1. EVaR (Entropic VaR) — primary tail metric

### 1.1 Theoretical foundation (Ahmadi-Javid 2012)

```
EVaR_α(L) = inf_{z > 0} (1/z) · log(E[exp(z · L)] / α)
```

- Coherent risk measure (Artzner et al. 1999 properties)
- Entropic upper bound: **EVaR ≥ CVaR ≥ VaR** (Ahmadi-Javid 2012 §3)
- EVaR ~1.5-2.5x CVaR magnitude (KR equity empirical norms)

### 1.2 SoftMin EVaR variant (Wood-Roberts-Zohren 2026 DeePM)

```
SoftMin EVaR_α,β(L) = -(1/β) · log(α · E[exp(-β · L)])
```

- Smooth differentiable approximation (NN backprop compatible)
- β = smoothness parameter (large β → exact min)
- Used in **Stage 4 DPL-RC Neural** training loss (alpha cycle inherit)

### 1.3 Window size grid

```r
evar_window_size_grid <- c(1, 3, 6)  # months
# k=1: single-period worst tail
# k=3: quarterly sustained drawdown
# k=6: semi-annual drawdown-aware
```

### 1.4 α level grid

```r
evar_alpha_range <- c(0.10, 0.20)
# 124 × 0.10 = 12.4 obs (robust)
# 124 × 0.20 = 25 obs (conservative)
# α=0.05 default (CVaR) → 1.2 obs single-window noise unstable for EVaR worst-window
```

### 1.5 β smoothing grid

```r
evar_beta_smoothing_grid <- c(10, 50, 100)
# β=10: smooth, NN-friendly
# β=50: balanced
# β=100: near-exact min
```

### 1.6 3-way estimator comparison

| Estimator | Computation | Use |
|---|---|---|
| empirical_evar | sample-based inf z>0 of (1/z)log(E[exp(z·L)]/α) | Stage 1-3 |
| gpd_evar | Pfaff Ch 7 FRM POT 80%/90%/95% threshold + GPD MLE fit | EVT validation |
| softmin_evar_neural | PyTorch differentiable | Stage 4 Neural training |

---

## 2. EVaR admission role

**loss term internal NOT admission gate** (v3 inherit). Indirect admission axes:

- axis_2_mdd (worst-window penalty → drawdown control)
- axis_4_bad_improvement (tail-aware bad-state hedge)

### Stage grid explicit

| Stage | Tail metric |
|---|---|
| Stage 1 Linear PPP | CVaR α=0.05 only (alpha cycle inherit) |
| Stage 2 ElasticNet | CVaR α=0.05 only |
| Stage 3 LightGBM | CVaR α=0.05 only |
| Stage 4 DPL-RC Neural | SoftMin EVaR α=0.10, k=3, β=50 (additional variant) |

---

## 3. Extended tail risk audit (v3 inherit)

| Metric | Target/Cap | Role |
|---|---|---|
| CVaR_5 (alpha cycle inherit) | -0.05 (loss term training) | Stage 1-3 loss |
| **CVaR_95** | **-0.025** monthly cap | **admission alarm RF-R6** |
| CDaR_95 | drawdown-aware (Pfaff Ch 4) | diagnostic |
| Hill α | 0.2-0.4 prior (KR equity, Hill 1975) | tail thickness |
| VaR_99 | 1% quantile (EKM 1997) | extreme quantile |
| ES_99 | mean of bottom 1% | expected shortfall |
| EVT-GPD | POT 80%/90%/95% + ξ + σ_u (Pfaff Ch 7) | EVT validation |

**Forge cycle measurement mandate** + `tail_risk.json` fresh generation.

---

## 4. Crowding audit (Phase 2.C, Acadian 2026)

### 4.1 80 features framework

```r
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
feature_allowlist_v2 <- read_csv("stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv")
# sha256 verified: b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee
# n_features = 80, defensive 55%

crowding_t <- crowding_score_per_factor(
  features = feature_allowlist_v2,
  universe = comp_universe_t,  # 1715 외부, NOT full KR_top342
  sig_date = t
)
```

| Sub-component | Weight | Description |
|---|---|---|
| hhi_top | 0.30 | Top-N portfolio weight HHI (Acadian 2026) |
| vol_concentration | 0.25 | Top-N volume / market volume |
| passive_overlap_proxy | 0.25 | Benchmark overlap (KOSPI200) |
| demand_elasticity_proxy | 0.20 | Behmaram 2024 size-weighted rank reversal cost |

### 4.2 Thresholds

| Threshold | Value | Action |
|---|---|---|
| static_threshold_high | 0.75 | crowding_flags 자동 등재 LEVEL_HIGH alert |
| dynamic_3m_delta | 0.15 | RAPID_INCREASE alert (decay/crowding emergence) |

### 4.3 1715 vs comp diff diagnostic

```r
crowding_1715 <- crowding_score_per_factor(production_universe = STR_1715_top_20, ...)
crowding_comp <- crowding_score_per_factor(comp_universe = comp_universe_t, ...)
diff_score <- crowding_comp - crowding_1715
```

| Diff status | Action |
|---|---|
| crowding_comp < crowding_1715 (negative diff) | comp sleeve diversifies (best case) |
| abs(diff) ≤ 0.05 | NO_DIFFERENTIATION warn |
| crowding_comp > crowding_1715 + 0.20 | comp sleeve adds crowding (anti-pattern) |

### 4.4 Per-sig_date measurement

```r
# 80 features × 124 sig_dates = 9,920 crowding_score evaluations
# ~2.75h CPU (parallel future_lapply 5 workers 권고)
```

---

## 5. Role checklist standard crowding metrics (v3 inherit)

### 5.1 TDC vs PG2 admit book (Joe-Clayton 1997)

```r
library(copula)
tdc_lower <- empirical_tdc_lower(returns_comp_blend, returns_pg2_admit_book)
# Joe-Clayton 1997 empirical or t-Copula parametric (regime_garch.R inherit)
```

**Threshold alarm**: TDC ≥ 0.40 (crowded common tail)

### 5.2 HHI complement sleeve

```r
hhi_comp <- sum(weights_comp_top_k^2)
```

**Threshold alarm**: HHI ≥ 0.20 (overly concentrated)

### 5.3 Style correlation with PG2

```r
style_comp <- compute_style_exposures(weights_comp, c("Size", "Value", "Mom", "Quality", "Vol"))
style_pg2 <- compute_style_exposures(weights_pg2_admit, c("Size", "Value", "Mom", "Quality", "Vol"))
cor_style_pair <- diag(cor(style_comp, style_pg2))
```

**Threshold alarm**: any single style |cor| ≥ 0.70

### 5.4 Family saturation (L-219)

```r
family_distribution_comp <- table(family_assignment(weights_comp_features))
```

**Threshold alarm** (L-219 saturation penalty):
- family_A ≥ 51 → -20pp admit penalty
- family_A 21-50 → -12pp
- family_A 6-20 → -8pp

---

## 6. DPL-RC specific crowding threshold

| Metric | Threshold | Action |
|---|---|---|
| sleeve_overlap_1715_comp | warn ≥ 0.70 | COMPLEMENT_DEGENERATE warn |
| differentiation_min | abs(crowding_comp - crowding_1715) ≤ 0.05 | NO_DIFFERENTIATION warn |

**Path A NAV-level 특수성**: 1715 외부 universe(`KR_TOP500_LIQ1E8 ∖ STR_1715_top_20`)로 sleeve overlap by construction 0% — DEGENERATE warn 자동 회피.

---

## 7. NAV-level vs weights-level crowding

### 7.1 weights-level (v3) 한계

WT_003 weights-level A-option은 comp ⊂ 1715 top-20 → sleeve overlap = 100% → DEGENERATE warn 자동.

### 7.2 NAV-level (v4) 해소

- Universe 0% overlap by construction
- crowding_comp 자유 측정 (1715 외부 mid-cap residual)
- diff_score (crowding_comp - crowding_1715) 정직 측정 가능
- 1715 vs comp differentiation 자연 확보

---

## 8. Expected crowding scores (학술 prior, NOT measured)

| Sleeve | Universe | Expected crowding score |
|---|---|---|
| STR_1715 (production retain) | KR_top342 top-20 | already validated (L-307~313 admit), retain |
| comp sleeve B | KR_TOP500_LIQ1E8 ∖ 1715 top-20 | **LOW prior** (mid-cap residual 다양성) |

**Honest estimate**: 1715는 KR top-tier large-cap 집중 (반도체 9 names L-274) → high crowding 있음. comp는 mid-cap 분산 → low crowding 예상. diff_score expected negative (comp diversifies).

**Forge cycle empirical mandate**: 학술 prior 무효, 측정 결과 binding.

---

## 9. Forge cycle measurement mandate

| Metric | Output |
|---|---|
| 80 features × 124 sig_dates crowding_score | `stage_artifacts/WT_D20260517_004/crowding_per_factor.parquet` (9,920 rows) |
| Sub-components hhi/vol/passive/demand | per-feature per-sig_date breakdown |
| 1715 vs comp diff_score | scalar per sig_date |
| TDC vs PG2 admit book | scalar per sleeve |
| HHI complement | scalar per sig_date |
| Style cor with PG2 | 5-dim per sig_date |
| Family saturation L-219 | family count + penalty pp |
| EVaR worst-window 3 estimators × 4 a_max | 12-cell matrix |
| Extended tail risk (CVaR_95 / CDaR_95 / Hill / VaR_99 / ES_99 / EVT-GPD) | `tail_risk.json` fresh |

---

## 10. Charter 정합

- **AX-002 PIT**: crowding Date ≤ sig_date strict (C10), Usable_Date ≤ sig_date (C14)
- **C15**: `load_month_factors_v2()` 경유 (feature_db 직접 load 금지)
- **Common Charter Principle 7 (비용·용량·군집)**: crowding_score_per_factor.R 직접 mandate
- **Common Charter Principle 8 (No Silent Override)**: 1715 vs comp diff diagnostic 의무, LEVEL_HIGH alert 자동
- **Research Philosophy P5 (Risk Model 고도화)**: crowding_score + concentration + Acadian 2026 + Behmaram 2024

---

## 11. Codex round (v3) C6/C7 PARTIAL_ACCEPT 정합

v3 Codex C6 (tail risk role checklist 통합) + C7 (crowding role checklist 통합):
- CVaR_95 cap -0.025 admission alarm RF-R6
- TDC vs PG2 + HHI + style cor + family saturation L-219 통합

Path A inherit + comp universe(1715 외부) 적용 (paradigm 정합).

---

## 12. Forge cycle compute estimate

| Step | Compute |
|---|---|
| 80 features × 124 sig_dates crowding × parallel 5 workers | ~2.75h CPU |
| TDC + HHI + style + family saturation (4 role checklist) | ~0.5h CPU |
| EVaR 3 estimators × 4 a_max × 3 windows | ~1h CPU |
| Extended tail risk (CVaR_95 / CDaR / Hill / VaR_99 / ES_99 / EVT-GPD) | ~1.5h CPU |
| **Total** | **~5.75h CPU** |

---

**End of artifact**. Step 5.5 (multi-sleeve stress + integration) 작성 진행.
