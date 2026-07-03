# Challenge Note — WT-D20260621_001 (alpha) — Codex Critic Round

**Agent**: alpha-research (Opus 4.8) | **Critic**: Codex GPT-5.5 (xhigh) | **Date**: 2026-06-21
**Codex stance**: `REVISE` (veto_flag=false) | **Agreement on core conclusion**: YES (Codex agrees the negative economic finding is honest and directionally correct; disputes artifact-safety + RF-A3 cleanliness only).

This is a **negative / non-graduating** result (hypothesis falsified). No capital admission is sought. Per measurement-graduation 2-tier, the signal routes to **screening-tier** only.

## Decision Protocol classification (Charter §8 No Silent Override)

| # | Codex concern (sev) | Class | Action / basis |
|---|---|---|---|
| C1 | RF-A7 single-snapshot `alpha_scores.parquet` (HIGH) | **ACCEPT** | `signal_matrix_ref` was pointing at the last-month snapshot. Repointed to `alpha_scores_fullts.parquet` (257 sig_dates, Date×Ticker×score). Snapshot retained as `alpha_scores_lastmonth.parquet` for inspection. Clear contract defect — fixed. |
| C2 | C15 lineage / direct rawdata read (HIGH) | **PARTIAL** | The task brief (request.json §PIT) *explicitly mandates* computing Hurst from rawdata Close/Ret "via the compute_momentum.R pattern" — a new-factor C15 carve-out identical in spirit to the ML daily-parquet carve-out. So the direct read is spec-authorized, NOT a violation. **BUT** Codex is correct that (a) no formal exception was documented and (b) no `artifact_lineage.json` was recorded. Action: documented C15 new-factor exception in factor_specs + `record_package_lineage()` called after final write (L-194 order). The momentum-cluster orthogonality reference (M01/M08/M13) is computed from the *same* rawdata path (not load_month_factors) because factor_db_daily is CRITICAL-stale (per task DATA NOTE) — labeled `metric_type` accordingly. |
| C3 | RF-A3 recent-IC inflation mislabeled "clean" (MEDIUM) | **ACCEPT** | Codex recomputed; I verified: a504 recent-3Y ICIR = **0.291** vs full-sample **0.085** = **3.41×** (> 1.5× trigger). My "RF-A3-clean" flag was **wrong**. Corrected to RF-A3=HIGH triggered. Interpretation: this inflation is *additional evidence against* the signal — a weak/noisy signal whose recent window catches favorable noise, not a robust improvement. It does NOT rescue the thesis. |
| C4 | RF-A2 non-additive; DPL route speculative (MEDIUM) | **ACCEPT** | This is my own central finding. Reframed the route language: DPL_FEATURE is described as a **weak/rejected orthogonal feature with expected contribution ≈ 0**, NOT an additive alpha. Recommendation strengthened to "no further single-sleeve pursuit." |
| C5 | RF-A4 sector-neutral IC untested (MEDIUM) | **ACCEPT** | Ran the test: a504 sector-neutral IC retention = **42%** (0.0148 → 0.0062) — about half the (already weak) signal is sector structure. Pure-H sector-neutral stays ~0/negative (−0.0095 → −0.0062), confirming H is **not** a sector artifact, it simply has no signal. Added to diagnostics. |
| C6 | AX-008 triangulation FAIL (MEDIUM) | **REBUTTAL (partial)** | AX-008 Verification Triangulation (Forge + Codex + Architect, 2/3) is a **downstream judge-stage** gate. At the **alpha stage** of a QEPM pipeline, risk_package / optimization_package / weights.csv / covariance.parquet do not yet exist *by design* (Q-Lead spawns Risk next). It is structurally impossible to satisfy at this stage and is not an alpha-agent obligation. What I *can* provide for cross-agent verification — challenge_note.md + artifact_lineage.json + the full canonical_screen artifacts — is now present. Codex축 of AX-008 is satisfied (this round). Forge/Architect축 are judge-stage. **No spec change; explicit rebuttal with basis.** |
| C7 | RF-A6 DSR chain-not-sweep framing (LOW) | **ACCEPT (language)** | Codex accepts the chain framing for a negative result. I tightened wording and removed reliance on DSR as any kind of pass signal (it is purely diagnostic; the result is negative regardless). |

## Self-rationalization auto-detection (mandate)

Codex flagged these phrases in my draft: `"chain != sweep"`, `"DSR diagnostic only"`, `"Not a graduation gate here"`, `"DPL model that can discover any weak non-linear interaction"`.

Grep self-check on the revised package for the banned rationalization set ("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일/영향미미/이미반영"): **0 hits.** The flagged English phrases are not in the banned list, but I tightened them anyway:
- DSR language: removed any "pass" framing — DSR is reported purely as a diagnostic number; the verdict is negative independent of DSR.
- "DPL can discover any weak non-linear interaction": softened to "expected contribution ≈ 0 on this evidence" — I am NOT using DPL as an escape hatch to keep a dead signal alive.

The verdict does not rest on any rationalized claim. The decisive evidence is the **direct mechanism test** (momentum IC weakest in high-H tercile, t=0.73; high-H names crash harder) and the **paired incremental test** (a504 − baseline, t=0.33) — both purely empirical, neither rationalized.

## Escalation check (auto-triggers)
- HIGH-severity concerns: 2 (C1, C2) — below the ≥5 escalate threshold.
- AX axiom hard FAIL: 0.
- PIT C1 lockbox/lookahead violation: none found (Codex C1/C7/C14 = PASS; C13 PASS; the C1 *concern id* is RF-A7 contract, not a lookahead).
- Codex stance = REVISE (not REJECT) and I ACCEPTED 5/7 + partial/rebuttal on 2 with explicit basis.
→ **No Q-Lead escalation required.** Revisions applied; finalize as negative result.

## Net effect of revisions
All revisions made the conclusion **more negative / more honest**, not less. The thesis remains falsified; capital graduation was never claimed. Final `screen_route.route = DPL_FEATURE` with `expected_contribution ≈ 0` and explicit "no further single-sleeve pursuit."
