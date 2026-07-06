# Self-Adversarial Challenge — WT-D20260706_012 (Alpha Agent, v8.2 Opus 4.8 native)

Finalize-time adversarial self-review of the small-cap-dedicated alpha package.
Classification: ACCEPT (spec change) / PARTIAL (partial + supplement) / REBUTTAL (evidence-backed defense).
Per Charter §8 No Silent Override + AX-008 (self-adversarial = 1 of 3 verification sources).

The verdict here is NEGATIVE, so most challenges probe whether I under-called a real signal
(false negative) rather than over-called (false positive). That is the honest risk direction for a
falsification.

---

## Concern 1 (HIGH) — "Is this just a size-beta artifact? Is any within-tier alpha genuine, or just the small-cap risk premium?"
**Devil's advocate**: Excluding mega-caps and buying smaller names could just be loading the SMB risk
premium (known premium, not alpha). If so the whole exercise measures beta, not skill.

**Classification: REBUTTAL (with a twist that STRENGTHENS the negative verdict).**
- Measured: excluding mega top-K makes the portfolio smaller (avg holding mcap 1.1e13 → 2.1e12) but
  performance gets MONOTONICALLY WORSE (active PORT_t 1.32 → 0.88 → 0.75; SR 0.96 → 0.87 → 0.83;
  calmar 0.50 → 0.45). So the size tilt is NOT paying — neither as alpha NOR as a size risk premium —
  in this sample/regime. The small-cap risk premium is absent/negative here (consistent with the
  2022+ mega-semi regime where small-caps underperformed).
- Within-tier genuine-alpha test: LS quintile spread within the mid/small tier is weak (comp_all t=1.54,
  comp_alive t=-0.17). Only V02_EP shows a real within-tier LS (t=2.51, driven by pre-2022). So there
  IS a genuine within-tier value effect, but it is (a) small, (b) pre-2022-concentrated, (c) does not
  survive into a long-only top-25 net-of-cost portfolio.
- Verdict: the negative is NOT a size-beta confound masking real alpha; it is a real absence of
  deployable within-tier alpha. Rebuttal upholds the NEGATIVE verdict.

## Concern 2 (HIGH) — "The thesis premise (small-tier LS t≈3.02, insider +330bps t≈5.19) was strong. Did I test the WRONG signal and thereby produce a false negative?"
**Devil's advocate**: The original probe's "score_eff mid-tier LS t≈3.02" may be a specific efficiency
signal I did not reproduce. My 9-factor DB composite is not that signal. Maybe the thesis is right and I
tested a strawman.

**Classification: PARTIAL (accept the caveat, document, but verdict stands).**
- True: I did not have "score_eff" or the insider signal as a full-history factor. Insider is explicitly
  data-limited (2024-26) and the WT itself said keep it a NOTE, not the base. I used a robust multi-axis
  DB composite as instructed ("build a robust small-cap composite from full-history signals").
- However, the DECISIVE finding is structural and signal-agnostic: even my STRONGEST within-tier signal
  by rank-IC (V02_EP full-t=6.78, D01_IdioVol t=4.22) FAILS to translate into a long-only top-25 that
  beats cap-w BM. This is the documented KR IC→PORT_t transition wall
  ([[project-dart-insider-exec-nonreturn-frontier]], [[project-uncertainty-aware-selection-transition-wall]]).
  D01_IdioVol is the clearest example: rank-IC t=+4.22 but LS quintile spread t=−0.86 (negative). A
  strong rank correlation whose realized long-side spread is zero/negative.
- Supplement recorded: the "score_eff / insider" specific signals were NOT tested here; if a future WT
  builds them as full-history factors they deserve their own dedicated measurement. But the transition-
  wall mechanism makes a positive deployment outcome low-EV a priori.
- Verdict: PARTIAL — caveat accepted and logged; the negative deployment verdict is robust to signal
  choice because the failure is at the long-only-top-25 translation layer, not the signal layer.

