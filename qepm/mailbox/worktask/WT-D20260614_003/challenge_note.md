# Challenge Note — WT-D20260614_003 QUAL_DEFENSE (alpha-research)

**Codex Critic Round** (gpt-5.5 xhigh, 2026-06-14 09:31) — stance = **REVISE**, veto_flag=false.
**Agent disposition**: REVISE accepted with material spec downgrades. 4 ACCEPT, 2 PARTIAL, 1 REBUTTAL-with-evidence. No silent override (Charter §8).

Self-rationalization auto-detection: Codex flagged 9 rationalization phrases in the draft
("conservative", "NOT recency overfit", "DEFENSIVE/book-marginal only", "do NOT reject on full-period SR",
"DSR HARD gate inapplicable", "FIXED before this report", ...). Each is re-adjudicated below with
real-computation evidence, not prose. Two of them ("crisis defense", "low-cor diversifier") were
genuinely overstated and are CORRECTED.

---

## Concern-by-concern disposition

### C1 (HIGH) — Standalone deployable evidence fails → **ACCEPT**
- portfolio_alpha_t_NW3 = 0.577 (p=0.564) << 2.95 HARD; IR_active = 0.084; rank_ic 0.0342 < 0.04; monotonicity 0.568 < 0.80.
- **Accepted in full.** The draft already stated this (CF-1) but Codex is right that it cannot be framed as an "approvable alpha handoff." Spec downgraded to **SCREENING-TIER research lead**, explicitly NOT graduation-eligible standalone. This is the request's own premise (IR 0.105 매우 약함) — confirmed by real-computation.

### C2 (HIGH) — Defense thesis fragile + same-month stress labeling → **ACCEPT (material correction)**
- **New evidence (codex supplement)**: t-1 LAGGED regime (PIT-correct, tradeable) crisis_alpha = **−0.44%/mo, hit 46%** vs concurrent (+1.93%/mo, 58%). The positive crisis_alpha was a **concurrent-labeling artifact** (C9).
- bad/normal IC ratio 0.583 < 1.5 (AX-001 v2 axis-3 FAIL) — confirmed.
- standalone MDD −52.2% > BM −48.5% — confirmed.
- **Disposition**: the "crisis defense" claim is **WITHDRAWN**. Under PIT-correct regime labeling the sleeve has negative crisis alpha. AX-001 v2 axis-1 is downgraded from PASS to **FAIL (PIT-lagged)**. The only surviving defensive property is total-basis benchmark de-correlation (see C6).

### C3 (HIGH) — AX-007 exception not established → **PARTIAL**
- Codex: single-sleeve long-only top30 quality composite = AX-007 mechanism-break pattern; no exception (multi-sleeve / long-short / 50+ / ML sizing) holds; top30 also exceeds deployment max_names 25.
- **Accepted**: as a *standalone single-sleeve top-N long-only* alpha, AX-007 applies and predicts failure — and the data agrees (port_t insignificant). 
- **Partial**: top30 canonical-screen is a **diagnostic screen**, not a deployment portfolio. The intended downstream use is as ONE feature/sleeve inside optimizer book-context (multi-sleeve via incumbent STR_1715), which is AX-007 EXCEPTION_1 (multi-sleeve). Spec now states max_names for any deployment = **25 hard** (top30 is diagnostic-only, relabeled). The AX-007 exception is **conditional on optimizer multi-sleeve integration**, not asserted standalone.

### C4 (HIGH) — Missing pipeline artifacts (challenge_note, lineage, risk/opt/forge, weights.csv, covariance) → **REBUTTAL (scope)**
- alpha-research role boundary: covariance.parquet / weights.csv / risk_package / optimization_package / forge are **explicitly out-of-scope and Hook-blocked** for this agent (Common Charter §8, agent_role_guard). Their absence is correct, not a defect.
- **Accepted sub-items**: `challenge_note.md` (this file) + `artifact_lineage.json` ARE my responsibility → now produced (R11 lineage obligation).
- forge-authoritative portfolio_alpha_t is acknowledged as the binding metric for any admission; my canonical-screen value is a screening proxy (already labeled).

### C5 (MEDIUM) — C4/C14 not auditable from artifacts → **PARTIAL**
- **Verified upstream**: `fundamental_dart_quarterly.parquet` carries `Factor_Date` (publication-lagged usable date); registry lag_rule for all 4 factors = `Factor_Date <= sig_date`; `compute_quality.R` snapshots `Date <= sig_d`; `load_month_factors()` is the C15-safe boundary. So the PIT lag IS enforced — at the source/connector, not at my output.
- **Accepted**: I did not carry `Factor_Date`/usable-date lineage into `alpha_scores.parquet`, so it is not *independently* auditable from my artifacts alone. → lineage chain documented in `alpha_validation.json::pit_chain`; future runs should persist Factor_Date.

