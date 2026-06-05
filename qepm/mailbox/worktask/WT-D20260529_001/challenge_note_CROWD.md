# Challenge Note — WT-D20260529_001 Track CROWD (Alpha)

**Agent**: alpha-research | **Codex round**: GPT-5.5 xhigh | **Date**: 2026-05-29
**Codex stance**: REJECT (veto_flag=false) | **Agent verdict**: ABORTED_NEGATIVE_ALPHA (agree)
**Triangulation (AX-008)**: Codex FAIL + Agent reject = CONCORDANT reject. agree_with_claude on the
reject conclusion; Codex additionally challenged the package's evidence hygiene (resolved below).

Codex critique is devil's advocate, no veto. Each of 6 concerns classified ACCEPT / PARTIAL /
REBUTTAL per Codex Round Decision Protocol. Codex AGREES with the reject; its concerns are about
making the evidence PIT/lockbox-clean and governance-complete before the result is cited.

---

## Concern-by-concern

### C1 (HIGH) — lockbox not applied; metrics include post-2023-12-22 data → ACCEPT
**Codex**: code set SIGNAL_CUTOFF=2023-12-22 but never filtered the panel; artifacts run to 2026-03.
Pre-lockbox rank_IC 0.0157 (t=1.82) vs combined 0.0209 (t=2.57) → "PIT lockbox strict" claim false.

**Resolution**: ACCEPTED. Re-ran with explicit lockbox split (init `<v61_window_isolation>` requires
Alpha use train+validation only). Authoritative graduation metrics now = **lockbox window (<=2023-12-22)**:
- rank_IC **0.0157**, ICIR **0.118**, IC_t **1.82**, Harvey_t **0.40**, monotonicity **-0.65**, n=240.
- The lockbox number is WEAKER than full-sample → the contaminated number was the more favorable one.
This strengthens the reject. Both windows now published separately (`diagnostics_window_split`).
**No rationalization** — the cleaner number is worse and I report it as authoritative.

### C2 (HIGH) — all alpha gates fail → ACCEPT
**Codex**: rank_IC 0.0209<0.04, ICIR 0.158<0.20, Harvey_t 1.62<3.0, mono -0.624, pa_t -1.36.
**Resolution**: ACCEPTED — this is exactly my verdict. On the authoritative lockbox window the failure
is even cleaner (rank_IC 0.0157, Harvey_t 0.40). Graduation FAIL on every criterion except the
misleading subperiod count.

### C3 (HIGH) — is_crisis_hedge=true artifact contradicts negative crisis_alpha → ACCEPT
**Codex**: alpha_validation set is_crisis_hedge=true from bad/normal IC ratio 1.18, while realized
crisis_alpha_bad is -0.0052. AX-001 v2 requires REALIZED crisis alpha/MDD relief, not IC ratio alone.
**Resolution**: ACCEPTED — artifact bug. `is_crisis_hedge` now derived from REALIZED active return in
bad months (`crisis_alpha_bad > 0`) → **FALSE**. Added `ic_ratio_favorable_but_not_realized=true` and
the bad-month decile spread (flat ~-7% across all deciles = no cross-sectional protection). AX-001 v2
conditional evaluation FAILS on the realized criterion.

### C4 (MEDIUM) — composite does not beat best single; recent-period concentration → ACCEPT
**Codex**: composite ICIR 0.158 < CR08 ICIR 0.173; last-36m ICIR 4x full-sample (RF-A2 + RF-A3).
**Resolution**: ACCEPTED. Computed `composite_vs_best_single`: composite lockbox ICIR 0.118 vs best
single CR08 0.173 = **-32% (negative improvement)**. RF-A2 fires. recent36_ICIR 0.80 vs lockbox ICIR
0.118 = **6.8x** → RF-A3 fires hard. The composite is static-blend dilution; the marginal IC lives in
the last ~3 years only. Recorded as HIGH challenge flag RF-A3.

### C5 (MEDIUM) — RF-A4/RF-A5 not auditable → PARTIAL
**Codex**: no sector-neutral IC report, no top-decile 20d trading-value table.
**Resolution (PARTIAL)**:
- RF-A5 (illiquidity) ACCEPTED + RESOLVED: added top-20 liquidity audit. Median 20d ADV = **5.23e9 KRW**,
  only **1.4%** of holdings below 2e8, 0% below 5e7. **Liquidity is NOT the problem** — this is an
  important nuance: the signal failure is genuine signal absence, not a microcap artifact.
