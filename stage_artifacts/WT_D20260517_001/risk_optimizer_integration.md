# Risk Inherit ↔ Optimizer Integration — Step 4.4

**WT-D20260517_001 · optimizer-research Step 4.4**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Lineage**: risk_package.json (35.8KB, post-Codex final) / alpha_package.json / dpl_architecture.md / dpl_risk_attribution_design.md

---

## 0. Scope

Risk Agent의 Σ_stocks + FMP implicit-B + tail risk + crowding + condition number constraint를 DPL optimizer-research design에 통합. **Alpha 재해석 X, Risk 재정의 X**. 단지 inheritance + integration spec.

---

## 1. Σ_stocks LW oracle 60m rolling per-sig_date integration

### 1.1 Risk inherit spec

`risk_package.json::sigma_estimator_choice`:
- Primary: Ledoit-Wolf oracle 60m rolling
- Backup: Gerber + RMT (δ=1.0 or cond > 100 fallback)
- Condition number target ≤ 100 strict (Codex C2 ACCEPT)
- min_eigenvalue ≥ -1e-8
- subperiod stability ≥ 0.5 (Frobenius cor)

### 1.2 DPL optimizer integration

**Current DPL loss** (dpl_architecture.md §3.2):
```
L_total = -mean(r_p) + γ_cost · 0.0015 · mean(TO) - λ_cvar · CVaR_5%
```

**Σ_stocks 직접 사용 안 함** — DPL은 features → weights 직접, loss는 portfolio return + cost + CVaR (returns-based).

### 1.3 Risk-aware loss term 통합 가능성 검토

**Option A — Σ inherited variance penalty (recommended Phase 4)**:
```
L_total_v2 = -mean(r_p) + γ_cost · 0.0015 · mean(TO) - λ_cvar · CVaR_5% + λ_var · w' Σ w
```

**Pros**:
- Explicit variance budget (vs implicit CVaR-only)
- Risk-aware joint training (alpha + risk co-optimized)
- Pfaff Ch.10 (Robust Portfolio) 정합

