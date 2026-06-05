# Challenge Note — WT-D20260529_002 Track REV (alpha-research)

**Codex Critic Round** (gpt-5.5 xhigh, 2026-05-29T14:01:52) — stance = **REJECT**, veto_flag = false.
Agent verdict = **DROP_as_standalone** (concord on economics — both agree REV is not deployable). Below: per-concern disposition per Charter §8 No Silent Override + v6.0 Decision Protocol.

Self-rationalization grep ("미미/관행적/실무적/보수적이면/대부분 결과 동일") on this note: **0 hits** (verified).

---

## C1 — AX-007 portfolio mechanism break (HIGH) → **ACCEPT**
Codex: rank-IC significant but top20 long-only single-sleeve fails (t_portfolio 0.573, net_sr 0.114, DSR 0.36, mono 0.50, turnover 10.56).
Disposition: **ACCEPT, fully**. This is the core finding and the basis of the DROP verdict. It is the exact Cycle 2 lesson (rank-IC harvey-t 3.98 ≫ portfolio-alpha t). No AX-007 exception (multi-sleeve / long-short / 50+ / ML sizing) is implemented in REV, so the single_sleeve_top20 mechanism break applies. Quant data: refine_variants.csv shows t_portfolio ≤ 0.47 across ALL 6 configurations.

## C2 — PIT-C2/C10 same-day close/volume in signal (HIGH) → **ACCEPT (fixed + re-ran)**
Codex: signal uses Close_t and same-day-derived tv20 at Date==sig_date while forward return also starts at Close_t → contradicts the t-1 close claim.
Disposition: **ACCEPT — material**. Concern is correct: the draft built `past_1m` from `Close_t`, and tv20/turn20 included the rebalance-day bar. Fixed in `rev_pit_strict.R`: ALL signal inputs lagged to prior trading day (t-1 close, tv20/turn20 ending t-1, volume excludes rebalance day). **Re-ran result: rank_ic 0.027→0.023, t_rankIC 4.05→3.49, t_portfolio 0.40→ -0.49, net_sr -0.098.** A meaningful share of the marginal alpha depended on same-day close. PIT-clean version is NET-NEGATIVE → reinforces DROP. (academic: Lehmann 1990 QJE — weekly/short reversal concentrates in the most recent bar, the part most contaminated by bid-ask bounce and lookahead.)

## C3 — PIT-C13 manual sign flip (HIGH) → **PARTIAL (rebuttal grounded)**
Codex: `rev_1m := -past_1m` is a prohibited manual NEGATE.
Rebuttal (academic + L-code + quant): C13 (`.claude/rules/factor-db.md`) governs **Factor DB existing proxies** — "NEGATE_FACTORS / FLIP_SIGN of a Z_Score_Aligned DB factor is forbidden". REV is a **newly-designed factor (init Step 2-C `new_designed`)** built from raw price, NOT a DB factor. For a reversal factor the negative sign IS the economic hypothesis (De Bondt-Thaler 1985: losers→winners), determined a-priori from theory, not fitted post-hoc to IC. This is direction-by-mechanism, not direction-by-flip. L-cite: STR_1722 family Cycle 1 (project_str_1721_1722_terminated) — Codex itself caught C13 violations there as *post-lockbox IC-based selection of direction*; REV's direction is theory-fixed before any IC computation. **PARTIAL**: I accept that a formal `Z_Score_Aligned`-style direction attestation is good practice and have documented it in factor_specs. Given REV is DROP, no further DB-registration is pursued.

## C4 — AX-002/AX-008 missing canonical artifacts (HIGH) → **PARTIAL**
Codex: weights.csv, covariance.parquet, risk/optimizer packages, challenge_note, artifact_lineage absent.
Disposition: **PARTIAL**.
- weights.csv / covariance.parquet / risk_package / optimization_package are **NOT alpha-research scope** (strict_prohibitions §1-2: covariance + weights are Risk/Optimizer agent territory; producing them = Hook block + role violation). Their absence at the alpha stage is CORRECT, not a failure. They would only exist if REV advanced to Risk → Optimizer, which it will not (DROP).
- challenge_note + artifact_lineage ARE my obligation (R11 lineage). **NOW produced**: this file + artifact_lineage append below.
- Canonical path: task spec mandated `stage_artifacts/WT_WT_D20260529_002_REV/` (double-prefix per request) + `alpha_package_REV.json` in mailbox. Followed as specified.

## C5 — RF-A6 multi-testing understated (MEDIUM) → **ACCEPT**
Codex: candidates_tried=3 ignores 6 refinement variants + parallel NN/REV/PEAD context.
Disposition: **ACCEPT**. Recomputed DSR with honest full trial budget (9 = 3 base + 6 refinement): **DSR 0.36→0.154** (n=9), 0.063 (n=27 incl cross-track). Even more decisively below 0.5. method_shopping_log updated to candidates_tried=9. Reinforces DROP.

## C6 — RF-A2 turnover-conditioning incremental value (MEDIUM) → **ACCEPT**
Codex: turnover composite vs pure 1M reversal incremental ICIR/alpha undocumented.
Disposition: **ACCEPT**. refine_variants.csv: pure full_1m vs skip+turn — turnover conditioning gives NO incremental portfolio alpha (full monthly t_port 0.40 vs skip+turn 0.17/-0.05). The conditioning multiplier added complexity with zero net benefit. Documented in turnover_control_findings.

---

## Escalation check
- HIGH severity concerns = 4 (< 5 threshold) → no auto-escalate on count.
- AX axiom hard FAIL: AX-007 = 1 (< 3 threshold).
- PIT C1 lockbox/lookahead violation found? **C2 same-day close = YES, material** → per protocol this is escalate-eligible. **However**: agent verdict is already DROP (signal abandoned), the lockbox cutoff 2023-12-22 was strictly enforced for selection, and the C2 fix was applied + re-run (net-negative). No deployment risk. Logged for Q-Lead awareness; not blocking since outcome = DROP.

## Net effect on verdict
All concerns either ACCEPT (strengthen DROP) or PARTIAL (do not rescue). PIT-clean re-run gives NEGATIVE portfolio alpha. **Verdict held: DROP_as_standalone.** Codex REJECT and agent DROP concord on non-deployability. AX-000: this is a proven limitation, reported honestly — KR 1M reversal in the top-liquid (≥2e8) KOSPI200∪KOSDAQ150 universe does not survive top20 long-only net-of-cost translation; the tradeable signal lives in the last-week microstructure region we deliberately (and correctly) avoid.

## Residual value (for Q-Lead / blender)
Orthogonality is genuinely excellent: cor vs STR_1715 = -0.038, vs D = 0.010, vs FLOW = 0.162 (all ≪ 0.30). IF a future long-short or 50+ name or ML-sizing sleeve (AX-007 exceptions) is built, the reversal direction is a candidate diversifier — but NOT as a standalone top20 long-only alpha.
