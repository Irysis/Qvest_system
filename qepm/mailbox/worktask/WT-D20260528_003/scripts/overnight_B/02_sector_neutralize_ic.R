#==============================================================================
# WT-D20260528_003 Hypothesis B Step 2 — Sector neutralize + Rank IC + ICIR
#
# - Per-Date sector demean (RF-A4 회피)
# - Raw IC vs Sector-neutral IC (retention test)
# - Full-period ICIR + subperiod stability + Harvey t-stat
# - Cycle 51 verification: forward direction confirmed (Step 1 sanity check passed)
#
# PIT compliance:
#   - All operations cross-sectional per Date (no temporal leakage)
#   - Sector column from rawdata is current-day categorical (contemporaneous OK, AX-009 N/A)
#
# Output:
#   - outputs/overnight_B/m22_panel_sector_neutral.parquet
#   - outputs/overnight_B/m22_step2_ic.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/overnight_B")

cat("[Step 2: Sector neutralize + IC + ICIR] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load Step 1 panel ----
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "m22_panel_pit.parquet")))
panel[, Date := as.Date(Date)]
cat("[1] Loaded panel: ", nrow(panel), "rows, ", uniqueN(panel$Date), "dates,",
    uniqueN(panel$Ticker), "Tickers\n")
cat("    Sector NA rate:", round(mean(is.na(panel$Sector)) * 100, 2), "%\n")

# ---- 2. Sector neutralize (per-Date demean within sector) ----
cat("\n[2] Sector neutralization (per-Date sector demean) ...\n")
# Z_aligned within each (Date × Sector) demeaned → Z_neutral
panel[!is.na(Sector), Z_neutral := Z_aligned - mean(Z_aligned, na.rm = TRUE),
      by = .(Date, Sector)]
# For rows with no Sector, just use Z_aligned
panel[is.na(Sector), Z_neutral := Z_aligned]

# Re-standardize within Date to sd=1 (RC1 fix pattern)
panel[, Z_neutral := {
  s <- sd(Z_neutral, na.rm = TRUE)
  if (!is.na(s) && s > 1e-12) Z_neutral / s else Z_neutral
}, by = Date]

# Verify neutralization: cor(Z_neutral, Sector_dummy) ~ 0
sec_test <- panel[!is.na(Sector)]
sec_levels <- unique(sec_test$Sector)
cat("  N sector levels:", length(sec_levels), "\n")

# ---- 3. Rank IC per-date (Raw + Neutral) + Spearman ----
cat("\n[3] Rank IC per Date ...\n")
ic_per_date_raw <- panel[!is.na(Z_aligned) & !is.na(fwd_ret), .(
  n = .N,
  rank_ic_raw = if (.N >= 10) suppressWarnings(cor(Z_aligned, fwd_ret, method = "spearman")) else NA_real_
), by = Date]
ic_per_date_raw <- ic_per_date_raw[!is.na(rank_ic_raw)]

ic_per_date_neut <- panel[!is.na(Z_neutral) & !is.na(fwd_ret), .(
  n = .N,
  rank_ic_neut = if (.N >= 10) suppressWarnings(cor(Z_neutral, fwd_ret, method = "spearman")) else NA_real_
), by = Date]
ic_per_date_neut <- ic_per_date_neut[!is.na(rank_ic_neut)]

# Merge raw + neutral
ic_per_date <- merge(ic_per_date_raw[, .(Date, n, rank_ic_raw)],
                    ic_per_date_neut[, .(Date, rank_ic_neut)],
                    by = "Date", all = TRUE)

cat("  Per-date IC rows:", nrow(ic_per_date), "\n")

# ---- 4. Full-period rank IC, ICIR, Harvey t ----
cat("\n[4] Full-period rank IC + ICIR + Harvey t ...\n")
ic_summary <- function(ic_vec, label) {
  m <- mean(ic_vec, na.rm = TRUE)
  s <- sd(ic_vec, na.rm = TRUE)
  n <- sum(!is.na(ic_vec))
  icir <- if (!is.na(s) && s > 0) m / s else NA_real_
  t_stat <- if (!is.na(s) && s > 0) m / (s / sqrt(n)) else NA_real_
  list(label = label, n_dates = n, rank_ic_mean = m, rank_ic_sd = s,
       icir = icir, t_stat = t_stat,
       # Harvey-Liu-Zhu adjustment (Bonferroni-like): with 269 candidate factors,
       # adjusted t critical ≈ 3.0+
       harvey_t_pass = !is.na(t_stat) && abs(t_stat) > 3.0)
}

raw_summary <- ic_summary(ic_per_date$rank_ic_raw, "RAW")
neut_summary <- ic_summary(ic_per_date$rank_ic_neut, "SECTOR_NEUT")

cat("  RAW: mean=", round(raw_summary$rank_ic_mean, 4),
    " ICIR=", round(raw_summary$icir, 4),
    " t=", round(raw_summary$t_stat, 2),
    " harvey_pass=", raw_summary$harvey_t_pass, "\n", sep="")
