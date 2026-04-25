# Risk Agent Challenge Note — WT-D20260425_011 (Iter 6 MEGA_06)

**Date**: 2026-04-25
**Agent**: Risk Research (Opus 4.7)
**Parent task**: WT-D20260425_011 (Iter 6 MEGA_06_STR1699_Kelly_Overlay)
**Inherits**: WT-D20260425_010 risk methodology + Codex triage precedent

---

## 1. Σ Estimation Summary (Iter 6)

| Metric | Value | Status |
|---|---|---|
| Σ method | factor_model BΩB' + D | — |
| Ω estimator | ledoit_wolf_oracle | selected (5 candidates compared) |
| LW shrinkage rho (Ω, factor cov) | 0.0203 | explicit (Codex ACCEPT fix) |
| Σ cond post-shrink | **19.14** | PASS (≤ 100) |
| Σ min eigenvalue | 3.21e-3 | PSD verified |
| Ridge lambda | 0 | not needed |
| Factor coverage R² mean | 23.0% | KR concentrated equity structural |
| Top common risk | MKT 19.1% | RF-R1 PASS |
| Multi-sleeve cor (Core/Defense) | 0.597 | improved from Iter 5's 0.692 |
| Diversification benefit | 9.15% | improved from Iter 5's 7.27% |
| Hill α (top 5%) | 3.00 | RF-R6 PASS (no extreme heavy tail) |
| Worst stress (cum_ret) | -28.14% (GFC 2008) | RF-R4 HIGH flagged |
| Kelly+Overlay compat | PASS | vol_ratio=1.688 → VolReg scale=0.59 |

---

## 2. Iter 6 Specific: Kelly + Overlay Σ Compatibility (NEW)

Iter 6 alpha_package.handoff_to_optimizer specifies four overlay layers as Optimizer-domain machinery. Risk Agent verified Σ-consistency without modifying alpha or weights.

| Spec | Value | Σ-implied check |
|---|---|---|
| Kelly_fraction (frac05) | 0.5 | per-name cap 0.10 binds before Kelly |
| VolReg target (annualized) | 0.12 | realized 0.2026 → ratio 1.69 → scale 0.59 PREDICTED |
| DD Brake light/medium/heavy | 0.06/0.08/0.20 | path-dependent; Σ implies 12M-rolling-min-DD prob 0.90/0.81/0.24 (context only) |
| FM Regime cash 0/5/15/30% | BULL/NORMAL/CAUTION/CRISIS | regime_state column present in alpha_scores |

**Compatibility status**: PASS (sigma_psd && sigma_cond ≤ 100 && vol_ratio ∈ [0.5, 5]).

---

## 3. Codex Critic Round 1 — Triage

Codex final stance: **REJECT** (no veto). Critical concerns: 8.

### ACCEPT (3 fixes applied to risk_package)

1. **SHRINKAGE_DELTA_AND_SELECTION_OBJECTIVE_UNAUDITABLE** (MEDIUM)
   - Fix: LW oracle shrinkage intensity rho=0.0203 explicitly logged (`sigma_estimation.shrinkage_intensity_rho`).
   - Fix: Selection rule rationale documented: LW preserves cross-factor correlation; diag_shrink (cond=37.7) marginally lower but zeros off-diagonals — destroys structural fidelity required by Σ = BΩB' + D.

2. **PIT_LINEAGE_ASSERTED_NOT_VERIFIED** (HIGH)
   - Fix: `pit_compliance.lineage_citations` block added with explicit cross-WT citations:
     - FF5 v2 → WT-D20260425_009 (Iter 4) Mandate 4 PASS
     - regime_panel → WT-D20260425_007 (Iter 2) C1+C2+C9+C11
     - RAWDATA → .cache/rawdata.parquet, hard cutoff 2023-10-31
     - factor_db → Alpha agent's wt011_lmf_equivalence_proof at sig_date 2023-11-01

3. **CRISIS_FALLBACK_FLAG_INCONSISTENCY** (HIGH, internal surfacing)
   - Fix: `per_regime_meta.CRISIS.fallback` set to TRUE with binding_reason. Pooled fallback Σ (cond=100) BOUND for Optimizer in CRISIS regime.

### PARTIAL (1)

4. **CRISIS_REGIME_SIGMA_UNRELIABLE** (HIGH)
   - Bootstrap LW oracle on CRISIS panel (T=6, B=500): **cond_mean=611.7, CI95 [98.6, 2540]**, mean_corr=0.229 CI95 [0.062, 0.364]. Wide CI confirms small-sample uncertainty.
   - The CRISIS LW point estimate (cond=107.9 from main pipeline) is REPORTED for completeness; **Optimizer is INSTRUCTED to use pooled fallback** (cond=100) per binding_rule.
   - RF-R8 challenge flag added with bootstrap details.

