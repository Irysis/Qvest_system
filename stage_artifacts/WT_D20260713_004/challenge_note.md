# R20 Self-Adversarial Challenge (WT-D20260713_004, FQ-033)

Opus 4.8 native adversarial pass, finalize-gate. Verdict under challenge: **config-scoped negative + frontier marker** (Benford index-level exclusion overlay = no distinguishable tail benefit vs random; audit-quality gradient FALSIFIED, Spearman -0.4). AX-008 self-adversarial source (2/3 with Forge/Architect n/a for a diagnostic — this is a screening diagnostic, not a graduation candidate).

## Concern 1 (prereg-mandated) — Renormalization inflates cap-concentration as a side effect
**Claim**: removing the worst decile and renormalizing cap weights concentrates the index into fewer (larger) names, which itself changes tail behavior — so any "improvement" could be a concentration artifact, not filter information.
**Classification: PARTIAL — and it CUTS TOWARD the null, not against it.**
- The random control is renormalized IDENTICALLY (same k removed, same cap-renormalization). So concentration side-effects are held constant between exfl and random. The exfl-vs-random contrast is the reported authority precisely to net this out.
- Evidence it matters: the ONE large cap-w number (K200 MDD +0.0214) collapses to +0.0018 under EW (no cap-concentration) — confirming it was a cap-concentration/single-name path artifact, exactly this concern. EW-basis shows ~0 everywhere. So the concern is real and its resolution REINFORCES the null. No rebuttal needed; the design already controls it and the EW cross-check confirms.

## Concern 2 (prereg-mandated) — Coverage-decresult missingness biases the small-cap effect direction
**Claim**: the post-2016 coverage collapse (KOSDAQ-all ~20-25%) means the scored subset is the better-disclosing firms; excluding low-coverage years could over- or under-state the small-cap effect.
**Classification: ACCEPT (drove a prereg design decision).**
- Handled by restricting PRIMARY to 2010-2015 where ALL universes have >=98% coverage — no missingness confound in the primary test. Post-2016 is honestly excluded, not imputed (mandate: no estimation substitution).
- Residual within-primary missingness is <2% per universe-year => negligible. The gradient falsification rests on the clean 2010-2015 window, so this concern does not threaten the primary verdict.
- Honest cost: this restricts the least-audited arm (KOSDAQ-all) to 2010-2015 only, where its tail-event content is thinner. Logged as next_probe #2 (coverage repair to re-open post-2016 small-cap arm).

## Concern 3 (prereg-mandated) — Survivorship (C6) inflates or deflates the tail
**Claim**: excluded delisted names bias the tail estimate.
**Classification: ACCEPT — direction is conservative for a positive claim.**
- Returns are survivorship-free (RAWDATA includes delisted history). Only the EXCHANGE LABEL is missing for 488 delisted-pre-2026 small codes (8.5% stock-days, median Size ~half), dropped from KOSPI-all/KOSDAQ-all.
- These are disproportionately manipulation/fraud collapses — the exact left-tail the Benford filter is supposed to catch. Excluding them UNDERSTATES both the base-index tail AND the filter's potential benefit => bias AGAINST finding a filter effect. So a stronger (survivorship-complete) sample could only help the filter; the null we observe is therefore not survivorship-manufactured. Cap-weighting further shrinks these tiny names' index weight.

## Concern 4 (self-generated) — The one favorable number could be cherry-picked framing
**Claim**: K200 cap-w MDD improvement +0.0214 is the single biggest effect; a motivated reader could headline it as "filter protects the flagship index."
**Classification: REBUTTAL (with quantitative refutation, 3 axes).**
- (i) It CONTRADICTS the prereg mechanism (K200 = most-audited => predicted effect ~0, not the max). A genuine forensic filter would show K200 ~0; getting the largest number in the most-audited universe is a noise signature, not signal.
- (ii) It is incoherent across tail metrics (2/4; cvar20 and worst5 WORSE than random) — a real tail-protection effect moves MDD/CVaR/worst5/dd together.
- (iii) Its bootstrap CI [exfl-rand MDD] = [-0.045, +0.017] straddles 0 (median -0.025 but not separated from 0), and it vanishes under EW (+0.0018). Three independent axes => artifact, not effect. No headline license.

## Concern 5 (self-generated) — Power: clean window excludes the crashes that matter
**Claim**: 2010-2015 excludes 2008 GFC and 2020 COVID — the biggest tail events — so the test may simply lack power to detect tail protection.
**Classification: PARTIAL (accepted as a genuine limitation, bounded).**
- True for ABSOLUTE tail-protection magnitude — logged as power_caveat + next_probe #3.
- BUT the DISCRIMINATING prediction is the GRADIENT SHAPE (monotonic across audit quality), which is far less dependent on which specific crash is sampled. The gradient fails cleanly (Spearman -0.4, EW ~0) and the least-audited universe is flattest — a shape result the window restriction does not manufacture. The verdict language is "config-scoped negative + frontier" (NOT structural-limit / NOT settled), preserving AX-000: the crash-window and coverage-repair probes are the open frontier.

## Self-rationalization auto-scan
Scanned draft for banned crutches ("미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 근사"). One legitimate use: "residual within-primary missingness <2% => negligible" — this is a measured quantity (<2%), an explicit labeled bound, not a hand-wave. No unsupported rationalization retained.

## Escalation check
HIGH-severity count: 0 graduation-blocking violations (this is a screening diagnostic, no capital claim, no HARD-gate PASS asserted). No AX axiom hard FAIL. No PIT C1 (lockbox/lookahead) violation — signal is Factor_Date+1, weights month-start, return month-forward (C5-safe). No Q-Lead auto-escalate trigger fired.
