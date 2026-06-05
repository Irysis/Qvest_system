# Challenge Note — WT-D20260529_003 Track VALUE (Alpha Research)

**Codex Critic Round** (gpt-5.5 xhigh): stance = **REJECT** (veto_flag=false — devil's advocate, no veto power).
**Agent decision**: alpha_package finalized as **honest negative/marginal discovery report** (NOT admission-ready). Per AX-000, proven limits are reported, not denied. Codex's central thesis (composite is not admissible as a 5th sleeve) is **largely ACCEPTED**; the package is emitted as a documented FAIL with the orthogonality opening characterized for future cycles.

## Self-rationalization auto-check
grep of {미미, 관행적, 실무적, 보수적이면 OK, 대부분 결과 동일} in this note + package: **0 hits**. Codex `rationalization_red_flags`: empty. No rationalization used; failures stated directly.

---

## Concern-by-concern classification

### C1 (HIGH) — RF-A2: composite ICIR 0.272 < best-single V02_EP 0.457 / best-axis ax_price 0.324
**Classification: ACCEPT.**
- Empirical: composite ICIR 0.272 is -40.6% vs V02_EP single, -16.2% vs price-multiple axis. QMJ lesson (Asness-Frazzini-Pedersen 2019 "Quality Minus Junk") fires: blending weak axes (cashflow ICIR 0.122, capital-alloc 0.238) **drags** the strong price-multiple axis (0.324). AX-003 forbids EP_STANDALONE (L-132/135) but does NOT make a weaker composite admissible — Codex is correct.
- Action: package emitted as negative finding. `composite_beats_single=false`, RF-A2 fires, recorded in challenge_flags. No admission claim.

### C2 (HIGH) — rank_IC 0.0301 < graduation gate 0.04; portfolio-alpha t 1.36 full / 1.64 lockbox
**Classification: ACCEPT.**
- rank_IC 0.0301 < 0.04 → graduation FAIL (4/5 criteria pass, IC-magnitude gate fails). portfolio-alpha t (1.36/1.64) << rank-IC t (4.21), confirming Cycle 2 lesson (IC t ≠ portfolio-alpha t). Judge authoritative metric = portfolio-alpha t, which is sub-2.0.
- Action: graduation_assessment in package reports min_rank_ic_0.04=FAIL explicitly. RF-PA-T + RF-RANKIC flags recorded.

### C3 (HIGH) — return orthogonality FAIL: realized return cor vs STR_1715 = 0.758 despite signal cor -0.062
**Classification: ACCEPT (this is the cycle's central finding).**
- This is exactly the BAB lesson the task mandate pre-warned: KR long-only top-N realized return cor is structurally high (~0.75) even at near-zero signal cor. Signal orthogonality (1715 -0.062, D 0.133, FLOW 0.077 — all <0.30 PASS) does NOT translate to portfolio-level diversification. The AX-007 multi-sleeve exception is **unproven at the realized-return level**.
- Action: RF-RETURN-COR (HIGH) recorded. 수익률직교 천장 미돌파 reported as the binding constraint.

### C4 (HIGH) — RF-A6: Harvey-t n_tests=12 ignores full VALUE/ACCRUAL/TECHNICAL sweep
**Classification: PARTIAL (rebuttal with data).**
- Rebuttal (value_supp.R): Harvey-t recomputed across broadened n_tests — n=12 → 3.565, n=24 → 3.369, n=**48** (realistic full unused-factor sweep: VALUE 12 + TECHNICAL 12 + ACCRUAL 24) → **3.164 (still PASS)**, n=100 → 2.935 (FAIL).
- So the Harvey gate survives the realistic full-sweep multiple-testing count (48), contradicting the implied collapse — but the margin is thin (3.16 vs 3.0). PARTIAL: I accept the multiple-testing universe must be the full sweep, and report the n_tests=48 Harvey-t 3.164 as the honest value. It does NOT change the overall REJECT given C1/C2/C3.
- Academic cite: Harvey-Liu-Zhu 2016 (multiple-testing haircut). L-code: this cycle's negative finding.

### C5 (MEDIUM) — RF-A3: recent36 ICIR 0.480 ≈ 1.77× lockbox ICIR 0.272 (recent-window selection bias)
**Classification: PARTIAL.**
- recent36_ICIR 0.480 vs lockbox 0.272 → RF-A3 fires (ratio >1.5). Partial rebuttal: the recent strength is consistent with the documented KR value-premium revival 2020-2026 (subperiod IC 2020-26 = 0.0448 vs 2008-14 0.0270), not pure selection bias — subperiod_stability=1.00 (all 3 subperiods same sign). But I ACCEPT the elevated recent window is a vulnerability flag; it is NOT used to inflate the headline (lockbox ICIR 0.272 is reported as authoritative, full 0.278). No cherry-picking of recent window.

### C6 (HIGH) — max_names=25 vs hard 20; liquidity audited post-selection (2.17% below 2e8)
**Classification: PARTIAL — one sub-claim REBUTTAL, one ACCEPT.**
- **max_names REBUTTAL**: The task mandate explicitly states "max 25 names (도훈 mandate 20→25)". Codex used the CLAUDE.md default-20 and lacked the 도훈 mandate context. N_NAMES=25 is **compliant with this WT's mandate**. (Cite: WT-D20260529_003 request prompt, 도훈 mandate.)
- **liquidity ACCEPT + rebuttal**: Codex correct that draft audited post-selection. Rebuttal (value_supp.R): re-ran IC and top25 on a **pre-filtered universe (adv20_lag≥2e8)** → IC 0.0305 (essentially unchanged vs 0.0301), top25 **0.0% below 2e8**. Liquidity is non-binding; pre-filter does not rescue the IC magnitude.

### C7 (HIGH) — missing challenge_note.md / artifact_lineage.json / weights.csv / covariance.parquet / risk_package / optimization_package
**Classification: REBUTTAL (scope boundary).**
- weights.csv / covariance.parquet / risk_package / optimization_package are **Risk-agent and Optimizer-agent deliverables** — producing them from Alpha is a hard Hook violation (agent_role_guard L3 block; init <strict_prohibitions> 1/2/3). Alpha's contract output = alpha_vector / confidence_vector / factor_specs / diagnostics / challenge_flags only. Their absence at the Alpha stage is **correct pipeline behavior**, not an omission.
- challenge_note.md = this file (now written). artifact_lineage.json = written via record_package_lineage (write_json → lineage order per L-194). ACCEPT for these two; produced.

### C8 (MEDIUM) — RF-A4: post_neutralization_ic reported = raw IC while neutralization=none (placeholder)
**Classification: ACCEPT (rebuttal with measured data).**
- Codex correct: draft reported post_neutralization_ic = raw IC (placeholder). Rebuttal (value_supp.R): actual **sector-neutral IC = 0.0151 (ICIR 0.210), retention = 50%** of raw IC 0.0301. So ~half the raw IC is sector-spurious — retention sits exactly at the >50% evaluation threshold (borderline). This further weakens the case (already-marginal IC halves under sector-neutralization). Package updated with measured value (no longer placeholder).

---

## Escalation assessment
- HIGH severity concerns: C1, C2, C3, C4, C6, C7 = 6 ≥ 5 → **Q-Lead escalate trigger met**.
- AX axiom hard FAIL: AX-003 FAIL (Codex), AX-007 FAIL (Codex) = 2 (< 3).
- PIT C1 (lockbox/lookahead): no violation (C13/C14/C15/C4/C9 all PASS per Codex).
- Codex stance=REJECT + agent does NOT rebut all (majority ACCEPT/PARTIAL) → escalate to Q-Lead as **negative discovery, NOT admission**.

**Verdict**: VALUE 3-axis composite is a **documented FAIL / negative discovery**. The orthogonality opening (signal cor near zero) is real but does NOT survive at the realized-return level (cor 0.758) — the binding ceiling per the BAB lesson. Composite underperforms best-single (QMJ). rank_IC below gate. portfolio-alpha t sub-2.0. AX-008 triangulation FAIL (Codex disagrees). Package emitted for the record and to characterize the opening for future cycles; **not advanced to Risk/Optimizer**.
