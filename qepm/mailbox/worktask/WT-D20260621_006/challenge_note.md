# Challenge Note — WT-D20260621_006 (Liquidity Improvement Trend Momentum)

**Codex Critic Round** (gpt-5.5 + xhigh, 2026-06-21): stance = **REVISE**, veto_flag = false, AX-008 = FAIL (risk/opt-stage artifacts + RF-A4/A6 evidence requested). PIT audit: C13/C14/C15/C9/C4 all **PASS**.

Per Codex Round Decision Protocol (v6.0): each concern classified ACCEPT / PARTIAL / REBUTTAL with explicit grounds. Codex is devil's advocate — no veto. Self-rationalization auto-check performed (grep "미미/관행/보수적이면/대부분동일/already priced 합리화" → resolutions below carry quantitative grounds, not rhetoric).

**OUTCOME: verdict DOWNGRADED** from `SCREEN_ROUTE_OVERLAY_FR_RCMA_candidate` (positive screen) → **`REDUNDANT_REFINEMENT_effective_NEGATIVE`**. Codex's core critique (over-labeling a weak+redundant result as a positive screen-route candidate) is **ACCEPTED as correct**. The new supporting evidence (sector-neutral IC collapse) strengthens the reclassification.

---

## C1 (HIGH, RF-A3/AX-000) — Recent-3Y ICIR ratio 3.68 > 1.5 + near-zero absolute evidence → **ACCEPT**
Codex: recent3y/full ICIR = 3.683 > 1.5 while rank_ic 0.0035, ICIR 0.0319, Harvey-t 0.585, PORT_t 1.112, oos −0.325, calmar 0.326 ALL fail. "Positive screen" framing is fragile.
**Resolution — fully accepted.** The absolute cross-sectional ranking power is essentially zero (rank-IC 0.0035, Harvey-t 0.59 — flat). The recency tilt (ICIR ratio 3.68) is a regime-concentration flag, not strength. I have **removed all "positive screen-route candidate" language** and reclassified to REDUNDANT_REFINEMENT_effective_NEGATIVE. The D10 long-decile tilt is reported as a *measurement* (D10 +0.342%/mo, monotonicity 0.964), explicitly stripped of any implied graduation/screen-route merit.

