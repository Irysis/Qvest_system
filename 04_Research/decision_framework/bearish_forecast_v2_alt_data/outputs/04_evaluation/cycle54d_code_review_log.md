# Cycle 54D Code Review — Phantom-0 Cleanup

Date: 2026-05-21

Scope: code-only review of `scripts/151_targets_observable_fix.R` and `scripts/152_observable_reeval_all_cycles.R`.

## Verdict

CLEAN

The Phantom-0 cleanup implementation is correct for the chosen NaN-propagation method, and the observable re-evaluation path merges existing prediction files against the observable q126 labels correctly for the files present in `outputs/03_models`.

## CRITICAL findings

None.

## HIGH findings

None.

## MEDIUM findings

None.

## LOW findings + suggestions

1. `scripts/152_observable_reeval_all_cycles.R:130-140` — the probability-column fallback is broad for future unknown schemas. It excludes `y_resolved` and other obvious metadata, and it works for all currently discovered files. However, if a future prediction parquet has no known p-column and contains numeric metadata before the probability column, the fallback could select a non-probability numeric column. Suggestion: add current fallback-only columns such as `p_patchtst_v5e` and `p_ew3` to the explicit priority list, and restrict fallback candidates to probability-like names (`^p($|_)`, `^pred`, or similar) plus a numeric range sanity check.

2. `scripts/152_observable_reeval_all_cycles.R:40-54` — `pr_auc()` handles the relevant current files, but degenerate/tied score cases are not fully robust. Empty and all-zero-actual cases return `NA` correctly. All-one predictions are evaluated in row order rather than as a single tied threshold, so the value can be order-dependent. All-positive actual labels also return below 1.0 because the integral does not prepend an initial recall-0 anchor. This does not affect the current discovered files, which have mixed labels and hundreds to thousands of unique probability values, but it is worth hardening if the helper becomes a general metric utility.

3. `scripts/151_targets_observable_fix.R:182-183` writes the audit JSON under `outputs/04_evaluation` without creating that directory. The directory exists in this workspace, so the script runs as intended here. Add `dir.create(dirname(audit_json_path), recursive = TRUE, showWarnings = FALSE)` if the script needs to be portable to a fresh checkout.

## Verified Clean

- `scripts/151_targets_observable_fix.R:103-113` uses `tgt_obs <- copy(tgt)` before mutation, so the in-memory source table is not modified by the cleanup loop.
- `scripts/151_targets_observable_fix.R:105-115` sets `y_tail_qH <- NA_integer_` exactly on `is.na(ret_qH)` rows for `q15`, `q63`, and `q126`.
- Existing observed-label values are preserved. Direct parquet check showed `diff_observed=0` for all three horizons where `ret_qH` is observed.
- Panel rows are preserved. Direct parquet check showed `targets_long_horizon.parquet` and `targets_long_horizon_observable.parquet` both have 8,955 rows, identical dates, and identical columns.
- Cleanup counts match the intended Phantom-0 removal:
  - `q15`: 21 `ret_q15` NA rows now have `y_tail_q15 = NA`; observed rows unchanged.
  - `q63`: 63 `ret_q63` NA rows now have `y_tail_q63 = NA`; observed rows unchanged.
  - `q126`: 126 `ret_q126` NA rows now have `y_tail_q126 = NA`; observed rows unchanged.
- `scripts/151_targets_observable_fix.R:143-153` correctly asserts that no row remains with `ret_qH` NA and non-NA `y_tail_qH`. The explicit M6 assertion covers q126, and the preceding `all_clean` assertion covers all three horizons.
- `scripts/152_observable_reeval_all_cycles.R:67-73` reads the observable target file, normalizes `Date`, and exposes only `(Date, y_q126_obs = y_tail_q126)` for q126 evaluation.
- `scripts/152_observable_reeval_all_cycles.R:147-150` merges predictions to observable labels by `Date` with `all.x = TRUE`. Direct schema/date checks found no duplicate prediction dates, no duplicate target dates, no row expansion, and no unmatched prediction dates in the discovered files.
- Probability-column selection works for all currently discovered q126 prediction files:
  - v5b, v5d sweep, v5d fixed, v5e usmacro, v5f ecos, and v6c stage1 select `p_patchtst`.
  - v6c stage2 variants select `p_meta`.
  - v6a MoE expert files select `p_expert`.
  - v6b DLinear/Informer/TimesNet select `p_dlinear`, `p_informer`, `p_timesnet`.
  - v5e multiseed selects `p_patchtst_v5e` via fallback.
  - v6b EW3 selects `p_ew3` via fallback.
- Observable-only PR-AUC and Spearman IC filtering in `scripts/152_observable_reeval_all_cycles.R:40-62` uses `!is.na(pred) & !is.na(actual)`, so q126 Phantom-0 rows where `y_q126_obs = NA` are excluded from observable metrics.
- `n_phantom_excluded` in `scripts/152_observable_reeval_all_cycles.R:160-161` correctly counts rows where the original prediction file still has `y` but the observable target is now `NA`.
- Existing downstream scripts that continue reading `outputs/02_targets/targets_long_horizon.parquet`, including `scripts/150_stage2_aggregate.R`, are unaffected because `151` writes a new `targets_long_horizon_observable.parquet` file and does not overwrite the original target parquet.
- No new PIT violation is introduced by these two scripts. `151` only rewrites unresolved target labels into a separate observable target file; `152` only re-evaluates already-generated predictions against that observable target.

## Notes

- Direct verification found 43 q126 prediction files discovered by `152` in this workspace. Merges preserved prediction row counts for all 43 files.
- Files with 2,042 prediction rows exclude 108 q126 rows during observable OOS re-evaluation because their prediction windows end at 2026-04-30 while q126 forward returns are unobservable from 2025-11-19 onward in that OOS frame. Files already trained/evaluated on resolved rows only showed `n_phantom_excluded = 0`.
- If future training scripts migrate from `targets_long_horizon.parquet` to `targets_long_horizon_observable.parquet`, audit `fillna(0)` / `fcoalesce(..., 0)` label handling first. Several legacy training scripts fill missing labels with 0; that would silently undo the observable-label semantics unless paired with an explicit resolved-label mask.
