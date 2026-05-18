# Weight Method Selected — DPL_KR_v3

**WT-D20260519_001 · optimizer-research Final**
**Date**: 2026-05-18
**Phase**: design_phase_a (Charter §10 v1.8 amendment-pending)
**Method selected**: `DPL_v3_DeepSet_MLP_continuous_softmax_STE_PAN_PartialAdjust_postPA_reprojection`
**Selection objective**: `net_ir` (v6.1 R4 P3 mandate)

---

## 0. TL;DR

DPL_v3 (Original DPL paradigm v3 redesign) selected as primary production method. Production weights = DPL_v3 only. Baselines B1-B7 = post-hoc validation only (paradigm-shift baseline doctrine, Codex v1 C4 + v3 C6 REBUTTAL retain).

**v3 vs v1 architectural deltas**:

| Aspect | v1 (REJECT) | v3 (this cycle) |
|---|---|---|
| Top-K mechanism | Gumbel hard top-K (τ-anneal) | Continuous softmax + concentration penalty + STE top-K mask |
| EW collapse risk | HIGH (observed 100% collapse) | LOW (concentration penalty active gradient) |
| Persistence layer | none | Partial Adjustment α=0.6 + post-PA re-projection (Codex C4 ACCEPT) |
| TO mitigation | λ_to = 1.0 (weak, observed 17.64) | λ_to ∈ {1.0, 2.0, 4.0} + 4-additional layers (decision clip + conc penalty + cont softmax + partial adjust) |
| Walk-forward | 5 × 52m | 13 × 24m = 304 test months (도훈 mandate 2026-05-19) |
| Loss | -E[r] + γ·TO + λ·CVaR | -E[r]/σ(r) + λ_to·TO + λ_conc·(HHI-0.10)² |
| Params | 165K (over-param) | 17K (10× reduction) |
| Baselines | 6 (B1-B6) | 7 (B1-B7, B7 NEW paradigm depth probe) |

---

## 1. Selected Method Rationale

### 1.1 DPL_v3 architecture (alpha-research inherit)

```
features X (N × 80)
   ↓
[Stage A: Continuous Concentration Softmax]
   w_raw = softmax(s / τ),  τ ∈ {0.5, 1.0, 2.0}
   ↓
[Stage B: STE Top-K Soft Selection]
   train: w_soft = w_raw · top_K_mask (STE forward hard, backward soft)
   infer: w_soft = scatter(top_K, w_raw) / Σ
   ↓
[Stage C: Projection-after-Normalize (PAN)]
   project_simplex_bounds(w_soft, bound_max=0.20, max_iter=3)
   + Dykstra v1.0 fallback (Codex v1 C3 ACCEPT)
   ↓
[Stage D: Partial Adjustment + post-PA Re-projection (Codex v3 C4 ACCEPT)]
   w_t_pre = α · w_new + (1-α) · w_old, α ∈ {0.4, 0.6, 0.8}
   top_k = torch.topk(w_t_pre, 20).indices         # post-PA top-K
   w_t = PAN(w_t_pre[top_k] / Σ)                    # post-PA PAN
   ↓
[Final w_t ∈ R^N]
   guaranteed: count(w > 0) = 20 + Σw = 1 + [0, 0.20] + long-only
```

### 1.2 Why DPL_v3 over baselines?

**You-Zhang 2025 RFS DPL Original paradigm**: features → weights end-to-end NN backprop with utility loss. Avoids two-stage μ̂→optimizer misalignment (Michaud 1989 error maximization + Elmachtoub-Grigas 2017 SPO).

**Decision rule (post-Forge cycle)**:
- Production = DPL_v3 only (Codex v1 C4 + v3 C6 REBUTTAL doctrine retain)
- Baselines B1-B7 = post-hoc validation (paradigm value-add proof + tail-aware proof + diversification benchmark)
- If `SR(DPL_v3) > SR(B1_MVO with DPL scores)` AND `MDD(DPL_v3) ≤ MDD(B1)` → paradigm value-add confirmed
- Else → WT reject (Scenario C, STR_1715 PG2 retain)

### 1.3 Loss function — 3-term Sharpe surrogate