- RF-A4 (post-neutralization IC) REBUTTAL (scoped out): the candidate is ABORTED on raw cross-sectional
  monotonicity (-0.65) and negative portfolio alpha. A sector-neutral IC report cannot rescue an
  inverted-monotone, negative-portfolio-alpha signal — neutralization removes systematic exposure but
  the long extreme is adverse cross-sectionally. Running a full neutralization grid on a dead candidate
  is method-shopping (init `R2-C` candidates cap = 5; I stopped at 2). Documented as not-pursued, not
  silently skipped.

### C6 (HIGH) — governance artifacts absent → ACCEPT (alpha-scope) + REBUTTAL (downstream)
**Codex**: challenge_note.md, artifact_lineage.json, risk/optimization packages, weights.csv,
covariance.parquet not found; status SPEC_APPROVED.
**Resolution**:
- challenge_note.md + artifact_lineage.json: ACCEPTED — these are MY (alpha) responsibility. This file
  is challenge_note_CROWD.md; artifact_lineage recorded via record_package_lineage() after final write.
- risk_package / optimization_package / weights.csv / covariance.parquet: **REBUTTAL**. These are
  downstream agent (risk / optimizer) artifacts and are OUT OF ALPHA SCOPE (init `<strict_prohibitions>`
  1-3: covariance + weights are Hook-blocked for Alpha). They are correctly ABSENT because the alpha is
  ABORTED — there is nothing to pass downstream. Per Common Charter §8 No Silent Override, I file the
  abort rationale (this note + alpha_package verdict=ABORTED_NEGATIVE_ALPHA) as the infeasibility report;
  I do NOT fabricate a covariance/weights for a dead alpha. status will advance to ALPHA_ABORTED.

---

## AX axiom compliance (Codex flagged AX-005 FAIL + AX-007 FAIL)
- **AX-005 echo (ACCEPT)**: crowding/defense standalone top-20 long-only signal→portfolio translation
  break. portfolio_alpha_t=-1.36, monotonicity inverted. This is the canonical AX-005 failure mode.
- **AX-007 (ACCEPT context)**: this WT is a multi-sleeve 4th-sleeve candidate (AX-007 multi-sleeve
  exception applies to the *structure*), BUT the candidate is evaluated as top-20 long-only and fails the
  signal→portfolio mechanism regardless. To be a viable 4th sleeve the crowding signal would need an
  AX-007 exception *implementation* (long-short or ML-sizing) — not provided, and not pursued because
  the index-universe cross-section shows no monotone tradable structure to harvest.

## CR07 thesis-anchor invalidation (my independent finding, pre-Codex)
The headline gap-directed candidate **CR07_Momentum_Crowding** (conditional_ic 0.114, ic_bad 0.083 in
conditional_ic_matrix.csv) has only **16 months** of factor_db coverage (2006-02..2010-08; n_months=18
in the matrix). Its high conditional_value is a small-sample GFC-window artifact, NOT a usable
2004-2026 signal. The gap-directed thesis foundation is invalid. EXCLUDED.

## Self-rationalization auto-check (Charter §8)
Grep of REBUTTAL/PARTIAL text for {미미, 관행적, 실무적, 보수적이면 OK, 대부분 결과 동일}: **0 hits**.
The two rebuttals (RF-A4 scope, downstream artifacts) cite: init `<strict_prohibitions>` (alpha cannot
produce covariance/weights), init `R2-C` (candidate cap), Common Charter §8 (infeasibility report in lieu
of fabrication), and quantitative basis (mono -0.65, pa_t -1.36). No rationalization language.

## Escalation check
HIGH-severity concerns from Codex: C1, C2, C3, C6 = 4 (< 5 threshold). AX hard FAIL: AX-005 + AX-007 = 2
(< 3 threshold). PIT C1 (lockbox) concern raised → ADDRESSED (re-ran with cutoff). Codex stance=REJECT
but agent does NOT rebut-ALL (agent concurs with reject). **No auto-escalate triggered.** Q-Lead receives
the concordant reject + orthogonality finding as the verdict.

## Final disposition
Codex and agent CONCUR: REJECT / ABORTED. All 6 Codex concerns resolved (4 ACCEPT + fixes, 1 PARTIAL,
C6 split ACCEPT/REBUTTAL). Final alpha_package_CROWD.json carries verdict=ABORTED_NEGATIVE_ALPHA with
lockbox-authoritative metrics. Orthogonality (cor<0.30 vs both) is the one positive, durable finding.
