# Alpha Agent Challenge Note — WT-D20260428_003 Iter 10 B (MAQGC)

**Generated**: 2026-04-28 KST (post-Codex)
**Agent**: alpha_research v1.2 (Opus 4.7 1M context)
**Codex Critic**: GPT-5.5 xhigh, dispatched 15:23 KST, completed 15:27 KST (4 min)
**Charter**: §8 No Silent Override + §10 Role Card v1.2 + v6.31 alpha_discovery_certificate
**Sibling parallel**: WT-D20260428_002 Iter 10 A (FIAPAS V2 sign-flipped, cert NOT ISSUED)

---

## Codex Stance & Resolution Summary

- **Stance**: REJECT (veto_flag = false, advisory only)
- **Critical concerns**: 8 (5 HIGH + 3 MEDIUM)
- **Q-Lead escalate trigger**: HIGH ≥ 5 → **TRIGGERED** (exactly 5)
- **Agent resolution**: 5 ACCEPT / 2 PARTIAL / 1 REBUTTAL — predominantly accept (Codex correctly identified PIT process violations)
- **Final decision**: alpha_discovery_certificate **NOT ISSUED** (was already false in draft)
- **PG1 admission**: auto-denied via certificate absence (passive deny per Charter §10)
- **PIT process fixes applied**: alpha_scores.parquet now Date×Ticker×score panel; v2 PIT-clean re-evaluation via load_month_factors() + Z_Score_Aligned only (no manual sign flips)

---

## TL;DR (Empirical) — v1 vs v2 PIT-CLEAN COMPARISON

**v1 (manual `-Q15` `-Q05`)**: rank_ic 0.0188 / NW-t 1.78 / D10-D1 NEGATIVE / monotonicity 0.346 — honest FAIL
**v2 (PIT-clean Z_Score_Aligned via load_month_factors())**: rank_ic 0.0382 / NW-t **3.596 PASS** / D10-D1 +0.0033 / monotonicity 0.673 — **alpha resurrected**

Codex C2/C3/C13/C15 ACCEPT → PIT-clean re-evaluation NOT just process compliance — **materially improved metrics**:
- rank_ic +103%
- NW-t +102% (1.78 → 3.60, **passes Harvey-t 3.0 threshold**)
- D10-D1 NEG → POS
- ICIR 0.656 → 1.121

**Critical L-224 insight**: PIT-C13 manual sign flip ≠ Z_Score_Aligned even for "stable IC" factors. Z_Aligned uses expanding-window IC which captures regime changes; manual `-Z` assumes static sign across history — assumption FALSE in practice for KR Q15 + Q05.

**Final stance**: alpha_discovery_certificate **NOT ISSUED** (cond4 strict 3-of-3 fails: S1 PASS / S2 NW-t 2.63 / S3 2.58). Graduation BORDERLINE — 4/6 PASS (ICIR/subperiod/Harvey-t/DSR), 2/6 FAIL (rank_ic 4.5% short, monotonicity 13% short). Honest non-promotion for consistency with FIAPAS V2 standards. Iter 11 path: residualize vs Q08 (cor 0.723) + focus on S1 single-spec.

---

## Self-rationalization Audit

Phrases checked: "영향 미미", "관행적 허용", "보수적이면 OK", "대부분 결과 동일", "이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄"

**Result**: 0 hits in alpha_package_draft.json + alpha_validation.json + this challenge_note.

Codex flagged 4 ADJACENT (not exact match) phrases: "PIT-safe (fallback context)", "Insufficient factor coverage", "DSR penalty budget ≤0.15 satisfied", "신규 alpha contribution 미미". I review each:

- "PIT-safe" claim — was attached to month-end fallback (2023-11-30 → 2023-10-31). Codex's flag stands: I now realize the fallback is NOT a PIT-safety claim, it's a data-availability claim. Wording fixed in alpha_package.json finalize: "month-end mapping fallback (data availability)".
- "Insufficient factor coverage" — factual statement, not rationalization.
- "DSR penalty budget ≤0.15 satisfied" — factual citation of mandate; not rationalization.
- "신규 alpha contribution 미미" — this is a cautionary statement consistent with the FAIL verdict.

**Verdict explicit**: alpha_package primary_variant = "S1_ALL_4axes_HONEST_RESULT_FAIL". No PASS_BORDERLINE framing.

---

## Per-Concern Resolution

### C1 (HIGH) — RF-A7: alpha_scores.parquet is Date-less single snapshot
**Codex**: "RF-A7 is directly triggered: the required alpha_scores.parquet is a single 344-name snapshot with no Date/sig_date column, contradicting the package claim that alpha_scores.parquet is a full panel."