## Concern 3 (HIGH) — "Is the oos_retention failure a fatal flaw or a manageable regime headwind?"
**Devil's advocate**: oos_retention is deeply negative (−0.54 to −0.76) BUT the WT pre-endorsed that the
2024-26 mega-semi regime is a headwind manageable by a later regime overlay. Maybe I am condemning a
strategy that a regime overlay would rescue.

**Classification: REBUTTAL.**
- The regime headwind is real and I split it: active-t pre-2022 = +3.08 to +3.55, post-2022 = −1.57 to
  −1.93. The full-period signal is entirely a pre-2022 phenomenon that flips sign post-2022.
- But the KEY comparison is that the small-dedicated variants are WORSE than the full-universe baseline
  in BOTH sub-periods (pre-2022: 3.08/3.21 < 3.55; post-2022: −1.93/−1.80 < −1.57). A regime overlay
  timing the mega-semi regime would help the full-universe book MORE than the small-dedicated one, so
  the overlay argument does not rescue the SMALL-DEDICATED thesis specifically — it argues for the
  full-universe (or a regime timer), not for mega exclusion.
- Also: oos_retention < 0.5 is an unconditional FAIL under measurement-graduation §3 regardless of
  supporting evidence. The negatives here are far below 0.5.
- Verdict: REBUTTAL — headwind acknowledged and quantified, but it argues AGAINST the mega-exclusion
  design, not for it.

## Concern 4 (MEDIUM) — "The 'alive' factor selection used full-sample IC (look-ahead in selection)."
**Devil's advocate**: I ranked factors 'alive' using full-2009-2026 IC, which peeks at the whole sample.

**Classification: ACCEPT (already mitigated in primary spec).**
- I deliberately made the PRIMARY composite the ALL-9 EW aligned set (no IC selection at all), precisely
  to avoid this. The 'alive' subset is reported as a diagnostic only, and when I DID build the alive-only
  composite it was WORSE (PORT_t −0.49, MDD −45%), so the selection bias, if anything, would have
  flattered a result that still failed. No spec change needed beyond the labeling already in place.

## Concern 5 (MEDIUM) — "PIT cleanliness of the panel and direction alignment."
**Devil's advocate**: mcap tier, ADV liquidity, and factor direction could leak future info.
**Classification: REBUTTAL.**
- mcap/membership/ADV taken at signal month-end (t), return realized in month t+1 (fwd_eom keying).
- Factor direction via connector align_factor_direction (Usable_Date ≤ sig_date, 36m expanding burn-in).
- Lag-stress: lag2 PORT_t (0.27) < lag1 (0.75) — decays with extra gap = correct direction, no
  look-ahead. PASS.

## Concern 6 (LOW) — "Capacity/liquidity mirage in small-cap top-25."
**Classification: REBUTTAL.** Holdings avg mcap 2.1e12 (excl top-30) with median 9.3e11 KRW and hard
adv20≥2e8 filter. These are real KOSPI200/KOSDAQ150 mid-caps, not microcaps. No capacity mirage; but this
also means the "small" tier here is genuinely liquid mid-cap, not the deep small-cap where the thesis
imagined the alpha lives (index membership caps how small we can go — a structural constraint of the
K200∪KQ150 mandate, correctly respected).

---

## Self-rationalization auto-check
Scanned my own reasoning for banned phrases ("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일"): none used
to wave away a violation. All claims are backed by measured numbers (canonical_screen real computation).

## Q-Lead escalation triggers
- HIGH severity concerns: 3 (all REBUTTAL/PARTIAL, none an unaddressed violation).
- No PIT C1 (lockbox/lookahead) violation. No AX axiom hard FAIL.
- Escalation trigger NOT met. Standard finalize as NEGATIVE / no-escalate.

## Net resolution
Verdict UPHELD: deployment-level thesis FALSIFIED (mega exclusion monotonically worse; mega tier not
signal-dead; small-tier alpha does not translate to long-only top-25). Genuine within-tier V02_EP value
signal is screen-tier / DPL-feature only. Do NOT escalate to full QEPM.
