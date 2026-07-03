# Self-Adversarial Challenge — WT-D20260701_001 (Alpha)

**Theme**: KR 투자자-유형 플로우(smart money) 횡단면 long-only 알파 + book(STR_1715) 직교성.
**Headline candidate**: `scC_revBroad` = EW of 9 flow-direction factors, **NEGATED** (reversal direction).
**Verdict (self-finalized)**: SCREEN-TIER signal exists (cross-sectional reversal, book-orthogonal) but **NOT capital-grade** and **NOT book-marginal-positive**. Honest negative for deployment; positive *diagnostic* on the orthogonality thesis.

method: Opus 4.8 native adversarial reasoning, no external Codex (v8.2). AX-008 source #2 of 3.

---

## Concern 1 — "Negating the flow factors is a data-mined sign flip (C13 / FLIP_SIGN violation)"
**Severity: HIGH (would invalidate the alpha if true).**

- Classification: **REBUTTAL.**
- Grounds:
  1. C13 prohibits NEGATE_FACTORS / FLIP_SIGN on **Z_Score_Aligned** factors (post-hoc sign chase). The INV* factors in the panel are **raw flow factors**, not C13-aligned z-scores — so the no-flip rule does not mechanically apply.
  2. The negative-IC direction is **NOT a performance-chasing flip**: the sign is empirically NEGATIVE in **both halves independently** — 2005-2014 (INV10 IC −0.0142) and 2015-2026 (INV10 IC −0.0285, t −3.24). A sign chosen on the full sample would be confirmed by the first half alone → no look-ahead in the sign choice.
  3. Economic mechanism (not a fishing artifact): short-horizon (20-60d) net-buying by foreign/institutions captures **crowding / over-extension that mean-reverts** at the monthly cross-section. "Smart money flow" predicting reversal-down is consistent with the documented KR retail-dominated micro-reversal literature.
  - Quant data (3 axes): (a) IC sign stable across 2 independent halves; (b) rank-IC subperiod_stability = **1.00** (3/3 subperiods same sign); (c) Harvey-t +3.06 on the negated composite.
- Residual risk acknowledged: the *label* "Smart_Money_Flow" is misleading; reported as **flow-reversal / anti-crowding**, not flow-following.

## Concern 2 — "rank-IC +3.06 is real but the long-only top25 cannot harvest it (short-leg trap)"
**Severity: HIGH (this is the actual kill).**

- Classification: **ACCEPT.**
- Grounds: canonical_screen_bt (top25 EW long-only, 15bps, 2e8 liq, contract NW3):
  - full-window **PORT_t = +0.31** (IR 0.07, mean active +0.001/mo ≈ +1.2%/yr) — essentially flat.
  - Decile evidence: the spread lives mostly in **avoiding the most-bought** (short side). The long leg (least-bought top25) has near-zero *net active*. Long-only cannot short the crowded names → reversal is uncapturable here.
  - This is exactly the rank-IC(+3.06) vs portfolio-alpha-t(≈0) divergence the charter warns about; **portfolio-alpha-t is authoritative** for long-only → FAIL.
- Action: headline reported as **screen-tier**, PORT_t < 2.95 HARD gate explicitly flagged. No capital claim.

## Concern 3 — "The 2021+ negative PORT_t = decay; the alpha is dead"
**Severity: MEDIUM.**

- Classification: **PARTIAL.**
- Grounds:
  - 2021-2024 active IR = **+0.33** (positive). 2021-2026 active IR = **−0.71**. The collapse is entirely the **2025-2026 tail** (~17 months).
  - That tail coincides with extreme/likely-distorted benchmark data (monthly BM +28~31% in 2026-03/04/05 — implausible for KOSPI200; panel fwd returns mirror it). So recent failure is **partly an extreme-regime / data-quality artifact**, not confirmed alpha death.
  - BUT: even excluding the tail (to-2024), PORT_t = **+2.27** still **< 2.95 HARD**. So the partial-rescue does not change the deployment verdict.
- Action: report both 2021-2024 and 2021-2026; flag BM-tail data-quality caveat; verdict unchanged (sub-threshold).

## Concern 4 — "Even if orthogonal, is it book-marginal-positive? (the real mission question)"
**Severity: HIGH (mission-critical).**

- Classification: **ACCEPT (negative result, honestly reported).**
- Grounds:
  - Book active correlation: scC **−0.012**, scA +0.075, scB +0.103 — **genuinely orthogonal** (≪ the earnings-revision failure's 0.60). The orthogonality THESIS is confirmed: flow info ⟂ price/fundamental factors in returns.
  - But book-marginal **ΔIR = +0.004** (blend +0.10/+0.25) ≪ **+0.05** graduation threshold.
  - PIT expanding-window residual (cand active residualized on book active) has **NEGATIVE** mean (scC −0.0064/mo, t −1.92): after removing book exposure the flow-reversal residual is *worse* than book. The book's own M4/AR anti-crowding overlay **already harvests the same reversal information** — return-correlation is low but **information overlaps**.
  - Net: orthogonal × (≈0 standalone IR) = ≈0 marginal. Cheap-kill on **signal strength**, not on book-redundancy.

## Concern 5 — "Turnover / implementation discipline"
**Severity: MEDIUM (RF-A5 / Principle 6).**

- Classification: **ACCEPT.**
- Grounds: turnover_annual ≈ **16.6–18.9x/yr** (top25 EW) ≫ **11.0/yr** limit. Flow-reversal is intrinsically high-turnover (20-60d flow windows). Net-of-15bps is already in PORT_t and still flat → cost makes a weak signal weaker.

---

## Self-rationalization auto-detection
Scanned my own draft for banned phrases ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일"). None used to excuse a gate failure. Every "near-zero" is backed by a measured number (ΔIR +0.004, PORT_t +0.31, residual t −1.92), not asserted.

## Escalation trigger check
HIGH-severity concerns: 3 (C1 rebutted, C2/C4 accepted-as-negative). No PIT C1 lockbox/lookahead violation (sign verified out-of-sample; PIT alignment IC +0.0423 t5.45 confirmed). AX axiom hard-FAIL: 0. → **No auto-escalate**; standard negative hand-back. The negative is informative (orthogonality thesis validated) and should be recorded.
