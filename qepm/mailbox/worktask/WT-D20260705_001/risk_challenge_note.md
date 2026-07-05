# Risk Research Self-Adversarial Challenge — WT-D20260705_001

**Agent**: risk-research (Opus 4.8 native adversarial reasoning, v8.2 — external Codex round removed)
**Date**: 2026-07-05 | **as_of**: 2026-06-30
**Target**: risk_package.json (Σ + tail + stress + crowding + style for XATTN 5-seed super-factor, top-25 EW deployment)

Devil's advocate: I raise ≥3 self-concerns against my own risk estimation, then classify ACCEPT / PARTIAL / REBUTTAL with evidence.

---

## Self-concern 1 — Σ estimation window is only n=16 complete-case months; the whole covariance may be an artifact of heavy shrinkage rather than data.

**Raised**: The complete-case block is n=16 (binding: LG CNS IPO 2025-02). With p=25, this is severely rank-deficient. Ledoit-Wolf δ=0.81 means 81% of Σ is the constant-correlation *target*, only 19% is data. Is the reported cond#=74 / PSD really informative, or am I reporting the target's conditioning?

**Classification: PARTIAL (accept the limitation, add safeguards + honest label).**
- Accepted: the 16-month complete-case window IS the binding weakness. δ=0.81 confirms the sample block carries little independent information. I already labeled `sigma_window` explicitly and flagged it under RF-R2. This is not hidden.
- Mitigation added: I did NOT rely on the 16m complete-case sample alone. The reported Σ uses **pairwise** covariance (each pair uses its full co-listed history, e.g. Samsung-SK Hynix have 300+ months) shrunk toward a constant-correlation target, so most off-diagonal entries draw on far more than 16 months. Betas, idio-vol, tail, and stress all use each ticker's *own full history* (up to 439 months), NOT the 16m block.
- Honest position: the **level** of Σ (absolute variances) is reasonably informed; the **cross-name correlation structure specific to the newest names (LG CNS, EcoPro Materials)** is shrinkage-dominated and genuinely uncertain. Downstream optimizer should treat those two names' pairwise correlations as low-confidence. This is now stated in `liquidity_flags` and RF-R2.
- No verdict change: LW remains the correct choice precisely BECAUSE p>n — this is the textbook use case for shrinkage, not a workaround.

## Self-concern 2 — Stress test coverage <85% on 3 of 4 crises makes the stress section nearly vacuous; RF-R4 "OK" may be false comfort.

**Raised**: GFC (cov 60%), Euro (64%), COVID (84%) are all flagged UNRELIABLE. Only RateHike2022 (92%) is trustworthy. So I effectively have ONE real historical stress observation, and I marked RF-R4 = OK. Am I under-warning?

**Classification: PARTIAL.**
- Accepted: I have only one high-coverage historical crisis. A single crisis is thin evidence for tail behavior. The skill's own rule (`book coverage <85% = UNRELIABLE, not hard-fail`) is followed correctly, but the *implication* — that stress evidence is weak — must be surfaced, not buried in a coverage_note.
- Rebuttal component: RF-R4's "OK" is driven by the **parametric** market_down_5 = β×(−5%) = −4.86%, which does NOT depend on coverage (it uses the full-history EW beta 0.973). That is a legitimate, coverage-independent systematic-loss estimate and it does not breach −8%. So RF-R4=OK on the parametric metric is defensible.
- Change made: I strengthen the note to state explicitly that historical crisis evidence is effectively single-observation (RateHike2022) and that the COVID borderline reading (port −24.1% vs bm −16.8%, underperform) is the more cautionary data point — high-beta growth cluster amplifies drawdowns. The self-rationalization check ("coverage low so ignore") is NOT invoked; I keep COVID's adverse reading visible.

## Self-concern 3 — Style-alpha intercept t=2.61 could be tempting me to over-claim "genuine alpha," contradicting the alpha agent's own SCREEN_TIER_FAIL.

**Raised**: I report FF5+WML intercept +0.78%/mo, t=2.61, and phrase RF-R5 as "genuine alpha, not repackaged style." But the alpha package itself judged portfolio-alpha t = 1.41 (< 2.95) = FAIL. Am I contradicting/overriding the alpha agent (silent override prohibited)?

