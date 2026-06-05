# Cycle 58A — Codex Code Review Log

- **Script**: `scripts/178_q15_3cycle_ensemble.R` (781 lines)
- **Reviewed at**: 2026-05-21 14:35 KST
- **Reviewer**: Codex CLI 0.128.0 (`codex exec --sandbox read-only`)
- **Scope**: code correctness ONLY (strategy / weight design / verdict thresholds excluded)
- **Inputs verified**: 3 Cycle 56A prediction parquets + ensemble_audit.json sample

## Codex Verdict: CONDITIONAL_PASS

> No current-run blocker found, but timezone-dependent `as.Date()` conversion and non-tie-safe PR-AUC computation should be fixed before treating the script as robust across runtimes or tied-score inputs.

## Run-Integrity Snapshot (confirmed by Codex)

- All 3 inputs: 2039 rows, 2039 unique dates, `n_seeds == 5`, no Date/p/y NAs
- 3-way intersection: 2039 (perfect overlap, no silent drop)
- `y_check_mismatch = 0` (predictions y matches `targets_full.parquet::y_tail_q15`)
- All 6 prediction columns (3 standalone + 3 ensemble) have 0 ties (`max_tie_run = 1`) — tie-handling code path NOT triggered this run

## Critical Issues (BLOCK)

**None.** No code bug invalidates the sample run.

## High Severity (FIX) — Latent Bugs (Did Not Fire)

### F1. Date normalization not timezone-agnostic
- **Location**: line ~241, `dt_53h[, Date := as.Date(Date)]` (and 53I/53B parallel lines)
- **Issue**: Arrow `timestamp[ms]` columns are UTC-midnight but display as `09:00:00 KST`. `as.Date(x)` uses local timezone semantics. On a runtime with negative UTC offset (e.g. America), the same timestamp could become the previous calendar date.
- **Why it did not fire**: Q-Lead runtime is Asia/Seoul `+0900` → UTC midnight + 9h = same KST calendar date.
- **Fix proposal (NOT applied in 58A)**: `as.Date(format(Date, "%Y-%m-%d", tz = "UTC"))` or `as.Date(Date, tz = "UTC")` for explicit UTC-anchored conversion.
- **Impact assessment**: 0pp on PR-AUC in current run (verified by Codex: `as.Date(x)` and `as.Date(x, tz="UTC")` both produce identical 2018-01-02 / 2018-01-03 / 2018-01-04 on Seoul tz).

### F2. PR-AUC ties not handled deterministically
- **Location**: line ~98, `ord <- order(p, decreasing = TRUE)` in `pr_auc()`
- **Issue**: `order()` is not stable across tied scores by default; tied-score positives/negatives can produce different PR-AUC depending on input row order.
- **Why it did not fire**: All 6 prediction columns are tie-free (`max_tie_run = 1` for all 12239 scores Codex sampled).
- **Numerical side note**: Trapezoid omits recall-0 anchor — anchored PR-AUC would add ~+0.00274 to each total. Difference is uniform across all methods, so verdict comparisons (Δ vs 53H) are unaffected.
- **Fix proposal (NOT applied in 58A)**: `ord <- order(p, decreasing = TRUE, runif(length(p)))` for random tie-break, or use a dedicated PRAUC library (e.g. `PRROC::pr.curve`).
- **Impact assessment**: 0pp on PR-AUC in current run (verified by Codex tie-count audit).

## Medium / Low (NOTE) — Confirmed Safe

| # | Check | Status |
|---|---|---|
| 1 | 3-way join silent date loss | Sample = 0 drops (Codex confirmed per-input unique dates = 2039 = common count) |
| 2 | `na_safe_mismatch` NA-handling | Correct (NA vs NA = not mismatched, NA vs non-NA = mismatched) |
| 3 | PR-weighted divide-by-zero | Cannot fire (NA→0 + `pmax(., 0.01)` clamp before normalize) |
| 4 | Regime `fcase()` exhaustiveness | Exhaustive over OOS_START..OOS_END (COVID 2020-2021 / Recent 2022-04-30 / Calm default) |
| 5 | Regime weights sum-to-1 | All 3 branches sum to 1.0 (verified by Codex) |
| 6 | Bootstrap reseeding | `bootstrap_ci_pr` single seed for 1000 reps (correct, no duplicate); `period_bootstrap_ci` `s <- s + 1L` per segment (no seed reuse) |
| 7 | `save_pred` Date class preservation | Verified Arrow schema = `date32[day]` for output parquets |
| 8 | `setnames(dt_out, "p", p_col)` rename | Correct (Codex schema dump confirms `p_ew3` / `p_weighted` / `p_regime_cond` as column names) |
| 9 | `stopifnot()` blocking | Did not block incorrectly (`n_seeds == 5` holds for all 3 inputs) |

## Disposition (Q-Lead — code-only scope, strategy disposition separate)

- **F1 timezone**: ACCEPT_DOCUMENTED, defer fix. Reason: Q-Lead runtime is permanently Asia/Seoul `+0900`; risk = 0 unless production redeployment moves to non-KST host. Add to backlog as "tz-agnostic Date conversion utility" for future cycles. Not blocking 58A.
- **F2 ties**: ACCEPT_DOCUMENTED, defer fix. Reason: PatchTST mean5 + averaged ensembles produce continuous-valued scores; tie probability essentially 0 (Codex verified 0/12239 ties). Risk only materializes if future cycles use rank-based or quantized prediction sources. Add to backlog. Not blocking 58A.
- **Medium/Low (9 items)**: All confirmed PASS by Codex.

## AX-008 Verification Triangulation (code-only sub-scope)

| Source | Verdict | Notes |
|---|---|---|
| Forge (Q-Lead execution) | PASS | Run completed, all 10 steps printed, 4 outputs (3 parquets + 1 JSON) written |
| Codex (code review) | CONDITIONAL_PASS | 0 BLOCK, 2 FIX latent (didn't fire), Medium 9/9 PASS |
| Architect | N/A this cycle | Not invoked (ensemble-only, no novel infra) |

**AX-008 minimum 2/3 PASS**: ACHIEVED (Forge PASS + Codex CONDITIONAL_PASS).

## Code Correctness Conclusion

The Cycle 58A script ran correctly for the provided inputs and outputs. The 2 latent FIX items do not affect the current verdict (`ENSEMBLE_NULL`) because:
- F1: 0pp impact on Asia/Seoul runtime
- F2: 0 ties in actual prediction scores (verified)

Both are added to backlog for future hardening but do not block 58A interpretation.
