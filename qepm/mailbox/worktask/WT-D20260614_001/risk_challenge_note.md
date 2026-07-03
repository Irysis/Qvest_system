# Risk Challenge Note — WT-D20260614_001 VAL_DIVERSIFIER

**Agent**: risk-research · **Stage**: post-Codex Critic Round · **Date**: 2026-06-14
**Codex stance**: REVISE (6 concerns, veto_flag=FALSE) · GPT-5.5 xhigh
**Net effect**: Codex concerns STRENGTHENED the core conclusion (NO-ADMIT). Sigma/contract gaps fixed; verdict unchanged.

---

## 1. Authoritative findings (risk-research, role = Σ + co-risk only; NO alpha edit, NO weights)

| Metric | Value | Note |
|---|---|---|
| **active_cor (sleeve vs incumbent active)** | **0.306** | realization-month aligned; bootstrap 90% CI [0.154, 0.416] |
| total_cor (total returns) | **0.754** | confirms KR VALUE ~0.76 established truth |
| IR_incumbent (active, 219m overlap) | 0.661 | |
| IR_sleeve (active) | 0.151 | |
| **optimal value tilt w\*** | **0.00** | book IR monotonically DECREASING in tilt |
| **ΔIR @ 10% tilt** | **−0.0094** | FAILS book-marginal ΔIR ≥ 0.05 DECISIVELY |
| Σ estimator | 1-factor market BΩB'+D | cond 58.9, PSD, R² mean 0.259 (15/25 <0.30) |
| MDD (total, clean value-4) | **−48.2%** | NOT carried 64.3% (contaminated 8-factor combo) |
| MDD (active basis) | −65.7% | GFC trough 2008-09 |
| CVaR95 monthly (ES95) | 13.3% | breaches 2.5% cap ~5.3x — INFEASIBILITY flagged |
| **CRISIS active_cor** | **0.422** | HIGHER than NORMAL (0.287) — co-crashes with book |
| total-return lower TDC vs incumbent | **0.68** | joint left-tail crash 68% of time |

### Verdict for governor (authoritative book-marginal input)
**NO-ADMIT / DEFER on book-marginal grounds.** The value-4 sleeve is NOT a book-marginal-positive diversifier. Mechanism: standalone active IR (0.15) << incumbent (0.66); even at active_cor 0.31 the variance reduction cannot offset the mean-IR drag (counterfactual cor=0 still gives only dIR@10% = +0.013, < 0.05). Crucially, the co-movement is **highest in crisis** (regime active_cor 0.42, total left-tail TDC 0.68) — the sleeve adds nothing where it matters and drags the mean elsewhere. Value's defensiveness is REDUNDANT with the STR_1715 AR-overlay (both defensive in the same crisis months).

### Correction of alpha
Alpha claimed active_cor 0.269 (realign) / 0.109 (draft) — both date-misaligned (signal-month vs realization-month join). Risk authoritative (realization-aligned, GFC 2008-10 spot-check confirms): **0.306**. alpha_vector and factor_specs UNCHANGED — risk does not edit alpha.

---

## 2. Codex concern resolution (autonomous classification per Charter §8 / v6.0 protocol)

Codex = devil's advocate, no veto. Each concern classified ACCEPT / PARTIAL / REBUTTAL with rationale.

### C1 (HIGH) — Missing B/Ω/D artifacts + 1-factor R²=0.259 < 0.30 → **PARTIAL-ACCEPT**
- **Accepted**: emitted `exposure_matrix.parquet` (B, betas), `factor_covariance.parquet` (Ω), `specific_risk.parquet` (D). Stopped implying a "complete high-coverage" decomposition.
- **Reported honestly**: 1-factor R² mean 0.259 (15/25 names <0.30) IS below the 0.30 guide. The mkt+sector multi-factor model covers far more (R² 0.632) but is ill-conditioned (cond 212.8 > 200) over the 60m window with low-N sector factors.
- **Rationale (not over-claim)**: I chose the well-conditioned-but-lower-coverage 1-factor Σ over an over-fit ill-conditioned one. Σ is a conditioned PSD market-risk frame, not claimed as high-coverage. ~75% of name variance is specific — optimizer should treat that as real idiosyncratic exposure.