```
L_total = L_sharpe + λ_to · L_to + λ_conc · L_conc

L_sharpe = -E[r_p] / (σ(r_p) + ε)                    # variance-normalized (vs v1 -E[r] direct)
L_to     = |w_t - w_{t-1}|_1 · 0.0015 · 2            # cost-aware, per-rebal (NO ×12)
L_conc   = (Σ w_i² - 0.10)²                          # concentration penalty (5× EW floor)

λ_to   ∈ {1.0, 2.0, 4.0}   grid (vs v1 1.0 weak)
λ_conc ∈ {0.5, 1.0, 2.0}   grid (NEW vs v1 absent)
τ      ∈ {0.5, 1.0, 2.0}   softmax temperature (vs v1 Gumbel τ-anneal)
α      ∈ {0.4, 0.6, 0.8}   Partial Adjustment (NEW vs v1 absent)
```

3³ × 3 = 81 combinations → sample 20 random (alpha-research training_protocol_v3.md §4.2).

---

## 2. Method Shopping Log (8 candidates, ≤ cap 10)

| # | Method | Role | Selected | Rationale |
|---|---|---|---|---|
| 1 | DPL_v3 | **Primary production** | YES | Original DPL paradigm v3 redesign — features → weights end-to-end NN |
| 2 | B1 MVO with DPL scores | Post-hoc baseline | NO | Two-stage paradigm baseline — DPL paradigm value-add proof |
| 3 | B2 HRP | Post-hoc baseline | NO | TO + diversification baseline |
| 4 | B3 ERC | Post-hoc baseline | NO | Risk-parity baseline |
| 5 | B4 CVaR LP | Post-hoc baseline | NO | Tail-aware baseline (Rockafellar-Uryasev 2000) |
| 6 | B5 MaxDiv | Post-hoc baseline | NO | Diversification-max baseline (Choueifaty-Coignard 2008) |
| 7 | B6 EW top-20 | Post-hoc baseline | NO | AX-007 #4 ML sizing exemption reference (HHI 0.05 floor) |
| 8 | B7 DPL_v3 → MVO post-hoc | Post-hoc baseline (NEW vs v1) | NO | Paradigm depth probe — local MVO refinement on DPL output |

**candidates_tried**: 8 (under cap 10, v6.1 R2-C compliant).

**Differentiable top-K alternatives evaluated** (7 alternatives, Continuous + STE selected):

| Alternative | Verdict |
|---|---|
| Continuous softmax + STE top-K | **RETAIN (v3 DEFAULT)** |
| Gumbel softmax + STE (v1 method) | REJECT — v1 EW collapse 100% precedent |
| Sinkhorn balanced | REJECT — O(N²) compute prohibitive for N=500 |
| Hungarian relaxation | REJECT — combinatorial O(N³) |
| Sparsemax / α-entmax | PARTIAL — v3.1 ablation if HHI degenerate |
| Smoothed projection (Beck-Teboulle 2009) | NEAR-EQUIVALENT to PAN |
| Gumbel-Rao top-K relaxation | REJECT — v3 STE alternative to avoid v1 EW collapse |

---

## 3. Hard Constraints Architectural Enforcement

| Constraint | Source | Layer | Pass at Design |
|---|---|---|---|
| `max_names ≤ 20` | request.json | Stage B (STE top-K) + Stage D (post-PA re-proj) | **PASS by construction** (count(w>0)=20 deterministic at inference) |
| `weight_bounds [0, 0.20]` | request.json | Stage C (PAN clip) + Dykstra fallback | PASS (violation_rate=0 strict per row, Forge audit) |
| `Σw = 1` (absolute) | request.json | Stage C (PAN L1) | PASS within tol 1e-6 |
| `long-only` (w ≥ 0) | request.json | Stage A (softmax > 0) + Stage C (clip 0) | PASS by construction |
| Universe `KR_TOP500_LIQ1E8` | request.json | pre-input filter | PASS (alpha-stage 2-stage mitigation + Forge ADV audit) |
| `cost 15bps × 2 round-trip` | cost_model_version | Loss L_to | declared explicit (Codex v1 C6 ACCEPT inherit, NO ×12) |
| `TO_annual ≤ 6.0` | request.json | 5-layer mitigation stack | design target ≤ 5 expected, Forge audit |
| `MDD ≥ -0.25` | request.json | strategy-level | N/A at design, Forge bt_result.rds 10-component |

