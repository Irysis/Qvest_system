# Judge — Codex Critic Round Disposition (WT-S20260626_001)

**Codex stance**: REVISE (veto_flag=false). **Core finding AGREES**: rejecting max-cash is directionally supported; A/B credible; formulas machine-precision; weights.csv real (269m, 20+CASH, max 0.20, Σ=1); covariance 18×18 PSD cond 40.95. Codex's own `agree_with_claude` is FALSE only re *process-closure labeling*, not the reject decision. **No veto, no hard-constraint violation → no Q-Lead escalate** (HIGH count = 3 but all are label/evidence-packaging, not axiom hard-FAIL; none reverses the verdict).

The verdict is **JUDGE_FAILED / REJECT max-cash** — over-determined by the judge's OWN independent recompute (judge = adjudicator AND independent source here: re-derived every headline from ab_panel_full.csv to machine-eps, re-md5'd all 4 packages, audited bt_result 16-check). Codex's concerns refine the *robustness/process labels*; they do not move dIR −0.0224 toward the +0.05 gate.

Autonomous disposition (ACCEPT / PARTIAL / REBUTTAL) of the 5 concerns:

## C1 (HIGH) — AX-008 overclaimed (no durable Architect artifact) — ACCEPT
Verified Codex's claim: there is **no standalone architect verification artifact** in the WT mailbox or stage dir; `source_3_architect` appears only as text inside forge/judge packages. I will **not** claim AX-008 SATISFIED on a self-referential basis.
- **Correction**: AX-008 label downgraded `SATISFIED` → **`INSUFFICIENT_INDEPENDENT_ARTIFACT (non-blocking for REJECT)`**.
- **Why non-blocking**: AX-008 (Verification Triangulation) gates *admission* of a new strategy. This WT is a **REJECT** of a sizing variant of an already-admitted book. The bar to reject is the book-marginal gate (dIR), which FAILS on the judge's own independent recompute. A reject does not require 2/3 independent PASS — it requires that the evidence does not support admission, which is over-determined. The two materially-present independent sources (judge's own machine-eps recompute + Codex's own formula/weights/cov verification, both AGREEING max-cash is worse) are sufficient for a reject. Were this an ADMIT, C1 would be blocking and I would require the durable architect artifact.

## C2 (HIGH) — 5-spec Harvey / DSR robustness label — PARTIAL (relabel accepted, substantive demand rebutted)
- **ACCEPT (label)**: Gate C relabeled from implied full-robustness PASS to **`POINT_ESTIMATE_PASS (PORT_t NW lag-3 only; 5-spec robustness not packaged)`**. Both arms clear PORT_t≥2.95 and net_IR>0.3 on the point estimate; I do not assert multi-spec robustness.
- **REBUTTAL (substance)**: (1) FF5/FF6 factor-return panels **do not exist in KR infra** — `portfolio_alpha_t_nw_lag3` is the authoritative judge Gate C statistic per measurement-graduation §2; forcing absent specs = fabrication. (2) **DSR chain-exempt** per measurement-graduation §3: sizing_only single pre-specified operator change (n_trials=2, not a sweep/argmax) → DSR HARD inapplicable. (3) **Reject-direction makes spec-shopping structurally absent**: max-cash is WORSE on the one authoritative spec (PORT_t −0.06) and on SR/IR/CAGR/Calmar/Sortino — there is no spec under which a uniformly-dominated arm could be cherry-picked to win. Robustness multiplicity matters when *selecting a winner*; here we are *rejecting a loser*.

## C3 (HIGH) — Gate A PIT too strong / alpha lineage not file-verifiable — PARTIAL
Verified on disk (converted Codex's assertion into a concrete check):
- Parent `alpha_package.json` **exists and sha256 == pinned `87662e5d4f92...`** (hash-verified at judge time — alpha lineage is cryptographically pinned, not merely asserted; `alpha_inheritance_cor=1.0`).
- Deep grand-parent discovery parquet `stage_artifacts/WT_D20260426_007/alpha_scores.parquet` is **ABSENT** on this machine (April scratch artifact, not an input to this WT).
- **Actual forge input** = `04_Research/.../03_period_returns.csv` (frozen base sleeve ret_net) — **present**. Forge Pure-Function boundary never opens alpha_scores.parquet.
- **Disposition**: The overlay min-operator PIT is **directly verified PASS** (all betas t-1 lagged, min(PIT,PIT)=PIT order-preserving, betas∈[0,1] confirmed). The **base-sleeve C6/C12/C14/C15 selection lineage** was adjudicated at STR_1715's OWN admission (SR 1.9536, in book) and is hash-pinned here — but is **not re-derivable from the now-absent April scratch parquet**.
- **Correction**: Gate A relabeled `PASS` → **`PASS (overlay PIT directly verified; base-sleeve selection-lineage hash-pinned to admitted STR_1715, NOT file-re-derivable on this machine — non-blocking for sizing_only REJECT)`**. For an ADMIT this incomplete file-lineage would warrant requiring the parquet restored; for a REJECT of a sizing variant it does not change the disposition.

## C4 (MEDIUM) — Tail / Gate 6 CVaR not packaged — ACCEPT (relabel)
Accepted: no *current A/B* CVaR delta packaged. The tail evidence already present (co-firing segment MDD −23.58% vs −17.13%, GFC −9.24% vs −4.59%, both WORSE for max-cash) supports rejection but is MDD-basis, not CVaR.
- **Correction**: Gate D/tail relabeled to **`INCOMPLETE_BUT_NON_BLOCKING (co-firing+GFC MDD show max-cash strictly worse on tail; current A/B CVaR not packaged; disposition is REJECT so tail-closure is moot)`**. CVaR would only reconfirm the direction already established.

## C5 (MEDIUM) — Echo-chamber / waiver-phrase risk — PARTIAL
- **ACCEPT**: Added explicit FAIL/N/A/INCOMPLETE gate labels (above) rather than soft waiver prose, to defuse RF-J5.
- **REBUTTAL**: The substantive waivers are defensible and now externally checked, not self-referential: DSR chain-exempt (measurement-graduation §3, rule-grounded), C15/lookahead-self-scan inapplicable (no factor_engine_path — overlay re-weights a frozen sleeve, does not build factors), formula parity machine-eps (judge independent recompute, not forge's word). "robust"/"common-mode" describe a genuinely single-basis overlay measurement (Architect-/judge-reproduced direction), not a gap-masking rationalization.

## Net disposition
- ACCEPT: C1 (AX-008 downgrade), C4 (tail relabel).
- PARTIAL: C2 (Gate C → point-estimate label; substance rebutted), C3 (Gate A lineage caveat label; substance hash-pinned), C5 (explicit labels added; waivers defended).
- **No concern reverses the verdict.** Codex agrees the reject is correct. Every label correction is incorporated into `judge_verdict.json`. Verdict stands: **JUDGE_FAILED → REJECT max-cash, RETAIN incumbent product-combine.** dIR −0.0224 (judge-independently-recomputed) fails the +0.05 book-marginal gate in the wrong sign.

## Escalation check
HIGH count = 3, but all are evidence-packaging/labeling for a REJECT (no axiom hard-FAIL, no PIT-C1 hard violation, no AX axiom FAIL≥3). Reject is the conservative disposition. **No Q-Lead escalate.**