### C2 (HIGH) — RF-R1 market 85% normalization → **ACCEPT**
- Removed normalizing language ("not a risk-model defect"). RF-R1 raised to formal HIGH red flag (`flagged=TRUE`). Root cause (KR long-only no-short 1st-eigenmode) still documented as the *mechanism*, but framed as a concentration to ESCALATE — with market-exposure reduction routed to the optimizer as a REQUIRED action (risk measures, does not prescribe weights).

### C3 (HIGH) — CVaR breach not flagged + only 6 stress periods → **ACCEPT**
- ES95 = 13.3%/month vs 2.5% cap = ~5.3x breach now flagged as **RF-R6 infeasibility** with explicit "optimizer must impose CVaR constraint" language.
- Stress suite completed to **8 periods** (added Brexit_2016, Volmageddon_2018). Worst total-return window = GFC −15.8% (all < 25%, so the CVaR breach is monthly-vol-driven, not single-scenario).

### C4 (MEDIUM) — regime_n / bootstrap CI / TDC vs PG2 missing → **PARTIAL-ACCEPT**
- **Accepted**: added regime-conditional active_cor with sample counts (CRISIS n=42 cor 0.42, NORMAL n=133 cor 0.29, BULL n=44 cor 0.32), block-bootstrap 90% CI [0.154, 0.416], and TDC vs incumbent (active lower 0.36, total-return lower 0.68). These are the MOST decisive new evidence.
- **Scope note (partial)**: a full regime-conditional **Σ** is out of scope for a single non-graduating diversifier sleeve — there is no per-regime weight set to attach it to. Provided the regime-conditional *correlation* structure instead, which directly answers the diversifier question.

### C5 (MEDIUM) — estimator selection not pre-declared → **ACCEPT**
- Recorded 4-rule pre-declared acceptance criteria in `method_shopping_log`: (1) PSD, (2) cond ≤ 200, (3) reject shrink ρ ≥ 0.99 (identity collapse), (4) prefer structured BΩB'+D. Applied: sample fails (2), LW fails (3), mkt+sector fails (2), factor1_market passes all → selected. Criteria are estimation-quality only, NOT return-based.

### C6 (MEDIUM) — AX-008 triangulation files absent → **REBUTTAL**
- The requested triangulation files (`risk_package.json`, `optimization_package.json`, `weights.csv`) are absent by **PIPELINE ORDERING**, not defect. Risk runs BEFORE optimizer/forge. AX-008 (Forge+Codex+Architect 2/3 PASS) completes at the **judge** stage — the alpha package itself states `ax_008_at_alpha_stage = FAIL_expected_completes_at_judge`. `risk_package.json` is now emitted (this round). The Codex critic IS one of the 3 AX-008 sources and has been satisfied at this stage. Not a risk-stage failure.

---

## 3. Self-verification (rationalization audit)
Codex flagged phrases: "expected for KR long-only", "not a risk-model defect", "optimizer scope", "conditioned, faithful choice", "benign", "NOT structural-hard-fail", "confirms KR VALUE ~0.76".
- Removed/reframed: "not a risk-model defect" (deleted), "faithful choice" (→ "conditioned PSD frame, not claimed high-coverage"), "benign" (→ added caveat that proxy crowding ≠ flow crowding).
- Retained with justification: "confirms KR VALUE ~0.76" — this is a *measured* total_cor 0.754 against a documented established-truth, not a hand-wave (memory [[reference-str1715-structure]]/[[learning-gate-calibration-longonly]]). "optimizer scope" — correct role boundary (risk must not prescribe weights), now paired with explicit REQUIRED-action language so it is delegation, not evasion. "NOT structural-hard-fail" — per measurement-graduation 2026-06-13 the MDD criterion is structural; value-4's 1 episode ≥45% with BM-2005+ MDD 54.5% does not meet the structural-hard-fail bar (this is a rule citation, not a rationalization).

---

## Escalation check
No auto-escalate trigger fired: HIGH concerns < 5 (and the HIGH items are completeness gaps now fixed, not Σ PD violations); no AX axiom hard FAIL ≥ 3; no PIT hard violation; **Σ PSD verified** (min eigenvalue 0.00193 > 0). Codex ax_002 "FAIL" was on *completeness* (missing artifacts), now remedied. Proceeding to finalize without Q-Lead escalation.
