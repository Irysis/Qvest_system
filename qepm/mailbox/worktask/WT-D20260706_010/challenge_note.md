# Self-Adversarial Challenge — WT-D20260706_010 (Revenue Forecast Revision Alpha)

**Agent**: Alpha Research (Opus 4.8 native adversarial). No external Codex (v8.2).
**Verdict pre-challenge**: canonical PORT_t whole-universe 1.36–1.74 (< 2.95 HARD); mega-inclusive long-only −0.77 to +1.21; screen-tier at best.
**Method**: 5 self-raised concerns (request-mandated axes) → ACCEPT / PARTIAL / REBUTTAL with evidence.

---

## Concern 1 (HIGH) — [PIT] The revision is a fwd-fill / staleness artifact
**Devil's advocate**: revenue_fy1 is daily but only 39.7% of days actually change value (60% stale fwd-fill). The prior `rev_rev` (3-obs diff on asof-rolled fwd-filled data) could manufacture fake "revisions" at fwd-fill boundaries, and the mega-tier LS_t 2.46 could be pure staleness noise.

**Classification: REBUTTAL (evidence)**
- Built PIT-precise asof-roll revision (latest consensus with cons-Date ≤ sig_date, C14) at both endpoints; window-robustness test C1: mega-tier IC t-stat post-2017 is **2.54 (1m) / 2.86 (3m) / 2.23 (6m)** — signal survives across fresh AND stale windows. A fwd-fill artifact would decay with window length, not persist.
- Placebo (C3, 200 within-date shuffles): real mega LS_t 2.81 vs placebo mean −0.07, 95th-pct 1.66, **p=0.01**. The cross-sectional mega-tier signal is statistically real, not staleness noise.
- **Conclusion**: fwd-fill is NOT the driver. The cross-sectional signal is genuine. (This does NOT rescue the portfolio-level verdict — see Concern 4.)

## Concern 2 (HIGH) — [FY-roll boundary] April roll jumps inject fake positive revisions
**Devil's advocate**: KR fiscal year = Dec; FY1 target rolls forward ~April (after annual filings). When FY1 switches from just-reported year to next year, revenue estimate jumps +15–30% mechanically. Naive revision counts these as huge positive "revisions" clustered in April → contaminates ~1/4 of months.

**Classification: ACCEPT (fixed)**
- Confirmed systemic: large jumps (|Δ|>0.15) by month = **6568 in April** vs ~500 elsewhere (all tickers). Roll-window (Apr–Jun) mean signed revision = +0.123 vs +0.026 other months (mechanical up-bias).
- Fix: `rev_clean3` drops roll-crossing windows (months 4–6); `rev_wins3` winsorizes ±20%.
- **Material impact on verdict?** NO in the reassuring direction: roll-clean mega LS_t is *stronger* (2.71 vs 2.46 naive), and canonical PORT_t whole-universe barely moves (naive 1.52 → clean 1.36). The FAIL is not caused by roll contamination; roll-clean confirms it.

## Concern 3 (MEDIUM) — [multi-testing] rev_rev was cherry-picked as strongest of 7 rough-screen signals
**Devil's advocate**: rev_rev was selected because it topped a 7-signal screen (eps_rev/escr/esbr/sue/rev_rev/op_rev/tp_rev). Selection bias inflates its apparent edge; DSR/Harvey-t should be deflated.

**Classification: PARTIAL**
- Acknowledged: rev_rev is a selection winner. But this is a hypothesis-driven **chain** (single core hypothesis = revenue-vs-earnings revision distinction, mechanistically motivated by KR mega=semi-export), not an argmax sweep — DSR gate is advisory here (measurement-graduation §3, selection_type=chain). The IS-only selection was on the *rough tier screen*, and the clean verification used a distinct PIT-precise construction.
- Placebo p=0.01 (C3) already survives one multiple-testing check. Whole-universe Harvey-t = 2.42–2.99 (below 3.0 advisory floor) — modest, consistent with a real-but-weak signal.
- **Net**: the cross-sectional signal is real but weak; the binding verdict comes from PORT_t (below), not from IC selection strength. No rescue needed — the honest verdict is already FAIL.