**RF-O5/O6/O7 (Hook block) compliance**: design spec architecturally guarantees + Forge cycle violation_rate = 0 strict per row + Dykstra v1.0 fallback automatic.

---

## 4. Risk Inheritance Integration

| Risk Construct | risk_package source | Optimizer usage |
|---|---|---|
| Σ 259×259 LW identity oracle | `covariance.parquet` (kappa 52.4, eig_ratio 84.7, PSD ✓, Codex C8 confirmed) | B1/B2/B3/B5 input |
| Factor B 259×22 ridge | `exposure_betas_ridge.parquet` (post-collinearity reduction 58→22) | B5 MaxDiv σ_i |
| Tail risk CVaR/EVT | `tail_risk.json` (CVaR_95=-35.3%, ξ=2.27 heavy) | **Universe baseline observation**, NOT DPL strategy — Branch A/B contingency at Forge (Codex C5) |
| 8 stress windows | `tail_stress_protocol.json` | Crisis-explicit 7 windows G3' gate alignment |
| Crowding score | `crowding_score_audit.parquet` (14 ELEVATED, 0 HIGH) | Post-Forge per-DPL-weight audit |
| PG2 comparison | TDC 0.32, return cor 0.196, **style cor 0.965 (RF-R6 HIGH)** | **Universe baseline measurement-basis**, NOT DPL strategy — Forge realized re-measure (Codex C7) |

**Critical RF-R6 disposition** (Codex C7 PARTIAL ACCEPT + PARTIAL REBUTTAL): Style cor 0.965 is `cor(STR_1715 PG2 weights, KR_TOP500 EW)`, measured at universe-baseline level. DPL_v3 strategy `cor(DPL_v3 weights, STR_1715 weights)` will be measured at Forge cycle. Negative prior acknowledged (KR equity style overlap by definition for top-20 universe), but DPL_v3 family-balanced 80 features (Risk_Beta_Vol 15 + Tail_Risk 15 + Momentum_Tech 15 + Other 15 + Liquidity 7 + Risk_Metric 7 + Reversal 2 + Technical 2 + Daily_LowFreq 2) provides differentiation opportunity via DeepSet + ScoreHead MLP non-linear cross-section interactions.

---

## 5. Sequential Admission Decision Logic (post-Forge)

| Scenario | Trigger | Book Mutation |
|---|---|---|
| A: 4th orthogonal source | `|cor(DPL_v3, STR_1715)| < 0.3` AND G5 PASS AND net_SR ≥ 1.0 AND CVaR Branch B | 1-sleeve {STR_1715 100%} → 2-sleeve {STR_1715 75% + DPL_v3 25%} |
| B: Substitution | `0.3 ≤ |cor| < 0.5` AND G5 PASS AND DPL_v3 SR > STR_1715 baseline AND CVaR Branch B | 1-sleeve {STR_1715 100%} → 1-sleeve {DPL_v3 100%} |
| C: Reject | `|cor| ≥ 0.5` OR G5 FAIL OR DPL_v3 SR < STR_1715 OR HHI ≤ 0.06 OR TO > 6.0 OR CVaR Branch A | 1-sleeve {STR_1715 100%} retain — no admission |

**Q-Lead authority**: Scenario A blend ratio (75/25 nominal) post-Forge re-optimize via Blender agent if multiple admit candidates. v3 cycle = single candidate, so 75/25 default if Scenario A triggers.

---

## 6. Codex Round Disposition Summary (8 concerns)

| Concern | Severity | Disposition |
|---|---|---|
| C1 weights.csv absent | CRITICAL | PARTIAL_ACCEPT — Charter §10 v1.8 amendment + Forge weights.csv schema explicit |
| C2 alpha_scores absent + diagnostics null | HIGH | PARTIAL_ACCEPT — Forge artifacts mandate + path B canonical |
| C3 walk-forward 52 vs 304 inconsistency | HIGH | **ACCEPT** — 304 canonical + alpha-research v3.1 reconcile escalate |
| C4 Partial Adjust max_names > 20 | HIGH | **ACCEPT** — post-PA re-projection mandate + Forge skeleton patch |
| C5 CVaR breach infeasibility_null | HIGH | PARTIAL_ACCEPT — Branch A/B contingency explicit |
| C6 method selection ex ante | HIGH | **REBUTTAL** — paradigm-shift baseline doctrine (You-Zhang §5 + L-272) |
| C7 PG2 style cor 0.965 above threshold | HIGH | PARTIAL_ACCEPT + PARTIAL_REBUTTAL — measurement-basis distinction |
| C8 universe override KOSPI∪KOSDAQ | HIGH | PARTIAL_ACCEPT — universe explicit disposition + operational equivalence |