**Cons**:
- Σ_t computation per sig_date (60m rolling LW) — Forge cycle compute overhead
- Backward pass: ∂L/∂w needs ∂(w'Σw)/∂w = 2Σw — easy, but ∂Σ/∂w = 0 (Σ is fixed input, not trainable)
- λ_var hyperparam search (new grid dim)

**Phase 4 adoption decision**: 본 Phase 3 v1.0은 **CVaR-only retain** (returns-based loss).
- CVaR_5% is empirically tighter tail-aware than parametric w'Σw (Rockafellar-Uryasev 2000)
- Σ-quadratic은 fat-tail KR equity 부적합 (Hill α 2.5+ heavy tail, normal-approximated quadratic underestimate)
- Forge cycle ablation 후 v1.1 검토

### 1.4 Phase 3 v1.0 integration spec

**Σ_stocks inherited usage** (DPL paradigm-defense):

| Use case | Mechanism | Forge mandate |
|---|---|---|
| Variance attribution (post-hoc) | FMP implicit-B reconstruction (risk_package §dpl_risk_attribution) | `dpl_risk_attribution.json` emit |
| Backward pass stability monitor | Σ cond ≤ 100 audit per window | `grad_norm` track, mean > 10 warn |
| Optimizer-comparison baseline (B1_MVO, B2_HRP, B3_ERC, B5_MaxDiv) | Σ_t = LW 60m rolling input | `optimizer_comparison.parquet` emit |
| Risk-constraint post-projection (sector / HHI / β) | Σ-derived sector decomposition | `sector_decomposition.parquet` emit |

---

## 2. FMP implicit-B 634 features integration

### 2.1 Risk inherit spec

`risk_package.json::paradigm_aware_sigma_structure`:
- Doctrine: DPL implicit-B paradigm (You-Zhang 2025 §3) → Σ = BΩB' + D 부적합
- Σ_stocks (LW oracle empirical 60m rolling) = **direct quantity of interest** for σ_p² = w' Σ_stocks w
- FMP-based implicit-B reconstruction = paradigm-correct variance attribution
- 634 features × 124 sig_dates × FMP regression (cross-sectional)
- Top-10 features explain ≥ 50% σ_p² target

### 2.2 DPL optimizer integration

**Optimizer-research role**: DPL은 features → weights 직접 paradigm → optimizer-research는 weight emission paradigm 검증 only. FMP는 risk-research deliverable.

**DPL feature gradient explanation 정합** (alpha CF-A2 + risk CF-R2 FMP linkage):

```python
# Forge cycle post-train (PyTorch + Captum)
from captum.attr import IntegratedGradients

ig = IntegratedGradients(dpl_model)
attrib = ig.attribute(X_t_input, target=None, n_steps=50)  # per sig_date

# attrib: tensor of shape (n_stocks, n_features) — per-ticker per-feature gradient × input

# Aggregate to per-feature contribution
feature_importance_per_sigdate = attrib.abs().mean(dim=0)  # n_features

# FMP regression cross-section per feature
for feature_f in features:
    fmp_coef_f, fmp_residual_f = regress(stock_returns, feature_exposure_f)
    fmp_per_sigdate[sig_date][feature_f] = {coef: fmp_coef_f, residual: fmp_residual_f}

# Variance decomposition
sigma_p_squared = w_dpl @ Sigma_stocks @ w_dpl
for feature_f:
    sigma_p_squared_f = w_dpl @ (fmp_f outer fmp_f) @ w_dpl × stock_var_f
    contribution_pct_f = sigma_p_squared_f / sigma_p_squared × 100
```

**Integration with Stage 2 Top-K**:
- Stage 2 Gumbel softmax top-K=20 selects subset of N=2000 stocks
- FMP_implicit_B per feature × top-20 selected stocks → variance attribution focused on actually-held positions
- → "Top-10 features explain ≥ 50% σ_p² target" (risk_package §paradigm_aware_sigma_structure)

### 2.3 Forge cycle obligation

- `FMP_implicit_B_per_feature.parquet` (634 features × 124 sig_dates × {coef, R², residual_var}) — risk-research mandate
- `dpl_risk_attribution.json` — optimizer-research consumes for sensitivity report
- `risk_adjusted_feature_ranking.csv` — top-10 features for explainability

---

## 3. CVaR_5% target -0.05 → λ_cvar 조정 검토

### 3.1 Risk inherit spec

`risk_package.json::risk_constraints_for_optimizer`:
- `cvar_5pct_target`: -0.06 (was -0.05 in request.json; **Codex C6 ACCEPT tightened**)
- `cvar_5pct_hard_abort`: -0.10
- 이유: STR_1715 baseline MDD -24.81% → DPL must improve → tighter target

### 3.2 DPL loss λ_cvar 검토

**Current spec** (dpl_architecture.md §3.2):
- λ_cvar ∈ {0.25, 0.5, 1.0} grid sweep
- Default: 0.5

**Risk_package c6 implication**:
- CVaR_5% target -0.06 (tightened from -0.05)
- λ_cvar 0.5는 medium penalty — Loss에서 -λ_cvar · CVaR_5% = -0.5 × (-0.06) = +0.03 contribution
- For target = -0.06 vs hard_abort -0.10 (4% gap) → tighter target → λ_cvar 권장 ≥ 0.5 (not lower)

**Optimizer-research recommendation**:
- Grid sweep {0.25, 0.5, 1.0} retain
- 그러나 ablation 후 λ_cvar = 0.5 OR 1.0 권장 (tighter CVaR target due to Codex C6 ACCEPT)
- Forge cycle: hyperparam 선택 시 CVaR_5% test 결과 ≤ -0.06 만족 트라이얼 우선

**Forge cycle gate (post-train)**:
```r
# Per-trial CVaR check
cvar_5pct_test <- quantile(r_p_test, probs = 0.05, na.rm = TRUE)
if (cvar_5pct_test < -0.10) {
  trial_status <- "HARD_ABORT_CVaR_FAIL"
} else if (cvar_5pct_test < -0.06) {
  trial_status <- "WARN_CVaR_TARGET_MISS"
} else {
  trial_status <- "PASS"
}
```

100 trials (5 windows × 20 random search) → select trial with min CVaR + max SR among PASS.

---

## 4. Crowding score per factor (Acadian 2026) integration

### 4.1 Risk inherit spec

`risk_package.json::crowding_audit`:
- **Track 1 (per-feature)**: 634 features × IG attribution × crowding score (Acadian 2026)
  - alert_threshold_high: 0.75
  - alert_threshold_delta_3m: 0.15
- **Track 2 (portfolio-level)**: standard expansion (Codex C8 PARTIAL ACCEPT)
  - TDC vs PG2 (Joe-Clayton)
  - HHI portfolio top20 ≤ 0.15
  - Sector_Lv2 HHI ≤ 0.30
  - Style cor (FF6/Carhart4) vs STR_1715 ≤ 0.5
  - Family saturation L-219 ≤ 3 features per single family

### 4.2 DPL output regularization 검토

**Risk Agent c8 inheritance**: portfolio HHI ≤ 0.15, sector HHI ≤ 0.30.

**Optimizer-research role (post-Codex C10 ACCEPT — assumption → Forge measurement obligation)**:
- HHI portfolio top20: DPL Stage 3 cap 0.20 + Stage 4 normalize 후 **Forge measurement obligation** (bounds: floor 0.05 EW fallback, ceiling 0.20 hard via cap).
- HHI > 0.15 위반 시 → trial reject (Forge gate). AX-007 #4 ML sizing exemption validity는 Forge HHI 비-EW 측정 의무 (alpha CF-A11 inherit).
- Sector HHI: **Forge measurement obligation**. 가정 없음 — 학습된 모델이 sector concentration 발생 가능, Forge gate ≤ 0.30 strict assertion.

**Phase 3 v1.0 regularization decision**:
- **추가 regularization 없음** — DPL output은 자체 ML sizing (top-20 spread) → Forge post-train gate.
- Forge cycle gate: HHI > 0.15 or sector HHI > 0.30 시 → trial reject.

**Optional Phase 4 regularization** (deferred):
- Loss에 `λ_hhi · w'w` (HHI penalty) 추가
- Sector dummy reg: `λ_sec · Σ_s (Σ_{i in sector_s} w_i - target_s)²`
- 본 cycle은 단순한 hard constraint check (Forge gate) — regularization 추가 시 hyperparam grid 5-dim → 7-dim, training time × 1.5

### 4.3 Crowding portfolio decision rule

`risk_package.json::crowding_audit.track_2_portfolio_level_codex_c8_expansion.decision_implication`:
- DPL_crowding < STR_1715_crowding AND TDC < str1715: 4th orthogonal source 자격 강화
- DPL_crowding ≈ STR_1715_crowding AND TDC ≈ str1715: substitution sleeve 검토
- DPL_crowding > STR_1715_crowding OR HHI_portfolio > 0.15: DEFER admit

**Optimizer-research action (post-Codex C10 ACCEPT)**: 
- 본 design phase는 DPL weights spread architecture spec emit only (Stage 2 Gumbel τ=0.1 + Stage 3 cap 0.20).
- **Forge cycle HHI 측정 의무** — design phase 추정치 없음 (assumption 정정).
- Decision rules (risk_package §crowding_audit Track 2): DPL_crowd < STR_1715 → 4th-orth 강화 / ≈ → substitution 검토 / > → DEFER. Forge measurement 정합.

---

## 5. Hard constraint compliance audit

Risk_package §risk_constraints_for_optimizer를 DPL design과 cross-check:

| Risk constraint | Risk_package value | DPL design provision | Verdict |
|---|---|---|---|
| max_factor_exposure | null (implicit-B) | FMP per-feature top-10 ≥ 50% σ_p² target | ✓ (post-hoc) |
| max_sector_weight | 0.30 | Forge gate (sector HHI ≤ 0.30 audit) | ✓ post-train |
| cvar_5pct_target | -0.06 | Loss λ_cvar grid + Forge gate -0.10 hard abort | ✓ |
| cvar_5pct_hard_abort | -0.10 | Hard abort | ✓ |
| condition_number_max | 100 strict | Forge per-window Σ cond audit; backward pass stability | ✓ |
| subperiod_stability_min | 0.5 | walk-forward 5 windows + Jaccard top-10 features ≥ 0.4 | ✓ |
| crowding_feature_alert_max | 100 | Track 1 per-feature 79K rows, threshold 100 alerts | ✓ |
| crowding_portfolio_threshold | DPL_crowd > STR_1715 → DEFER | Forge measurement | ✓ |
| hhi_portfolio_top20_max | 0.15 | Forge gate (DPL output HHI audit) | ✓ |
| hhi_sector_lv2_max | 0.30 | Forge gate | ✓ |
| style_correlation_vs_str1715_pairwise_max | 0.5 | G2 substitution gate (alpha-stage) | ✓ |
| family_saturation_per_family_max | 3 | Risk Track 2 expansion | ✓ |
| jaccard_top10_stability_min | 0.4 | Risk dpl_risk_attribution §stability_check | ✓ |
| min_eigenvalue_tol | -1e-8 | Σ_stocks min_eig audit | ✓ |

**Verdict**: 14/14 PASS — risk_package constraints 정합 with DPL design.

---

## 6. Forge cycle integration mandate

본 doc은 Forge cycle implementation의 inheritance reference:

1. **Loss function final**: `-mean(r_p) + γ_cost · 0.0015 · mean(TO) - λ_cvar · CVaR_5%`
   - λ_cvar grid {0.25, 0.5, 1.0}, prefer ≥ 0.5 due to Codex C6 tighter target
2. **Σ inherit**: per-sig_date LW oracle 60m rolling, cond ≤ 100 strict
3. **FMP per-feature**: post-train Captum IG attribution + cross-sectional regression
4. **CVaR test gate**: per-trial cvar_5pct_test ≤ -0.06 prefer, hard abort < -0.10
5. **HHI / sector / style gate**: post-train Forge audit (no Loss regularization Phase 3)
6. **Backward pass stability**: grad_norm tracking, clip max_norm=1.0
7. **Optimizer comparison**: 6 baseline (B1-B6) with risk_package Σ_t input — `optimizer_comparison_protocol.md` reference

---

## 7. Codex Round disposition expectations

본 doc Codex Critic Round (optimizer stage) 입력:

1. **λ_cvar grid lower bound 0.25**: Codex C6 tightened CVaR target (-0.06) 시 grid lower bound 0.5 권장 가능. Disposition.
2. **HHI regularization Phase 4 priority**: Codex가 Phase 3 즉시 regularization 권고 시 disposition.
3. **Σ-quadratic loss term**: Phase 4 deferred decision retain. Codex 즉시 추가 권고 시 disposition.
4. **Risk_package C2 cond ≤ 100 strict**: 정합. Codex 추가 권고 없을 시 retain.

---

**Submitted**: 2026-05-17 optimizer-research Step 4.4 deliverable. Risk inheritance ↔ DPL optimizer integration spec complete. Forge cycle implementation reference.
