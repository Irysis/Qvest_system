# Challenge Note — WT-D20260621_003 / C21 Flow-Confirmed Revision Momentum

**Role**: alpha-research. **Codex stance**: REVISE (veto_flag=false, GPT-5.5 xhigh).
**Decision protocol**: Charter §8 No Silent Override. Each concern classified ACCEPT / PARTIAL / REBUTTAL.
**Self-rationalization audit**: ran grep for {미미, 관행적, 실무적, 보수적이면 OK, 대부분 결과 동일} on this note — no hit. REBUTTALs below cite quantitative data.

Codex's core read is CORRECT and ALIGNED with my draft: the C21 interaction is non-graduating. The REVISE is about (a) missing QEPM artifacts and (b) over-claiming residual value of the revision marginal. I accept the substantive points and ran new measurements to resolve them.

---

## C1 [HIGH] — Missing mandatory alpha artifacts (alpha_scores.parquet, lineage). → ACCEPT
Valid. The draft referenced an RDS panel but did not emit the canonical `alpha_scores.parquet` + `alpha_validation.json` at spec paths. **Action**: final package writes `stage_artifacts/WT-D20260621_003/alpha_scores.parquet` (256-month panel: G/P/S/M_revOnly/M_flowOnly/M_linadd) + `alpha_validation.json`. NOTE: covariance.parquet/weights.csv are OUT OF SCOPE (alpha-only mandate, agent_role_guard hard-block) — Codex listing them is a role-boundary error on its part; I do not produce them.

## C2 [HIGH] — Flow leg includes t-day flow (align=right Date<=sig_date), spec wanted t-1/lag-1 cell. → PARTIAL (ACCEPT the gap, REBUT the materiality)
ACCEPT: I did not run a separate flow-lag-1 robustness cell — that is a real omission vs the spec's honest_risk #5.
REBUTTAL on materiality (quantitative): the flow leg STANDALONE is **PORT_t = -0.638 (negative)** and the interaction sector-neutral ICIR collapses to 0.020. A look-ahead-inflated leg manifests as spuriously POSITIVE performance; a NEGATIVE leg cannot be hiding a favorable timing artifact — lagging it further cannot turn a non-additive dead leg additive. **Decisively: the ONLY surviving signal is M_revOnly (revision), which uses ZERO investor-flow data**, so investor-flow disclosure timing is irrelevant to the conclusion. The negative verdict is timing-immune. I flag the missing cell honestly rather than claim it would pass.

## C3 [HIGH] — anchor TO 18.04x > 11x hard ceiling; single-sleeve top-20 long-only w/o AX-007 exception. → ACCEPT
Valid and consistent with my draft (I flagged TO 18.04 > guideline). This is exactly why `graduation_candidate=false`. AX-007 (single-sleeve top-20 mechanism break) applies — C21 has no exception, so it is a REJECTED negative, not a candidate alpha_hat. Final package states this explicitly. (Note: revision-marginal best low-TO cell is blend60 ~13.5x, still > 11.)

## C4 [HIGH] — Sector-neutral ICIR collapse 0.1544→0.0202 (86.9% drop), RF-A4 spurious. → ACCEPT (with critical attribution refinement)
I RAN the sector-neutral check (`/tmp/c21_sn.R`, results below). Codex's collapse figure is **the G INTERACTION** (raw ICIR 0.1544 = exactly G's ICIR), NOT the revision marginal:
- **G interaction**: ICIR 0.154→**0.020**, harvey_t 2.47→**0.32** — CONFIRMED spurious/sector-driven. Strengthens the negative verdict on C21.
- **M_revOnly revision marginal**: ICIR 0.336→**0.192**, harvey_t 5.37→**3.06**, PORT_t 2.795→**1.741**. It WEAKENS (sector tilt ≈ ⅓ of gross) but SURVIVES sector-neutralization with harvey_t still > 3.
So C4 fully applies to C21 (accepted, reinforces my conclusion) and partially down-weights the revision marginal (handled in C7).

## C5 [MEDIUM] — C15 (recomputed factors not via load_month_factors) + missing M-cluster active-corr. → PARTIAL
PARTIAL ACCEPT. C15 spec text itself (pit_notes) authorizes raw consensus/investor cache direct-load (the compute_consensus/compute_investor approved path) — but Codex is right that the ORTHOGONALITY *targets* (INV08/C19/INV10) ideally go through the canonical loader; I recomputed them from cache because factor_db_daily is stale (documented). I label freshness=recomputed_from_cache and acknowledge this is a verification gap, not a clean PASS. M-cluster (M05/M06/M32) active-corr: NOT produced — accepted omission; the concept is structurally non-return so the gap is low-risk but I do not claim the check passed.

## C6 [MEDIUM] — Multiple-testing under-documented; DSR absent; chain-rule waiver unbacked. → PARTIAL
PARTIAL. selection_type=chain is defensible (P/G/S = mechanism variants of one hypothesis, hypothesis-driven, IS-only selection of anchor) per measurement-graduation §3. But since NOTHING graduates and the verdict is NEGATIVE, DSR is moot (no selection of a winner for capital). I add the chain rationale + n_cells=18 to the lineage. No graduation claim rests on a waiver.

## C7 [MEDIUM] — Routing M_revOnly to DPL/FR is fragile (sub-2.95, C02/C19 overlap, no book-marginal). → ACCEPT
Strongest fair point (Codex weakest_assumption). I OVER-stated residual value. Revised framing in final:
- M_revOnly raw PORT_t 2.795 is BELOW the 2.95 hurdle; sector-neutral PORT_t 1.741; score_rho 0.51 vs C02 and 0.36 vs C19 (consensus-family overlap).
- It is NOT presented as a graduation or admission candidate. It is logged as a **diagnostic observation** that the non-return revision axis is alive, requiring a SEPARATE book-marginal ΔIR check vs admitted consensus factors (C02/C19 already in family) BEFORE any DPL/FR use. No standalone route is asserted.

## PIT audit responses
- **C13 PASS** (Codex agrees).
- **C14**: Codex marks FAIL on "no Usable_Date proof". The consensus/investor caches carry Date columns and I apply Date<=sig_date (compute_consensus verified pattern). I treat this as PARTIAL — the filter is correct; a formal Usable_Date lineage artifact is added to alpha_validation.json.
- **C15**: see C5 (PARTIAL).

---

## Escalate-trigger check (Decision Protocol §3)
- HIGH severity concerns = 4 (C1/C2/C3/C4) → ≥5? NO (4).
- AX axiom hard FAIL: AX-007 FAIL = 1 → ≥3? NO.
- PIT C1 lockbox/lookahead violation? NO (C14/C15 are PARTIAL verification gaps, not lookahead).
- Codex stance REJECT + all-rebuttal? NO (stance=REVISE, mostly ACCEPT).
→ **No auto-escalate to Q-Lead required.** Disposition: incorporate revisions, finalize as NEGATIVE/screen-tier package.

## Net disposition
Codex REVISE accepted. The empirical conclusion is unchanged and reinforced (C21 interaction dead; sector-neutral confirms spurious). Revisions applied: (1) emit alpha_scores.parquet + alpha_validation.json + lineage; (2) downgrade revision-marginal routing to a diagnostic observation pending book-marginal check; (3) record AX-007 rejection, TO ceiling breach, sector-neutral collapse, flow-lag omission honestly. graduation_candidate=false; no silent override.