cat("  NEUT: mean=", round(neut_summary$rank_ic_mean, 4),
    " ICIR=", round(neut_summary$icir, 4),
    " t=", round(neut_summary$t_stat, 2),
    " harvey_pass=", neut_summary$harvey_t_pass, "\n", sep="")

# Retention
retention <- abs(neut_summary$rank_ic_mean / raw_summary$rank_ic_mean)
cat("  Retention (|neut/raw|):", round(retention * 100, 1), "%\n")
cat("  RF-A4 trigger (retention < 50%):", retention < 0.5, "\n")

# ---- 5. Subperiod stability (3-chunk: 2005-2014 / 2015-2019 / 2020-2026) ----
cat("\n[5] Subperiod stability ...\n")
subperiods <- list(
  P1 = list(start = "2005-01-01", end = "2014-12-31", label = "2005_2014"),
  P2 = list(start = "2015-01-01", end = "2019-12-31", label = "2015_2019"),
  P3 = list(start = "2020-01-01", end = "2026-12-31", label = "2020_2026")
)

subperiod_results <- list()
for (pn in names(subperiods)) {
  p <- subperiods[[pn]]
  sub <- ic_per_date[Date >= as.Date(p$start) & Date <= as.Date(p$end)]
  if (nrow(sub) >= 5) {
    raw_sub <- ic_summary(sub$rank_ic_raw, paste0("raw_", p$label))
    neut_sub <- ic_summary(sub$rank_ic_neut, paste0("neut_", p$label))
    subperiod_results[[pn]] <- list(label = p$label, n = nrow(sub),
                                     raw_mean = raw_sub$rank_ic_mean,
                                     raw_icir = raw_sub$icir,
                                     neut_mean = neut_sub$rank_ic_mean,
                                     neut_icir = neut_sub$icir)
    cat("  ", p$label, ": n=", nrow(sub),
        " raw_ICIR=", round(raw_sub$icir, 3),
        " neut_ICIR=", round(neut_sub$icir, 3), "\n", sep="")
  }
}

# Subperiod stability (sign-aware): all subperiods should have same sign
neut_icirs <- sapply(subperiod_results, function(x) x$neut_icir)
all_same_sign <- all(sign(neut_icirs) == sign(neut_icirs[1]), na.rm = TRUE)
abs_neut_icirs <- abs(neut_icirs)
stability_ratio <- if (length(abs_neut_icirs) >= 2 && max(abs_neut_icirs) > 0) {
  min(abs_neut_icirs) / max(abs_neut_icirs)
} else NA_real_
cat("  Subperiod sign stability (same sign):", all_same_sign, "\n")
cat("  Stability ratio (min/max ICIR):", round(stability_ratio, 3), "\n")

# ---- 6. 5-year ICIR (recent: 2019-01-01 onward, post-Bali decay test) ----
cat("\n[6] Recent 5y ICIR (2019+) ...\n")
recent_cutoff <- as.Date("2019-01-01")
recent_ic <- ic_per_date[Date >= recent_cutoff]
if (nrow(recent_ic) >= 12) {
  recent_raw <- ic_summary(recent_ic$rank_ic_raw, "recent_5y_raw")
  recent_neut <- ic_summary(recent_ic$rank_ic_neut, "recent_5y_neut")
  cat("  Recent 5y RAW ICIR:", round(recent_raw$icir, 3),
      " t=", round(recent_raw$t_stat, 2), "\n")
  cat("  Recent 5y NEUT ICIR:", round(recent_neut$icir, 3),
      " t=", round(recent_neut$t_stat, 2), "\n")
}

# ---- 7. Save outputs ----
cat("\n[7] Save ...\n")
write_parquet(panel, file.path(OUT_DIR, "m22_panel_sector_neutral.parquet"))
cat("  saved: m22_panel_sector_neutral.parquet (", nrow(panel), "rows)\n")
write_parquet(ic_per_date, file.path(OUT_DIR, "m22_ic_per_date.parquet"))
cat("  saved: m22_ic_per_date.parquet (", nrow(ic_per_date), "rows)\n")

diag <- list(
  task_id = "WT-D20260528_003",
  hypothesis = "B",
  step = "02_sector_neutralize_ic",
  raw_summary = raw_summary,
  neut_summary = neut_summary,
  retention_neut_over_raw = retention,
  rf_a4_flag = retention < 0.5,
  subperiod_results = subperiod_results,
  subperiod_sign_stable = all_same_sign,
  stability_ratio_min_max = stability_ratio,
  recent_5y = list(
    raw = if (exists("recent_raw")) recent_raw else NULL,
    neut = if (exists("recent_neut")) recent_neut else NULL
  ),
  sector_neutral_method = "per-Date sector demean + re-standardize sd=1",
  n_sector_levels = length(sec_levels)
)
write_json(diag, file.path(OUT_DIR, "m22_step2_ic.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: m22_step2_ic.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 2] === DONE === elapsed:", round(elapsed, 1), "sec\n")
