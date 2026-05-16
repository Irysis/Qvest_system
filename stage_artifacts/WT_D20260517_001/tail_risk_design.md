# Tail Risk + Stress Test Design — WT-D20260517_001 risk-research Step 5.2

**Author**: risk-research agent
**Date**: 2026-05-17
**Lineage**: alpha_package.json loss = -E[r] + γ|Δw|·c + λ·CVaR_5% → Risk Agent CVaR protocol

---

## 1. CVaR_5% / CVaR_1% measurement protocol

### 1.1 Definition (Rockafellar-Uryasev 2000)

For portfolio return distribution F_r:
- **VaR_α** = inf{r : F_r(r) ≥ α}
- **CVaR_α** = E[r | r ≤ VaR_α] (Conditional Tail Expectation)

α ∈ {0.05, 0.01} — 5% (regulatory standard), 1% (extreme).

### 1.2 DPL output 가정 시 측정

```
# Forge cycle emission 후 (dpl_v1_weights.pt + walk-forward 5 windows test period)
# Per sig_date: weights w_t (N × 1, top-20 nonzero)
# Per t+1 period: r_t+1 (N × 1, realized monthly return)
# Portfolio return: r_p,t+1 = w_t' r_t+1

r_p_series ← {r_p,t+1 : t ∈ test_windows}  # 52 monthly obs canonical

# Empirical CVaR (preferred for monthly data)
sorted_r ← sort(r_p_series, ascending)
threshold_5pct ← ceil(52 × 0.05) = 3  # 3 worst months
CVaR_5pct ← mean(sorted_r[1:3])  # bottom 3 months mean return

threshold_1pct ← ceil(52 × 0.01) = 1  # 1 worst month
CVaR_1pct ← sorted_r[1]  # worst month return
```

### 1.3 Bootstrap CI (Pfaff Ch.4)

```r
# Confidence interval via stationary bootstrap (Politis-Romano 1994)
boot_cvar <- function(r, alpha, B = 1000, block_size = 4) {
  cvar_boots <- numeric(B)
  for (b in 1:B) {
    indices <- ... # stationary bootstrap
    r_boot <- r[indices]
    cvar_boots[b] <- mean(sort(r_boot)[1:ceiling(length(r_boot) * alpha)])
  }
  c(point = quantile(cvar_boots, 0.5),
    lower_95 = quantile(cvar_boots, 0.025),
    upper_95 = quantile(cvar_boots, 0.975))
}
```

### 1.4 Acceptance threshold (DPL output ≪ baseline)

| Metric | DPL Target | Baseline STR_1715 reference | Hard Abort |
|--------|-----------|----------------------------|-----------|
| CVaR_5% (monthly) | ≥ -8% | ~-6.5% (255m est) | < -12% |
| CVaR_1% (monthly) | ≥ -15% | ~-11% (255m est) | < -25% |
| CDaR_5% (drawdown) | ≥ -25% | -24.81% admit | < -35% |

DPL은 loss function에 λ·CVaR_5% 직접 포함 — 학습 시 CVaR 최소화가 inherent. 따라서 baseline 대비 약간 우월 가능 (학습 효과).

---

## 2. 4 Stress Scenario Design (Pfaff EVT + 8대 stress periods inherit)

### 2.1 Scenario 정의

| # | Scenario | Period (YYYY-MM) | KOSPI200 worst month | Notes |
|---|----------|------------------|---------------------|-------|
| 1 | **2008 GFC** | 2008-09 ~ 2009-03 | -23.13% (2008-10) | 본 WT 124 sig_dates는 2016~ → **out-of-sample** historical replay |
| 2 | **2020 COVID** | 2020-02 ~ 2020-04 | -11.97% (2020-03) | DPL test window 2 (2023-2024) 외부, scenario stress |
| 3 | **2022 Inflation/Rate** | 2022-01 ~ 2022-10 | -12.81% (2022-06) | DPL test window 1 (2022) **in-sample stress** |
| 4 | **2024 KR Disinflation** | 2024-08 ~ 2024-12 | -7.20% (2024-08) | DPL test window 3 (2024) in-sample |

**Strategy choice**: 본 WT 124 sig_dates는 2016~2026 → 2008/2020은 OOS bootstrap stress, 2022/2024는 in-sample real test.

### 2.2 Stress test protocol (DPL output 가정)