**Classification: REBUTTAL (with clarification to prevent misreading).**
- These measure different things and do not conflict. My style-alpha t=2.61 is a **full-period (224m, 2007+) FF5+WML factor-model intercept on the gross portfolio return** — it answers "is there return unexplained by FF5+WML style?" The alpha agent's port_t=1.41 is the **net active portfolio-alpha (NW lag-3) vs KOSPI200 on the deployment universe** — the authoritative graduation metric. A significant style-intercept over 20 years is fully consistent with a weak *recent net active* alpha (post-2018 port_t = −0.29, post-2022 = −0.76 per alpha package). The long-horizon intercept is dominated by the strong pre-2018 regime.
- No override: I do NOT re-judge the alpha. risk_package `metric_type=risk_estimation`, not a graduation verdict. My role is to say style ≠ the whole story (RF-R5 = LOW because it is not pure style re-exposure), NOT to upgrade the alpha's verdict.
- Change made: RF-R5 note now explicitly cross-references the alpha's post-2018/2022 decay and states the style-intercept is full-period and NOT a graduation signal. Prevents a downstream reader from mis-citing t=2.61 as an alpha rescue.

## Self-concern 4 — 40 TDC pairs ≥0.30 with several ~1.0 is a large tail-clustering risk that RF-R5 severity=LOW may understate.

**Raised**: 40 of 300 pairs show tail-dependence ≥0.30, and SK Hynix–Samsung = 1.00. In a crash the 25 names co-crash far more than the average-cor 0.30 suggests. Should RF-R5 be MEDIUM/HIGH?

**Classification: PARTIAL → adjust framing.**
- Accepted: tail clustering is real and material. Regime correlation confirms it (bull 0.264 → bear 0.362, +0.098 lift). The EVT 1% ES −26.5% and CVaR1 −24.2% already price heavy joint tails.
- Rebuttal component: RF-R5 is specifically the *style-overlap* red flag; tail-dependence is a distinct axis. I keep RF-R5's style verdict LOW (style overlap genuinely low) but the TDC/tail-clustering concern is carried in `tail_risk.tdc_pairs_ge_030=40`, regime_correlation bear_lift, and I add an explicit line to RF-R5's metric so it is not lost. The concentration/tail-clustering flag is effectively MEDIUM and I state it belongs to concentration (RF-R1) + tail axes, which are surfaced.

---

## Self-rationalization auto-detection scan
Checked my notes for banned phrases ("영향 미미 / 관행적 / 보수적이면 OK / 대략 / 유사"). None used as a load-bearing justification. Coverage-based dismissals are labeled UNRELIABLE per skill rule (not "미미"), and every soft claim carries a metric.

## Auto-escalation trigger check
- HIGH red flags: 0 hard-HIGH (RF-R2 = HIGH_MITIGATED post-shrinkage; RF-R1/R3/R4/R5 = MEDIUM/LOW/OK). Not ≥5.
- Σ PD violation: none — LW Σ is PSD (min eigenvalue > 0). No escalation.
- AX axiom hard FAIL: none.
- PIT hard violation: none — all windows rolling/expanding, factor-DB PIT lags respected, coverage uses ≤ sig_date snapshots.
→ **No auto-escalate to Q-Lead required.** Package proceeds to optimizer.

## Net changes applied to risk_package
1. RF-R5 metric line extended to carry TDC=40 tail-clustering + explicit alpha post-2018/2022 decay cross-reference.
2. RF-R4 note strengthened: historical crisis = effectively single high-coverage observation (RateHike2022); COVID adverse reading kept visible.
3. liquidity_flags / sigma_window already carry the n=16 / δ=0.81 low-confidence caveat for LG CNS & EcoPro Materials pairwise correlations.

## Boundary attestation
No alpha_vector modification. No weight proposed. No good/bad-stock judgment. RF exposure bounds are measurement + recommendation only (optimizer scope). No silent override of the alpha agent's SCREEN_TIER_FAIL verdict.
