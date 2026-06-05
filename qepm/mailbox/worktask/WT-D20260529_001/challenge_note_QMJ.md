# QMJ Alpha — Codex Critic Round 1 Challenge Note (Charter §8 No Silent Override)

- WT: WT-D20260529_001 Track QMJ
- Codex stance: **REJECT** (veto_flag=false, devil's advocate — no veto power)
- Agent overall disposition: **AGREE on standalone verdict + ACCEPT 5 concerns (with fixes) + PARTIAL 2 + REBUTTAL 1**
- Self-rationalization grep ("미미/관행적/실무적/보수적이면/대부분 결과 동일") run on this note → 0 hits.

Codex REJECT and my own draft converge: **QMJ FAILS standalone Discovery→Deployment graduation.** My draft graduation_assessment already labeled it `FAIL_AS_STANDALONE`. The substantive debate is narrow — whether QMJ may be *documented as a 4th-orthogonal diversifier candidate* for downstream multi-sleeve research. Codex's remediation demands materially sharpened the evidence and in two places weakened QMJ further (I accept those).

## Concern disposition

### C1 (HIGH, AX-002/004/007/RF-A1) — alpha gate stack fails → ACCEPT
QMJ fails rank_IC (0.0256<0.04), Harvey-t (2.68<3.0), DSR (0.358→0.105<0.50), subperiod (0.33<0.50), portfolio-alpha-t (0.63<<2). **Fully accepted.** This is exactly my draft's `FAIL_AS_STANDALONE` verdict; I never proposed QMJ as an admittable standalone alpha. The package is finalized as a **diagnostic/diversifier-candidate report, not a deployment alpha.** No silent override — verdict retained as FAIL.

### C2 (HIGH, PIT-C1/C12/C6) — label-conditioned handoff → ACCEPT + FIXED
Valid PIT/survivorship concern. The original alpha_scores.parquet membership was filtered on `!is.na(Ret_1m)` (forward-return availability), so name inclusion was label-conditioned even though the label column itself was not exported. **Fix applied (qmj_fix_c2_c7.R):** alpha_scores.parquet re-emitted with membership = universe ∩ factor-coverage only (244,105 rows, was 59,995). IC/portfolio diagnostics now use a SEPARATE label-merged frame that never touches the handoff artifact. PIT-clean.

### C3 (HIGH, AX-001/AX-005/RF-A1) — crisis claim fragile → ACCEPT (downgrade claim)
Accepted. AX-001 v2 ratio (8.1) is comforting but the realized crisis portfolio usefulness is modest (crisis_active_net=+1.16%/mo) and the recent-period (2020-lockbox) IC is **negative (-0.007)**. Per AX-001 v2, defensive evaluation requires crisis_alpha AND realized portfolio usefulness, not IC-ratio alone. **Disposition:** crisis-hedge value is downgraded from "strong" to "conditional/unproven — requires optimizer-stage realized-active validation before any sleeve role." Recorded as challenge_flag RF-A3-inverse (HIGH).

### C4 (HIGH, RF-A2/RF-A6/L-119) — multiple-testing understated → ACCEPT (worsens QMJ)
Accepted, and the requested evidence *weakens* QMJ — I report it honestly:
- **RF-A2 best-single test:** composite ICIR 0.2019 is **WORSE than best single proxy Q03_ROA (ICIR 0.2654), -23.9%.** The 3-axis composite does NOT improve ICIR over single ROA. RF-A2 NOT cleared.
- **RF-A6 expanded DSR:** with realistic N_trials=22 (15 proxies + 3 axes + composite + 2 universes + inclusion rule), DSR = **0.105** (was 0.358 at N=4). Far below 0.50.
Both folded into validation. These reinforce the standalone REJECT. Note (no rationalization): the composite is still justified on AX-004 grounds (single-axis long-only is structurally prohibited) and on orthogonality/turnover, NOT on ICIR superiority — I explicitly drop the implicit "composite beats single" claim.

### C5 (MEDIUM, RF-A4/RF-A5/PIT-C10) — sector-neutral + liquidity unaudited → PARTIAL
- **RF-A5 (liquidity):** ACCEPTED + audited. Top-quintile fraction below 2e8 KRW = **0.0%** across 192 months (KR_top342 already enforces liquidity). RF-A5 cleared.
- **RF-A4 (sector-neutral IC):** PARTIAL. The PIT `universe.parquet` Sector column is NA across the entire panel (verified empirically). Sector-neutral IC is **not computable** from available KR PIT data without an external sector map (cross-market/alt-data prohibited by mandate). Reported as `status: UNAVAILABLE` per answer-principles (no fabrication, no silent skip). This is a genuine data-infra gap, flagged to Q-Lead, not a methodological dodge.

### C6 (HIGH, AX-008/AX-002) — no challenge_note, lineage FLOW/CROWD only, no weights/cov → PARTIAL/REBUTTAL
- **challenge_note:** ACCEPTED — this file remedies it.
- **weights.csv / covariance.parquet / downstream stage dirs absent:** REBUTTAL with role-boundary basis. Per `alpha_research_init.md` <strict_prohibitions> 1-3 and agent_role_guard Hook, the Alpha agent is **prohibited** from producing weights or covariance — those are Optimizer/Risk outputs. Their absence at the alpha stage is *correct cooperative behavior*, not a gap. AX-008 triangulation (Forge+Codex+Architect) is a downstream gate, not an alpha-stage deliverable. The FLOW/CROWD lineage entries belong to the sibling tracks of this multi-track WT, not QMJ; QMJ lineage will be appended on package finalize.
- **artifact_lineage:** ACCEPTED — QMJ lineage appended on finalize (record_package_lineage after package write, L-194 order).

### C7 (MEDIUM, AX-008/RF-A6) — D-orthogonality not reproducible → ACCEPT + FIXED
Valid and fair. The first qmj_diag.log reported cor_vs_D=NaN (n=0) due to a date-grain mismatch (QMJ month-start vs D ML POSIXct month-end); I had patched the validation value (0.2036) outside the committed script, breaking reproducibility. **Fix:** month-normalization (D month-end → month-start) folded into qmj_fix_c2_c7.R. Reproducible cor_vs_D = **0.2036** (n=39,046, 116 months). PASS <0.30 confirmed reproducibly.

### C8 (LOW, AX-004/AX-002) — citation depth + KR contradiction → PARTIAL
- KR validation "contradiction" (FREEFLOAT ICIR 0.1835, Harvey-t 2.42 fail gates): ACCEPTED — this is consistent with my own verdict (standalone fail) and with KR quality-anomaly nuance (memory: learning_kr_lottery_anomaly_reversal — KR retail lottery preference reverses pure distribution/quality premia). Not a contradiction of a claim I made; I claim orthogonality + AX-004-compliant structure, not robust standalone premium.
- Page-level citations: PARTIAL — references retained (Novy-Marx 2013; Asness-Frazzini-Pedersen 2019 JFE; Sloan 1996; Ohlson 1980; Ball-Gerakos-Linnainmaa-Nikolaev 2016). Per Charter, "논문은 출발점, 승인서 아님" — citations are mechanism support, not admission basis; the admission basis is empirical (and it fails). Page-level depth deferred as non-binding for a FAIL verdict.

## Escalation check
- HIGH severity concerns = 5 (≥5 trigger). PIT C1 (C2 concern) was a real lookahead-adjacent finding → fixed, not escalated as a violation since the label column was never exported and the fix is clean.
- AX axiom hard FAIL: AX-004 PASS (Codex agrees), AX-005/AX-007 "FAIL" are about standalone single-sleeve viability — which I AGREE fails; not a methodology violation, the verdict already reflects it.
- **Q-Lead escalation: YES — but as an informational FAIL verdict, not a dispute.** Codex REJECT and agent verdict CONCUR that QMJ is not a standalone admit. Q-Lead decision needed only on whether to retain QMJ as a diversifier-candidate for future multi-sleeve research (my recommendation: retain as candidate, do NOT advance to deployment).

## Net outcome
Final package verdict = **FAIL_AS_STANDALONE / RETAIN_AS_DIVERSIFIER_CANDIDATE.** Codex REJECT accepted in substance. 5 ACCEPT (3 with code fixes), 2 PARTIAL, 1 role-boundary REBUTTAL (weights/cov). No silent override: all metric weaknesses (including the RF-A2 best-single loss and DSR collapse to 0.105) are surfaced, not buried.
