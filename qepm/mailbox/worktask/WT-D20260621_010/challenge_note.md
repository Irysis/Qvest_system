# Challenge Note — WT-D20260621_010 (Alpha) — Codex Critic Round

**Date**: 2026-06-21
**Agent**: QEPM Alpha Research
**Codex model**: gpt-5.5 (xhigh)
**Codex stance**: APPROVE_CONDITIONAL (veto_flag=false, agree_with_claude=false on language strength, agree on non-graduation verdict)
**Result verdict**: CLEAN_NEGATIVE — REJECT (unchanged; Codex concurs with rejection)

Codex confirmed the substantive finding (negative portfolio alpha, perverse D10, RF-A7 not present) and conditioned approval on softening overreaching language and adding process artifacts. Below: each concern classified ACCEPT / PARTIAL / REBUTTAL per the v6.0 Decision Protocol.

## Concern Resolution

### C1 (MEDIUM) — Concept-closure language vs 29-cell grid → **ACCEPT**
Codex: draft labels the concept "closed/deprioritized" off a 29-cell representative grid while the spec registered a 576-cell surface. Non-graduation supported, but permanent dead-end language overreaches.
**Action**: Verdict + next_route narrowed to "negative under the tested representative grid (29 cells spanning all axes)". Explicitly NOT a permanent-dead-end proof. A future revival path requiring the full 576-cell grid is documented in next_route. AX-000 (no "structural limit/dead-end") respected.

### C2 (MEDIUM) — AX-007 escape claim is wrong → **ACCEPT**
Codex: the spec premised the binary event gate "escapes AX-007"; the realized implementation is single-sleeve long-only top-20 (not an AX-007 exception), and the positive-rank-IC / negative-port / worst-D10 pattern IS the AX-007 translation failure.
**Action**: Added challenge_flag RF-AX007 (MEDIUM). Reframed: this WT does NOT escape AX-007 — it DEMONSTRATES the translation failure. Noted the failure is doubly severe here because the underlying signal is also gross-negative (event-vs-market −0.43%/mo), so it would fail even with a translation-wall-immune construction.

### C3 (MEDIUM) — Novelty=5 overclaim → **ACCEPT**
Codex: only active-return FF correlations were run; the binding cross-sectional checks (net-payout-yield, C23, value, size, flow, insider) were not. "Novelty=5 confirmed" is too strong.
**Action**: Novelty claim WITHDRAWN. orthogonality.verdict changed to "NOVELTY UNVERIFIED". The package makes no novelty assertion. Future revival must run the cross-sectional redundancy battery first.

### C4 (LOW) — Missing lineage / triangulation artifacts → **ACCEPT**
Codex: no artifact_lineage.json / challenge_note.md present at critique time; AX-008 / Charter §8 not yet satisfied for finalization.
**Action**: artifact_lineage.json recorded via record_package_lineage (write_json → lineage order per L-194). This challenge_note.md written. (Risk/optimizer/weights absence is correct — alpha agent does not produce those; agent_role_guard.)

### C5 (LOW) — Usable_Date not persisted for row-level C14 audit → **PARTIAL**
Codex: C14 is enforced in fe_buyback_drift.R by the Usable_Date<=t filter, but alpha_scores.parquet omits Usable_Date, so PIT verification depends on source-code inspection.
**Action (partial)**: Built `stage_artifacts/WT_D20260621_010/c14_usable_audit.parquet` — per signal-Date max(Usable_Date) with ok flag. Audit result: **all 138 signal dates have max(Usable_Date) <= signal Date (no future leak)**. This gives an independent, data-level C14 audit table. (Did NOT join per-row Usable_Date into the score parquet because the most-recent-active-decision Usable_Date is well-defined per firm-month and the date-level audit table is sufficient for reproducible PIT verification — hence PARTIAL not full.)

## Rationalization self-check (Decision Protocol auto-detection)
Codex flagged 3 rationalization phrases in the draft:
- "This does not change the verdict (signal is negative regardless of novelty)" — **REMOVED**, replaced with explicit novelty withdrawal.
- "Verdict unaffected (signal negative regardless)" — **REMOVED**.
- "EXEMPT (selection_type=chain, single pre-registered primary)" — **RETAINED**: this is a legitimate per-request governance fact (the WT request and measurement-graduation §3 explicitly classify chain selection as DSR-exempt), not a self-rationalization. It is a factual exemption citation, not a hedge that minimizes a finding.

Grep self-check on final package for prohibited hedges ("미미/관행/보수적이면/대부분 결과 동일/이미 반영"): none present.

## Escalation check
- HIGH severity concerns: 0 (all MEDIUM/LOW). No Q-Lead escalate trigger.
- AX axiom hard FAIL: AX-007 flagged but as DEMONSTRATED failure of a negative signal (not a violation by the agent — the agent reported it honestly). Not an escalate trigger.
- PIT C1 (lockbox/lookahead): none. C14 audit PASS.
- Codex stance APPROVE_CONDITIONAL with all concerns ACCEPTED/PARTIAL (no full rebuttals) → no Q-Lead escalation required.

## Final
Package finalized with C1-C4 accepted and C5 partially accepted. Verdict (CLEAN_NEGATIVE / REJECT) unchanged and concurred by Codex.
