# FQ-017 m1 Overlay Drain — Self-Adversarial Challenge Note

**Agent**: alpha-research · **Date**: 2026-07-12 · **Prereg sha256**: b93e48f2f238c4496e5774c9dd8b7c66bdfe89d9d9dccc4e514b683e79d1a3ee
**Charter §8 No Silent Override compliance.** Verdict: m1 as stock-level exclusion/tilt overlay = **no significant marginal contribution (all paired NW-t < 2.0) → SCREEN_TIER / feature preserved, NOT a value-adding overlay.**

## A. No-Silent-Override infeasibility (surfaced, not silently substituted)
Literal task = stock-level m1 exclusion/tilt on carrier STR_1715 via `drain_main`. Three hard blockers (see preregistration.json `infeasibility_surface`):
- **F1** carrier per-stock holdings time series UNAVAILABLE (bt_result$holdings 0 rows, 04_holdings.csv header-only, alpha_scores single-month). Reconstruction requires re-running carrier construction (out of recon-read-only scope).
- **F2** carrier lives in m1-dead mega/mid tier (current snapshot: Samsung/SK Hynix/semis/retail + 75% cash; Phase A MEGA_wshare 0.012).
- **F3** drain runner overlay = market-level exposure SCALAR; cannot express cross-sectional stock-level exclusion.
→ **Chosen**: reuse drain runner's CONTRACT PRIMITIVE (`weighted_screen_bt`/`.nw_t_mean`/`drain_oos_v2`/`overlay_pit_guard`, sourced QVEST_DRAIN_NORUN=1) on dual-tier bases from the m1 panel. All returns via contract path (no self-synthesis, no new engine). Documented, not silent.

## B. Adversarial concerns (>=3 raised, classified)

**C1 — Base ≠ real carrier (base-choice sensitivity).** Could the carrier's actual factor-selected names show a stronger m1 increment than my proxy bases?
- **Classification: PARTIAL (caveat, not reversal).** Carrier unavailable (F1). Dual-tier brackets the range: carrier's tier = LARGE (top-25 liquid) shows paired NW-t 0.75–1.27; broad m1-locus shows ~0. Carrier's factor book is a subset of the large-cap tier, so its m1 increment plausibly falls in the same weak-insignificant band. Independently, Phase A established m1 is dead in MEGA/MID tiers (cap-tier localization). Base-choice is a stated caveat; the sub-threshold conclusion is robustly bracketed on both sides.

**C2 — kappa=0.30 / 80th-pctile exclusion arbitrary; a stronger tilt might clear the bar.**
- **Classification: REBUTTAL.** A stronger tilt = more concentration into clarity = converges to Phase A's clarity-selected top-25, which was ALREADY measured standalone (cap-w PORT_t 2.35 < 2.95, OOS retention ~0.06, decay). The OVERLAY question is about *marginal* consumption of a mild overlay; the aggressive limit is the already-FAILED standalone selector. Mild parameters pre-registered (appropriate for an overlay). Not a reversal.

**C3 — Full-period paired NW-t may mask post-2017 decay.**
- **Classification: ACCEPT (strengthens verdict).** oos_v2 for BROAD arms is NEGATIVE (base −0.049, excl −0.110); LARGE excl/tilt oos_v2 positive but on a near-zero base. The marginal effect decays too — a post-2017 split would be weaker than the already-sub-threshold full-period. Reported as confirming the post-2017 decay wall (measurement-graduation §6).

**C4 — LARGE PORT_t "jump" 0.07→0.39 looks like a 5x improvement.**
- **Classification: ACCEPT (report discipline).** Both are ≪ 2.95; the ratio is meaningless (increase from ~nothing to ~nothing). Primary judgment metric = paired NW-t (0.75), NOT PORT_t ratios. Reported accordingly; PORT_t ratios never cited as the finding.

**C5 — 6 arms + lag/strict = implicit selection / cherry-pick?**
- **Classification: REBUTTAL.** All arms pre-registered, all reported, NONE clears 2.0, no best-of-N pick. selection_type=chain (not sweep); DSR not applicable. No cherry-picking possible when nothing passes.

## C. Self-rationalization auto-detection
Scanned own reasoning for banned phrases ("미미/관행적/실무적/보수적이면 OK/대부분 동일"). None used to justify a pass. The verdict is a FAIL-to-clear (screen-tier), so no rationalization pressure toward a false positive. The one directional positive (LARGE_tilt +74bps/yr) is explicitly labeled insignificant (t=1.27), not upgraded.

## D. PIT verification (07-06 BearProb incident firewall — all 4 clean)
1. `assert_overlay_pit` HARD **PASS** (cutoff=ym2date(t) ≤ holding_start=ym2date(t+1), ≥1m margin; panel construction: active_from=rcept_ym+1, forward Ret_1m).
2. lag1 staleness: no collapse (LARGE persists 0.65/1.08; BROAD within noise) → no same-month leak. Consistent with slow annual signal (Phase A lag12 STRONGER).
3. strict-PIT A/B: inflation **−20%/−22%** (current SR LOWER than strict) → clean; current timing is conservative, not inflated.
4. IC(score=−z1, fwd_excess) mean +0.0155, NW-t +2.80 → PIT-normal direction (clarity predicts higher excess; matches Phase A magnitude).

## E. Escalation check (Q-Lead auto-triggers)
HIGH severity ≥5? **No** (0 — verdict is honest sub-threshold, no PIT violation, no hard-gate breach attempt). AX axiom hard FAIL ≥3? **No**. PIT C1 (lockbox/lookahead) violation? **No** (4/4 clean). → **No escalation required.** Routine screen-tier disposition.

## F. AX-008 Verification Triangulation
self-adversarial (this note) = 1 of 3 sources. Forge N/A (screen-tier diagnostic, not forge dossier). Architect N/A. This is an alpha-stage screen diagnostic (metric_type=weighted_screen, tier=screen_diagnostic) — not a capital-graduation claim, so the full 2/3 triangulation gate (which governs capital admission) is not the operative gate here; PIT 4-guard + contract-primitive measurement are the integrity anchors.
