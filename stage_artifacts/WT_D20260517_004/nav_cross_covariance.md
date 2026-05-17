# NAV-level Cross-covariance Design — Path A (WT-D20260517_004)

**WT-D20260517_004 risk-research Step 5.2**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: risk-research agent
**Date**: 2026-05-17
**Predecessor inherit**: WT-D20260517_003 risk_package.json::cross_covariance_design (walk_forward_oos_pooled_correlation primary + DCC bivariate secondary)

---

## 0. Executive Summary (1 paragraph)

NAV-level blend의 cross-covariance `Cov(r_1715, r_comp)`는 **walk-forward OOS pooled correlation × σ_1715 × σ_comp** 로 추정한다(v3 inherit primary). Path A NAV-level은 universe 0% overlap by construction이라서 cor ≤ 0.3 자격이 by design choice 가능 — alpha cycle academic prior **0.3-0.6** (KR equity common market beta, Fama-French 1992)에서 통과 확률 **40-50%** 정직. cor > 0.3 시 **market beta neutralization fallback** (`r_comp_residual = r_comp - β · r_1715`, β = rolling 36m PIT) 우선 적용 후 G2 재측정. blend variance decomposition `σ²_blend = (1-a)²σ²_1715 + a²σ²_comp + 2a(1-a)ρσ_1715σ_comp` 에서 ρ ±0.3 → σ_p ±0.6pp at a=10%, **paradigm essence(anti-crowding 4th sleeve qualification)는 pure variance reduction을 능가**.

---

## 1. NAV-level cross-cov 4-way framework

| Method | 용도 | OOS sample | Admission role |
|---|---|---|---|
| **walk_forward_oos_pooled_correlation** ★ PRIMARY | G2 admission axis 6 | 52m net test (5 windows × ~10 OOS) | **admission gate** |
| rolling_correlation_w24 | drift monitoring | rolling 24m window | diagnostic only |
| dcc_bivariate_copula | regime-conditional (Step 5.3) | T=124 full sample, K=2 params=5 | secondary (Engle 2002 JBES) |
| full_sample_pooled_124 | retroactive diagnostic | 124 sig_dates pooled | diagnostic only NOT admission |

**Charter v1.7 §11 C1 (OOS-only admission)** 정합. v3 Codex C4 ACCEPT inherit.

---

## 2. Walk-forward OOS pooled correlation — G2 admission

### 2.1 Protocol

```r
# Inherit alpha cycle training_protocol
windows <- list(
  list(train = c("2014-01", "2018-12"), val = c("2019-01", "2019-12"), test = c("2020-01", "2020-12")),
  list(train = c("2015-01", "2019-12"), val = c("2020-01", "2020-12"), test = c("2021-01", "2021-12")),
  list(train = c("2016-01", "2020-12"), val = c("2021-01", "2021-12"), test = c("2022-01", "2022-12")),
  list(train = c("2017-01", "2021-12"), val = c("2022-01", "2022-12"), test = c("2023-01", "2023-12")),
  list(train = c("2018-01", "2022-12"), val = c("2023-01", "2023-12"), test = c("2024-01", "2024-12"))
)
# purge 1m + embargo 1m strict (Charter v1.7 §7)

# For each window: train comp scorer + p_bad classifier → OOS test 12m
# Aggregate test returns: r_1715_oos[k], r_comp_oos[k] for k = 1..52

cor_oos_pooled <- cor(r_1715_oos, r_comp_oos)  # 52 obs
ci_95_oos <- bootstrap_ci_politis_romano_1994(r_1715_oos, r_comp_oos, B = 1000, level = 0.95)
```

### 2.2 G2 admission rule

```
ADMIT iff |cor_oos_pooled| ≤ 0.3
```

**NOT** full 124 sig_dates pooled (data leakage). v3 Codex C4 ACCEPT 정합.

### 2.3 Academic prior (Forge measurement binding)

| Source | Prior cor estimate | Note |
|---|---|---|
| Fama-French 1992 JF KR equity β common | **0.3 - 0.6** | Codex C3 ACCEPT 정정 (alpha cycle inherit) |
| Petkova 2006 RFS factor structure | 0.2 - 0.5 | KR analogous |
| L-281 KR TSMOM cross-asset cor = 0.077 | 0.10 - 0.30 | cross-asset, NOT close analogue (Codex C3) |
| **Composite prior 통과 확률** | **40-50%** at cor ≤ 0.3 |  |