## Concern 4 (HIGH) — [mega-tier LS ≠ long-only] The milestone claim conflates LS with deployable long-only
**Devil's advocate**: the entire motivation ("mega-tier survives, LS_t 2.46") is a top-half-minus-bottom-half **long-short** within 10 mega names. KR is no-short. The deployable long-only mega portfolio may be dead — same LS≠long-only trap that killed 16/16 prior candidates.

**Classification: ACCEPT (this is the binding verdict)**
- Canonical long-only mega constructions: mega-tier-30 top-5 PORT_t **−0.54**, top-10 **−0.77**, large-cap-50 top-20 **−0.36**, rev+size tilt **−0.09**. All FAIL, most negative.
- Leg decomposition (vs *tier-EW*): long_vs_ew t_post17 = +2.71 AND short_vs_ew t_post17 = −2.69 — the edge is **symmetric**; long leg beats tier-EW but the cap-w KOSPI200 benchmark (Samsung/Hynix-dominated) is a different, harder bar. An EW top-N of good-revision mega names does not hold enough Samsung/Hynix at cap-weight → loses to cap-w benchmark in the 2025–26 mega surge.
- **Refinement (not a rescue)**: a cap-weighted revision-TILT (overweight good, underweight bad, keep cap-weight base) among top-50 gives active t_post17 = **2.38** (~0.8%/yr) — mildly return-additive on a cap-w base, but (a) below 2.95, (b) requires cap-weighting + tilt = optimizer/weighting territory, not a long-only EW top-N alpha. Reported as a diagnostic for downstream, not a weight proposal (Alpha role boundary).

## Concern 5 (MEDIUM) — [benchmark regime] 2025–26 benchmark is an extreme mega-cap surge; verdict may be edge-of-sample fragile
**Devil's advocate**: KOSPI200 ran 605→1370 (2.3x) in 6 months to 2026-06 (Samsung/Hynix). Panel ends 2026-04. The most extreme benchmark months sit near the panel edge and could dominate post-2022 t-stats.

**Classification: PARTIAL (caveat retained)**
- Real regime (memory reference-kr-2025-megacap-semi-regime; benchmark verified continuous, no discontinuity). This is genuinely why long-only can't beat cap-w — it's the mechanism, not a bug.
- But: the negative verdict does NOT depend on the tail — whole-universe PORT_t post-2017 is 0.38–0.55 across the *whole* 2017–2026 window, and post-2022 ~0. The FAIL is broad-based, not edge-driven. Retained as caveat for magnitude interpretation of the cap-w-tilt diagnostic (t_post22 1.76 vs t_post17 2.38 = some regime dependence).

---

## Escalation check
- HIGH-severity concerns: 3 (C1 rebutted with evidence, C2 fixed, C4 accepted = binding FAIL). No AX axiom hard-FAIL. No PIT C1 lookahead (C14/C4 asof-roll verified, roll-boundary handled). **No Q-Lead auto-escalate trigger** (HIGH sev accepted-fails < 5, no PIT C1 violation).

## Self-rationalization auto-check
Scanned my own text for "미미/관행/실무적/보수적/대부분 동일". Found none used to justify passing a gate. The cap-w-tilt "mildly additive" is quantified (t=2.38, 0.8%/yr) and explicitly labeled below-gate + out-of-role, not hand-waved.

## Final verdict (post-challenge)
**FAIL — screen-tier at best.** Revenue-forecast-revision has a genuine, roll-clean, placebo-surviving *cross-sectional* mega-tier signal (IC t_post17 ~2.7, cleanly distinct from dead earnings-revision), but it does NOT transmit to a deployable long-only top-N portfolio (canonical PORT_t 1.36–1.74 whole-universe; −0.77 to +1.21 mega long-only) — the IC→PORT_t transition wall, driven by (a) the signal's edge being symmetric/short-side-accessible-only in the mega tier under no-short, and (b) the cap-w benchmark's Samsung/Hynix concentration. Route: DPL_FEATURE (cross-sectional revenue-revision as a feature) + a flagged cap-w-tilt diagnostic (t_post17 2.38) for optimizer/RAMP consideration. Not a milestone; a well-characterized honest negative.
