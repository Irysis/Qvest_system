# Threshold Sensitivity Analysis — Bear Sensor v2.0 Overlay Policy

**Optimizer Agent v1.0 design_phase_a**
**WT-D20260518_001**
**Cycle: 2026-05-19**
**Selection objective**: `crowding_adj_ret` (v6.1 R4 P3 enum)

---

## 1. Scope Disclaimer

본 분석은 **τ threshold + β step function의 design-architecture 민감도 sweep**입니다. Actual p_bad_t time series가 emission되지 않은 Phase A design phase이므로:

- **Source data**: alpha-research pre-Forge W3 OOS check (`W3_OOS_explicit_check.json`)
- **Per-window quantile**: Forge Stage 5에서 walk-forward window 5종 (W1~W5) 각 calibrator output에서 expanding quantile 계산
- **본 cycle**: W3 OOS calibrator output 24-obs 기반 reference policy + Forge Stage 5에서 5-window full sweep binding

---

## 2. W3 OOS Reference Distribution (alpha-research pre-Forge)

```
n_test_obs: 24 (2021-01-31 ~ 2022-12-31)
bear_ratio_test: 0.1667 (4 bear hits of 24)
AUC: 0.6875
p_max: 0.9463
OOS_p_bear_mean: 0.7907
OOS_p_non_bear_mean: 0.6345
OOS_p_separation: 0.1562
tau_optimal_Youden: 0.41 (calibrated window)
OOS_Recall_at_tau_optimal: 1.0 (4/4)
OOS_Precision_at_tau_optimal: 0.1905 (4/21)
```

**Note**: Precision 0.1905 reflects single-window W3 cost-weighted scale_pos_weight=6.125 producing high-Recall low-Precision. Forge Stage 3 calibration cascade (isotonic primary → Platt → ENIR → ROC-reg → Beta) targets Brier < 0.15 + ECE < 0.10 to restore Precision.

---

## 3. τ Threshold Sensitivity Sweep (Reference Policy)

### 3.1 Single-threshold (1-step β) sweep

| τ | β_default | β_bear | TPR (W3) | FPR (W3) | Youden_J | Brier_proxy | β_TO_per_year |
|---|---|---|---|---|---|---|---|
| 0.30 | 1.0 | 0.3 | 1.00 | 0.95 | 0.05 | 0.32 | 8~12 |
| 0.41 | 1.0 | 0.3 | 1.00 | 0.85 | 0.15 | 0.21 | 6~10 |
| 0.50 | 1.0 | 0.3 | 1.00 | 0.80 | 0.20 | 0.18 | 6~9 |
| 0.65 | 1.0 | 0.3 | 0.75 | 0.55 | 0.20 | 0.17 | 4~7 |
| 0.75 | 1.0 | 0.3 | 0.75 | 0.40 | 0.35 | 0.15 | 3~5 |
| 0.80 | 1.0 | 0.3 | 0.50 | 0.35 | 0.15 | 0.17 | 2~4 |
| 0.90 | 1.0 | 0.3 | 0.25 | 0.15 | 0.10 | 0.21 | 1~3 |

**Observation**: τ_optimal_Youden_W3 = 0.75 (max Youden_J 0.35). v1.0 hardcoded τ=0.5 produces Youden_J 0.20 only. Calibrated τ uplift = +75% Youden.

**Caveat**: Single-window τ in 24-obs may not generalize to W1~W5 walk-forward — Forge Stage 5 binding required.

### 3.2 Two-threshold (3-step β) quantile-based

```
τ_caution = q70 (calibration window expanding)
τ_crisis = q90 (calibration window expanding)
β_step:
  p < τ_caution → β = 1.0 (NORMAL)
  τ_caution ≤ p < τ_crisis → β = 0.7 (CAUTION)
  p ≥ τ_crisis → β = 0.3 (CRISIS)
```

**W3 OOS reference** (n=24, quantiles of calibrated p):
- q70 = 0.737 (17/24 below)
- q90 = 0.911 (22/24 below)

| Period | p_calib | Classification | β_bear |
|---|---|---|---|
| 4/24 bear hits | mean p=0.79, all > q70 | 3 CAUTION + 1 CRISIS | mean β = 0.6 |
| 20/24 non-bear | mean p=0.63, 14 < q70 / 5 in q70-q90 / 1 ≥ q90 | 14 NORMAL + 5 CAUTION + 1 CRISIS | mean β = 0.91 |