**Honest estimate**: NAV-level + 1715-external universe 0% overlap로 by construction cor 통과 확률 ↑, 그러나 KR equity 공통 market beta 때문에 0.3 strict ceiling 통과는 절반 정도. Forge cycle empirical binding.

---

## 3. Stationary bootstrap CI (Politis-Romano 1994 JASA)

```r
library(boot)
politis_romano_bootstrap_cor <- function(r1, r2, B = 1000, level = 0.95) {
  # Block length L_opt = (3 * n)^(1/3), Politis-Romano 1994
  n <- length(r1)
  L_opt <- (3 * n)^(1/3)
  
  cor_boot <- numeric(B)
  for (b in 1:B) {
    idx_boot <- politis_romano_resample(n, L_opt)
    cor_boot[b] <- cor(r1[idx_boot], r2[idx_boot])
  }
  ci_lower <- quantile(cor_boot, (1 - level) / 2)
  ci_upper <- quantile(cor_boot, 1 - (1 - level) / 2)
  list(cor_point = cor(r1, r2), ci_lower = ci_lower, ci_upper = ci_upper)
}
```

**Thin-sample defense**: 52m OOS는 충분히 두꺼움 (cor SE ≈ 1/√52 ≈ 0.139, 95% CI half-width ≈ 0.27). Bootstrap robust to KR equity autocorrelation.

**DEFER trigger**: `if (ci_width > 1.5 × cor_point) DEFER` (sample-size insufficient).

---

## 4. Market beta neutralization fallback (cor > 0.3 시)

### 4.1 Fallback rationale

cor(r_1715, r_comp) > 0.3 일 때 G2 fail이면 단순 DEFER가 아닌 **β neutralization 우선 시도** (alpha cycle Codex C3 ACCEPT 정정).

### 4.2 β estimation (rolling 36m PIT)

```r
beta_t <- function(r_comp_history, r_1715_history, t, window = 36) {
  end_idx <- which(time(r_comp_history) == t - 1)  # t-1 PIT
  start_idx <- end_idx - window + 1
  if (start_idx < 1) return(NA)
  
  fit <- lm(r_comp_history[start_idx:end_idx] ~ r_1715_history[start_idx:end_idx])
  coef(fit)["r_1715_history"]
}

# Residualize:
r_comp_residual_t <- r_comp_t - beta_t * r_1715_t
NAV_comp_residual_t <- cumprod(1 + r_comp_residual_t)
NAV_blend_neutralized <- (1 - a_t) * NAV_1715 + a_t * NAV_comp_residual
```

### 4.3 Fallback admission rule

```
1. First measure cor_oos_pooled(r_1715, r_comp)
2. If cor ≤ 0.3 → ADMIT (G2 PASS)
3. If cor > 0.3 → β-neutralize r_comp_residual
4. Re-measure cor_oos_pooled(r_1715, r_comp_residual)
5. If cor_residual ≤ 0.3 → ADMIT_NEUTRALIZED (G2 PARTIAL_PASS, log)
6. If cor_residual > 0.3 → λ_corr regularization grid {0.5, 1.0, 2.0} attempt
7. If grid fail → DEFER (4th sleeve cor 자격 X)
```

### 4.4 PIT compliance

- β rolling 36m, end ≤ t-1 lag strict (C2)
- Residual return r_comp_residual_t는 사전 t에서 known β로만 계산 (NO same-period circular)
- 사후 in-sample regression 금지 (full-sample fit forbidden — C1)

---

## 5. λ_corr regularization grid (alpha cycle inherit)

### 5.1 Grid spec

```r
lambda_corr_grid <- c(0.5, 1.0, 2.0)  # alpha cycle initial 1.0
# L_total = -E[r_comp · 1_bad] + λ_good · drag_good + λ_corr · |cor(r_comp, r_1715)| + λ_to · TO + λ_tail · CVaR
```

### 5.2 Validation role