```r
# Scenario A: In-sample real stress (2022, 2024)
# Forge cycle test_window predictions에서 직접 측정
# Method: r_p for 2022-Jan~Dec & 2024-Aug~Dec from realized test outputs

# Scenario B: OOS historical replay (2008, 2020) — Monte Carlo bootstrap
# Step 1: 2008-09~2009-03 KOSPI200 stock-level returns (7m × N stocks)
# Step 2: 2026-04 (latest sig_date) DPL weights w_2026_04 추출
# Step 3: simulate r_p = w_2026_04' × r_2008_period (assumption: DPL weights stable transferable)
# Step 4: Σ portfolio loss across 7 months
# Caveat: 본 method는 assumption-heavy. Forge cycle 보고서에 STRESS_HISTORICAL_REPLAY_CAVEAT 명시
```

### 2.3 Per-scenario stress thresholds

| Scenario | Monthly worst | Cumulative loss | Hard Abort |
|----------|--------------|-----------------|------------|
| 2008 GFC (7m sim) | ≥ -20% | ≥ -40% | < -50% cumulative |
| 2020 COVID (3m sim) | ≥ -15% | ≥ -25% | < -35% cumulative |
| 2022 Inflation (real) | ≥ -10% | ≥ -25% | < -35% cumulative |
| 2024 Disinflation (real) | ≥ -8% | ≥ -15% | < -25% cumulative |

위반 시 challenge_flags + Forge cycle abort 권고.

---

## 3. Regime-Conditional CVaR

### 3.1 KR Regime classification (m4 BOCPD + AR threshold inherit)

본 WT는 STR_1715_AR_on_M4_R05_overlay_PG2 동일 regime engine 활용:
- **NORMAL** (m4=1.0): KOSPI200 30~250d MA trend up
- **CAUTION** (m4=0.7): trend ambiguous
- **CRISIS** (m4=0.3, R05 active): trend down + tail dependence high

### 3.2 Conditional CVaR per regime

```r
# Forge cycle measurement
r_p_NORMAL <- r_p_series[regime_t == "NORMAL"]    # ~70% obs
r_p_CAUTION <- r_p_series[regime_t == "CAUTION"]  # ~20% obs
r_p_CRISIS <- r_p_series[regime_t == "CRISIS"]    # ~10% obs

CVaR_5pct_NORMAL <- empirical_cvar(r_p_NORMAL, 0.05)
CVaR_5pct_CAUTION <- empirical_cvar(r_p_CAUTION, 0.05)
CVaR_5pct_CRISIS <- empirical_cvar(r_p_CRISIS, 0.05)

# Crisis alpha conditional defense (AX-001 v2)
# DPL은 ML sizing — defense classification은 Forge bt_result post-hoc 측정
crisis_alpha_dpl <- mean(r_p_CRISIS) - mean(r_KOSPI200_CRISIS)
# AX-001 v2 conditional: crisis_alpha_dpl > 0 + bad/normal IC ratio > 1 → defense qualified
```

### 3.3 Output schema

```
qepm/stage_artifacts/WT_D20260517_001/tail_risk.json (Forge cycle emission)
{
  "cvar_5pct_overall": -0.0XX,
  "cvar_5pct_NORMAL": -0.0XX,
  "cvar_5pct_CAUTION": -0.0XX,
  "cvar_5pct_CRISIS": -0.XX,
  "cvar_1pct_overall": -0.XX,
  "stress_2022_in_sample": {"worst_month": ..., "cumulative_12m": ...},
  "stress_2024_in_sample": {...},
  "stress_2008_historical_replay": {...},
  "stress_2020_historical_replay": {...},
  "bootstrap_ci": {"cvar_5pct_lower": ..., "cvar_5pct_upper": ...}
}
```

---

## 4. EVT (Extreme Value Theory) — Pfaff Ch.7

### 4.1 GPD (Generalized Pareto Distribution) tail fit

본 WT는 monthly data 52 obs → EVT GPD fit 통계적 power 부족. **Forge cycle 권고**:
- threshold u = 75th percentile (POT — Peaks Over Threshold)
- `fExtremes::gpdFit(losses, u)`
- Hill α estimator (tail index)
- 결과: tail risk measure 정밀화 (CVaR vs GPD-derived)

### 4.2 Recommendation

본 WT n=52 → GPD fit 보조용. **primary measure = empirical CVaR + bootstrap CI**.

---

## 5. References

- Rockafellar R.T., Uryasev S. (2000) "Optimization of Conditional Value-at-Risk" *J. Risk* 2(3): 21-42
- Pfaff B. (2016) *Financial Risk Modelling* Ch.4, Ch.7 (EVT)
- Politis D.N., Romano J.P. (1994) "The Stationary Bootstrap" *JASA* 89(428): 1303-1313
- Acerbi C., Tasche D. (2002) "On the coherence of expected shortfall" *J. Banking & Finance* 26(7)
- 8대 stress periods reference: `strategy_analyzer.R:L498 def_stress_periods`
- L-326 sample size lesson (124 sig_dates × 52 test months)
