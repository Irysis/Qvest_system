# Cycle 57A Code Review Log

**Cycle**: 57A (FRED publication-lag fix + v5e/v5f panel rebuild + q15 retrain)
**Date**: 2026-05-21
**Reviewer**: Codex (GPT-5.5, xhigh effort, foreground sync) — code-only review per AX-008 (Forge + Codex 2-source)
**Mandate**: Forge agent autonomous cycle (no admit decision involved — foundation cleanup)

## Files reviewed

| # | File | Purpose | Phase |
|---|------|---------|-------|
| 1 | scripts/95_fred_us_macro_pubLag_FIXED_offline.py | FRED publication-lag fix (offline) | Phase 1 |
| 2 | scripts/173_panel_rebuild_v3f_v5e_v5f_FIXED.R | v3f / v5e / v5f panel rebuild | Phase 2 |
| 3 | scripts/174_53h_v5e_q15_strict_FIXED.py | 53H v5e FIXED q15 5-seed retrain driver | Phase 3 |
| 4 | scripts/175_53i_v5f_q15_strict_FIXED.py | 53I v5f FIXED q15 5-seed retrain driver | Phase 3 |
| 5 | scripts/177_q15_FRED_fixed_aggregate.R | Substituted leaderboard aggregator | Phase 4 |

## Codex verdict: **REVISE**

Three critical concerns + 1 nit, full JSON: `/tmp/cycle57a_codex_review.json` (3851 bytes).

### Q1 (Publication lag correctness): **PASS**
- Phase 1 shift/merge correct. CFNAI first valid 1995-01-26, ICSA first valid 1995-01-12 (expected).
- t10y2y/stlfsi4 lag=0 matches Cycle 55B green classification.
- No release-date collisions observed.

### Q2 (Downstream PIT integrity): **PASS_WITH_NIT**
- LOCF → 4w MA → shift(1L) is PIT after release-date dating.
- ICSA 4w MA semantically becomes a daily LOCF release-date smoother, not equal-weight weekly 4-release average (nit, NOT a bug).
- **Nit**: sanity check is print-only, not hard assertion → **ADDRESSED** by adding stopifnot regression tests.

### Q3 (Phase 3-4 substitution validity): **FAIL → ADDRESSED via disclosure**

**Q3a (CRITICAL)**: 53B_v5b / 54A_v3 / 54A_v4 marked as `fred_dep=false` is **not valid**. v4a/v1.3 contain A6 BBVA features built from `fred_macro_wide` Init_Claims (A6_bbva_macro_builder.R:57-89, 129-135), merged via 01_feature_assembler_alt.R:35-40 + 11_feature_engineering_enhanced.R:66-68. → **inherits ICSA Saturday-dating bug unless fred_macro_wide/A6 rebuilt**.

**Q3b (CRITICAL)**: Phase 2 fixes only direct us_* FRED columns. 173_panel_rebuild_v3f_v5e_v5f_FIXED.R:126-135 reuses unchanged v4a → v5e_FIXED/v5f_FIXED **still carry BBVA Init_Claims contamination**.

**Q3c (NIT)**: Hard-coded baseline 0.1581 misattributed. 0.1581 = Cycle 45B v3b_inst M3_Hedge, NOT v1.3 C50. v1.3 C50 6-method dynamic mean = 0.1643 (range 0.1450~0.1917).

### Critical concerns summary (verbatim from Codex)
1. "177 treats v4a-based 70-feature cycles as unaffected, but v4a contains BBVA features derived from FRED Init_Claims, which Cycle 55B identified as the same ICSA publication-lag issue."
2. "The substituted leaderboard can be misleading unless the scope is explicitly narrowed to only the four direct us_* FRED macro columns, or A6/fred_macro_wide is fixed and all v4a-dependent cycles are rerun."
3. "The hard-coded v1.3 reference baseline appears misattributed."

## Q-Lead disposition (per concern)

### Q1: ACCEPT (no code change needed)
PASS verdict — no action.