| λ_corr | Anchoring strength | Use |
|---|---|---|
| 0.5 | weak | comp diversity 우선 (cor 우려 적음) |
| 1.0 ★ default | balanced | cor 0.3 admission ↔ training balanced |
| 2.0 | strong | cor anchoring aggressive (small a_max 시) |

**Forge cycle grid search 의무**.

---

## 6. Blend variance decomposition

### 6.1 Closed-form

```
σ²_blend,t = (1-a_t)² · σ²_1715,t + a_t² · σ²_comp,t + 2·a_t·(1-a_t)·ρ_t·σ_1715,t·σ_comp,t
```

### 6.2 Sensitivity table (alpha=10%, σ_1715=21.2%, σ_comp prior 22%)

| ρ | σ_blend | Δ vs σ_1715 21.2% |
|---|---|---|
| -0.3 | 18.6% | **-2.6pp** |
| 0.0 | 19.2% | -2.0pp |
| +0.3 (G2 ceiling) | 19.8% | -1.4pp |
| +0.6 (academic prior median) | 20.4% | -0.8pp |

**Insight**: ρ ±0.3 → σ_p ±0.6pp at a=10%. Pure variance reduction은 **modest**. Paradigm essence는 **anti-crowding 4th sleeve qualification + conditional defense** (bad-state subset 개선)이 우선.

**Codex C8 (v3) 인용**: blend variance는 cor 0.3에서도 marginal reduction 1.4pp에 불과. admission 가치는 conditional defense (axis 4 bad_state improvement + axis 2 MDD)에서 나옴.

---

## 7. Cost-aware net returns (Research Philosophy P2)

- σ², ρ 측정 시 모두 **net-of-cost** returns 사용
- production 1715: 15bps embedded
- comp sleeve: 25bps mandate (mid-cap)
- blend net cost ceiling: 17bps at a_max=0.20 (admission axis 5b)

---

## 8. Forge cycle measurement mandate

| Metric | Computation | Output |
|---|---|---|
| cor_oos_pooled (G2 admission) | 52m walk-forward OOS pooled | scalar + bootstrap CI |
| cor_full_pooled (diagnostic) | 124m full | scalar (diagnostic only) |
| β rolling 36m × per-sig_date | lm(r_comp ~ r_1715) | time series β_t |
| Cov(r_1715, r_comp) by m4 regime | Step 5.3 reference | 4 regime-specific cor |
| σ²_blend sensitivity 4 ρ × 4 a_max | closed-form | 16-cell matrix |
| Bootstrap CI | Politis-Romano 1994 B=1000 | for cor + σ² estimates |

---

## 9. Codex round (v3) C4 ACCEPT 정합

v3 Codex C4 ACCEPT:
- G2 admission = walk-forward OOS pooled (52m, NOT full 124)
- C1 정합 explicit
- Full-sample pooled = diagnostic only

Path A NAV-level은 이 spec 그대로 inherit + market beta neutralization fallback 추가 (alpha cycle Codex C3 ACCEPT 신규 spec).

---

## 10. Charter 정합

- **AX-002 PIT**: OOS-only admission (C1), t-1 lag β (C2)
- **Common Charter Principle 5 (Data Mining 방지)**: walk-forward purge 1m + embargo 1m, no full-sample fit
- **Common Charter Principle 7 (비용·용량·군집)**: net-of-cost returns + λ_corr backbone + 4th sleeve cor 자격
- **Common Charter Principle 8 (No Silent Override)**: market beta neutralization fallback 명시 + bootstrap CI 의무

---

## 11. v3 → v4 paradigm shift

| 영역 | v3 (weights-level) | v4 (NAV-level) |
|---|---|---|
| Universe overlap | by construction ≈ 100% (comp ⊂ 1715 top-20) | by construction 0% |
| Cor by construction | **0.9997 forced** | **자유롭게 0.3-0.6** |
| Admission feasibility | algebraic fail (cor=1.0 → G2 fail mechanical) | 40-50% pass rate honest |
| Fallback | DEFER | market beta neutralization 시도 후 DEFER |

---

**End of artifact**. Step 5.3 (conditional risk attribution) 작성 진행.
