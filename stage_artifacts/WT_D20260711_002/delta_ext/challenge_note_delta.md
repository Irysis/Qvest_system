# Self-Adversarial Challenge — N2 / FQ-021 Δm1 change axis (delta_ext)

**Charter §8 No Silent Override.** Opus 4.8 native adversarial reasoning (v8.2 — no external Codex). AX-008 3-source: self-adversarial is 1 of {Forge, self-adversarial, Architect}.
prereg sha256 = `4bdda5f82fcdf70f47eff42dd253033802410f13d2864db7a26abe406cbde926` (frozen before signal→return merge).

## Verdict under challenge: NULL / HARD FAIL / kill-criterion MET — stands.

## Concerns raised (devil's advocate) + classification

### C1 — "Positive rank-IC is a real reversed effect (worsening→higher return), not just noise." → REBUTTAL
- Observed rank-IC(Δm1, fwd excess) = **+0.0079** (c1), Harvey-t **1.85** (|t|<2), placebo two-sided **p=0.085** (≥0.05). Residual (c2) +0.0109, Harvey-t 2.255 — still < Phase A level 2.80 and wrong-signed vs hypothesis.
- Evidence it is not a capital signal: cap-w PORT_t 0.77/0.64 (both fail 2.95), IS→OOS sign-flip (c1 1.58→−0.83), EW-universe t −0.61/−0.78 (**not a cap-w bench artifact** — dual-basis clears it), placebo insignificant.
- Classification: the hypothesized direction (Δ>0 → negative return) is **not corroborated**; the weak opposite-signed trend is statistically indistinguishable from zero. Reported as NULL, not as a reversed alpha. No sign-flip re-test (that would be a post-hoc sweep; prereg fixed direction).

### C2 — "The null is a power artifact of annual cadence, not a real absence." → PARTIAL
- Accept in part: an annual signal deployed monthly with 12m carry has effective ~1 independent draw/firm/yr; a fast post-filing drift (Li 2008 change effects can decay within weeks) is **unobservable at monthly/annual resolution**. This is a genuine measurement-resolution limit, recorded as caveat.
- Reject the "no power" framing: 12m-carry primary has **157 signal-months, 263 names/month, 3,657 doc-level Δ pairs / 585 tickers** — ample cross-sectional breadth; rank-IC SE small enough that a Phase-A-magnitude effect (Harvey-t −2.80) would have been detected. 6m carry (event-concentration test) is *weaker* (rank-IC ≈0), the opposite of what a fast-decaying-event signal would show. So within the tested resolution the null is real; the only unfalsified residual is a sub-monthly window requiring daily returns (not in scope, not a rescue).

### C3 — "The change (Δ) is the level (m1) in disguise, so this just re-runs Phase A." → REBUTTAL
- cor(Δm1, level m1) is low by construction (Δ is a difference); residual config c2 explicitly orthogonalizes Δm1 on level m1 per month and its rank-IC (2.255) does **not** collapse toward raw Δ (1.85) — it is marginally higher and **opposite-signed** to the level's negative IC. So Δ is its own dimension, not the level restated.
- But being independent does not make it a signal: c2 cap-w PORT_t 0.641 FAIL, OOS −0.504. Conclusion: **change is an independent-but-null dimension**; the LEVEL m1 (Phase A, Harvey-t −2.80, screen-tier) remains the only real readability signal, and the change adds nothing capital-relevant.

### C4 — "cap-tier localization / small-cap tilt (92% OTHER) means a mid-cap slice could pass." → ACCEPT-as-known-wall
- Same cap-w trap as Phase A level and as `project-captier-alpha-localization-20260706`: clarity/Δ selection localizes in benchmark-underweight small caps → long-only cross-sectional selection cannot escape cap-w. This is a structural wall documented across the arc, not a new escape hatch. EW-universe basis (which neutralizes the cap-w bench) is *also* weak/negative here, so the localization is not hiding a real cap-w-masked alpha.

### C5 — "Multiple testing across the chain inflates any apparent hit." → moot (nothing to correct)
- Cumulative n_trials = 11 (Phase A family 7 + Δ 4), selection_type = **chain** (level→change axis extension, IS-only config comparison, not argmax sweep). null max |Harvey-t| across Δ family = 2.255 < Phase A 2.80. No config reaches capital or even rank-IC significance, so Bonferroni/DSR is diagnostic-only and non-binding. No survivor to deflate.

## Self-rationalization auto-scan
Scanned this note for {미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 동일}: none used as a pass-justification. All PASS/FAIL claims are tied to contract values (canonical_screen_bt PORT_t, NW Harvey-t, placebo p, dual-basis EW/cap-tier).

## Q-Lead escalation trigger check
HIGH severity ≥5: NO. AX axiom hard FAIL ≥3: NO. PIT C1 (lockbox/lookahead): NO (annual-lag signal, active_from=rcept_ym+1, PIT-safe; Phase A already stress-tested lag12 on level). → **No escalation.** Clean honest negative.
