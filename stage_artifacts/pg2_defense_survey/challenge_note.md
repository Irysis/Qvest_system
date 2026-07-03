# Self-Adversarial Challenge Note — PG2 Defense Factor DB Survey (2026-07-03)

Diagnostic survey (no graduation declared). AX-008 self-adversarial per v8.2.

## Concern A — badnormal_ic ratio is noise (methodology weakness)
- **Raised**: step2's `badnormal_ic` = mean(down IC)/mean(up IC) is dominated by the up-IC denominator crossing zero. Q07 (known defense engine) scored -3.43; M08 (known NON-defensive) scored +2.66 — inverted vs ground truth. The "112 TRUE_DEFENSE / 166" headline from step2 is a false positive from a loose, noisy verdict.
- **Classification: ACCEPT.** step2 verdict superseded by step2b confound-corrected measures. I do NOT report the 112 number as a finding. Authoritative discriminators = beta level, beta_asymmetry, excess_down_active vs EW-universe, crisis_ic, and canonical PORT_t.

## Concern B — canonical PORT_t tested on only 5/166 (coverage gap)
- **Raised**: An untested candidate might have positive standalone PORT_t.
- **Classification: PARTIAL.** Tested set = strongest-by-diagnostic (D20/D11/D45/D50 + Q07/M08/Q25). All pure-defense = negative PORT_t (D20 -1.26 ... D45 -1.42). Untested factors rank LOWER on the same crisis_ic/excess_down_active and share the identical long-only structure (β<1, mean_active_net<0). I therefore state the conclusion as "strongest-by-diagnostic defensives all fail PORT_t; others untested but structurally same," NOT "all 166 negative." Stated in meta caveats.

## Concern C — panel universe is defensively tilted (β<1 confound)
- **Raised**: Panel = STR_1715 tracked ~256 names (quality/defense-tilted), so absolute β<1 and down_active>0 are near-universal universe artifacts, not per-factor defense.
- **Classification: ACCEPT (corrected).** EW-universe baseline β 0.735, down_active +0.0068 measured explicitly; all per-factor metrics read RELATIVE to it (excess_down_active, def_score z-scores within-panel). Verdict unaffected — relative ranking and canonical PORT_t are internally consistent within the panel. Stated as caveat.

## Concern D — orthogonality basis (gross vs active)
- **Raised**: 06-18 lesson — gross correlation overstates redundancy vs active.
- **Classification: REBUTTAL.** cor_Q07 0.85-0.90 was computed on ACTIVE (long-leg minus forward-BM) monthly returns, the correct basis. Redundancy with Q07 is real, not a gross artifact. Top defensives are the SAME dimension as the existing Q07 sleeve.

## Self-rationalization auto-check
No "미미/관행적/보수적이면 OK/대부분 동일" used to wave away a violation. PORT_t negatives reported as-is; no forcing. No PIT C1/lookahead trigger (forward alignment at signal-month ym for both stock and BM; benchmark = corrected IKS200; no realized_ym offset; single-thread; taskkill before R).

## Escalation
No Q-Lead escalate trigger fired (no HARD violation, no AX axiom FAIL, no PIT C1). This is a survey; verdict = "no standalone defense upgrade available in DB," consistent with prior 06-30 "defense reweight settled."