### REBUTTAL (5)

5. **TAIL_AND_MDD_CAP_BREACH_DEFERRAL** (HIGH)
   - **Iter 5 (WT-D20260425_010) Codex precedent**: REBUTTAL_VALID. Hard caps are Optimizer/Forge gates per Charter §8 boundary.
   - EW top-20 21-year proxy MDD=-56.2% reflects unhedged concentrated equity (incl. GFC 2008 peak-to-trough). This is Σ INPUT, not portfolio metric.
   - Iter 6 Kelly+Overlay (Optimizer-domain) reduces realized tail: VolReg compresses 0.20 → 0.12 ann (scale 0.59); DD Brake heavy → cash 50%; FM Regime CRISIS → cash 30%.
   - Risk DOES flag breaches: RF-R4 stress -28.14% HIGH, RF-CRISIS-COUPLING MEDIUM, RF-R8 regime small sample MEDIUM.
   - **Decision**: REBUTTAL_VALID (Iter 5 precedent + Risk-vs-Optimizer role boundary).

6. **FACTOR_COVERAGE_BELOW_GATE** (HIGH)
   - **Iter 5 Codex precedent**: PARTIAL_ACCEPT for this exact concern (KR structural property).
   - B_DT R² range 0.089~0.522 (mean 0.230). Σ remains PSD with cond=19.14 — factor model + diagonal D structure intact.
   - Higher LW shrinkage to identity (rho already 0.020 — modest) would REDUCE structural information further. Stronger D treatment risks inflating idio variance, breaking Σ = BΩB' + D fidelity.
   - **Decision**: REBUTTAL_VALID (KR concentrated equity property, not estimation flaw).

7. **PG2_CROWDING_NOT_MEASURED** (HIGH)
   - Direct PG2 alpha vector unavailable: STR_1656 is ML-model output without trail; STR_1631 SYN_05 alpha vector not exposed in mailbox.
   - **Q-Lead 2026-04-25 update** (`fair_comparison_note.md`): STR_1699 vs MEGA_05 fair-period (243m) pairwise NAV cor=**0.10** — strongest direct comparison currently available; very low.
   - Iter 6 = STR_1699 alpha + MEGA_05 machinery (Optimizer-domain handoff). The 0.10 cor refers to STR_1699 NAV vs MEGA_05 NAV, NOT Iter 6 itself.
   - Risk's Jaccard=0.111 vs Iter 5 (intentional inheritance) and HHI=0.054 are alpha-vector level proxies. Portfolio-level realized correlation against PG2 NAV is FORGE backtest deliverable.
   - **Decision**: REBUTTAL_VALID (data unavailability + boundary).

8. **WALK_FORWARD_WEIGHTS_ABSENT** (HIGH)
   - weights.csv is OPTIMIZER artifact (Charter §8 boundary). Risk Agent does NOT produce weights.
   - alpha_scores.parquet 69715 rows × 239 sig_dates × 773 tickers verified — full Date×Ticker panel. Optimizer consumes per-sig_date selection.
   - **Decision**: REBUTTAL_VALID (Charter §8 boundary; Optimizer domain).

9. **AX001_DEFENSE_CLAIM_NOT_VALIDATED** (HIGH)
   - Risk MEASURES bad/normal IC ratio (-1.8355 from Alpha agent CRISIS bootstrap n=5).
   - Risk MEASURES per-regime CVaR_95: BULL -2.28%, NORMAL -2.51%, CAUTION -5.09%, CRISIS -3.75% (top-20 EW proxy).
   - AX-001 v2 conditional defense (multi-sleeve + crisis_alpha + bad/normal IC ratio + core MDD mitigation) is FORGE backtest deliverable on Kelly+Overlay portfolio returns.
   - Iter 6 enhancement: FM_Regime overlay forces cash 30% in CRISIS — Optimizer-domain machinery.
   - **Decision**: REBUTTAL_VALID (Forge backtest delivers AX-001 v2 conditional metrics).

---

## 4. Challenge to Alpha (R3 v6.1 — required by GAP-1)

**objection** = TRUE (not silent — 3 explicit objections):

1. **RF-CRISIS-COUPLING** (inherited Iter 5): Alpha CRISIS IC -0.173 (n=5) is structural risk that Risk cannot resolve. Optimizer must apply CRISIS-conditional weight tightening + pooled-Σ fallback + FM_Regime cash 30% layer.

