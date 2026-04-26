# Risk Challenge Note — WT-D20260426_008 (Iter 15 V3)

**Author**: Risk Research Agent
**Date**: 2026-04-26
**Target**: Alpha Package (Track A V3 STR_1701 Direct Upgrade)
**Status**: REVIEWED + ESCALATIONS (objection=TRUE)

---

## 1. Targets reviewed

- `alpha_package.json` (V3 vector + factor_specs + ax_axiom_compliance)
- `confidence_vector` (20 names)
- `factor_specs` (Analyst_Consensus + RegimeOverlay + TurnoverDampening)
- `regime_classification` (lambda_neutral selected — λ=1 across regimes)
- `inheritance_proof` (cor 0.9284 vs STR_1701)

## 2. Objections (2)

### O1. **Crisis-coupling structural risk inherited from STR_1701** (severity=MEDIUM)

Alpha package reports `bootstrap_ci.crisis_ic_mean = -0.1945` with CI95=[-0.2827, -0.0834], n_crisis=5. This is a structural inheritance from STR_1701 base scores (V3 score-level cor 0.93 — confirmed by Risk-side measurement: per_date_mean cor=0.9319). Risk-side confirms:
- CRISIS regime panel T=6 months in regime_panel
- CRISIS regime Σ cond=218.20 > 100 (small-sample instability)
- Pooled fallback Σ provided with binding rule (cond=100.00 PSD T=57)

**Risk Agent does NOT validate this as benign**. Optimizer **must** apply CRISIS-conditional weight tightening or pooled-Σ fallback. λ_neutral mutation does NOT mitigate CRISIS coupling — by design, λ_BULL=λ_NORMAL=λ_CAUTION=λ_CRISIS=1.

### O2. **DSR FAIL (1.739 < 3.0) under multi-test penalty** (severity=MEDIUM, INFO_TO_FORGE)

Alpha pkg `graduation_status.dsr_gate.pass=false` at threshold 3.0. n_trials_full_grid=72 honest disclosure. Risk Agent flags this as remaining structural risk despite Harvey 5/5 PASS. PG2 incremental SR uplift (target +0.05~0.15) within DSR uncertainty band. Forge backtest realized PG2 SR comparison vs baseline 1.4625 must apply Bailey-Lopez de Prado deflation explicitly.

## 3. INFO escalations (no objection but explicit measurement)

### I1. **V3 ↔ STR_1701 score per_date cor = 0.9319** (vs alpha pkg claim 0.9284 — within 0.4pp)

Risk-side re-measurement confirms L-224 PASS (≥ 0.85 mandate). Higher than claimed — consistent with V3 being direct upgrade of STR_1701 base. **Iter 14 학습 적용 (silent omission 금지)**: explicit measurement disclosed.

### I2. **V3 NAV proxy ↔ STR_1701 monthly NAV cor = 0.0463** (Pearson, n=215)

Despite score cor 0.93, realized monthly NAV correlation diverges to ~0.05. Driver: top-20 cross-section divergence (Jaccard=0.48) + persistence buffer + EW averaging produce low-cor realized P&L. **TDC q5 = 0.0909** (n_both=1/n_str=11) — minimal joint tail dependence at portfolio level.

### I3. **V3 ↔ STR_1656 cor = -0.0905** (cross-family diversifier preserved)

TDC q5 = 0.0 (no joint q5 tail hits). 20% STR_1656 slot in PG2 retains independent alpha source. PG2 blend(V3 80 + STR_1656 20) ↔ PG2 active cor = 0.0247 — essentially independent at NAV level despite score-level overlap.

## 4. Risk-vs-Alpha role boundary

Risk Agent **measures** common-risk structure + tail/stress diagnostics. Risk does **NOT** endorse Alpha rationale. Specifically:
- Risk does NOT validate `RF-A2 dilutive` REBUTTAL (composite vs core_only ICIR judgment) — that belongs to Forge realized SR/IR.
- Risk does NOT validate `regime-λ INERT` claim (Codex finding) — λ_neutral selection means regime tilt has zero alpha effect, but Risk Σ uses no λ.
- Risk does NOT prescribe weights or hard caps. Cap thresholds (CVaR<2.5%, MDD<45%, stress<25%) belong to Optimizer/Forge/Governor decision gates.

## 5. Hand-off bindings

| Binding | Recipient | Strength |
|---------|-----------|----------|
| Pooled fallback Σ in CRISIS/CAUTION regimes | Optimizer | MUST |
| PG2 'V3 80 + STR_1656 20' is REPLACEMENT (not additive blend) | Forge | MUST |
| Realized SR comparison vs PG2 active baseline 1.4625 | Forge | MUST |
| DSR deflation under 72-trial multi-test penalty | Forge/Judge | MUST |
| Crowding monitoring V3 score-level vs production going forward | Monitoring | SHOULD |

## 6. PIT compliance (C1~C15)

PASS — PIT_HARD_CUTOFF=2023-11-30 enforced, EST_END=2023-11-01, FF5/RAWDATA filtered, lockbox 2024-01-23~ untouched. Score schema inherits Iter 11 (verified via score_eff_str1701 column).

## 7. Σ structural quality

- Method: factor_model BΩB' + D, Ω = Ledoit-Wolf oracle
- Σ cond=22.83 (well below 100 threshold)
- PSD: TRUE, min_eig > 0
- Factor coverage: ~25% R² (KR concentrated equity structural property)
- Multi-sleeve cor_core_def=0.611, diversification benefit=9.06%
- Pooled fallback Σ cond=100.00 PSD T=57

## 8. Final stance

**objection = TRUE**, two MEDIUM-severity escalations (O1 CRISIS coupling + O2 DSR FAIL). Risk Agent role limited to measurement and binding recommendations to Optimizer/Forge. No alpha modification, no weight proposal.
