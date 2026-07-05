# Self-Adversarial Challenge — WT-P20260706_002 Forge (mega-cap anchor)

**Mode**: Opus 4.8 native self-adversarial (v8.2, Codex Round 제거). AX-008 source 2 of 2.
**Target**: `forge_package.json` verdict = milestone=FALSE, capital_grade=FALSE, book-marginal FAIL.
**Mandate**: interrogate my own authoritative measurement on 5 axes; raise ≥3 concrete weaknesses. Confirm or overturn the FAIL verdict.

---

## Axis 1 — Concentration risk (40% mega-cap)

**Challenge**: Is the −8% simultaneous-anchor-crash tail materially understated? HHI 0.10 / effN 10 halves EW-20 diversification. And is the in-sample MDD 0.380 hiding regime-specific tail because 2004-2026 was mostly a mega-cap-favorable sample (2020-2026 Samsung/Hynix leadership)?

**Finding**: The stress figure −0.08 is a *single-month* both-anchors −20% shock; a sustained mega-cap bear (e.g. 2018 semi downcycle, or a KR-specific Samsung governance shock) would compound beyond one month. The MDD 0.380 is comparable to C0 baseline 0.392 — so concentration does NOT blow out in-sample MDD, but that is *because* the sample contains the mega-cap up-regime that motivated the anchor in the first place. **This is circular**: the anchor looks safe in-sample precisely because in-sample mega-caps led. Out-of-regime (mega-cap reversal) the −8%/month tail is undiversifiable and asymmetric. **WEAKNESS CONFIRMED — but it does not change the verdict** (verdict already FAIL on book-marginal, independent of concentration). Concentration is a *secondary* reason to be cautious, not the binding one.

## Axis 2 — Vintage / measurement basis

**Challenge**: The book-marginal FAIL rests on comparing anchored_overlay_IR 0.928 vs incumbent 1.416. But my own overlay reconstruction of the incumbent (base_recon+overlay) reaches only IR 0.839 — 0.58 BELOW the recorded 1.416. If my overlay path systematically under-measures IR by ~0.58, then the "true" anchored IR might be ~0.928+0.58 ≈ 1.51 > 1.416, which would FLIP the verdict to PASS. Is the FAIL an artifact of my imperfect overlay reconstruction?

**Finding**: This is the single most important challenge to the verdict, and I must be scrupulously honest. Two facts:
(a) My overlay-scalar check cor(ret_orig×ovl, ret_L5_V5)=0.962 and align cor 0.821 — the reconstruction is *good but not exact*. The 0.839 vs 1.416 gap is real reconstruction error (different alpha panel base, benchmark alignment offset, no Layer4-removal exact replication).
(b) HOWEVER — the apples-to-apples comparison is INTERNALLY consistent: anchored (0.928) vs base_recon (0.839) are measured on the *identical* overlay basis, benchmark, and alignment. That marginal = +0.089, and its paired NW-t = **−1.522** (negative! the sign of the t-stat and the raw ΔIR disagree because the improvement is not robust across the autocorrelation structure). So even granting my reconstruction is low-biased, the *within-basis marginal* is (i) small (+0.089) and (ii) statistically insignificant/negative-t. The naive "add 0.58 back" argument is invalid because it assumes the bias is identical for anchored and base — but the anchor changes the return structure, so the bias need not be constant. **WEAKNESS PARTIALLY VALID**: the −0.488 headline overstates the case (basis mismatch); the DEFENSIBLE statement is the within-basis one: ΔIR +0.089, paired NW-t −1.522 → **not a significant improvement**. Verdict HOLDS (fail on significance) but I have SOFTENED the package language to lead with the within-basis reading. → package `measurement_caveat` already flags both readings.

## Axis 3 — Overlay interaction

**Challenge**: The anchor was discovered/measured STANDALONE (vs cap-w bench, PORT_t 4.76). But deployment applies m4×R05 overlay (cash-scaling regime timing). Does the overlay *destroy* the anchor's edge? The standalone anchor PORT_t 4.535 → overlay-context PORT_t 4.836 (goes UP), but IR only 0.928. Is there an interaction where the overlay's cash-scaling clips exactly the mega-cap up-months the anchor relies on?

**Finding**: Overlay-context PORT_t 4.836 > standalone 4.535 — the overlay does NOT destroy the alpha t-stat; if anything the cash-scaling in bad regimes improves the risk-adjusted active t. But IR stays 0.928 (< incumbent 1.416) because the overlay applies EQUALLY to incumbent and candidate — it's a common multiplier, so it cannot create marginal advantage for the anchor. The anchor's contribution is orthogonal-ish to the overlay (paired-t −1.522 confirms near-zero marginal). **WEAKNESS EXPLORED, verdict HOLDS**: overlay does not rescue the candidate; the anchor's benefit (tracking cap-w bench) is largely redundant with what STR_1715×m4×R05 already delivers (incumbent IR 1.416).

