#==============================================================================
# WT-D20260528_003 v3.7 — Step 3: Single vs Composite Diagnostic
#
# RF-A2 회피 의무 — v1/v3.5/v3.6 3 cycles lesson:
#   "Composite paradigm < best single factor" — composite dilution
#
# Test scenarios:
#   (a) Each single factor (sector-neut Z_neut) ICIR
#   (b) Composite ALL 12 (equal-weight): 모든 12 factor 합성
#   (c) Composite TOP 6 (full ICIR_neut 상위): D22 + D43 + M22 + D44 + L44 + CR08
#   (d) Composite TOP 4 distribution+lottery: D43 + D44 + M22 + L44
#   (e) Composite TOP 3 (best): D22 + D43 + M22
#
# Mandate: composite ICIR >= best single ICIR
# RF-A2 fail if composite < single (per spec instruction)
#
# Output:
#   - outputs/v3_7/single_vs_composite_diagnostic.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")

TOP12 <- c("D43_Skewness", "D44_Kurtosis", "L44_Vol_Ret_Asymmetry",
           "CR08_Volume_Price_Divergence", "Q07_Earnings_Stability",
           "M22_Max_Return", "L42_Vol_Skewness", "CR01_Sector_Comovement",
           "Q11_Net_Margin", "D22_Tracking_Error", "Q32_Interest_Coverage",
           "L33_AbsRet_Vol_Corr")

cat("[Step 3: Single vs Composite] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load neut panel ----
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "top12_factor_panel_neut.parquet")))
panel[, Date := as.Date(Date)]
cat("  panel:", nrow(panel), "rows |", uniqueN(panel$Date), "dates\n\n")

neut_cols <- paste0(TOP12, "_neut")

# ---- 2. ICIR per single factor (already from Step 2) ----
cat("[2] Re-compute single ICIR per factor (verification) ...\n")
single_dt <- data.table()
for (fc in TOP12) {
  fc_n <- paste0(fc, "_neut")
  if (!fc_n %in% names(panel)) next
  ic <- panel[!is.na(fwd_ret) & !is.na(get(fc_n)),
              .(rank_ic = if (.N >= 10) suppressWarnings(cor(get(fc_n), fwd_ret, method="spearman")) else NA_real_),
              by = Date][!is.na(rank_ic)]
  m <- mean(ic$rank_ic, na.rm = TRUE)
  s <- sd(ic$rank_ic, na.rm = TRUE)
  single_dt <- rbind(single_dt, data.table(
    Factor_Name = fc,
    icir = if (!is.na(s) && s > 0) m / s else NA_real_,
    rank_ic = m,
    t_stat = if (!is.na(s) && s > 0) m / (s / sqrt(nrow(ic))) else NA_real_,
    n_dates = nrow(ic)
  ))
}
setorder(single_dt, -icir)
print(single_dt)
cat("\n")

# Best single = top ICIR
best_single <- single_dt[1]
cat("[BEST SINGLE]:", best_single$Factor_Name, " ICIR=", round(best_single$icir, 4),
    " t=", round(best_single$t_stat, 2), "\n\n")

# ---- 3. Composite builders ----
compute_composite_ic <- function(panel, cols, label) {
  # Equal-weight composite over 'cols' (already Z_neut standardized)
  # Per-Date: mean of cols (NA-safe), then rank IC vs fwd_ret
  panel_copy <- copy(panel)

  # Composite = row-wise mean
  panel_copy[, composite := rowMeans(.SD, na.rm = TRUE), .SDcols = cols]
  # Re-standardize per Date (re-Z cross-section composite)
  panel_copy[, composite_z := {
    z <- composite
    s <- sd(z, na.rm = TRUE)
    if (!is.na(s) && s > 0) (z - mean(z, na.rm = TRUE)) / s else z
  }, by = Date]

  ic <- panel_copy[!is.na(fwd_ret) & !is.na(composite_z),
                   .(rank_ic = if (.N >= 10) suppressWarnings(cor(composite_z, fwd_ret, method="spearman")) else NA_real_),
                   by = Date][!is.na(rank_ic)]

  m <- mean(ic$rank_ic, na.rm = TRUE)
  s <- sd(ic$rank_ic, na.rm = TRUE)
  list(
    label = label,
    n_factors = length(cols),
    cols = cols,
    icir = if (!is.na(s) && s > 0) m / s else NA_real_,
    rank_ic = m,
    t_stat = if (!is.na(s) && s > 0) m / (s / sqrt(nrow(ic))) else NA_real_,
    n_dates = nrow(ic)
  )
}

# ---- 4. Build composites ----
cat("[4] Composite scenarios ...\n")

composites <- list()

