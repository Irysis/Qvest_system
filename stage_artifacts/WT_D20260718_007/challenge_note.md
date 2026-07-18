# Self-Adversarial Challenge — WT-D20260718_007 (Opus 4.8 native adversarial, v8.2)

**Object under attack**: unsupervised autoencoder (LSTM seq-AE + point-AE) regime detector as a book-timing overlay, detector-swap vs incumbent M4 BOCPD. Verdict claimed: **VALIDATED_MIXED / conditional positive** (root-cause solved + calmar/MDD edge, paired-return insignificant → route to risk-research).

AX-008: this self-adversarial pass is 1 of 3 verification sources (Forge / Self-Adversarial / Architect; 2/3 PASS). Forge not run (screening-stage kill-adjacent; forge only for a positive to graduate). Production-parity EXACT substitutes as an independent measurement anchor.

Devil's-advocate concerns raised (≥3 mandated; 6 raised), each classified ACCEPT / PARTIAL / REBUTTAL with evidence, plus self-rationalization auto-detection.

---

## C1 — "The calmar/MDD 'win' is not statistically real (paired-return insignificant)" — **ACCEPT (partial)**
The cleanest test of book improvement — paired monthly net return, NW lag-3 — is **negative and insignificant in every subperiod** (−1.49 full / −1.08 ex-2008 / −1.14 post-2015). A skeptic is right that the calmar 2.196 vs 2.069 is a point estimate not backed by a significant paired test.
- **Disposition**: ACCEPTED into the verdict. I explicitly do **not** claim a book-return win. The verdict is downgraded from "positive" to **MIXED / conditional positive**, and the alpha_package/validation state prominently that the improvement is confined to tail-risk (calmar/MDD) + crisis targeting, not return, and is **not graduation-ready standalone**. This is the honest kill-adjacent finding — surfaced, not buried.
- **Why not a full kill?** The pre-registered kill-①'s primary condition is "no calmar/MDD improvement"; that condition is false (calmar/MDD do improve, persistently). And a de-risk overlay's *objective* is MDD/calmar, not monthly mean return. So the correct classification is MIXED, and the honest route is risk-research (as the WT's own output section anticipates), not a clean-negative kill.

## C2 — "The MDD edge is just the fire-rate mismatch (AE de-risks more, not times better)" — **PARTIAL → REBUTTAL**
AE fires 0.172 vs target M4 0.126; avg_exp 0.775 vs 0.786 (detector-only 0.948 vs 0.974). More de-risking mechanically lowers MDD.
- **Rebuttal evidence (3-axis)**: (a) **detector-only** AE has better calmar (1.442 vs M4 1.322) at only marginally lower exposure — calmar-per-unit-de-risk is higher, not just more de-risk. (b) **post-2008 AE_SR EXCEEDS M4_SR** (1.878 vs 1.868; 1.683 vs 1.670) — indiscriminate over-de-risking would *lower* SR (you sit out up-months), so higher SR proves the extra firing lands in genuinely bad months. (c) **crisis-firing corr 2x M4 + 2008 9/9 vs 6/9** — the surplus firing is concentrated in real crashes (academic: Malhotra 2016 LSTM-AD — recon error spikes on regime breaks). 
- **Residual concession**: I did **not** re-tighten τ to exactly 0.126 (time budget) → the budget confound is present but bounded; flagged as challenge_flag + risk-research NP2. Honest limitation, not swept.
- **Literature anchor**: Sakurada-Yairi 2014, Malhotra et al 2016 (LSTM encoder-decoder anomaly detection) — recon error as OOD/regime-break signal is the established mechanism.

## C3 — "PIT leakage — the AE learned future 'normal'" — **REBUTTAL**
Three independent PIT tests all pass: assert_overlay_pit 0/221 (window ends strictly < holding-month start), strict-PIT loose-vs-strict inflation +0.2%/−0.7% (<<5%), lag1 no collapse (1.809→1.802), python self-check 0/221 last_feat_date≥decision_date, production parity EXACT. Standardization μ/σ frozen on training only; training windows end before year boundary; τ on IS errors. **Decisive counter-evidence**: OOS fire-rate DRIFTED UP (0.126→0.172) — a leaky "future-normal" model would fit OOS *too well* (fire-rate would stay at/below target); the upward drift is genuine extrapolation. No self-rationalization used.

## C4 — "The whole result is the 2008 episode (first refit, thin 2000-07 training)" — **REBUTTAL with data**
Subperiod excl-2008 (2010+): calmar edge **+0.161** (2.390 vs 2.229) — *larger* than full-sample +0.127. MDD is **identical across all splits** (−0.187 M4 / −0.170 AE) → the book's max-DD episode is **post-2015** (COVID/2022-era), not 2008, and AE reduces it everywhere. The edge strengthens without 2008. Not an artifact.

## C5 — "3 arms + ensemble = cherry-picking AEseq (multiple-testing / DSR)" — **PARTIAL (ACCEPT disclosure)**
I ran seq-AE, point-AE, ensemble. AEseq (calmar 2.196) selected. **Full disclosure**: AEpt does **NOT** beat M4 on calmar (1.976 < 2.069) despite the best crisis-corr (0.148) — reported, not hidden. This is a hypothesis-driven **chain** of 3 architecturally-motivated variants (measurement-graduation §3: selection_type=chain → DSR advisory, not hard; n_variants=3 recorded for audit). If it graduates, risk-research/forge applies proper multiple-testing. Selection criterion (calmar) is the overlay's true objective, disclosed.

## C6 — "AE only catches sharp crashes; useless for slow bears (2011/2018/2022)" — **ACCEPT (scoped, INV-7)**
True: reconstruction-error is a **sharp-OOD-crash specialist** — 2011 0/3, 2018 0/3, 2022 0/10 (2022 was a slow grind, not a daily-dynamics anomaly). This is a genuine coverage gap, scoped honestly. It is *also* the basis for the **ensemble** recommendation: AE (sharp OOD: 2008 9/9) + M4 (broader firing) are **complementary** detectors, not substitutes — which is precisely why the standalone swap is only MIXED and the ensemble/complement route is the live NP. Next-probe NP3 (slow-regime drawdown-duration signal) addresses the gap.

---

## Self-rationalization auto-detection (mandated)
Scanned my own reasoning for banned crutch phrases ("미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일"). **None used as a pass-justification.** Where an effect is small (AX-001 v2 cushion −0.0275 vs −0.0284; SR delta ~0.0001), it is reported as *small and correct-signed*, not waved through as "negligible / fine". The paired-return insignificance is treated as a real limitation (C1 ACCEPT), not minimized.

## Q-Lead auto-escalate triggers — **NONE FIRED**
No HIGH-severity ≥5, no AX axiom hard-FAIL, no PIT C1 (lockbox/lookahead) violation (PIT clean ×3+parity). No escalation required. Standard risk-research handoff.

## Net effect of this challenge on the deliverable
- Verdict held at MIXED (not upgraded to positive [C1], not downgraded to clean-kill [C2/C3/C4 rebut the negatives]).
- Added: fire-rate-mismatch caveat + τ-rematch NP (C2), prominent paired-insignificance statement (C1), 2008-robustness table (C4), AEpt-loses disclosure (C5), sharp-vs-slow scope + ensemble rationale (C6).
- All landed in alpha_package.challenge_flags + alpha_validation + this note (no silent override — Charter §8).