## Axis 4 — EW vs LinearTilt (fill robustness)

**Challenge**: Discovery used EW-fill (A). I claim B (LinearTilt) is "stronger" (oos 0.894 > 0.550). But is B's higher oos a genuine production-fidelity signal or just a different overfit? And does B's LinearTilt concentrate the non-anchor sleeve enough that we're effectively betting on <18 names (defeating diversification)?

**Finding**: B PORT_t 4.535 < A 4.761 (slightly lower t), but B oos 0.894 >> A 0.550. The oos gap is large and in B's favor — LinearTilt's turnover penalty (φ3.0) produces more stable holdings → better OOS retention. This is *mechanistically sensible*, not overfit (it's the production weighting, not a tuned choice). But it does NOT change deployment: BOTH A and B feed the same overlay book-marginal FAIL. LinearTilt fill-concentration: λ1.5 is mild, sleeve stays diversified (not a <18-name collapse). **WEAKNESS ADDRESSED**: B is production-faithful and legitimately stronger standalone, but the binding gate (book-marginal) is fill-invariant. Verdict HOLDS.

## Axis 5 — PIT / lag1

**Challenge**: The anchor uses SAME-month size cross-section to pick top-2. Is "top-2 by size is PIT-safe because slow-moving" a hand-wave? A market-cap ranking on rebalance date D uses price at D — if that's same-day close, it's a C2 same-day circular concern for the anchor selection. And score_eff is "already PIT-patched at source" — did I verify that, or trust it?

**Finding**: (a) Top-2 by size: Samsung + SK Hynix are the #1/#2 KR mega-caps continuously for the entire sample — the top-2 identity does NOT change month-to-month with price (they are 6-14x the #3 name, per reference-kr-2025-megacap-semi-regime). So even at t vs t-1 the anchor SET is identical → no PIT leak in *selection*. The lag1 test confirms this empirically: delaying the ENTIRE alpha (score) by 1 month gives PORT_t 3.78 (graceful, no collapse) — if there were same-month leakage the lag1 would collapse. (b) score_eff PIT: I did NOT independently re-verify the production panel's PIT patching — I trusted the 05_Production source label. This is a genuine residual assumption. **WEAKNESS: score_eff PIT is trusted, not re-audited by me.** Mitigant: the lag1-graceful result (3.78) bounds the leakage — if score_eff had look-ahead, lag1 would degrade far more. Verdict on PIT: **acceptably clean** (lag1 graceful + anchor-set stability), with a flagged residual (trusted production PIT patch).

---

## Summary — 5 weaknesses raised (≥3 required: MET)

| # | Axis | Weakness | Effect on verdict |
|---|---|---|---|
| 1 | Concentration | in-sample MDD safety is circular (sample is mega-cap-favorable); −8%/mo tail undiversifiable | secondary caution, not binding |
| 2 | Vintage/basis | −0.488 headline overstates (overlay reconstruction low-biased 0.839 vs 1.416); defensible claim = within-basis +0.089 **non-significant (t −1.522)** | SOFTENED language, verdict HOLDS on significance |
| 3 | Overlay interaction | overlay is common multiplier → cannot create anchor marginal; anchor redundant with incumbent | verdict HOLDS |
| 4 | EW vs LinearTilt | B legitimately stronger standalone, but gate is fill-invariant | verdict HOLDS |
| 5 | PIT/lag1 | score_eff production PIT trusted not re-audited; anchor-set stability + lag1-graceful bound leakage | acceptably clean, flagged |

## Verdict after self-adversarial challenge

**HOLDS: milestone=FALSE, capital_grade=FALSE, book-marginal FAIL.**

The strongest challenge (Axis 2) forced me to correct the package: the honest, defensible book-marginal statement is the **within-basis marginal ΔIR +0.089 with paired NW-t −1.522 (statistically insignificant)** — NOT a clean −0.488 (which mixes measurement bases). Both readings fail the spec gate, but for the right reason: the anchor does not *significantly* improve the current incumbent book. The discovery's SIGNAL is real (reproduction exact, placebo p=0, lag1 graceful, alpha-edge +5.6), and this is genuine measured knowledge (cap-w benchmark artifact confirmed at authoritative level). But it is not capital-grade for THIS incumbent book. governor 정지 — no book_state change.