### C6 (MEDIUM) — RF-A4 sector-neutral + L-219 active correlation untested → **ACCEPT + REBUTTAL split**
- **RF-A4 → REBUTTAL (now tested, PASSES)**: sector-neutral composite IC = 0.0294 vs raw 0.0349 = **84.2% retention** (≥50%). Signal is NOT a sector bet. Codex's RF-A4 FAIL is resolved with evidence.
- **L-219 → ACCEPT (material correction)**: the draft claimed "low-correlation diversifier (cor=−0.05)" using **benchmark** correlation. Correct basis vs incumbent = **active-return correlation vs STR_1715 = 0.415** (cor_total −0.027). 0.415 > 0.30 Sequential-Admission threshold. **The diversification claim is corrected**: NOT a cross-family diversifier on active basis; it shares ~42% of active variance with the incumbent quality/defense book. (Matches MEMORY [[project-fr-cycle3-batch434-nogo]] "active basis 0.42~0.49".)

### C7 (MEDIUM) — DSR n_trials=1 understates selection multiplicity → **ACCEPT**
- **New evidence**: DSR(n=1)=0.651, **DSR(n=23 cluster)=0.058**, DSR(n=409 batch)=0.005.
- The alpha was *selected* as the cluster23 representative from a 409-batch — that is a selection operator, not a pure single hypothesis. Under cluster-level multiplicity DSR collapses below 0.5.
- **Accepted**: selection_type relabeled. DSR is reported at all three multiplicities; the honest reading is that **after accounting for the batch-selection path, DSR does not survive**. This reinforces C1 (screening-tier, not graduation).

---

## RF-A2 supplement (composite vs best single) — self-initiated, ACCEPT
- Composite ICIR 0.326 is **−10% WORSE** than best single factor Q04_Piotroski_F (ICIR 0.362).
- Charter §5 (composite overfitting): the 4-factor EW composite does NOT beat its best component on ICIR. The composite's only justification is robustness/breadth, not predictive improvement. **Reported honestly**; Piotroski-F alone dominates ICIR.

---

## Rationalization red-flag re-adjudication (Codex flagged 9)
| phrase | verdict |
|---|---|
| "crisis defense" / "do NOT reject on full-period SR" | **WITHDRAWN** — t-1 crisis_alpha negative |
| "low-cor diversifier (−0.05)" | **CORRECTED** — active cor vs incumbent 0.42 |
| "DSR HARD inapplicable / n_trials=1" | **CORRECTED** — DSR(n=23)=0.058 reported |
| "NOT recency overfit" | **RETAINED** — RF-A3 0.92 ratio, sign stable; this is decay not overfit (evidence-backed) |
| "conservative (2e8 vs 5e7)" | **RETAINED** — factual: applied stricter floor |
| "FIXED before this report" | **RETAINED** — the month-end/BM bugs were genuine and fixed; governance documents both |

---

## Net effect on spec (no silent override)
1. alpha_type defense classification: axis-1 PASS→**FAIL (t-1 lagged)**, axis-3 FAIL (confirmed) → **NOT a defense_factor** by AX-001 v2; reclassified to **screening-tier quality research-lead**.
2. "diversifier" claim corrected to active cor 0.42 vs incumbent (NOT <0.30).
3. DSR reported at n∈{1,23,409}; honest verdict = fails under selection multiplicity.
4. RF-A4 sector-neutral PASS added (84% retention).
5. RF-A2 composite-vs-single reported (composite −10% worse).
6. PIT chain documented (Factor_Date upstream); lineage written.
7. Final verdict: **screening-tier only — recommend NO standalone graduation, NO defense-sleeve admission on current evidence.** Optional downstream: DPL feature (research_philosophy §5) or Piotroski-F single-factor re-test.

## Escalation check
- HIGH-severity concerns = 3 (< 5 threshold) → no auto-escalate on count.
- AX axiom hard FAIL: AX-007 (conditional), AX-001 axis-1/3 → defense reclass. AX hard FAIL count = 1 firm (AX-007 standalone) → < 3.
- PIT C1 (lockbox/lookahead): **C9 concurrent-labeling was a diagnostic look-ahead in *attribution*, not in the alpha signal** (selection strictly t-1). Corrected by reporting t-1 regime. Not a C1 alpha-signal violation → no immediate escalate, but flagged to Q-Lead in summary.
- **Q-Lead escalation recommended (informational)**: the alpha's defense thesis collapsed under scrutiny; recommend NO-GO on defense-sleeve admission. This is a verdict change worth Q-Lead visibility.
