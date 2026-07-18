# Self-Adversarial Challenge — WT-D20260718_002 (Insider-selling EXCLUSION filter)

**Agent**: alpha-research (Opus 4.8 native adversarial). **Verdict under review**: FALSIFIED (exclusion degrades base momentum PORT_t across all tested configs). **AX-008**: self-adversarial = 1 of 3 verification sources.

Devil's-advocate: could this be a *false* negative (mechanism real but my test failed to detect)? ≥3 concerns raised, classified, resolved.

---

## Concern 1 — Sell-intensity DEFINITION under-explored (could a different formula flip the sign?)
**Raise**: The primary + 18-cell sweep vary lookback L and exclusion percentile P but hold one intensity formula (net on-market value / mcap). Miller overvaluation might register on a *different* measure — gross selling (ignoring offsetting insider buys), seller breadth, or share-count normalization.
**Class**: REBUTTAL (evidence).
**Resolution**: Ran 3 additional intensity definitions at the primary L6/P10 frame (`04_intensity_robust.R`): gross-sell/mcap (paired t=−1.13), seller-breadth #reports (t=−1.49), gross-sell P20 (t=−0.94). **All negative.** Total **21/21 configurations negative** (18 sweep + 3 alt-intensity). No formula in the tested space produces a positive exclusion effect. The sign is a robust property, not a formula artifact.

## Concern 2 — Base = momentum only; exclusion might help a different base (value / incumbent multi-factor book)
**Raise**: I tested exclusion on mom_12_1 top-25. The incumbent book (STR_1631/1656) is multi-factor; maybe insider-sell exclusion helps a value or blended base where overvalued names cluster differently.
**Class**: PARTIAL.
**Resolution**: (a) The `why_now` binding is *momentum decay* — momentum is the on-point base. (b) The paired diff only bites at the momentum-top ∩ insider-seller intersection; a negative diff means insider-sold momentum winners *outperform* their replacements — a mechanism finding, not a base-specific quirk. If officer net-selling carried forward-underperformance info it would surface here. (c) **Scope limit acknowledged + logged as frontier**: exclusion on value/incumbent base is untested (next_probe #1). Not a reason to withhold the kill — the mechanism (sell-side info content) is base-agnostic and shows null-to-adverse.

## Concern 3 — Is this just R33 re-run? (redundancy vs triangulation)
**Raise**: R33 already found KR officer net-SELL direction uninformative (t≈0) in the monitoring frame. Am I re-deriving a known negative and mislabeling it novel?
**Class**: ACCEPT (consistency) — but distinct frame.
**Resolution**: Mechanisms are genuinely different: R9 = insider as long-side *selection* signal (pool inclusion, cap-w cross-sectional wall); R33/R37 = *monitoring* (per-holding forward hold-safety); THIS = *exclusion* from base universe before momentum selection (Miller short-constraint harvest). R9 explicitly left "universe filter (exclusion)" as unmeasured. The negative RESULT converging across three independent frames (selection / monitoring / exclusion) is **triangulation** that KR liquid-universe officer net-selling has no exploitable forward-underperformance signal — stronger than any single frame. This is the value of running it, not redundancy.

## Concern 4 — Look-ahead / PIT contamination inflating the (negative) effect
**Class**: ACCEPT clean. `assert_overlay_pit` PASS (formation month-end < holding-month start). lag1 stress: primary diff −2.15% is *more* negative than lag1 −0.97% (inflation −121%, `overlay_lookahead_ab`=clean) — no upward look-ahead. Signal genuinely lagged (rcept_dt month ≤ formation month).

## Concern 5 — Cap-weighted-benchmark artifact (small-cap exclusion noise)
**Class**: REBUTTAL. Dual-basis: excluded names median size-pct 0.284 (upper-third by size — NOT small-cap-localized). Negative holds in **both** bases: cap-w 1.171→0.771 AND EW-universe 1.857→1.442. Not a benchmark-construction artifact.

---

## Self-rationalization auto-check
No banned hedges used ("미미/관행적/보수적이면 OK/대부분 결과 동일"). The negative is decisive on its own terms — 21/21 configs, both eras, both bases, no crisis defense. No REVIEW triggered.

## Escalation check (Q-Lead auto-triggers)
HIGH-severity violations ≥5: NO. AX axiom hard FAIL ≥3: NO. PIT C1 (lockbox/lookahead): NO (clean). → **No escalation.** Clean terminal negative (ALPHA_DONE_NEGATIVE), not a violation.

## Verdict after challenge
**FALSIFIED / KILL upheld.** Every adversarial angle either strengthens the negative (concerns 1,3,5) or is a logged scope-limit frontier (concern 2). No self-rationalization, no PIT breach. Pre-registered kill criterion met (paired_t < 2; in fact negative).
