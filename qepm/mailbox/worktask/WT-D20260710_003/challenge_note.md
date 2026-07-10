# Self-Adversarial Challenge — WT-D20260710_003 (joint-design alpha, negative discovery)

Agent: alpha-research (Opus 4.8 self-adversarial, v8.2 — no external Codex). AX-008 3-source: this = source #2 (Self-Adversarial); Forge/Architect pending. Charter §8 No Silent Override.

Context: 26-config joint sweep (H1 tier-stratified×tier-weighting + H3 regime-conditional active-share + baselines; H2/H4/H5 pre-demoted per Q-Lead). IS-only selection (2005–2018) → winner H3g_flat_thrMed → OOS(2019–2026) 1 look + DSR(sweep)+placebo+jackknife+holdout. Result: NO graduation; winner fails 3 of 4 hard discipline gates.

## Concern 1 [HIGH] — Winner selection is noise-mining; H3g ≈ baseline
The "winner" H3g (IS port_t 3.282) is statistically indistinguishable from the flat baseline (3.209) and 4 other H3 configs cluster at 3.25–3.28. The inverted-regime control H3h = **exactly 3.209** (identical to baseline) → the regime active-share mechanism is near-inert. Selecting max-IS among a tie cluster is noise selection.
- **Classification: ACCEPT.** I do NOT present H3g as a distinct discovery. Correct framing: *no joint config beats the flat baseline; the nominal winner is baseline-equivalent and fails OOS.* This ACCEPT strengthens (not weakens) the negative conclusion — there is no false-positive risk because the "winner" is admittedly baseline-noise. Recorded in alpha_validation `winner_is_baseline_equivalent=true`.

## Concern 2 [HIGH] — Is the OOS collapse just a cap-w mega-cap benchmark artifact? (memory: post-2017 decay partly artifact)
If OOS failure is only the cap-weighted KOSPI200 benchmark hugging mega-caps, the alpha might survive vs a fair EW-universe benchmark (memory: earnings alpha post2017_t 0.41→2.04 on EW basis).
- **Classification: PARTIAL (measured, not assumed).** Ran sanctioned `canonical_screen_bt(diag_dual_basis=TRUE, size_dt)`. OOS cap-w port_t −2.05 softens to EW-universe **−0.87** — so ~half the collapse is benchmark artifact, BUT it stays **negative** on the fair basis. Cap-tier decomposition: flat composite holds **92% OTHER-tier (small-cap, rank 31+)**; that small-cap alpha was strong IS (OTHER gross-ann +0.20) and genuinely decayed OOS (+0.04). Conclusion: the wall is **real signal decay concentrated in small-caps, amplified (not created) by the cap-w benchmark**. A fairer benchmark alone does not rescue it. dual_basis_captier_diag.json.

## Concern 3 [MEDIUM] — DSR 0.457 is borderline (just below 0.5); is the negative fragile to n_trials count?
DSR(sweep)=0.457 with N=26. If N were smaller (e.g., 4 baselines) the hurdle sr0 drops and DSR could clear 0.5.
- **Classification: REBUTTAL.** The negative verdict does NOT hinge on DSR. Two independent hard gates fail regardless of trial count: (a) **jackknife 3 continuous blocks = 2.28 / 2.67 / −1.88** (3rd block negative — the exact continuous-block failure the mandate warned jackknife-by-year would miss); (b) **holdout falsification = FAIL_FALSIFIED** (OOS realized Sharpe −0.49 < IS-bootstrap q05 0.23). DSR borderline-fail is corroborating, not load-bearing. Grounds: 3 gates, 3-axis (IS/OOS split + jackknife + holdout).

## Concern 4 [MEDIUM] — IS/OOS leakage via factor direction alignment (C15)?
Composite uses load_month_factors Z_Score_Aligned; direction could leak future IC.
- **Classification: REBUTTAL.** Direction alignment is expanding-window PIT-safe (connector v2.0 L-168: Usable_Date ≤ sig_date, 36m burn-in). Composite family weights are **fixed a priori** (cross_family_wtd 0.3/0.3/0.2/0.2 or EW) — no in-sample weight fitting. size_neutral/residual_ortho use per-month cross-sectional lm (same-month only). Regime signal uses trailing-6M realized returns (known at signal month t). Panel reused from WT-002 build_panel.R (PIT C1–C15 validated). No leakage vector identified.

## Concern 5 [MEDIUM] — H1d survives OOS (+1.07): is it a real escape from the cap-tier trap?
H1d_q5_15_5_twMega (mega-heavy tier weighting) is the ONLY positive-OOS config.
- **Classification: PARTIAL/REBUTTAL.** H1d "survives" by near-passivity: weak IS (0.854), full port_t only 1.37 (≪2.95), book-marginal ΔIR +0.013 (< informal 0.05 gate). Its mega-heavy cap-weighting = closet-indexing → tracks benchmark, neither wins IS nor loses OOS. This is exactly the established finding [[project-megacap-anchor-construction-discovery]]: mega-cap anchoring = tracking-error reduction, NOT return-additive alpha. Not a novel escape; it is the trap's other jaw (hold mega at bench weight = passive). Documented as "closest interaction to OOS-stable" but explicitly non-graduating.

## Self-rationalization auto-check (banned phrases)
No use of "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" to wave away a gate. Every gate measured and reported at face value. The one place I could have rationalized (Concern 2 "it's just a benchmark artifact") was instead **measured** and found only half-true → reported the genuine-decay residual. No auto-RE-VIEW triggered.

## Escalation check
HIGH severity count = 2 (< 5). AX axiom hard FAIL = 0. PIT C1 (lockbox/lookahead) violation = none. → No Q-Lead auto-escalate trigger. Negative discovery reported normally.

## Net disposition
Winner (H3g ≈ baseline) is REJECTED for graduation on evidence: DSR 0.457<0.5, jackknife 3rd-block −1.88, holdout FAIL_FALSIFIED, OOS port_t −1.63. No joint config in the swept space graduates. Honest map recorded (alpha_validation.json). This is a VALIDATED_NEGATIVE for the joint-design space (H1+H3), not a fixable overfit.