# (b) ALL 12
composites$ALL12 <- compute_composite_ic(panel, neut_cols, "ALL12")

# (c) TOP 6 (full ICIR_neut 상위)
top6_factors <- single_dt$Factor_Name[1:6]
top6_cols <- paste0(top6_factors, "_neut")
composites$TOP6 <- compute_composite_ic(panel, top6_cols, "TOP6")

# (d) TOP 4 distribution+lottery (D43 + D44 + M22 + L44)
top4_dist_lottery <- c("D43_Skewness", "D44_Kurtosis", "M22_Max_Return", "L44_Vol_Ret_Asymmetry")
top4_cols <- paste0(top4_dist_lottery, "_neut")
composites$TOP4_DIST_LOTTERY <- compute_composite_ic(panel, top4_cols, "TOP4_DIST_LOTTERY")

# (e) TOP 3 (best 3 by single ICIR_neut)
top3_factors <- single_dt$Factor_Name[1:3]
top3_cols <- paste0(top3_factors, "_neut")
composites$TOP3 <- compute_composite_ic(panel, top3_cols, "TOP3")

# (f) TOP 5 selective (best 5)
top5_factors <- single_dt$Factor_Name[1:5]
top5_cols <- paste0(top5_factors, "_neut")
composites$TOP5 <- compute_composite_ic(panel, top5_cols, "TOP5")

# (g) High-retention only (retention > 70% from Step 2)
# D43/D44/L44/CR08/M22/L42/CR01/D22/L33 (대략 9)
high_retention <- c("D43_Skewness", "D44_Kurtosis", "L44_Vol_Ret_Asymmetry",
                     "CR08_Volume_Price_Divergence", "M22_Max_Return",
                     "L42_Vol_Skewness", "CR01_Sector_Comovement", "D22_Tracking_Error",
                     "L33_AbsRet_Vol_Corr")
hr_cols <- paste0(high_retention, "_neut")
composites$HIGH_RETENTION <- compute_composite_ic(panel, hr_cols, "HIGH_RETENTION_9")

# Print composite results
comp_dt <- rbindlist(lapply(names(composites), function(nm) {
  cmp <- composites[[nm]]
  data.table(
    composite = cmp$label,
    n_factors = cmp$n_factors,
    icir = cmp$icir,
    rank_ic = cmp$rank_ic,
    t_stat = cmp$t_stat,
    n_dates = cmp$n_dates
  )
}))
setorder(comp_dt, -icir)
print(comp_dt)
cat("\n")

# ---- 5. RF-A2 verdict ----
cat("[5] RF-A2 verdict ...\n")
best_composite_icir <- max(comp_dt$icir, na.rm = TRUE)
best_composite_label <- comp_dt[which.max(icir), composite]
verdict_dt <- data.table(
  metric = c("best_single_icir", "best_composite_icir", "best_single_factor", "best_composite_label"),
  value = c(round(best_single$icir, 4), round(best_composite_icir, 4),
            best_single$Factor_Name, best_composite_label)
)
print(verdict_dt)

rf_a2_pass <- best_composite_icir >= best_single$icir
cat("\n  RF-A2 (composite >= single)?", if (rf_a2_pass) "PASS ✅" else "FAIL ❌", "\n")
cat("  Diff (composite - single):", round(best_composite_icir - best_single$icir, 4), "\n\n")

# ---- 6. Diagnostic save ----
diag <- list(
  task_id = "WT-D20260528_003",
  step = "03_single_vs_composite_diagnostic",
  scenarios = "best_single vs ALL12 / TOP6 / TOP5 / TOP4_DIST_LOTTERY / TOP3 / HIGH_RETENTION_9",
  single_per_factor = lapply(seq_len(nrow(single_dt)), function(i) as.list(single_dt[i])),
  composites = lapply(names(composites), function(nm) {
    cmp <- composites[[nm]]
    list(label = cmp$label, n_factors = cmp$n_factors,
         cols = cmp$cols,
         icir = cmp$icir, rank_ic = cmp$rank_ic, t_stat = cmp$t_stat,
         n_dates = cmp$n_dates)
  }),
  rf_a2_verdict = list(
    best_single = list(factor = best_single$Factor_Name,
                        icir = best_single$icir,
                        t_stat = best_single$t_stat),
    best_composite = list(label = best_composite_label,
                           icir = best_composite_icir),
    pass = rf_a2_pass,
    diff = best_composite_icir - best_single$icir
  )
)

write_json(diag, file.path(OUT_DIR, "single_vs_composite_diagnostic.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: single_vs_composite_diagnostic.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 3] === DONE === elapsed:", round(elapsed, 1), "sec\n")
