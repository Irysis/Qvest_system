# Cycle 56B — Codex Code Review Log

**Date**: 2026-05-21
**Reviewer**: codex CLI v1.0.4 (gpt-5-codex)
**Scope**: code correctness only (PIT / data leakage / numerical / regime split / reproducibility)
**Files reviewed**:
- `scripts/142_regime_detector.R`
- `scripts/143_regime_bucket.R`
- `scripts/144_moe_patchtst_v5e_q126.py`
- `scripts/145_moe_aggregate.R`

## Codex runs (2 independent sessions)

Both sessions independently flagged the SAME 2 CRITICAL/HIGH bugs (AX-008 2-source verification).

### Codex Session #1 (PID 1707275, 26 minutes runtime)
- Verdict: **FAIL**
- Bugs found: 3

### Codex Session #2 (PID 1708827, 21 minutes runtime)
- Verdict: **FAIL**
- Bugs found: 2

## Bugs found (consolidated)

### Bug #1 — CRITICAL: q126 label-time leakage in CV folds

**File**: `scripts/144_moe_patchtst_v5e_q126.py` line 361 (Codex #2) / 361 (Codex #1)

**Issue**: `train_idx` filtered only on `dates_seq <= train_end`. For target `y_tail_q126`, the label at date t is the realized return over [t, t+126 business days]. Training rows in the last ~126 business days of each fold's training window have labels realizing INSIDE the validation period → CV uses validation-period outcomes → bias in early-stop epoch selection.

**Fix applied** (2026-05-21):
- Added `ENABLE_PURGED_CV = True` constant
- Added `TARGET_HORIZON_DAYS = {"y_tail_q126": 126, ...}`
- In `train_one_expert_window`, when `has_valid=True`:
  - Compute `train_offset = np.busday_offset(dates_seq, H, roll='forward')`
  - Require `train_offset < valid_start` (i.e., label realization must precede valid start)
  - Added `purge_count` to per-fold result + log line
- Verification: BULL Fold1 (train_end=2007-12-31, valid_start=2008-01-01) purged 39 dates from `2007-07-?? ~ 2007-12-31`, where 2007-07-01 + 126b = 2007-12-24 (still pass), 2007-08-01 + 126b = 2008-01-26 (purged). After purge, n_train_bear dropped from 28 to 0 (most BULL bears in that fold were leaking from 2008 GFC into "BULL training") → fold SKIPPED. Correct PIT behavior.

### Bug #2 — HIGH: Unresolved q126 labels treated as y=0

**File**: `scripts/144_moe_patchtst_v5e_q126.py` line 279 (Codex #2) / line 95 (Codex #1)

**Issue**: `prepare_data_full()` did `y_raw = panel[target_col].fillna(0)` — but `targets_long_horizon.parquet` marks dates after `2025-11-18` (last realized q126 cutoff) as `y_tail_q126=0` when `ret_q126` is NA. These 108 OOS dates (Nov 2025 ~ Apr 2026) appear as "non-events" → inflate negative class → contaminate OOS PR-AUC.

**Fix applied** (2026-05-21):
- `prepare_data_full()` now also loads `ret_q126` column
- Returns additional `y_valid_mask = panel["ret_q126"].notna().values`
- `train_one_expert_window` threads `y_valid_mask`:
  - `std_mask = regime_mask & y_valid_mask` (standardization on resolved labels only)
  - `train_idx = ... & y_valid_seq`
  - `valid_idx = ... & y_valid_seq`
- OOS mask: `oos_mask = (date in [OOS_START, OOS_END]) & y_valid_seq` (filters unresolved)
- Verification: prepare_data_full reports `n_y_valid=8829 n_y_unresolved=108`, OOS now 1934 (was 2042), last valid date = 2025-11-18.

### Bug #3 — HIGH: Aggregate also includes unresolved q126 rows

**File**: `scripts/145_moe_aggregate.R` line 182 (Codex #1 only)

**Issue**: After fixing #2 at training stage, aggregator still reads `predictions_moe_mean_y_tail_q126.parquet` (which now contains only resolved dates) — but to be safe, add explicit filter join in aggregate.

**Fix applied** (2026-05-21):
- Added `y_valid_dt` from `targets_long_horizon` ret_q126 maturity
- `moe_mean` filtered by `ret_q126_resolved == TRUE` before any metric computation
- Also added FULL expert as the **strict-PIT fair baseline** (computed within this cycle), separate from the leaky-PIT 53H baseline (kept for documentation)
- Per-period bootstrap CI now reports both `h53_leaky_pr` and `full_strict_pr` columns
- Primary verdict uses `delta_vs_full_strict` (apples-to-apples)

## Items NOT bugs (correct as-is)

Codex confirmed correct:
- **Regime detector lag** (142): `Date_join = sig_date + 1` enforces t-1 lag in roll join. Audit `lag1_violation_count = 0` confirmed.
- **MoE gating routing** (144 line 711-713): `np.where` nesting correctly routes BULL→BULL, NORMAL→NORMAL, CAUTION/CRISIS/UNKNOWN→FULL.
- **Seed propagation** (144 `set_seed`): random + torch + numpy + cuda all seeded; verified by 5-seed identical OOS dates / y arrays in `build_gating_weighted_ensemble`.
- **Per-seed/expert array alignment** (144 line 689-694): explicit sanity checks raise RuntimeError on mismatch.
- **Regime bucket feasibility** (143): properly distinguishes FEASIBLE (BULL/NORMAL) vs INFEASIBLE (CAUTION/CRISIS) regimes given 1995-2015 train data.

## Implications for headline metric

The 53H headline `OOS PR-AUC = 0.4012` (seed=42) was computed under leaky-PIT (both bugs present in template script `132_patchtst_q126_usmacro.py`). After applying strict PIT:
- Per Codex review, the value is **expected to drop** (less leakage = less inflation).
- This Cycle 56B's `FULL expert` (full-panel + strict PIT) provides the **fair re-baseline** for comparison.
- The MoE verdict criterion now uses `delta_vs_full_strict` (NOT `delta_vs_53H_leaky`) as the primary verdict input.

## Verdict acceptance

Both bugs fixed, scripts re-run, outputs replaced. All other code paths confirmed correct by Codex 2-source independent review (AX-008 PASS).
