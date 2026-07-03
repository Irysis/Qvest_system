# Challenge Note — WT-D20260621_009 (Buyback Yield Confirmed Momentum)

**Role**: alpha-research | **Codex stance**: REVISE (gpt-5.5 xhigh, veto_flag=false) | **Agent verdict**: SCREEN_ROUTE (clean negative)

Per Charter §8 (No Silent Override): each Codex concern classified ACCEPT / PARTIAL / REBUTTAL with basis.

## C1 — Standalone alpha decisively non-deployable, SCREEN_ROUTE ≠ approval (HIGH, AX-007)
**ACCEPT.** This is exactly my verdict. rank_IC -0.0002, ICIR -0.001, Harvey-t -0.016, base PORT_t 0.044, monotonicity 0.479, D10 PORT_t -0.305, D10-D9 t -0.485. AX-007 FAIL stated explicitly in `graduation_assessment.ax_007`. Verdict language tightened: SCREEN_ROUTE routes a post-hoc sub-signal to a NEW hypothesis, not capital. No silent upgrade.

## C2 — Liquidity PIT overstated: same-date ADV, not t-1 (HIGH, PIT-C10)
**ACCEPT (code fixed).** Valid catch. Original `adv20` = 20d trailing mean ending AT month-end Date, keyed on that same Date — the sig-date's own volume leaked into the filter. Fixed: `adv20 := shift(adv20_raw, 1L, type="lag")` per ticker, so the 20d window ends at t-1. Re-ran the full build: base PORT_t 0.015→0.044, D10 PORT_t -0.40→-0.31, oos_retention -1.30→-1.24 — all still far below every threshold. **Verdict unchanged**, but correctness restored (AX-002 grade). No self-rationalization ("영향 미미" avoided — re-ran and reported actual deltas).

## C3 — Fresh-disclosure drift is post-hoc, no portfolio t-stat/cost/holdout (MEDIUM, RF-A6|AX-000)
**PARTIAL ACCEPT.** Correct that the +0.42%/mo fresh-month split was inspected AFTER the monthly-carry failure (post-hoc) and lacks portfolio-level NW t-stat, cost-adjusted backtest, and holdout. `spike_survival.status` and `.caveat` now state explicitly it is a NEW-HYPOTHESIS candidate ONLY (prospective event-driven WT, 1-month cohort holding) + DPL feature — NOT current DPL/overlay admission evidence. I retain that it is a *real, orthogonal, mechanism-consistent* observation worth a follow-up WT (this is reporting a finding, not claiming alpha — AX-000 honest reporting), but with no admission weight now.

## C4 — No sector-neutral ICIR, RF-A4 unverifiable (MEDIUM, RF-A4)
**ACCEPT.** Added sector-demeaned (within Sector per month) rank-IC = 0.0043, ICIR 0.022. Confirms no rescue (still ~zero). RF-A4 now verifiable. Cheap completeness fix.

## C5 — Verification triangulation incomplete: no forge bt / lineage / risk / opt / cov / weights (MEDIUM, AX-008)
**PARTIAL ACCEPT / SCOPE REBUTTAL.**
- **Accepted**: `record_package_lineage()` now called post-write (L-194 order). RF-A5 D10 liquidity distribution added (D10 median ADV 4.36e9, cap 5.11e11 — not a micro-cap basket).
- **Scope rebuttal (basis)**: forge `build_bt_result`, risk Σ, optimizer weights, covariance.parquet, weights.csv are **downstream-agent deliverables**, NOT alpha-stage outputs — `agent_role_guard` HARD-BLOCKS this agent from producing weights/covariance (strict_prohibitions 1-3). AX-008 triangulation (Forge+Codex+Architect 2/3) is a *judge/governor-stage* gate applied to a graduation candidate. Since this alpha is decisively non-deployable (every HARD gate fails), no downstream pipeline is triggered — there is nothing to triangulate for capital. This is correct cooperative behavior, not a gap. Codex itself (1 of 3 sources) is satisfied as the alpha-stage critic.

## Self-rationalization audit (Decision Protocol §2)
grep of REBUTTAL/PARTIAL text for {미미, 관행적, 실무적, 보수적이면, 대부분 결과 동일, 영향미미}: the C2 resolution would naturally tempt "영향 미미" — explicitly avoided by **re-running and reporting actual numerical deltas** (0.015→0.044 etc.) rather than asserting negligibility. No hit.

## Escalate triggers (Decision Protocol §3)
- HIGH concerns = 2 (< 5) → no auto-escalate.
- AX axiom hard FAIL: AX-007 FAIL is the *expected/designed* finding (campaign tests the AX-007 wall), not a process violation → no escalate.
- PIT C1 lockbox/lookahead: none. C10 was an implementation lag, now fixed.
- Codex stance = REVISE (not REJECT) and revisions accepted/scoped → no Q-Lead escalate required. Standard finalize.

## Outcome
All 5 concerns resolved (3 ACCEPT incl. 1 code fix, 2 PARTIAL). Verdict robust to the C10 fix. alpha_package.json finalized as SCREEN_ROUTE clean negative.