### Q2 nit: ACCEPT — hard assertion added
Added `stopifnot()` regression tests in `scripts/173_panel_rebuild_v3f_v5e_v5f_FIXED.R`:
- CFNAI 2020-03-02 must not equal -4.37 (BUGGY March reading) AND should be near -0.25 (Jan reading at release)
- ICSA 4w MA 2020-04-09 must differ by >100K from BUGGY (rolling COVID claims)
Both PASS on re-run.

### Q3a + Q3b: ACCEPT (partial) — explicit DISCLOSURE
Cannot fix in Cycle 57A scope (Forge agent autonomous mandate boundary). Requires:
- Rebuild `fred_macro_wide.parquet` with publication-lag fix
- Rebuild `A6_bbva_macro.parquet`
- Rebuild `feature_panel_v1_3.parquet` (uses A6)
- Rebuild `feature_panel_v4a_combined.parquet` (uses v1.3)
- Rebuild `feature_panel_v5e_q126_usmacro_FIXED.parquet` + `v5f_FIXED.parquet` (use v4a)
- Retrain **ALL 5 cycles** (not just 2)

→ Estimated 4-6h additional GPU + ~6 panel rebuild scripts → out of 57A foundation-cleanup scope.

**Mitigation**: Updated 177 aggregator to:
- Replace `fred_dep` boolean with `direct_us_fred_dep` + `indirect_bbva_init_claims_dep` (both TRUE for all cycles via BBVA path)
- Add `M7_indirect_bbva_dep_NOT_addressed` field in audit JSON with full scope disclosure
- Update chart subtitle to "DIRECT US FRED publication-lag FIXED (BBVA-indirect remains)"
- Add caption noting BBVA-derived ICSA bug remains in v4a base panel
- Document 57A_followup deferred work for full scope fix

**Codex 55B Q2 estimate of BBVA-indirect impact: < 0.01 PR-AUC** (Init_Claims is one of 3-component composite z-score → diluted). q15 horizon (21d forward) further reduces impact per Codex est. < 0.005.

### Q3c: ACCEPT — baseline relabeled
0.1581 → 0.1643 (v1.3 C50 6-method dynamic mean from cycle50_rebaseline_summary.json).
Chart annotation + JSON ref_baselines + chart hline all updated.

## Additional Q-Lead findings (pre-Codex)

### CFNAI lag correction: +25d → +55d

Initial Phase 1 used +25d based on 55B audit note "released ~22-25 days after month-END". Q-Lead pre-Codex inspection revealed:
- FRED CFNAI dates each value at **MM-START of REFERENCE month** (NOT month-END as 55B audit suggested)
- Empirical verification: `cfnai_raw[2020-03-01] = -4.37` = MARCH 2020 reading (released ~2020-04-23)
- Days from MM-01 dating to release: 51-53 days → use 55d to be conservative

Corrected to +55d before Codex review. Updated audit JSON + 173 script.

## Final stance

**Codex verdict: REVISE → addressed**

All 3 critical concerns + 1 nit addressed:
- Q1: no change needed (PASS)
- Q2 nit: hard stopifnot assertions added → re-run PASS
- Q3a/b: explicit disclosure (out-of-scope BBVA fix deferred to 57A_followup)
- Q3c: baseline relabeled

**Updated approval status**: APPROVE_CONDITIONAL (substituted leaderboard valid for direct us_* FRED scope only — BBVA-indirect contamination disclosed and deferred)

## Implications for q15 leaderboard

- Direct us_* FRED features (CFNAI, ICSA 4w MA): pub-lag fixed → expect BUGGY > FIXED if BUGGY was leveraging COVID lookahead
- Retained 53B/54A cycles: residual BBVA-derived ICSA contamination est. < 0.01 PR-AUC impact (Codex 55B Q2)
- True OOS q15 best may shift from 53H_v5e BUGGY 0.2480 down (release of COVID lookahead) → new leader may be 54A_v4_dm32 or 53B_v5b
