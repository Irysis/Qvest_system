# Judge Challenge Note — WT-D20260528_003 (D_PROD)

**Codex stance**: REVISE (3 concerns: 2 HIGH, 1 MEDIUM)
**Self-rationalization audit**: 0 forbidden-phrase hits in draft.
**No Silent Override (Charter §8)**: each concern classified below.

---

## C1 [HIGH] — max_drawdown_days=100 hurdle omitted → ACCEPT

**Codex**: request.json graduation_criteria includes `max_drawdown_days=100`; 09_drawdowns.csv DD#2 shows total_underwater_period=952. Additional hurdle FAIL not recorded.

**Adjudication: ACCEPT.** Independently verified — 09_drawdowns.csv DD#2: peak 2021-09-23 → trough 2022-10-13 → recovery 2025-08-11, **total_underwater_period = 952 days** (Max_DD_Duration_Months=952 in 06_metrics.csv confirms). 952 >> 100 hurdle → **5th graduation criterion FAIL**. Additionally significant: recovery date 2025-08-11 lies in the OOS deploy-extension period, so the prolonged drawdown is NOT an in-sample artifact — it persists out-of-sample, strengthening the FAIL. Draft corrected: official criteria FAIL count 2/5 → **3/5** (Harvey-t, DSR, max_drawdown_days). No quantitative impact on verdict (already JUDGE_FAILED) but completeness restored.

## C2 [HIGH] — AX-008 source set wrong → ACCEPT

**Codex**: AX-008 Triangulation requires Forge + Codex + **Architect** (≥2/3), not Forge + Judge + Codex. Draft over-claimed with Judge as a source.

**Adjudication: ACCEPT.** AX-008 canonical sources = {Forge, Codex, Architect}. Judge is the adjudicator, not a triangulation source. Corrected: of the 3 canonical sources, **Forge PASS** (self-surfaced 4-gate FAIL honestly) + **Codex PASS** (REVISE — agrees all FAILs are real, no rebuttal to FAIL finding) = **2/3 PASS** on the FAIL verdict. Architect not invoked (not required when ≥2/3 already satisfied for a FAIL conclusion; Architect is escalation path for contested PASS, not needed here). AX-008 SATISFIED via Forge+Codex, not Judge.

## C3 [MEDIUM] — stale lineage path quarantine → PARTIAL

**Codex**: `qepm/stage_artifacts/WT_WT-D20260528_003` (double-WT prefix) holds stale STR_1721/v3.6 alpha artifacts (83 dates, no covariance.parquet); canonical D_PROD is `stage_artifacts/WT_D20260528_003` + `_risk_PROD`. Judge should explicitly quarantine.

**Adjudication: PARTIAL.** Verified the stale double-prefix path exists. However contamination is REFUTED by forge hash audit: artifact_lineage hash START==END PASS for all 5 inputs (alpha 2b8df9b2 / risk 347f8d7d / opt 31c5fdcb / cov 27a6643a / weights bf4974d2), and lineage note explicitly states "archive_v3_* NOT inputs; canonical PROD lineage." So the stale path did NOT feed the backtest. ACCEPT the housekeeping recommendation: I flag `WT_WT-D20260528_003` (double prefix) + `WT_WT-D20260528_003_v3_7` for Q-Lead quarantine/cleanup. PARTIAL because the verdict is unaffected — the canonical lineage is hash-verified clean.

---

## Escalation check
- HIGH count = 2 (< 5 threshold) → no auto-escalate
- AX hard-FAIL = 0 → no auto-escalate
- PIT C1 hard violation = 0 (both detector hits are reporting-metric false positives) → no auto-escalate
- **No Q-Lead escalation required.** All 3 concerns ACCEPT/PARTIAL, none alter the JUDGE_FAILED verdict; they strengthen it (C1) or correct framing (C2/C3).

## Net outcome
Verdict UNCHANGED: **JUDGE_FAILED / GRADUATION_FAIL / NOT admission-eligible.** Codex REVISE fully addressed: 3/5 official criteria FAIL (added max_drawdown_days), AX-008 corrected to Forge+Codex 2/3, stale path quarantine flagged. Independent re-verification of all 4 (now 5, incl DD-days) hard FAILs stands — none fabricated.