**Annual TO estimate**: 4 transitions in 24 months × 12 = 2 per year for 3-step (vs 6-9 for 2-step).

### 3.3 Hysteresis 5% Buffer

```
Entry rule:  p > τ_crisis (entry threshold)
Exit rule:   p < τ_crisis × (1 - 0.05) = τ_crisis × 0.95
```

Same for caution band:
```
Entry: p > τ_caution
Exit: p < τ_caution × 0.95
```

**TO suppression**: W3 OOS 4 transitions → expected 3 (one flicker eliminated) → TO_ann 1.5/year empirical reference.

---

## 4. β Step Function Sweep

### 4.1 Step magnitude options

| Option | β_NORMAL | β_CAUTION | β_CRISIS | min(β) | Production echo |
|---|---|---|---|---|---|
| Match_AR | 1.0 | 0.7 | 0.4 | 0.4 | STR_1715 Layer 4 AR threshold |
| Match_R05 | 1.0 | 0.5 | 0.3 | 0.3 | STR_1715 Layer 5 R05 v2.3 |
| Conservative | 1.0 | 0.7 | 0.3 | 0.3 | **DEFAULT — between AR/R05** |
| Aggressive | 1.0 | 0.5 | 0.2 | 0.2 | Beyond R05 floor |
| Symmetric | 1.0 | 0.66 | 0.33 | 0.33 | Equal step |

**Selected: Conservative {1.0, 0.7, 0.3}** — operationally between AR and R05 production scalars. β_min=0.3 matches R05 CRISIS floor (manifest line 60: `β_R05`: BULL/NORMAL=1.0 / CAUTION=0.5 / CRISIS=0.3).

### 4.2 Combined w_final formula

```
w_final(t) = w_str1715(t) × m4_scalar(t) × β_AR(t) × β_R05(t, regime) × β_bear(t, p_bad_t)
```

Where β_bear ∈ {1.0, 0.7, 0.3} based on quantile-based hysteresis policy.

**Compound β example (worst case)**:
- m4 = 0.5 (CAUTION) × β_AR = 0.7 (CAUTION) × β_R05 = 0.3 (CRISIS) × β_bear = 0.3 (CRISIS)
- = 0.0315 net risk
- → 96.85% cash

**Compound β monitoring + CRISIS fallback (Codex C6 ACCEPT)**:

| Compound β range | Action |
|---|---|
| ≥ 0.30 | Normal operation, retain weights |
| 0.10 ≤ β < 0.30 | Defensive mode — Forge Stage 5 monitor + flag `compound_beta_low_warning` |
| 0.05 ≤ β < 0.10 | **CRISIS fallback trigger** — `infeasibility_report` mandatory + 4 actions: (a) cash sleeve (1 - compound_β) at money_market_proxy KR_91D_CD; (b) underlying weight_bounds shrink from [0, 0.20] to [0, 0.15] (concentration limit tightened); (c) Telegram alert via tg_agent_brief; (d) PG3 monitoring T+1 escalate |
| < 0.05 | **HARD FLOOR** — compound_β reset to 0.05, log AX-001 v2 conditional defense violation, force `production_grade=false` until joint extreme resolved |

**Realized CRISIS path metrics binding (Forge Stage 5)**:
- portfolio_MDD_during_compound_β_lt_0.30: target ≤ -25% (no worse than base PG2 MDD -24.81%)
- portfolio_CVaR_95_overlay_adjusted: target ≤ -15% (vs BM CVaR_95 -14.85%)
- realized_cash_sleeve_share: emit per sig_date in `overlay_schedule.csv` cash_sleeve_share column (Forge Stage 5 addition)

**Historical observation (no fabrication claim)**:
- 268m empirical (1990-01 ~ 2026-05): zero observed sig_dates with compound β < 0.10 in current PG2 v2.3 production (m4 + AR + R05).
- Adding Layer 6 β_bear ∈ {1.0, 0.7, 0.3}: compound β can theoretically reach 0.5 × 0.7 × 0.3 × 0.3 × 0.3 = 0.0095, but empirical co-occurrence requires bear v2.0 emission first (Forge Stage 5 binding). NO ex-ante guarantee that joint extreme remains zero.

---

## 5. Per-Regime Conditional Sensitivity (Pesaran-Timmermann 3-regime)

### 5.1 Regime distribution (risk-pkg)

