# Cycle 54B — Code Review Log (Codex Critic Round 폐기, code-only scope)

**Coordinator mandate 2026-05-21**: 5단계 Codex Critic Round 흐름 폐기 → codex-companion task (code-only review). Design verdict (abs15 primary 전환 vs orig retain) Q-Lead 독립 평가 (본 log 외 별도 final response).

**Reviewer**: Codex (gpt-5.5 via codex-companion task --effort high)
**Target file**: `scripts/138_cycle54b_abs15_reeval.R` (initial v1)
**Review date**: 2026-05-21 KST
**Items audited**: 8 (numerical / implementation correctness only)

## Result Summary

| # | Topic | Status | Action |
|---|-------|--------|--------|
| 1 | abs15 forward semantics | OK | none |
| 2 | PR-AUC trapezoidal | **BUG** | **fix applied** (anchored PR curve) |
| 3 | Moving-block bootstrap | OK / WARN dep | retained block_len=21, documented dep risk |
| 4 | Date POSIXct→Date / merge | WARN tz | retained (KST 09:00, no current shift) |
| 5 | Segment boundary inclusion | OK | none |
| 6 | NA handling in yearly rate | **BUG** | **fix applied** (label-specific denominators) |
| 7 | Spearman on rounded values | **BUG** | **fix applied** (raw values) |
| 8 | `%||%` definition order | WARN / BUG | **fix applied** (moved to top) |

## Fixes Applied

### Item 2 — PR-AUC anchoring (BUG, material)
**Codex finding**: The unanchored trapezoidal PR-AUC understates by integrating over all sorted rows including flat-recall negative steps, and omits the initial recall segment from 0 → first positive. Perfect ranking returns 1 - 1/events instead of 1.

**Empirical verification** (3 test cases):
- Perfect ranking [1,1,1,0,0,0]: unanchored 0.667, anchored 1.000
- Random predictions: unanchored 0.098, anchored 0.098 (no impact at random)
- Informative predictions (p=0.5y+0.5u): unanchored 0.992, anchored 1.000

**Impact on Cycle 54B headlines**:
- Best orig q126 c53E_v2: 0.4747 → 0.4778 (+0.0031, +0.65%)
- Best abs15 c53E_v2: 0.1421 → 0.1578 (+0.0157, +11.0%)
- Spearman rank corr (orig vs abs15): 0.7048 → 0.7269 (+0.022)
- Best cycle consistency UNCHANGED (c53E_v2_q126 dominant under both labels)

**Fix**:
```r
# Old (unanchored, BUG)
ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
prec <- cumsum(y_ord) / seq_along(y_ord)
rec <- cumsum(y_ord) / sum(y_ord)
n <- length(prec)
sum(diff(rec) * (prec[-1] + prec[-n]) / 2)

# New (anchored, fixed per Codex)
ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
tp <- cumsum(y_ord); pos <- which(y_ord == 1L)
rec <- c(0, tp[pos] / sum(y_ord))
prec <- c(1, tp[pos] / pos)
n <- length(prec)
sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
```

### Item 6 — Label-specific yearly denominators (BUG, defensive)
**Codex finding**: View A NA→0 convention biases denominators (2025 has 29 NA abs15 rows due to incomplete forward window). View B subsetting by `!is.na(y_tail_q126)` could exclude rows where abs15 is known but orig is NA.

**Empirical**: In this dataset, orig has NO NAs (1386 events / 8829 known = legacy convention upstream sets NA→0). abs15 has 126 NA (boundary). NA-alignment ratio = 0.9859 (orig OK & abs15 OK in 8829 rows, mismatched in 126 boundary rows where abs15 NA but orig OK).

**Fix**:
- View A (OOS legacy 53M) RETAINED (NA→0 .N denominator) — apples-to-apples with 53M reported SD=0.0714. Resulting SD: orig=0.2751, abs15=0.0715, abs10=0.1533.
- View A_known (NEW): non-missing per-label denominator. SD: orig=0.2751, abs15=0.0715, abs10=0.1533 (identical in OOS since orig has no NAs in OOS period).
- View B (Full 1990-2026): per-label denominators. SD: orig=0.2272, abs15=0.1968, abs10=0.2398.
- na_alignment_orig_vs_abs15 field added (0.9859 → boundary-row mismatch disclosed).

### Item 7 — Spearman on raw (unrounded) values (BUG)
**Codex finding**: `flat_tbl` rounds pr_auc and ic_rank to 4 decimals before merge into `merged_rank`, which can introduce artificial ties.

**Empirical impact**: Pre-fix spearman = 0.7048; Post-fix (raw) = 0.7269. Small but real drift — Codex finding correct.

**Fix**:
```r
# New: build merged_rank from raw all_rows entries, not from rounded flat_tbl
raw_orig <- rbindlist(lapply(raw_rows_q126[label=="orig"], ...))
raw_abs15 <- rbindlist(lapply(raw_rows_q126[label=="abs15"], ...))
merged_rank <- merge(raw_orig, raw_abs15, by = "cycle")
```

### Item 8 — `%||%` operator order (WARN/BUG)
**Codex finding**: First R 5.0.x verified that base R 4.5+ provides `%||%`, so script ran. But fragile on older R versions where base lacks it.

**Fix**: Moved local `%||%` definition to top of script (line 39, before first use at line 354).

## WARN items NOT fixed (intentional)

### Item 3 — Block-bootstrap dep risk
Codex noted: "blocks formed after dropping NA rows compresses internal time gaps, and block_len=21 is short relative to 126-day forward label dependence — CI can be too narrow."

**Q-Lead decision (code-review boundary respected)**: WARN noted but NOT applied. block_len=21 retained for 53M consistency. Future cycle (54C+) may adopt block_len=63 (1 quarter) or 126 (= forecast horizon) for fully conservative CI.

### Item 4 — Date tz handling
Codex noted: "as.Date(POSIXct) uses local TZ unless tz= supplied; current 09:00 KST timestamps safe but fragile for future timezone-shifted files."

**Q-Lead decision**: WARN noted but NOT applied. Current orig-label cross-check 100% match confirms zero current impact. Add `as.Date(Date, tz="Asia/Seoul")` in future scripts if Date columns ever shift to UTC midnight.

## Code review log file
- prompt: `outputs/04_evaluation/cycle54b_codex_review_prompt.txt`
- response: `outputs/04_evaluation/cycle54b_codex_response.json` (8 items, JSON structured)
- code-fixed script: `scripts/138_cycle54b_abs15_reeval.R` (v2, anchored + raw + ordered)

## Re-run verification
After all 4 BUG fixes applied:
- Best orig q126: c53E_v2_q126 PR=0.4778 (was 0.4747)
- Best abs15: c53E_v2_q126 PR=0.1578 (was 0.1421)
- Best consistency: TRUE (unchanged)
- Spearman PR (orig vs abs15): 0.7269 (was 0.7048)
- Spearman IC (orig vs abs15): 0.8855 (unchanged)
- All cycle-level rankings stable; absolute PR-AUC values slightly higher; relative ordering preserved.
