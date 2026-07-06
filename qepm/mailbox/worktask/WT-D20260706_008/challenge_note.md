# Self-Adversarial Challenge — WT-D20260706_008
## KRX 파생-implied positioning 횡단 알파 (개별주식선물 basis/OI)

**Agent**: Alpha Research (Opus 4.8 native adversarial, v8.2 — no external Codex)
**Date**: 2026-07-06
**Verdict**: **NEGATIVE (screening-tier) — NOT long-side harvestable at monthly frequency.** Feasibility = GO (data collected), alpha decision = REJECT for capital, route = DPL_FEATURE / screen.

---

## Devil's-advocate concerns raised (≥3 mandatory)

### C1 — [BENCHMARK ARTIFACT] The negative PORT_t is a benchmark data-quality artifact, not a real signal failure.
**Attack**: The `.cache/benchmark.parquet` monthly returns contain 6 glitch months in-sample (2026-01 +27%, 2026-04 +33%, 2026-05 +35% — impossible for KOSPI200). These inflate benchmark variance and drag active-return regression, producing spuriously negative PORT_t (−1.04 for the basis screen).
**Classification**: **ACCEPT (partial)** — the concern is valid and materially changed the numbers.
**Resolution**: Re-ran with the 6 glitch fwd-bench months removed. PORT_t(A) −1.04 → **+0.01**; PORT_t(F) −0.08 → **+0.39**; benchmark-free EW-universe-relative active = **+0.445%/mo, t=+2.65**. So the raw −1.04 WAS partly benchmark-driven. **However**, even fully cleaned, PORT_t is +0.01 to +0.39 vs the K200 gate of **2.95** — the harvestability conclusion (NOT capital-grade) is unchanged; only its severity softened (from "clearly negative" to "small positive tilt, far below gate"). challenge_note-logged; alpha_validation records both bench-clean and bench-glitch numbers explicitly.

### C2 — [MEASUREMENT FLATTERY] The one positive signal (EW-universe t=+2.65) is an equal-weight-benchmark artifact that will vanish cap-weighted.
**Attack**: `reference-kr-2025-megacap-semi-regime` + `measurement-graduation §6` establish that EW-universe-relative measurement systematically flatters small-cap/dispersed tilts by ~+1.3t vs the cap-weighted deployable benchmark. The stock-futures universe over-weights mid-caps (74 KOSDAQ names). So +2.65 EW → likely ~+1.3 cap-weighted, below any gate.
**Classification**: **ACCEPT** — consistent with established system truth.
**Resolution**: The cap-weighted-basis result (canonical_screen_bt vs K200 TR) already reflects this: PORT_t +0.01 (clean bench). The +2.65 is explicitly labeled `metric_type=ew_universe_relative` (advisory only, NOT authoritative) in alpha_validation. Authoritative reading = canonical vs K200 = fail.

### C3 — [FAST DECAY / NOT A MONTHLY ALPHA] The rank-IC is a contemporaneous micro-effect that does not survive to a tradeable holding.
**Attack**: The headline rank-IC (+0.045, t=+5.5) is measured signal@t → return@t+1. But is it look-ahead? And does it persist?
**Classification**: **ACCEPT (this is the core finding, not a flaw to rebut)** — decisively tested.
**Resolution**: (a) **PIT clean** — signal is month-end close basis (t), forward return is t→t+1 (strictly future); no contamination. (b) **Lag-1 test**: shifting the signal one extra month collapses IC from +0.045 (t=5.5) to **+0.010 (t=+1.35, insignificant)**. The signal is a ~1-month-decay effect. (c) **3M smoothing** (to cut turnover) makes PORT_t *worse* (−1.04 → −1.56) — the alpha is in the freshest reading, killed by any averaging. Conclusion: real signal, wrong frequency for monthly long-only deployment.

### C4 — [TURNOVER DESTROYS IT] Even if the tilt is real, 1875% annual turnover at 15bps is uninvestable.
**Attack**: The basis screen churns at 1875%/yr (vs research_philosophy TO≤11.0/yr = 1100% hard-fail ceiling). Costs eat the alpha.
**Classification**: **ACCEPT** — structural killer.
**Resolution**: Confirmed. TO=1875% is above the 1100% screening hard-fail. Attempted mitigation (3M smoothing → TO 1059%) destroys the signal (C3). No turnover-band or holding rule tested rescues it because the alpha *is* the fast-moving component. Logged as a hard structural fail independent of PORT_t.

### C5 — [SHORT-SIDE ONLY / NOT HARVESTABLE LONG-ONLY] The signal's edge is entirely in avoiding the bottom, which long-only cannot monetize.
**Attack**: Quintile forward returns: Q1 (cheapest basis) = −0.055%/mo (only negative), Q2-Q5 = +1.15% to +1.38% (statistically indistinguishable). A long-only top-25 picks from Q5, which ≈ Q2-Q4 → no selection edge.
**Classification**: **ACCEPT (the harvestability answer the WT demanded)**.
**Resolution**: The exclusion test (E→F→G) confirms: excluding bottom-20% basis lifts a liquidity book marginally (PORT_t −0.53→−0.08 raw; −0.53→+0.39 clean-bench) but excluding bottom-40% reverts (G worse than F). The monetizable edge is a thin avoid-the-worst effect insufficient for a 25-name long-only book. **This is a short-interest-style signal** — no-short KR mandate means the productive leg is unavailable (aligns with prior short-interest / `/srt` findings, though this came via a *different, working* data path `/drv/eqsfu_stk_bydd_trd`).

---

## Self-rationalization auto-detection (mandatory scan)
Scanned my own reasoning for banned phrases ("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일"). 
- Did NOT rationalize the negative away. Did NOT claim "close enough to gate." Did NOT invoke "관행적."
- The ONE place I softened (C1: −1.04→+0.01 after glitch removal) is backed by explicit re-measurement, not hand-waving — and I still conclude REJECT because +0.01 ≪ 2.95. No auto-RE-VIEW trigger fired.

## Escalation check (Q-Lead auto-escalate triggers)
- HIGH severity ≥5? No (findings are consistent, not conflicting).
- AX axiom hard FAIL ≥3? No.
- PIT C1 (lockbox/lookahead) violation? **No** — lag-1 test + strict t→t+1 forward confirm PIT clean.
→ **No escalation required.** Standard negative-result handoff.

## Net verdict
Data feasibility **GO** (novel working KRX endpoint `/drv/eqsfu_stk_bydd_trd`, 284 underlyings, 127 months). Signal **REAL & PIT-clean** (basis rank-IC +0.045 t=5.5, survives post-2018). **NOT long-side harvestable**: short-side-driven (C5) + fast-decay wrong-frequency (C3) + uninvestable turnover (C4); best cap-weighted PORT_t +0.01–0.39 ≪ 2.95 gate (C1/C2). **Route = DPL_FEATURE** (fast positioning signal could feed a daily/intraday or multi-signal ML layer) — NOT a standalone monthly book candidate. Honest negative.