**Total**: 2 ACCEPT + 4 PARTIAL_ACCEPT + 1 REBUTTAL + 1 hybrid

**Q-Lead escalate triggers**: HIGH ≥ 5 (7+1=8) + AX-002 FAIL + AX-008 FAIL 1/3 + Codex REJECT + Charter §10 v1.8 amendment + alpha-research v3.1 reconcile.

---

## 7. Forge Cycle Mandate (handoff)

| Artifact | Path | Schema/Content |
|---|---|---|
| weights.csv | qepm/mailbox/worktask/WT-D20260519_001/weights.csv | 304 sig_dates × ≤20 active × {Date, Ticker, weight, method_selected, confidence} |
| alpha_scores.parquet | stage_artifacts/WT_D20260519_001/ | 304 sig_dates × ~500 stocks × {Date, Ticker, alpha_score, confidence, w_dpl_v3} |
| ic_history.parquet | stage_artifacts/WT_D20260519_001/ | 304 rows × {sig_date, IC, ICIR, Usable_Date≤sig_date} |
| bt_result.rds | stage_artifacts/WT_D20260519_001/ | Backtest Contract v1.0 10-component PerformanceAnalytics standard |
| bt_result.rds.sha256 | stage_artifacts/WT_D20260519_001/ | Anti-fabrication binding (v5 lesson inherit) |
| optimizer_comparison.parquet | stage_artifacts/WT_D20260519_001/ | 304 sig_dates × 8 methods × 12 metrics |
| paradigm_value_add_audit.json | stage_artifacts/WT_D20260519_001/ | DPL_v3 vs B1_MVO SR/MDD direct (Codex v3 C6 doctrine evidence) |
| scenario_admission_measurements.json | stage_artifacts/WT_D20260519_001/ | Scenario A/B/C realized blended metrics + realized cor/TDC/style_cor |
| dpl_v3_risk_attribution.json | stage_artifacts/WT_D20260519_001/ | Integrated Gradients + factor variance decomp + Jaccard stability |
| crowding_summary.json | stage_artifacts/WT_D20260519_001/ | risk_package crowding × DPL_v3 weights (Acadian 2026) |

**Forge per-row strict assertions** (304 sig_dates × ≤20 rows = ~6000 row audit):
1. `0 ≤ weight ≤ 0.20 + 1e-6` (Stage C clip)
2. `Σ_Ticker weight = 1 ± 1e-6` (Stage C L1)
3. `count(weight > 0) ≤ 20` (Stage B + Stage D post-PA re-proj)
4. `weight ≥ 0` (long-only)
5. `LIQ_20d ≥ 2e8 KRW` (universe filter)
6. `Usable_Date ≤ sig_date` (PIT C14)
7. `method_selected = "DPL_v3"` (production paradigm doctrine)

**Single violation** → Dykstra v1.0 fallback automatic OR infeasibility_report.

---

## 8. AX-008 Status

Currently: **1/3** at optimizer_completion.
- Codex round complete (REJECT veto=false, 8 concerns disposed)
- Forge stage Codex round (TBD post-Forge GPU train)
- Architect independent reproduction (TBD post-Forge)

Admit gate (G6): ≥ 2/3 required.

---

## 9. Conclusion

DPL_v3 selected as primary production weight method. paradigm-shift baseline doctrine: production = DPL only. 7 baselines (B1-B7) post-hoc validation. selection_objective = net_ir (cost-aware Net Sharpe).

**Forge cycle obligation**: GPU train + 13 walk-forward × 24m test = 304 test months + per-row strict assert + Codex Round 2/3 + Architect 3/3.

**Q-Lead escalate**: Charter §10 v1.8 amendment-pending + alpha-research v3.1 reconcile cycle.

---

**End of Weight Method Selected v3**
