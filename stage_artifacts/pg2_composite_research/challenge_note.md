# Self-Adversarial Challenge — PG2 Composite Re-Research (2026-07-03)

**Charter §8 No Silent Override.** Finalize 직전 산출물을 스스로 적대 검증. Opus 4.8 native adversarial (외부 Codex 없음, v8.2).

Verdict under challenge: **CORE COMPOSITE SETTLED, no book-marginal lever.** Below I raise the 5 strongest concerns against my own conclusion and classify each.

---

## Concern 1 [ACCEPT of null / REBUTTAL of a false GO] — "B_split_75 ΔIR +0.0475 is basically 0.05; you're 0.0025 short of GO. Round up?"
- **Classification: REBUTTAL (the +0.0475 is NOT a GO).**
- Rationale (self-rationalization guard: I must NOT say "close enough / practically 0.05"):
  1. **Statistical**: paired NW-t(lag3) of (split75 − base) active = **0.976 << 1.96**. The +0.0475 alpha-IR delta is within one SE. The gate is ΔIR≥0.05 *as a screen*, but a delta indistinguishable from 0 at t=0.98 does not qualify regardless of the point value.
  2. **Overlay reversal**: proxy book-marginal (variant alpha delta passed through incumbent M4/R05/cash gate) = **−0.0175**. The standalone +0.0475 is a bare-alpha number; the deployment target is the *book*, and the tilt goes negative there. §4 admission is explicitly book-marginal, not standalone.
  3. **Plateau**: fine sweep shows w∈[0.70,0.80] all IR≈0.76 — no sharp optimum. Picking 0.75 is picking a point on a flat ridge; the "gain" over 0.65 is a soft tilt, not a discovered edge.
- Evidence: `battery_gates.csv` (paired_NWt 0.976), `book_marginal_alpha_ir.csv` (−0.0175), `adversarial_split_sweep.csv` (plateau).

## Concern 2 [ACCEPT] — "The +0.10 IR gain in 2015-2026 is your strongest recent-alpha signal — you're burying a live lever by calling it noise."
- **Classification: ACCEPT (it is noise, honest report).**
- Rationale: base IR in 2015-2026 = **0.091** (near zero — the earnings decay). split75 = 0.191. Both are dwarfed by Sharpe SE ±0.6 on a 135-month window (per measurement-graduation holdout regs, 18-24m SE ±0.7-0.8; even 135m active-IR SE is ~0.15-0.2, and the recent sub-block that drives it is far shorter). A +0.10 IR delta sitting on a ~0 base, in the exact cohort (2015+) where §6 memory documents systematic earnings decay, is a textbook noise-level artifact. Recent 2021+ PORT_t for split75 = 0.35 (near-zero), and for ALL variants ≤ 0.54. This is cohort-wide decay-pattern (§3), not a strategy-specific edge. I keep the finding visible in meta (subperiod_IR) but do not promote it.

## Concern 3 [PARTIAL] — "You didn't run axis D (nonlinear). You can't declare 'settled' with an unexecuted axis — that's a premature-limit call (AX-000)."
- **Classification: PARTIAL (deferred with executed-adjacent evidence, not blind omission).**
- Rationale: AX-000 forbids declaring dead-end after 3-4 failures. I ran **12 linear trials across 5 axes**, not 3-4. The nonlinear deferral is reasoned, not fatigue:
  - Phase-0 (373-factor HGB, memory `project-discovery-substrate-phase0`) already showed nonlinear recombination of THIS factor family deflates to screen-tier under seed/book-marginal — a directly relevant precedent.
  - The binding failure is **recent cohort-wide decay** (data property), which no model form can synthesize into alpha absent a new recent-alpha input factor.
  - A 6-7 factor tree over the same 267m panel would be a sweep → DSR-binding, with negative expected book value and real overfit risk.
- **Concession**: this is a *deferral*, not a proof of null for nonlinear. Meta `decision_D` states the re-open trigger explicitly (new recent-alpha factor added to panel). I do NOT claim nonlinear is refuted — I claim it has no expected lever on the *current* panel and running it now is -EV. If 도훈 wants it run regardless, it is a 2-hour job on this infra.

## Concern 4 [REBUTTAL] — "Your proxy book-marginal isn't a real overlay re-run; you approximated the cash gate with invested-fraction. Maybe the real forge overlay gives +ΔIR."
- **Classification: REBUTTAL (with named residual uncertainty).**
- Rationale: The overlay (M4 regime + R05 + cash) applies the *same* gate to whichever alpha is selected — it is (to first order) a multiplicative regime scaler on active exposure, independent of the alpha's internal core/def weight. So book_active_delta ≈ gate_t · (var_active_t − base_active_t), which is exactly my proxy. The direction (negative) is robust because the tilt's gain concentrates in NORMAL/BULL months that the cash gate down-weights least, yet the gain is noise. **Residual uncertainty (named, not hand-waved)**: the true overlay has λ-tilt (λ1.5) + buffer zone that I did not replicate; these could shift the number by ±0.02-0.03. But even the optimistic edge of that band (−0.0175 + 0.03 ≈ +0.013) is < 0.05. The conclusion is insensitive to the proxy error. **Forge re-measurement is the authoritative arbiter** and I flag it — but I do not have a candidate worth forge's cost, because the alpha-level paired-t already says insignificant.

## Concern 5 [ACCEPT] — "Base sanity: are you sure your reconstruction is faithful, not an artifact? A wrong benchmark align would corrupt every PORT_t."
- **Classification: ACCEPT of the concern, RESOLVED by evidence.**
- Rationale: This is the load-bearing risk (07-02 misalignment lessons). Three independent validations:
  1. Market-proxy β scan: only bm_offset −1 gives β 0.827/cor 0.813 (all others |β|<0.16) — alignment is not free-parameter-tuned, it's forced.
  2. **Incumbent book IR recomputed = 1.416 == manifest 1.416** (exact) via the same pipeline — end-to-end validation.
  3. Base ordering (blend 3.58 > core 3.10 > defense 2.09) reproduces b1 forensic gross ordering.
  - fwd-return consistency: w2 fwd_ret_1m vs panel Ret_1m cor 0.997.
- No lookahead: score@month-end(t), return=forward month(t)+1; lag1-stress DROPS PORT_t (3.69→2.28) confirming no concurrent leakage (a lookahead artifact would be robust to added lag).

---

## Escalation check (Q-Lead auto-triggers)
- HIGH severity ≥ 5? **No** (0 — this is a null-confirmation, no capital-facing HIGH flag).
- AX axiom hard FAIL ≥ 3? **No.**
- PIT C1 (lockbox/lookahead)? **No** (lag1-stress + β-scan + IR-parity confirm PIT-clean).
- → **No escalation required.** Result is a settled-null, reported honestly.

## Self-rationalization scan (auto RE-VIEW terms)
- Searched my own verdict for: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일". 
- Concern 1 originally tempted "practically 0.05" → auto-reviewed → replaced with paired-t + overlay-reversal quantitative rebuttal. No remaining unbacked hedges.
