# Alpha Challenge Note — WT-D20260621_007 (M36_SignedFlowRun)

**Codex Critic Round** (GPT-5.5, xhigh, 2026-06-21T17:53). Stance = **REVISE**, veto_flag=false.
Decision protocol per measurement-graduation / Charter §8 No Silent Override.
Agent verdict (unchanged after round): **MEANINGFUL_NEGATIVE → SCREEN-ROUTE, NOT graduation candidate.**
Codex explicitly agrees with the no-capital-admission conclusion; REVISE is about packaging/robustness, not the core rejection.

| Codex concern | Severity | Classification | Resolution |
|---|---|---|---|
| C1 — missing challenge_note + lineage (AX-008 / No Silent Override) | HIGH | **ACCEPT** | This note created + lineage recorded. risk/optimizer/weights/cov correctly absent → marked **N/A** (alpha-only stage; those are downstream agents' scope, not produced here). |
| C2 — DPL_FEATURE recommendation overreaches | HIGH | **ACCEPT** | Recommendation **downgraded** in final package: from "route=DPL_FEATURE" to "do_not_promote=true; PARK; feature-retention is a HYPOTHESIS requiring a separate cost-aware incremental ablation vs INV09/INV10 + PG strategies — NOT asserted here." |
| C3 — no sector/size-neutral ICIR (RF-A4) | MEDIUM | **ACCEPT (resolved)** | Ran sector+log(Size) neutralized IC: rank-IC −0.0276 (89.6% retention of −0.0308), ICIR −0.454. **Negative signal SURVIVES neutralization** → it is a structurally real flow-streak effect, NOT a sector/size/coverage proxy. Sharpens, not dissolves, the finding. |
| C4 — alpha_scores ends 2026-02-27 not 2026-03-31; normalization wording | MEDIUM | **ACCEPT** | Factual correction applied. The 254 scored sig_dates with forward returns span 2005-01-31..**2026-02-27** (terminal 2026-03-31 signal has no forward-return window → correctly excluded from the screen, no look-ahead). |
| C5 — DSR n/a + PG crowding absent | MEDIUM | **PARTIAL** | DSR n/a is **correct** for chain selection_type (measurement-graduation §3) and moot given negative PORT_t — retained as labeled, not a rationalization. The crowding/multi-test concern attaches only to the feature-retention claim, which C2 now downgrades → no longer load-bearing. |

## Rationalization self-audit (Codex flagged 7 phrases)
Codex's `rationalization_red_flags` grep hit my hedging language. Re-examined each:
- "screening, NOT admission-binding" / "A clean negative IS success" / "This is NOT a structural limit" — these are **required labels** under measurement-graduation §1 and AX-000-amended, not rationalizations. **Retained.**
- "all configs agree on the negative direction" — load-bearing evidence (6/6 configs negative, direction robust to all knobs), not a dodge. **Retained.**
- "moot given negative PORT_t" (re DSR) — **trimmed** to plain factual statement; DSR is n/a by chain rule independent of the sign.
- **"As a DPL input feature"** — this WAS overreach (Codex C2). **Removed as a recommendation**; reframed as an untested hypothesis to park. This is the one genuine self-rationalization corrected.

## Unresolved disputes (logged, not blocking the negative verdict)
1. Whether inverted M36 adds cost-aware incremental value inside DPL after INV09/INV10 + PG strategies — **NOT tested; explicitly deferred** (the package no longer claims it does).
2. Codex requested weights.csv / covariance.parquet — **N/A**: this is the alpha stage; no weights or Σ are produced (agent_role_guard forbids it). Not an omission.
3. Codex path note (`stage_artifacts/WT_WT-...`) — actual artifacts are under `stage_artifacts/WT-D20260621_007/` (correct convention); the WT_ prefix paths in the prompt template do not exist by design.

## Net effect on verdict
No change to the core conclusion (reject as standalone long-only alpha; screen-route only). The two substantive REVISE items — (C2) overreaching DPL claim and (C3) neutralization gap — are resolved by **downgrading the recommendation** and **running the neutralization** (which confirms the signal is real-but-inverted). AX-008 triangulation: Forge n/a at this stage; Codex REVISE addressed; agent self-audit done.