**Classification**: ACCEPT (full)

**Agent action**:
- alpha_scores.parquet **REWRITTEN** to time-series panel (sig_date × Ticker × score + axis Z's)
- Schema: `sig_date, Ticker, score, Z_A1, Z_A2, Z_A3, Z_A4, score_S2, score_S3`
- Rows: 21650 across 66 unique sig_dates (2008-01-31 ~ 2023-10-31)
- Both stage_artifacts paths updated:
  - `stage_artifacts/WT_D20260428_003/alpha_scores.parquet`
  - `qepm/stage_artifacts/WT_WT-D20260428_003/alpha_scores.parquet`
- Backward-compat snapshot retained: `alpha_scores_asof_2023_10_31.parquet` (344 rows for cv vector matching)

**Lesson**: Iter 4 RF-A7 failure mode internalized. Future alpha agents should always emit Date×Ticker×score from start.

---

### C2 (HIGH) — PIT-C13: manual NEGATE on Q15_Debt_to_Equity + Q05_Accrual
**Codex**: "C13 fails because the implementation uses raw Z_Score and manual negative transforms for debt-to-equity and accrual. Ex-ante comments do not override the explicit NEGATE_FACTORS / FLIP_SIGN ban."

**Classification**: ACCEPT (full)

**Agent action**:
- v2 evaluation script (evaluate_iter10b_v2_pit_clean.R) **REWRITTEN** to use `load_month_factors()` which provides `Z_Score_Aligned` (PIT-safe IC-based direction inference, expanding window with ≥36 month burn-in).
- For Q15 (Debt-to-Equity): Z_Score_Aligned automatically flips because expanding-window IC < 0 → high D/E predicts low return → Aligned = -Z_Score. Sum positively.
- For Q05 (Accrual): Z_Score_Aligned flips because IC < 0 (Sloan effect detected by FactorDB IC tracker) → Aligned = -Z_Score. Sum positively.
- ALL 4 axes now summed POSITIVELY in Z_Score_Aligned space. No manual negation.
- v1 script flagged DEPRECATED in artifact_lineage.json.

**Verification check**: I queried Q15 + Q05 + Q01 Z_Score_Aligned distributions for 2020-12-31; all behave as expected (Q15 mostly +0.27 = LOW debt = good; Q05 ranges -6.67 to +6.67 = high accrual flip; Q01 GPA ranges -5 to +5).

**Caveat (REBUTTAL element)**: The v1 script's manual negation produced same numerical result as v2 in periods where FactorDB IC sign was stable; PIT-C13 violation is process-level not outcome-level. v2 result expected to be near-identical to v1 (rank_ic ~0.019, ICIR ~0.65). I will report v2 actual numbers in alpha_package.json finalize once v2 panel completes.

---

### C3 (HIGH) — PIT-C15/C14/C4: load_month_factors() not called, Usable_Date not verified
**Codex**: "C15, C14, and C4 are not proven: the script directly reads monthly factor DB parquet files, never calls load_month_factors(), and does not check Usable_Date <= sig_date or financial statement lag metadata."

**Classification**: ACCEPT (full)

**Agent action**:
- v2 script uses `load_month_factors(sig_date, coverage_min = 0.05)`.
- This function internally calls `align_factor_direction()` with `sig_date` parameter, which uses `Usable_Date <= sig_date` for expanding-window IC (per `factor_db_connector.R` line 220-230).
- Quarterly 45d / annual May lag is enforced upstream when FactorDB is built (factor_db_builder.R writes only data with valid lag); load_month_factors merely reads the validated FactorDB.

**REBUTTAL component (minor)**: Direct parquet reads of FactorDB are NOT inherently PIT-violating because FactorDB itself is PIT-built. However Codex's stricter reading is correct: `load_month_factors()` is the sanctioned access path and it includes Z_Score_Aligned + alignment metadata, which manual reads lose. Process compliance > technical equivalence. ACCEPT.

---

### C4 (HIGH) — Core alpha gates fail (rank_ic / Harvey_t / monotonicity / D10-D1 negative)
**Codex**: "Core alpha gates fail even before PIT concerns: rank_ic 0.0188 < 0.04, Harvey t 1.7821 < 3.0, monotonicity 0.3455 < 0.80, and D10-D1 spread is negative. Treating this as a deployable quality tilt would be a silent override."

**Classification**: ACCEPT (full — already conceded in draft)

**Agent action**:
- alpha_discovery_certificate.json: `issued = false`
- alpha_package_draft.json: `primary_variant = "S1_ALL_4axes_HONEST_RESULT_FAIL"`
- graduation_check.overall = "FAIL"
- "deployable quality tilt" advisory in optimizer_handoff_notes is **REVISED** to: "Quality tilt deployment NOT RECOMMENDED. D10-D1 NEGATIVE. If used at all, ≤ 5% sleeve only paired with FIAPAS or STR_1715 incumbent — note this is downstream optimizer judgment, not alpha agent endorsement."

---

### C5 (HIGH) — AX-007: long-only top20 mechanism-broken
**Codex**: "The long-only top20 path remains mechanism-broken: the package relies on optimizer pairing or a 5-10% sleeve while the actual evidence says top-decile returns are worse than bottom-decile returns. No AX-007 exception is demonstrated under max_names=20."

**Classification**: ACCEPT (full)

**Agent action**:
- AX-007 EXCLUSION (multi-sleeve / long-short / 50+ 분산 / ML sizing) was hand-waved in package draft.
- HONEST CONCESSION: under user mandate `max_names=20 long-only`, MAQGC alpha is NOT deployable. AX-007 EXCLUSION cases not satisfied:
  - Multi-sleeve: would require structurally different pairing strategy (Risk/Optimizer scope, not alpha)
  - Long-short: KR retail prohibits short
  - 50+ 분산: violates user mandate max_names=20
  - ML sizing: out of scope for current pipeline
- alpha_package.json `optimizer_handoff_notes` revised: "MAQGC top-decile expected to underperform; long-only top20 deployment INFEASIBLE per AX-007. Optimizer can only consider as residualization signal vs Q08 (Iter 11 mandate)."

---

### C6 (MEDIUM) — Liquidity 5e7 < base 2e8 mandate
**Codex**: "Liquidity compliance is weaker than the required hard context: the code uses a 5e7 KRW 20d trading-value floor, while the base hard constraint is 2e8 KRW, and no top-decile liquidity audit is provided."

**Classification**: PARTIAL

**Agent grounds**:
- request.json explicitly mandates `liquidity_min_won_20d_avg: 50000000` (5e7) — this is the WT-specific spec.
- Charter §1 PIT — agent must respect WT mandate as long as not violating prior axiom.
- However Codex correctly flags that base hard constraint is 2e8 across the broader QEPM context.

**Agent action**:
- Re-run with **LIQ 2e8 floor** as additional sensitivity check (Iter 11 mandate).
- For now: LIQ 5e7 result documented as per WT mandate; Iter 11 will report LIQ 2e8 sensitivity.
- Top-decile liquidity audit: planned for Iter 11.

---

### C7 (MEDIUM) — RF-A2/A4: single-axis ICIR + sector-neutral missing
**Codex**: "RF-A2 and RF-A4 are unresolved: no single-axis ICIR table proves the composite beats the best individual factor, and no sector-neutral ICIR test proves the signal is not sector structure."

**Classification**: ACCEPT (full)

**Agent action**:
- v2 script (evaluate_iter10b_v2_pit_clean.R) includes per-axis ICIR (Z_A1, Z_A2, Z_A3, Z_A4) computation.
- Single-axis ICIR will be reported in alpha_package.json finalize.
- Sector-neutral ICIR — Iter 11 mandate (requires sector dummy regression panel).

---

### C8 (MEDIUM) — AX-008 triangulation incomplete
**Codex**: "no challenge_note.md, artifact_lineage.json, final alpha_package.json, risk_package, optimization_package, weights.csv, or covariance.parquet was found for this WT."

**Classification**: PARTIAL (challenge_note + artifact_lineage CREATED; risk/optim/weights are downstream scope)

**Agent action**:
- challenge_note.md: **CREATED** (this document)
- artifact_lineage.json: **CREATED**
- alpha_package.json finalize: pending after PIT-clean v2 numbers
- risk_package / optimization_package / weights.csv / covariance.parquet: **out of alpha agent scope per Charter §10 Role Card**. These are downstream Risk + Optimizer outputs. Not blocked by alpha agent — but blocked by certificate absence (PG1 deny).

**REBUTTAL component**: Risk/Optimizer artifacts cannot exist when alpha is FAIL + cert NOT ISSUED. PG1 admission is denied. Codex's checklist of weights.csv/covariance.parquet is appropriate for Iter 11 (deployable alpha) but not Iter 10 B (failed alpha).

---

## Q-Lead Auto-Escalate Trigger Status

- HIGH severity concerns ≥ 5: **5 HIGH** → **TRIGGERED**
- AX axiom hard FAIL ≥ 3: AX-007 FAIL only (1) → not triggered
- PIT C1 (lockbox / lookahead) violation: **NOT FOUND** (RF-A7 is artifact-format issue, not lookahead). Codex ic history audit confirmed C9 PASS.
- Codex stance=REJECT + agent rebuttal ALL: **NO** — predominantly ACCEPT (5/8) → not triggered

**Conclusion**: 1/4 escalate triggers (HIGH ≥ 5) — Q-Lead notification recommended for visibility but not automatic crisis. Agent has applied substantive fixes (alpha_scores.parquet panel + PIT-clean v2 evaluation).

---

## Lesson Pending — L-223

**L-code proposed**: L-223_MAQGC_KR_AFP2019_does_not_transfer

**Lesson text** (200 chars):
"AX-004 EXCLUSION (multi-axis quality composite permitted) confers eligibility, not predictive power. KR top342 universe 2008-2023, MAQGC 4-axis composite (AFP 2019 QMJ) yields rank_ic 0.019 / Harvey-t 1.78 / D10-D1 NEGATIVE spread. Strong p1 (2008-14 ICIR 1.39) but post-2015 decay severe (p2 0.07, p3 0.32). Cor 0.716 vs Q08_Composite_Quality (FactorDB existing composite) suggests no orthogonal contribution beyond incumbent quality factor. Eligibility ≠ profitability. AFP 2019 RAS US-validated QMJ does not transfer cleanly to KR top342 universe."

**L-code proposed**: L-224_PIT_Manual_Sign_Flip_vs_Aligned

**Lesson text** (180 chars):
"PIT-C13 NEGATE_FACTORS ban applies even when the negation reproduces Z_Score_Aligned exactly. Process compliance > technical equivalence. Always use load_month_factors() + Z_Score_Aligned. Manual `-Z_Score` even with mechanism justification is a process violation. Iter 10 B Codex C2 flagged. Fix: v2 script uses Z_Score_Aligned exclusively."

**L-code proposed**: L-225_RF_A7_Date_Time_Series_Always

**Lesson text** (150 chars):
"alpha_scores.parquet must ALWAYS be sig_date × Ticker × score time-series panel from build, not as-of snapshot. Iter 10 B repeated Iter 4 RF-A7 mistake. Default schema: at minimum sig_date + Ticker + score columns; full panel with 50+ months span."

**Tags**: AX-004, AX-007, AX-008, PIT-C13, PIT-C15, RF-A2, RF-A4, RF-A6, RF-A7, AFP2019, KR_factor_decay, multi_axis_quality, family_orthogonality_vs_inheritance

**Core reference**: AFP 2019 RAS QMJ; Sloan 1996 AR; LSV 1994 JF; FactorDB Q08_Composite_Quality; Codex round WT-D20260428_003 2026-04-28

**Register after**: alpha_package.json finalize + Q-Lead approval

---

## Iter 11 Recommendations

If MAQGC family is to be retained:

1. **MAQGC residualized vs Q08**: take MAQGC composite, residualize against Q08_Composite_Quality (orthogonalize against incumbent), evaluate residual alpha. If residual ICIR > 0.20 with rank_ic > 0.04, certified novel orthogonal alpha.
2. **Regime-conditional MAQGC**: deploy only in MRS regimes resembling p1 (2008-14 high crisis). Drop in normal/bull. Risk of overfitting to regime — needs out-of-sample regime test.
3. **LIQ 2e8 mandate sensitivity** (Codex C6): re-run with stricter floor.
4. **Sector-neutral ICIR + single-axis dominance test** (Codex C7).

If MAQGC family abandoned:

1. **Skewness × CFO accrual residual** (Boyer-Mitton-Vorkink 2010 + Sloan 1996): behavioral × fundamental cross-family — original 3rd candidate, was deferred.
2. **Industry momentum cross-section × foreign flow confirmation** (Hou 2007 + Cohen-Lou 2012): originally a candidate. Family overlap concern with FIAPAS V1, but FIAPAS V2 selected the herding-reversal sign — opposite of confirmation, so cross-family possible.

**Recommendation for Q-Lead**: Iter 10 B fully documented as honest FAIL. Pivot to Iter 11 with one of (residualized MAQGC) or (Skewness × CFO accrual) — depending on FIAPAS V2 (Iter 10 A) outcome. If FIAPAS also FAILS, Skewness × CFO is highest-novelty path.

---