2. **RF-A1 sub_stab 0.041 < 0.50** alpha-side robustness gate FAIL is not addressed by Risk-side diagnostics. Iter 5 acceptance + Iter 6 inherits — Forge backtest must validate Kelly+Overlay machinery compensates at portfolio level.

3. **Iter 6 Kelly+Overlay specs received** via handoff_to_optimizer. Σ predicts realized port vol/target ratio. VolReg scaling (12% target) Σ-consistent if vol_ratio ∈ [0.5, 5.0] — currently 1.69 PASS. DD Brake (6/8/20%) thresholds are PATH-DEPENDENT — Σ-implied probabilities are CONTEXT only, NOT validation.

`targets_reviewed` = `["alpha_package", "confidence_vector", "factor_specs", "regime_classification", "kelly_overlay_handoff_specs"]`

Note: Risk Agent measurement (NOT endorsement). Realized sleeve cor=0.597, diversification benefit=9.15%, Kelly+Overlay compat=PASS. Risk's role is measurement, not endorsement. Optimizer/Forge own portfolio-level realized SR/MDD/IR.

---

## 5. PIT Compliance — Iter 6

| Check | Status | Evidence |
|---|---|---|
| C1 expanding window | PASS | OLS exposure 2002-08~2023-10, no full-sample cherry-pick |
| C2 t-1 lag | PASS | PIT_HARD_CUTOFF=2023-10-31 < signal_as_of=2023-11-01 |
| C3 same-period | PASS | EST_END=2023-10-01 strictly < signal_as_of |
| C4 fundamental lag | PASS | FF5 v2 inherits Iter 4 quarterly 45d / annual May |
| C9 daily/monthly lag | PASS | regime label t-1 attribution via RP_M ym join |
| C11 KR-only | PASS | RAWDATA + KR FF5 v2 only, no FRED |
| C12 future filtering | PASS | FF5 v2 Date <= 2023-10-31 enforced |
| C13 Z-score alignment | PASS | Z_Score_Aligned upstream (Alpha) |
| C14 IC time axis | PASS | Σ on Ret_M post-listing only |
| C15 Factor DB lineage | PASS | Alpha LMF spot-check 2023-11-01 21/21 cor>0.999 |

PIT_HARD_CUTOFF Iter 6 = 2023-10-31 (one month tighter than Iter 5's 2023-11-30).

---

## 6. Optimizer Handoff (Recommendations)

1. Use `security_covariance_ref` (covariance.parquet, cond=19.14) for primary Σ in MVO/CVaR.
2. **BIND POOLED FALLBACK**: Use `security_covariance_pooled_fallback_ref` when regime_state in {CRISIS, CAUTION} OR when CRISIS regime cond > 100. Pooled Σ cond=100 PSD T=34.
3. Multi-sleeve diversification benefit 9.15% (cor=0.597) — Optimizer hierarchical or score-level composite.
4. Apply Kelly+Overlay specs from `alpha_package.handoff_to_optimizer`: Kelly_frac05 (per-name cap 0.10), VolReg 12% (scale=0.59 predicted), DD Brake 6/8/20% (cash 10/30/50%), FM_Regime (cash 0/5/15/30%).
5. Σ-implied vol_ratio = 1.688 (realized 0.2026 / target 0.12). VolReg scale = min(1, 0.12/realized) = 0.592.
6. Cash overlay (Sleeve 3): regime_state column in alpha_scores.parquet → FM_Regime cash policy.
7. TDC vs Iter 5 (PG2 ancestor): cross-section Jaccard=0.1111 (intentional inheritance). PG2 NAV correlation (per Q-Lead fair_comparison_note.md, STR_1699 vs MEGA_05 = 0.10) at Forge backtest stage.

---

## 7. Lineage + Reproducibility

- Reproduction command: `Rscript -e 'set.seed(20260425); source("stage_artifacts/WT_D20260425_011/run_risk_iter6.R"); source("stage_artifacts/WT_D20260425_011/enrich_risk_iter6.R"); source("stage_artifacts/WT_D20260425_011/finalize_risk_iter6.R")'`
- Random seed: 20260425
- Input hashes: recorded in artifact_lineage.json by record_package_lineage()
- Lineage call ORDER: write_json(risk_package.json) → record_package_lineage (per L-194 fix)

---

**Status**: Risk pipeline DONE, codex round triaged (3 ACCEPT + 1 PARTIAL + 5 REBUTTAL, no veto), challenge_review.objection=TRUE. Ready to transition ALPHA_DONE → RISK_DONE.
