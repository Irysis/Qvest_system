# Self-Adversarial Challenge — WT-D20260705_008 (AND-gate conjunctive intersection)

Agent: Alpha Research (Opus 4.8 native adversarial). Codex round removed (v8.2). AX-008 3-source: this self-adversarial is 1 of {Forge, self-adversarial, Architect}.

Verdict entering challenge: **CLEAN_NEGATIVE** (AND-gate does not restore OOS long-only realized active; hypothesis falsified).

Measurement basis: all PORT_t = `canonical_screen_bt()` NW lag-3 (metric_type=canonical_screen). Study window 2005-01..2026-07 (258 net-active months), K200∪KQ150, liq≥2e8, 15bps, top-25 EW long-only. IS/OOS cut = 2017-01-01. tau tuned IS-only (selection_type=chain).

## Concerns self-raised (≥3 required) + classification

### C1 [ACCEPT] — "The intersection is too small to form a standalone top-25; the top-25 AND-gate was mostly relaxation-filled (non-gated names), so Phase 2 did not truly test the intersection."
- Valid. Median gated names @tau*=0.60 = 6 (min 0, max 18) vs top-25 requirement. Phase 2's canonical top-25 therefore diluted the gate with progressive-relaxation fill.
- **Handling**: added Phase 3 (a) **pure-intersection gate-only EW** (no top-25 fill, variable N). Result: every tau IS-positive (t 2.6–3.3) → OOS-negative (t −1.7 to −2.6), full ~0. The pure intersection *itself* has no OOS edge. Concern resolved by direct test; conclusion unchanged (strengthened).

### C2 [ACCEPT] — "IS-only selection integrity: was OOS ever consulted when picking tau?"
- Audit: tau* chosen by `which.max(IS_PORT_t)` over IS(<2017) only (Phase 2 IS_SWEEP). OOS computed once afterward at tau*. Phase 4-D confirms IS>0/OOS<0 holds across 3 cut dates → not a cut-date fish. tau sweep is nearly flat across IS (all ~3.4) because relaxation makes tau weakly binding — so even the IS selection has almost no degrees of freedom to overfit. Integrity holds.

### C3 [ACCEPT→refutes hypothesis] — "Is AND-gate success (IS) actually confound-cancellation, or merely sample-size reduction / random balanced selection?"
- **Placebo (Phase 4-B, 20 draws of random same-size balanced pool)**: real AND OOS PORT_t −2.274 is *inside* placebo dist (mean −1.555, sd 0.871) — statistically indistinguishable from random balanced selection OOS. Real full +0.094 is ~0.7sd above placebo mean (weak, IS-side noise).
- Confound-cancellation IS mechanically achieved (Phase 3-c: AND-gate cross-axis percentile dispersion 0.108 vs single-axis top-quintile ~0.30; mean_minpct 0.66 vs 0.26) — the gate genuinely selects balanced, confound-diversified names. **But the balance does not translate to OOS active.** This falsifies the *causal* claim of the hypothesis: confound is not the binding constraint.

### C4 [ACCEPT] — "Does the intersection collapse into a small-cap / low-liquidity tilt (spurious edge)?"
- AND-gate median 20d adv 3.05e9 vs universe median 6.65e9 (ratio 0.46). A mild small-cap tilt, but all names ≥ 2e8 floor by construction (liq filter applied pre-gate). Not a micro-cap collapse (contrast KNS/allliq micro-cap artifacts). The tilt does not rescue OOS (still negative), so it is not a hidden positive driver either.

### C5 [REBUTTAL-style, but resolved to ACCEPT-negative] — "Maybe the decile non-monotone wall is real and the AND-gate just needs a better axis set."
- Decile profiles (Phase 3-b) show the premise itself is partly mis-stated: **full-period** additive & softAND deciles are already fairly monotone (Spearman 0.82, D10−D1 ≈ 70–81 bps). The non-monotone D10≈D1 wall is **not** the full-period binding constraint. **OOS(≥2017)** is where it breaks: additive monotonicity 0.27, softAND 0.03 (flat), and **every decile D1..D10 is deeply negative active** (−56 to −139 bps/mo). Axis-swap (Q07+BAB, Phase 4-A) reproduces IS+/OOS− identically. So "better axes" is not the fix — the wall is regime decay of the signal, not confound in the top decile.

## Self-rationalization auto-detection (grep: 미미/관행/실무/보수적/대부분 동일)
None used. No metric was reported as "approximately" passing; all HARD gates reported with exact measured values. No leniency applied.

## Escalation triggers (Q-Lead)
- HIGH severity ≥5? No (this is a negative result; no capital claim).
- AX axiom hard FAIL ≥3? No.
- PIT C1 (lockbox/lookahead)? No — asof/forward-shift standard; IS-only tuning audited; C15 via load_month_factors.
- No escalation. Report CLEAN_NEGATIVE with mechanism to Q-Lead.

## Net effect on package
No spec change to the verdict. Phase 3-4 (pure intersection, placebo, axis-swap, split-sensitivity) were **added in response to C1/C2/C3** and all confirm CLEAN_NEGATIVE. Mechanism recorded for next-frontier input: **the KR post-2017 IC→realized-active wall is a signal-decay wall, not a selection/confound wall — conjunctive selection cannot recover an OOS edge that no longer exists in any decile.**