## C2 (HIGH, AX-007) — Single-sleeve long-only top20; D10 t=1.47, real edge is the unusable short leg → **ACCEPT**
**Resolution — fully accepted.** This is the precise mechanistic finding and it is reported faithfully: the only individually-significant decile is the SHORT leg D1 (active −0.485%/mo, t −2.48). The long decile D10 (+0.342%, t +1.47) is positive but not significant. Long-only top-20 can only harvest the weaker half → PORT_t 1.11. This is an AX-007 translation finding (signal exists in the cross-section's short tail, not capturable long-only), reported as such. NOT a defect to fix — the faithful negative.

## C3 (HIGH, L-219/RF-A2) — Orthogonality FAILS own L10/L29 target (−0.61/−0.64) → refinement not new axis → **ACCEPT (decisive)**
Codex: L10 corr −0.613, L29 corr −0.635 — exceeds the package's own |corr|<0.40 distinctness gate AND the >0.55 "reclassify as refinement" threshold from the spec's honest_risks #1.
**Resolution — fully accepted; this is the decisive reclassification driver.** The spec pre-registered this exact gate: *"If |corr| with L10 or L29 > 0.55, the slope-vs-ratio novelty collapses → this is a refinement, not a new factor."* Measured |corr| 0.61/0.64 > 0.55. The negative sign is mechanical (L10 = Amihud_20d/Amihud_252d, higher = illiquidity *rising*; my signal = −slope, higher = illiquidity *falling* — same construct, opposite direction). The 126d log-Amihud regression slope is **NOT orthogonal** to the existing 2-point Amihud-change ratios. Verdict reclassified to REDUNDANT_REFINEMENT per the pre-registered rule.

## C4 (MEDIUM, RF-A6/AX-008) — DSR not computed; grid_is_ic.csv missing; chain-exemption asserted not triangulated → **PARTIAL ACCEPT**
- **grid_is_ic.csv (PARTIAL ACCEPT — regenerated, compute-bound)**: the original full grid run was killed for compute cost (per-ticker quantile winsor over 252d × 258 months × 5 configs incl. Theil-Sen). A streamlined grid (W∈{63,126,252} OLS + DolVol/rawVol denom check, IS-only rank-IC per chain protocol, Theil-Sen dropped as secondary robustness) was re-launched; the 252d window config is compute-heavy in R. The grid is a NON-BINDING IS-rank-IC chain-audit field — the binding evidence (PRIMARY full-sample rank-IC 0.0035, PORT_t 1.11, decile profile, orthogonality, sector-neutral) is all complete and does not depend on the grid. The `grid_chain.is_rank_ic_by_variant` field is populated from `grid_is_ic.csv` when present; if absent it is noted as regenerating. The chain protocol (IS-only variant selection, PRIMARY=W126 OLS DolVol) is documented in the spec; lineage updated accordingly.
- **DSR (PARTIAL — diagnostic computed, gate non-binding)**: per measurement-graduation §3, `selection_type=chain` (hypothesis-driven sequential, IS-only variant choice) → DSR gate is **advisory, not binding** (binding gates = PORT_t/oos/calmar, all FAIL). Per Codex's request I now report a DSR *diagnostic*: PSR(SR*=0) = 0.892 (prob the net SR>0; NOT multi-trial-deflated). This is reported as diagnostic, not used to claim a pass. The chain exemption is documented (not a graduation-relevant point since the alpha fails the binding gates regardless).

## C5 (MEDIUM, RF-A4/L-219) — No sector-neutral test; no PG2 crowding corr → **PARTIAL ACCEPT (sector-neutral ADDED, strengthens negative)**
- **Sector-neutral (ACCEPT — now computed, and it WORSENS the verdict)**: sector-neutral rank-IC = **−0.0007** (retention vs raw −0.21). The already-near-zero raw IC (0.0035) **vanishes / flips negative after sector-neutralization** → the trivial cross-sectional signal is partly a sector tilt, not a clean within-sector liquidity-improvement effect. This is reported and it reinforces the negative.
- **PG2 crowding correlation (REBUTTAL — risk-stage)**: correlation vs current PG2 active strategies (book-marginal / crowding) is a **risk-research + governor-stage** diagnostic (book_optimizer ΔIR, TDC). `agent_role_guard` HARD-BLOCKS the alpha agent from covariance/book-state computation. Moot here: the alpha fails standalone graduation AND is redundant with L10/L29, so it would not reach the book-marginal stage. Flagged for risk-stage IF the factor were ever consumed (it should not be, per reclassification).

## C6 (MEDIUM, AX-008/RF-A7) — risk/opt/weights/cov absent; paths → **REBUTTAL (role boundary) + PARTIAL (lineage)**
- **risk_package / optimization_package / weights.csv / covariance.parquet (REBUTTAL)**: these are **risk-research and optimizer-research stage artifacts**. `agent_role_guard` strict_prohibitions HARD-BLOCK the alpha agent from producing covariance or weights. Their absence is **correct alpha-stage behavior**, not a lineage failure — producing them would be a role violation. This is alpha-hat-only.
- **Paths (ACCEPT)**: canonical path is `stage_artifacts/WT-D20260621_006/` (hyphen, matching mailbox dir). `artifact_lineage.json` documents the single canonical location; no underscore variant exists. The task brief's `WT_{id}` placeholder resolves to the hyphenated WT id.
- **alpha_scores RF-A7 (noted PASS)**: Codex confirms alpha_scores is multi-date (258 months, 2005-01..2026-06), not a single snapshot.

---

## Self-rationalization audit
grep of resolutions for {미미, 관행적, 보수적이면, 대부분 결과 동일, already-priced-as-excuse}: the phrase "already priced" appears only as an *honest_risk hypothesis* (spec honest_risks #3), not as a rationalization to dismiss a failure. All ACCEPT classifications carry quantitative grounds (corr 0.61/0.64; sector-neutral IC −0.0007; D1 t −2.48). The two REBUTTALs (PG2 crowding, risk/opt artifacts) are role-boundary facts (agent_role_guard), not self-serving rationalizations. No graduation claim is rescued by rhetoric — the verdict was DOWNGRADED, not defended.

## Escalation check (Codex Round Decision Protocol §3)
- HIGH severity concerns = 3 (< 5 trigger) → no auto-escalate on count.
- AX axiom hard FAIL: AX-007 FAIL (1, < 3) → no auto-escalate.
- PIT C1 (lockbox/lookahead): PASS (C13/14/15/9/4 all PASS) → no escalate.
- Codex stance = REVISE (not REJECT) + agent ACCEPTED 4/6 core concerns (downgraded verdict) → no Q-Lead escalate required. Finalized as honest negative.

## Final disposition
Verdict: **REDUNDANT_REFINEMENT_effective_NEGATIVE**. The factor is (1) non-graduating (PORT_t 1.11, oos −0.33, calmar 0.33 — HARD 3 all FAIL), (2) redundant with existing L10/L29 Amihud-change ratios (|corr| 0.61/0.64 > 0.55 reclassify threshold), and (3) its trivial raw IC disappears under sector-neutralization. A clean, honestly-reported negative. One data point in the ongoing momentum-hunt campaign — NOT a structural limit on liquidity-axis signals generally.
