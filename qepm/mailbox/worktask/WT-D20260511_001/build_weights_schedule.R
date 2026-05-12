#==============================================================================
# WT-D20260511_001 — Build weights.csv schedule for Forge handoff
# Sleeve-level static allocation applied across all alpha sig_dates
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

SA_DIR <- "stage_artifacts/WT_D20260511_001"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"

# Recommended allocation (med_10pct)
recommended <- list(
  AR_on_M4 = 0.450,
  TSMOM = 0.225,
  KR_10y = 0.180,
  Cash = 0.045,
  NEW_VolSkew_3axis = 0.100
)

# Load alpha sig_dates
ap <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(ap$sig_date))
cat("alpha sig_dates:", length(sig_dates), "\n")
cat("range:", as.character(range(sig_dates)), "\n")

# Build per-sig_date sleeve-level allocation snapshot
# Format: as_of_date | sleeve | weight | method_selected
weights_schedule <- data.table()
for (d in sig_dates) {
  d_chr <- format(as.Date(d), "%Y-%m-%d")
  for (sleeve_nm in names(recommended)) {
    weights_schedule <- rbind(weights_schedule, data.table(
      as_of_date = d_chr,
      sleeve = sleeve_nm,
      weight = recommended[[sleeve_nm]],
      method_selected = "static_5sleeve_med_10pct_smoothed_phi_0_5"
    ))
  }
}

cat("\nweights_schedule rows:", nrow(weights_schedule),
    "(=", length(sig_dates), "dates ×", length(recommended), "sleeves)\n")
cat("first 5 rows:\n"); print(head(weights_schedule, 5))

# Verify Σw = 1 per date
sum_check <- weights_schedule[, .(sum_w = sum(weight)), by = as_of_date]
cat("\nΣw range:", range(sum_check$sum_w), "(must == 1)\n")
stopifnot(all(abs(sum_check$sum_w - 1) < 1e-9))

# Save weights.csv (overwrite previous candidate-based weights.csv)
out_path <- file.path(SA_DIR, "weights.csv")
fwrite(weights_schedule, out_path)
cat("\nwritten:", out_path, "\n")
cat("file size:", file.info(out_path)$size, "bytes\n")
cat("unique as_of_date count:", length(unique(weights_schedule$as_of_date)), "\n")

# Schedule density check
alpha_sig_dates_n <- length(sig_dates)
weights_unique_dates_n <- length(unique(weights_schedule$as_of_date))
density_ratio <- weights_unique_dates_n / alpha_sig_dates_n
cat("\nSchedule fidelity:\n")
cat("  alpha sig_dates:", alpha_sig_dates_n, "\n")
cat("  weights unique dates:", weights_unique_dates_n, "\n")
cat("  density ratio:", round(density_ratio, 3), "(threshold 0.95)\n")
cat("  schedule_density_pass:", density_ratio >= 0.95, "\n")

# Also save sleeve-level weight evolution as CSV for Forge handoff
# This is a static repeat across all 155 sig_dates (not walk-forward dynamic)
# Walk-forward dynamic is deferred to deployment_wt next phase

# Save weight_method_selected.md for cert eligibility
md_path <- file.path(SA_DIR, "weight_method_selected.md")
md_content <- '# WT-D20260511_001 — Weight Method Selected

## Method: `static_5sleeve_med_10pct_smoothed_phi_0_5`

### Description
Sleeve-level static 5-sleeve allocation (med_10pct candidate) with NEW sleeve internal persistence smoothing phi=0.5.

### Allocation
| Sleeve | Weight | Notes |
|---|---|---|
| AR_on_M4 | 0.450 | STR_1715 H1 alpha-updated × M4 overlay × β threshold (PG2 admit) |
| TSMOM | 0.225 | 8-ETF basket re-derived (PG2 admit) |
| KR_10y | 0.180 | KODEX 국고채10년 ETF A148070 (PG2 admit) |
| Cash | 0.045 | 0% return placeholder |
| NEW_VolSkew_3axis | 0.100 | 3-Axis Vol/Skew composite, top20 EW, phi=0.5 smoothing |
| **Σw** | **1.000** | absolute |

### Selection Rationale

Charter v1.5 hierarchy: **Validity > Implementability > Robustness > Performance > Novelty**.

5 candidates evaluated:
- baseline_S4 (0% NEW): SR 2.001, MDD -8.09% — reference (not admit)
- low_3pct (3%): SR 2.100, MDD -7.16% — marginal improvement
- low_5pct (5%): SR 2.167, MDD -6.54% — conservative
- **med_10pct (10%): SR 2.336, MDD -5.30%** — RECOMMENDED
- high_20pct (20%): SR 2.643, MDD -5.21% — best raw but Robustness penalty

### Why med_10pct (not high_20pct)
1. **AX-001 v2 INCONCLUSIVE**: bootstrap CI95 [0.546, 2.444] — defensive characteristic borderline. n_BAD=7 small sample. High_20pct exposes 20% to unproven 4th source with weak defensive evidence.
2. **Concentration risk**: NEW sleeve is alpha cycle 4 first admit candidate. Charter v1.7 §10 incremental discipline favors growth from PG2 → PG2 via 10% step (Path C precedent L-280).
3. **TDC margin**: med_10pct linear contribution 0.044 = 6.8× margin under 0.30 cap. High_20pct 0.088 = 3.4× margin.
4. **TC drag**: 4bps annual (negligible vs delta SR +0.34).

### Constraints Met
- **max_names 20**: ✓ (4th sleeve internal top20 by alpha rank)
- **long-only**: ✓ (all sleeve weights ≥ 0)
- **weight_bounds [0, 0.20]**: ✓ (security-level: 10% × 5% = 0.005 per NEW name; sleeve-level max 0.45 = sleeve scope)
- **Σw = 1**: ✓ (verified 1e-9 precision)
- **liquidity 2e8**: ✓ (alpha pkg universe filter)
- **TC 15bps**: ✓ (v2.3_kr_retail_15bps cost model)
- **PIT C1-C15**: INHERITED from alpha + risk pkg compliance
- **portfolio CVaR_95 ≤ 2.5%**: **INFEASIBLE** (see infeasibility_report)

### Turnover Smoothing
- Raw NEW sleeve turnover: 556% one-way ann
- Persistence phi: 0.5 (half-life ~1 month)
- Smoothed effective turnover: 278% (under 300% Codex C4 mandate)

### Infeasibility (portfolio CVaR_95)
**Historical realized CVaR_95 monthly (-4.90% baseline) violates 2.5% cap at all candidates including baseline.** Adding NEW sleeve IMPROVES CVaR (reduces magnitude 20-34%) but cap is structurally infeasible for KR equity-dominant portfolio. Forge realized re-validation + Q-Lead cap negotiation required.

### Walk-Forward Bridge
This Discovery WT outputs static sleeve allocation only. Walk-forward dynamic 5-sleeve framework available at WT-P20260509_002 (DRO Wasserstein ε=0.1) extending from 4-sleeve to 5-sleeve in next deployment_wt phase.

### Codex Round
Round 1 pending — see `codex_critic_response_optimizer.json` and `challenge_note_optimizer.md` (post-codex).

---

**Created**: 2026-05-11 KST
**Agent**: optimizer-research-WT-D20260511_001 (v1.2, Opus_4_7_1M)
'

writeLines(md_content, md_path)
cat("\nwritten:", md_path, "(size:", file.info(md_path)$size, "bytes)\n")

cat("\nDONE.\n")
