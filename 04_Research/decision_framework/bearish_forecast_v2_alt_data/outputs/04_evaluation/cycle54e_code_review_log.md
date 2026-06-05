# Cycle 54E — Code Review Log

**Date**: 2026-05-21
**Scope**: Code correctness only (per Q-Lead mandate 2026-05-21)
**Files**:
- `scripts/155_patchtst_v5e_q126_10seed_strict.py`
- `scripts/156_10seed_strict_observable_aggregate.R`

---

## Round 1 — Codex Initial Review

**Codex CLI**: codex-cli 0.128.0 / model: gpt-5.5 default
**Prompt**: `/tmp/cycle54e_codex_review_prompt.md` (10-section binding checklist)

### Verdict per section

| Section | Status |
|---|---|
| A_strict_determinism (Python) | PASS |
| B_per_seed_reproducibility (Python) | PASS |
| C_10seed_mean_calculation (Python) | PASS |
| D_observable_mask (R) | PASS |
| E_period_balanced (R) | PASS |
| F_std_reduction (R) | PASS |
| G_headline_verdict (R) | **FAIL** |
| H_reuse_strategy (Python) | PASS |
| I_pit_walkforward (Python) | PASS |
| J_schema_compat | PASS |

**Overall**: FAIL → Fix critical bugs before run

### Critical bug (HIGH)

```
File: scripts/156_10seed_strict_observable_aggregate.R
Line: 424-429, 482-490 (original numbering)
Issue: Period robustness is documented as a 3/3 segment check, but
       q126_mean10_seg filters out NA lift rows before counting.
       If any configured segment is skipped by the n_obs/n_events threshold,
       period_robust_q126_mean10 can still be TRUE on 1/1 or 2/2 valid
       segments, allowing HEADLINE_STRONG_VALIDATED without all three
       periods being robust.
Fix:   period_robust_q126_mean10 <- n_seg_total_q126_mean10 == length(SEGMENTS) &&
                                    n_seg_lift_gt1_q126_mean10 == length(SEGMENTS)
       Otherwise route high-PR cases to HEADLINE_PARTIAL.
```

### Minor concern

```
File: scripts/156_10seed_strict_observable_aggregate.R
Line: 477-488 (original)
Issue: HEADLINE_UNAVAILABLE branch not safely reachable if mean10 q126 row
       is absent. headline_q126_obs becomes length 0, so
       if (!is.na(headline_q126_obs)) errors.
Fix:   Use length(headline_q126_obs) == 1 && !is.na(headline_q126_obs)
       OR fail fast on required mean10 file absence.
```

### Summary

> "Python strict-det, seed reset, source reuse, 10-seed probability mean, observable masking, and std logic pass; R headline period-robust logic can over-validate when any segment is skipped."

---

## Round 2 — Fixes Applied (Q-Lead direct)

### HIGH fix — Period robustness full coverage

**File**: `scripts/156_10seed_strict_observable_aggregate.R` lines ~462-474

**Before**:
```r
q126_mean10_seg <- seg_dt[label == "mean10" & target == "y_tail_q126" & !is.na(lift)]
n_seg_lift_gt1_q126_mean10 <- sum(q126_mean10_seg$lift > 1)
n_seg_total_q126_mean10 <- nrow(q126_mean10_seg)
period_robust_q126_mean10 <- (n_seg_lift_gt1_q126_mean10 == n_seg_total_q126_mean10) &&
  (n_seg_total_q126_mean10 > 0)
```

**After**:
```r
q126_mean10_seg <- seg_dt[label == "mean10" & target == "y_tail_q126" & !is.na(lift)]
n_seg_lift_gt1_q126_mean10 <- sum(q126_mean10_seg$lift > 1)
n_seg_total_q126_mean10 <- nrow(q126_mean10_seg)
n_seg_configured <- length(SEGMENTS)
period_robust_q126_mean10 <- (n_seg_total_q126_mean10 == n_seg_configured) &&
  (n_seg_lift_gt1_q126_mean10 == n_seg_configured)
period_full_coverage_q126_mean10 <- (n_seg_total_q126_mean10 == n_seg_configured)
```

### MINOR fix — Scalar guard for headline values

**File**: `scripts/156_10seed_strict_observable_aggregate.R` lines ~515-527

**Before**:
```r
headline_q126_obs <- mean_dt[label == "mean10" & target == "y_tail_q126", obs_pr_auc]
...
if (!is.na(headline_q126_obs)) {
```

**After**:
```r
.pull_scalar <- function(x) if (length(x) == 1) x else NA_real_
headline_q126_obs  <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_pr_auc])
headline_q126_orig <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", orig_pr_auc])
headline_q126_ci_lo <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_ci_lo])
headline_q126_ci_hi <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_ci_hi])
v_q126_10 <- std_combined[target == "y_tail_q126" & source == "merged10", stability_verdict]
if (length(v_q126_10) == 0) v_q126_10 <- NA_character_

if (length(headline_q126_obs) == 1 && !is.na(headline_q126_obs)) {
```

### JSON traceability addition

Added to `verdict_json$period_balanced`:
- `period_full_coverage_q126_mean10` (boolean)
- `n_seg_configured` (integer)
- `codex_fix_note` (string)

---

## Round 3 — Additional Q-Lead Findings (Pre-emptive, beyond codex scope)

### Critical insight — 54C SOURCE seeds contain UNDETECTED collapsed predictions

During sanity-check of 54C source data alignment for Cycle 54E reuse, Q-Lead discovered:

| seed | p_max | p_p99 | logit_median | COLLAPSED |
|---|---|---|---|---|
| 42 | 4.84e-01 | 0.4631 | -0.61 | FALSE |
| **123** | **3.14e-09** | **0.0000** | **-41.42** | **TRUE** |
| 456 | 5.43e-01 | 0.5035 | -0.88 | FALSE |
| **789** | **5.57e-04** | **0.0000** | **-17.77** | borderline (p_max barely > 1e-4 threshold) |
| 1024 | 3.90e-01 | 0.3590 | -1.30 | FALSE |

Cycle 54C did NOT have logit-collapse detector (only Cycle 54A FIXED did). Therefore:
- 54C 5-seed mean PR-AUC = 0.5617 is computed across **3 healthy + 1 collapsed + 1 borderline** predictions.
- Arithmetic mean of {~0.0, ~0.0, ~0.3, ~0.4, ~0.5} = uniformly shrunk values; ranking dominated by 3 healthy seeds.
- PR-AUC is ranking-only metric → ranking survives even with collapsed contributions.
- However, **mean prediction calibration is broken** — absolute thresholding meaningless.

### Code addition (non-breaking)

**File**: `scripts/156_10seed_strict_observable_aggregate.R`

Added:
1. **R-side logit-collapse detector** in `eval_seed()` (mirrors Python `detect_logit_collapse`)
2. **Per-seed `p_max / p_p99 / p_mean / logit_median / detected_collapse`** columns in `per_seed_dt`
3. **Step 1b — Collapse audit** prints summary table + flags collapsed/borderline seeds
4. **JSON `collapse_audit_summary` block** with per-target counts + per-seed details + interpretation

This surfaces the finding without altering the 5-seed/10-seed mean calculation (which honors the original 54C intent — include all seeds).

---

## Round 4 — Codex Recheck on Fixes (COMPLETE)

**Codex CLI**: codex-cli 0.128.0 / Methodology: parse R script + execute test R snippets via Rscript -e to validate logic
**Prompt**: `/tmp/cycle54e_codex_recheck_prompt.md`
**Output JSON**: `outputs/04_evaluation/cycle54e_codex_review_round4_recheck.json`

### Verdict

```json
{
  "review_scope": "code_only_recheck",
  "fix_status": {
    "high_period_robust": "FIXED",
    "minor_scalar_guard": "FIXED"
  },
  "new_bugs_introduced": [],
  "additions_review": {
    "logit_collapse_audit_step1b": "PASS",
    "per_seed_p_max_diagnostic": "PASS"
  },
  "verdict_overall": "PASS",
  "recommendation": "Approved as-is",
  "summary_one_line": "period_robust_q126_mean10 now requires full configured segment coverage plus all lift>1; scalar guards/fallbacks, period_balanced JSON fields, and collapse diagnostics are present and parse cleanly."
}
```

### Codex verification methodology (notable)

Codex actively ran small R test snippets via `Rscript -e ...` to verify:
- R script parses cleanly (`PARSE_OK`)
- `data.table` scalar subset behavior (returns length-1 vector on hit, length-0 on miss — confirming the `.pull_scalar()` helper is needed)
- Stability verdict value extraction via the same data.table syntax

This is more thorough than pure static review.

### Final verdict status

| Section | Round 1 | Round 4 |
|---|---|---|
| Python (sections A, B, C, H, I) | PASS | n/a (not re-reviewed; no Python changes since round 1) |
| R observable mask (D) | PASS | (preserved) |
| R period balanced (E) | PASS | (preserved) |
| R std reduction (F) | PASS | (preserved) |
| **R headline verdict (G)** | **FAIL** | **PASS (fixed)** |
| R schema compat (J) | PASS | (preserved) |
| Step 1b collapse audit (new addition) | n/a | PASS |
| Per-seed p_max diagnostic (new addition) | n/a | PASS |

### Final overall verdict

**APPROVED FOR PRODUCTION RUN** — Codex code-review chain complete (2 rounds).
- Python script (155) running in background since 2026-05-21 10:14 KST.
- R aggregate script (156) ready to run after Python finishes.

---

## Files

| File | Status |
|---|---|
| `scripts/155_patchtst_v5e_q126_10seed_strict.py` | PASS round 1 (no changes needed) |
| `scripts/156_10seed_strict_observable_aggregate.R` | FAIL round 1 → FIXED round 2+3 → recheck round 4 |
| `outputs/04_evaluation/cycle54e_code_review_log.md` | This file |
| `/tmp/cycle54e_codex_review_prompt.md` | Round 1 prompt (full 10-section checklist) |
| `/tmp/cycle54e_codex_review_stdout.txt` | Round 1 codex full output |
| `/tmp/cycle54e_codex_recheck_prompt.md` | Round 4 prompt |
| `/tmp/cycle54e_codex_recheck_stdout.txt` | Round 4 codex output |

---

## AX-008 Compliance

Per Q-Lead 2026-05-21 mandate ("Codex 코드 검증 의무 (코드만)"):
- **Forge** (Q-Lead direct): Python + R aggregate authored and run
- **Codex** (code only): Round 1 review + Round 4 recheck on fixes

This is a **partial 2-source AX-008** (Forge + Codex). Architect is NOT engaged this cycle (Q-Lead mandate explicit "code only"). Forge multi-seed audit type is **EXEMPT** from full 3/3 AX-008 (per `M5_AX_008 = "EXEMPT (Forge multi-seed audit + Codex code review only; NOT admit cycle)"` in checklist).