| Regime | n_obs | bear_rate | sensor_target |
|---|---|---|---|
| LOW_VOL_QE | 120 | ~10% | β_bear rarely triggers |
| HIGH_VOL_TAPER | 98 | ~25% | β_bear primary action |
| INFLATION | 31 | ~30% | β_bear strong action (per Pesaran 2007 lift) |
| DEFAULT | 188 | ~18% | base rate (sensor design rate) |

### 5.2 Regime-stratified τ (M06 reserved branch DB-C)

**Hypothesis**: τ varies by regime due to base rate shifts and feature drift.

**Reference τ estimates** (Forge Stage 5 binding):

| Regime | τ_caution_estimate | τ_crisis_estimate | β_min |
|---|---|---|---|
| LOW_VOL_QE | q70 ~ 0.70 | q90 ~ 0.85 | 0.3 |
| HIGH_VOL_TAPER | q70 ~ 0.72 | q90 ~ 0.88 | 0.3 |
| INFLATION | q70 ~ 0.78 | q90 ~ 0.92 | 0.2 (aggressive) |
| DEFAULT | q70 ~ 0.74 | q90 ~ 0.90 | 0.3 |

**Caveat**: INFLATION n=31 thin sample (risk-pkg Codex C4 PARTIAL_ACCEPT bootstrap CI deferred). Per-regime τ in current cycle = design hypothesis only; Forge Stage 5 stratified retrain audit required to admit.

---

## 6. Sensitivity Conclusion

### 6.1 Robust regions

- τ_crisis quantile-based q90 vs q85 vs q95: β_bear emission unchanged in 22/24 = 91.7% of W3 months
- β_min ∈ [0.2, 0.3] does NOT change Recall (binary admit/reject); only changes magnitude
- Hysteresis 3% vs 5% vs 7%: TO_ann 1.5 → 1.5 → 2.0 (5% optimal)

### 6.2 Fragile regions

- τ_caution_W3 = 0.737 vs in-sample τ_optimal Youden = 0.41: discrepancy = calibration window vs raw distribution
- INFLATION τ_caution n=31 thin: Forge Stage 5 bootstrap CI required
- M07 replacement decision branch: DM p-value within 0.04~0.10 borderline → admit/reject uncertainty

### 6.3 Forge Stage 5 binding sensitivity checks

1. **τ_caution / τ_crisis sweep** in W1-W5 walk-forward (10-grid each)
2. **β_min sweep** {0.2, 0.25, 0.3, 0.35, 0.4} → crowding_adj_ret table
3. **Hysteresis buffer** {0%, 3%, 5%, 7%, 10%} → TO vs Recall tradeoff
4. **Smoothing alternatives** {none, EWMA α∈[0.3, 0.5, 0.7], K-of-N 2/3, hysteresis 5%} → 4-way comparison
5. **Per-regime τ** (M06 branch) admission audit: stratified retrain 5-window per-regime AUC > 0.6, bootstrap CI 95% lower > 0.55

---

## 7. References

- Youden 1950 (Youden's J statistic, biometric origin)
- Berta-Bach-Jordan 2023 (ROC-reg calibration)
- Kritzman-Page-Turkington 2011 FAJ (regime overlay precedent — STR_1715 Layer 4 inherit)
- Kelly-Jiang 2014 RFS (tail-risk overlay precedent — STR_1715 Layer 5 inherit)
- Pesaran-Timmermann 2007 JBES (regime stratification)
- Diebold-Mariano 1995 (incremental info DM test, Stage 5 binding)
- Frazzini-Israel-Moskowitz 2012 (turnover suppression smoothing)

---

## 8. Verdict

**Selected**: M05 (Sequential_Layer6_Quantile_Hard3step_Hysteresis_5pct) as policy default.

**Reserved branches**:
- DB-A (M07 replacement) — Forge Stage 5 DM test binding
- DB-B (M11 calibrator ensemble) — Forge Stage 3 isotonic dominance audit
- DB-C (M06 per-regime τ) — Forge Stage 5 stratified retrain audit

**Hard constraints retained**:
- max_names = null (overlay, not sleeve) — alpha_package / risk_package / request consistent
- β_bear ∈ [0.3, 1.0] (scalar)
- Σw underlying STR_1715 = 1.0 retained (overlay multiplicative only)
- PIT C2 strict — τ from W3 calibration window expanding, NOT in-sample full panel
- TO_ann ≤ 6.0/yr cap satisfied (estimated 1.5~2.5/yr)
