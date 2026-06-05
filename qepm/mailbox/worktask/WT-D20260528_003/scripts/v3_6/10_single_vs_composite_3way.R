#==============================================================================
# Step 3 — Single vs Composite vs Regime-Weighted Composite 3-Way Test v3.6
#
# v3.5 → v3.6 fix:
#   - RF-A2 fix verification: composite ≥ best single family ICIR
#   - 3-way comparison:
#       (a) Single best family (low_vol_neut, dividend_neut, etc.)
#       (b) Equal-weighted 8-family composite_neut
#       (c) Regime-weighted (HMM 4-state) composite_neut
#   - Sector-neut panel으로 비교 (v3.5 sector retention 48.1% 본질 의문 해결)
#   - RF-A2 verdict: (b) or (c) > (a) PASS, else FAIL → terminate 권고
#
# Output:
#   - outputs/v3_6/three_way_ic_comparison_v36.json
#   - outputs/v3_6/family_individual_ic_v36.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
PANEL_NEUT <- file.path(OUT_DIR, "k200_factor_panel_sector_neut_v36.parquet")
PANEL_RAW <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5/k200_factor_panel_v35.parquet")
REGIME_MONTHLY <- file.path(OUT_DIR, "regime_labels_monthly_v36.parquet")

cat("[3-Way IC v3.6] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load panels ----
cat("[1] Loading panels ...\n")
panel_raw <- as.data.table(read_parquet(PANEL_RAW))
panel_raw[, Date := as.Date(Date)]
panel_neut <- as.data.table(read_parquet(PANEL_NEUT))
panel_neut[, Date := as.Date(Date)]

fam_cols <- c("F_value", "F_quality", "F_momentum", "F_growth",
               "F_consensus", "F_low_vol", "F_size", "F_dividend")
neut_cols <- paste0(fam_cols, "_neut")

# ---- 2. Load regime monthly labels ----
cat("[2] Loading regime labels ...\n")
regime <- as.data.table(read_parquet(REGIME_MONTHLY))
regime[, Date := as.Date(Date)]
regime[, ym := format(Date, "%Y-%m")]
regime_lookup <- regime[, .(ym, regime_state)]

# ---- 3. Forward 1-month return per Ticker ----
cat("[3] Loading rawdata + computing forward 1M return ...\n")
rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Close","K200")))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)

# Per Ticker: forward 1M return aligned at sig_date (month-end)
# For each sig_date t, find next month-end m+1, compute log(P_{m+1}/P_t)
sig_dates <- sort(unique(panel_raw$Date))
fwd_returns <- list()

# Build a Ticker × Date → Close lookup
rd_wide_keys <- rd[K200 == 1, .(Date, Ticker, Close)]
setkey(rd_wide_keys, Ticker, Date)

# For each sig_date, find next sig_date (month-end) Close
for (i in seq_along(sig_dates)) {
  if (i == length(sig_dates)) break  # last has no forward
  t0_d <- sig_dates[i]
  t1_d <- sig_dates[i + 1]
  sub_t0 <- rd_wide_keys[Date == t0_d, .(Ticker, P0 = Close)]
  sub_t1 <- rd_wide_keys[Date == t1_d, .(Ticker, P1 = Close)]
  merged <- merge(sub_t0, sub_t1, by = "Ticker")
  merged[, fwd_ret := log(P1 / P0)]
  # Winsorize ±30%
  merged[fwd_ret > 0.3, fwd_ret := 0.3]
  merged[fwd_ret < -0.3, fwd_ret := -0.3]
  merged[, Date := t0_d]
  fwd_returns[[i]] <- merged[, .(Date, Ticker, fwd_ret)]
}
fwd_dt <- rbindlist(fwd_returns, use.names = TRUE)
cat("  fwd_ret rows:", nrow(fwd_dt), " | dates:", length(unique(fwd_dt$Date)), "\n")

# ---- 4. Single-family + composite + composite_neut IC per Date ----
cat("[4] Computing per-Date IC for each family (raw + neut) + composite ...\n")

# Equal-weighted composite per Date
panel_raw[, F_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = fam_cols]
panel_neut[, F_composite_neut := rowMeans(.SD, na.rm = TRUE), .SDcols = neut_cols]

# Merge raw + neut + fwd
panel_all <- merge(panel_raw[, c("Date","Ticker", fam_cols, "F_composite"), with = FALSE],
                    panel_neut[, c("Date","Ticker", neut_cols, "F_composite_neut"), with = FALSE],
                    by = c("Date","Ticker"), all = TRUE)
panel_all <- merge(panel_all, fwd_dt, by = c("Date","Ticker"))
cat("  panel_all rows (with fwd_ret):", nrow(panel_all), "\n")

ic_dates <- sort(unique(panel_all$Date))
ic_per_date <- list()
all_signal_cols <- c(fam_cols, neut_cols, "F_composite", "F_composite_neut")

for (sig_d in ic_dates) {
  sub <- panel_all[Date == sig_d]
  row <- list(Date = sig_d, n = nrow(sub))
  for (sc in all_signal_cols) {
    x <- sub[[sc]]
    y <- sub$fwd_ret
    valid <- !is.na(x) & !is.na(y)
    if (sum(valid) >= 10L) {
      ic <- suppressWarnings(cor(x[valid], y[valid], method = "spearman"))
    } else {
      ic <- NA_real_
    }
    row[[paste0("ic_", sc)]] <- ic
  }
  ic_per_date[[length(ic_per_date) + 1L]] <- row
}
ic_dt <- rbindlist(ic_per_date, fill = TRUE, use.names = TRUE)
ic_dt[, Date := as.Date(Date)]
ic_dt[, ym := format(Date, "%Y-%m")]

cat("  IC per-Date rows:", nrow(ic_dt), "\n")

# ---- 5. ICIR per signal ----
cat("[5] Computing ICIR per signal ...\n")
icir_results <- list()
for (sc in all_signal_cols) {
  ic_col <- paste0("ic_", sc)
  ic_vec <- ic_dt[[ic_col]]
  ic_vec <- ic_vec[!is.na(ic_vec)]
  if (length(ic_vec) >= 12L) {
    mean_ic <- mean(ic_vec)
    sd_ic <- sd(ic_vec)
    icir <- if (sd_ic > 1e-10) mean_ic / sd_ic else NA_real_
    # Harvey-NW t (lag 6 m-end)
    h <- 6L
    n <- length(ic_vec)
    if (n > h) {
      gamma0 <- var(ic_vec)
      gammas <- sapply(1:h, function(k) cov(ic_vec[1:(n-k)], ic_vec[(1+k):n]))
      bartlett_w <- 1 - (1:h) / (h + 1)
      lrv <- gamma0 + 2 * sum(bartlett_w * gammas)
      lrv <- max(lrv, 1e-10)
      se <- sqrt(lrv / n)
      t_nw <- mean_ic / se
    } else {
      t_nw <- NA_real_
    }
    icir_results[[sc]] <- list(
      signal = sc,
      n_obs = length(ic_vec),
      mean_ic = round(mean_ic, 4),
      sd_ic = round(sd_ic, 4),
      icir = round(icir, 4),
      t_nw_lag6 = round(t_nw, 3)
    )
  }
}
icir_dt <- rbindlist(lapply(icir_results, as.data.table), use.names = TRUE)
cat("  ICIR summary (sorted by ICIR):\n")
print(icir_dt[order(-icir)])

# ---- 6. Regime-conditional composite (regime-weighted) ----
cat("[6] Regime-weighted composite (HMM 4-state, post-sector-neut) ...\n")
# Merge regime + ic_dt → compute per-state per-family family IC mean
ic_with_regime <- merge(ic_dt[, .(Date, ym, ic_F_value_neut, ic_F_quality_neut, ic_F_momentum_neut,
                                    ic_F_growth_neut, ic_F_consensus_neut, ic_F_low_vol_neut,
                                    ic_F_size_neut, ic_F_dividend_neut)],
                          regime_lookup, by = "ym")

# Per-state per-family mean IC (using past data only — walk-forward expanding by sig_date)
# For each sig_date t, family weight w_f(state(t-1)) = mean(IC_f | state) using IC up to t-1
ic_with_regime <- ic_with_regime[order(Date)]
state_weights_list <- list()
ic_cols <- c("ic_F_value_neut", "ic_F_quality_neut", "ic_F_momentum_neut",
              "ic_F_growth_neut", "ic_F_consensus_neut", "ic_F_low_vol_neut",
              "ic_F_size_neut", "ic_F_dividend_neut")
fam_labels <- c("value", "quality", "momentum", "growth", "consensus", "low_vol", "size", "dividend")

# Pre-compute lag1 regime (predict t with state(t-1))
ic_with_regime[, regime_state_lag1 := shift(regime_state, n = 1L, type = "lag")]
ic_with_regime[, ym_decision := ym]

# Walk-forward expanding family weights
for (i in seq_len(nrow(ic_with_regime))) {
  past <- ic_with_regime[seq_len(i - 1L)]  # strictly past
  if (nrow(past) < 6L) {
    # bootstrap: use overall mean for first months
    wt <- rep(1 / length(fam_labels), length(fam_labels))
    names(wt) <- fam_labels
    state_weights_list[[i]] <- data.table(
      ym = ic_with_regime$ym[i],
      Date = ic_with_regime$Date[i],
      regime_state = ic_with_regime$regime_state_lag1[i],
      weight_source = "bootstrap_overall",
      t(wt)
    )
    next
  }
  st <- ic_with_regime$regime_state_lag1[i]
  if (is.na(st)) {
    wt <- rep(1 / length(fam_labels), length(fam_labels))
    src <- "no_lag_state"
  } else {
    past_st <- past[regime_state_lag1 == st]
    if (nrow(past_st) >= 3L) {
      wt <- sapply(ic_cols, function(c) mean(past_st[[c]], na.rm = TRUE))
      wt[is.na(wt)] <- 0
      # Black-Litterman shrinkage: keep positive only (long-only), then renormalize
      wt[wt < 0] <- 0
      if (sum(wt) > 1e-10) wt <- wt / sum(wt) else wt <- rep(1 / length(fam_labels), length(fam_labels))
      src <- "state_specific"
    } else {
      wt <- sapply(ic_cols, function(c) mean(past[[c]], na.rm = TRUE))
      wt[is.na(wt)] <- 0
      wt[wt < 0] <- 0
      if (sum(wt) > 1e-10) wt <- wt / sum(wt) else wt <- rep(1 / length(fam_labels), length(fam_labels))
      src <- "all_state_fallback"
    }
  }
  names(wt) <- fam_labels
  state_weights_list[[i]] <- data.table(
    ym = ic_with_regime$ym[i],
    Date = ic_with_regime$Date[i],
    regime_state = st,
    weight_source = src,
    t(wt)
  )
}
state_weights <- rbindlist(state_weights_list, fill = TRUE, use.names = TRUE)
cat("  state_weights rows:", nrow(state_weights), "\n")
cat("  weight_source distribution:\n")
print(table(state_weights$weight_source))

fallback_pct <- mean(state_weights$weight_source == "all_state_fallback")
state_specific_pct <- mean(state_weights$weight_source == "state_specific")
cat("  state_specific:", round(state_specific_pct * 100, 1), "% | fallback:", round(fallback_pct * 100, 1), "%\n")

# ---- 7. Compute alpha_regime_weighted_neut per sig_date ----
cat("[7] Compute regime-weighted composite alpha + IC ...\n")
alpha_rw_list <- list()
for (i in seq_along(ic_dates)) {
  sig_d <- ic_dates[i]
  ym_d <- format(sig_d, "%Y-%m")
  sub <- panel_all[Date == sig_d]
  if (nrow(sub) == 0) next
  wt_row <- state_weights[ym == ym_d]
  if (nrow(wt_row) == 0) {
    wts <- rep(1 / 8, 8); names(wts) <- fam_labels
  } else {
    wts <- as.numeric(wt_row[1, fam_labels, with = FALSE])
    names(wts) <- fam_labels
  }
  # Apply weights to neut family columns
  alpha_rw <- numeric(nrow(sub))
  for (k in seq_along(fam_labels)) {
    nc <- paste0("F_", fam_labels[k], "_neut")
    x <- sub[[nc]]
    x[is.na(x)] <- 0
    alpha_rw <- alpha_rw + wts[k] * x
  }
  alpha_rw_list[[i]] <- data.table(Date = sig_d, Ticker = sub$Ticker, alpha_rw = alpha_rw)
}
alpha_rw_dt <- rbindlist(alpha_rw_list, use.names = TRUE)
panel_alpha_rw <- merge(alpha_rw_dt, fwd_dt, by = c("Date","Ticker"))
cat("  alpha_rw + fwd rows:", nrow(panel_alpha_rw), "\n")

ic_rw <- panel_alpha_rw[, .(ic = suppressWarnings(cor(alpha_rw, fwd_ret, method = "spearman", use = "pairwise.complete"))),
                          by = Date]
ic_rw_vec <- ic_rw$ic[!is.na(ic_rw$ic)]
mean_ic_rw <- mean(ic_rw_vec)
sd_ic_rw <- sd(ic_rw_vec)
icir_rw <- if (sd_ic_rw > 1e-10) mean_ic_rw / sd_ic_rw else NA_real_

# Harvey-NW t for regime-weighted
n_rw <- length(ic_rw_vec)
h <- 6L
if (n_rw > h) {
  gamma0 <- var(ic_rw_vec)
  gammas <- sapply(1:h, function(k) cov(ic_rw_vec[1:(n_rw-k)], ic_rw_vec[(1+k):n_rw]))
  bartlett_w <- 1 - (1:h) / (h + 1)
  lrv <- gamma0 + 2 * sum(bartlett_w * gammas)
  lrv <- max(lrv, 1e-10)
  se <- sqrt(lrv / n_rw)
  t_nw_rw <- mean_ic_rw / se
} else {
  t_nw_rw <- NA_real_
}

# ---- 8. Three-way verdict ----
cat("[8] 3-way verdict ...\n")
# Find best single (across raw + neut individual families)
single_signals <- c(fam_cols, neut_cols)
best_single_icir <- max(icir_dt[signal %in% single_signals, icir], na.rm = TRUE)
best_single_name <- icir_dt[signal %in% single_signals][icir == best_single_icir, signal]
# Equal-weight composite_neut
comp_eq_neut <- icir_dt[signal == "F_composite_neut", icir]
comp_eq_raw <- icir_dt[signal == "F_composite", icir]
# Regime-weighted composite_neut
comp_rw_neut <- round(icir_rw, 4)

cat(sprintf("  (a) Best single        : %s ICIR = %.4f\n", best_single_name, best_single_icir))
cat(sprintf("  (b) Equal-w comp (raw) : F_composite ICIR = %.4f\n", comp_eq_raw))
cat(sprintf("  (b') Equal-w comp (neut): F_composite_neut ICIR = %.4f\n", comp_eq_neut))
cat(sprintf("  (c) Regime-w comp (neut): alpha_rw_neut ICIR = %.4f (t_nw=%.2f)\n", comp_rw_neut, t_nw_rw))

rf_a2_eqw_neut_pass <- comp_eq_neut >= best_single_icir
rf_a2_rw_neut_pass <- comp_rw_neut >= best_single_icir
rf_a2_pass <- rf_a2_eqw_neut_pass || rf_a2_rw_neut_pass
cat(sprintf("  RF-A2 fix: eq-w neut composite >= best single: %s\n",
             if (rf_a2_eqw_neut_pass) "PASS" else "FAIL"))
cat(sprintf("  RF-A2 fix: regime-w composite >= best single: %s\n",
             if (rf_a2_rw_neut_pass) "PASS" else "FAIL"))
cat(sprintf("  RF-A2 overall: %s\n", if (rf_a2_pass) "PASS" else "FAIL"))

# ---- 9. Sector-neut IC retention per family (raw vs neut) ----
sector_retention <- list()
for (fam in fam_labels) {
  raw_sig <- paste0("F_", fam)
  neut_sig <- paste0("F_", fam, "_neut")
  raw_icir <- icir_dt[signal == raw_sig, icir]
  neut_icir <- icir_dt[signal == neut_sig, icir]
  if (length(raw_icir) > 0 && length(neut_icir) > 0 && abs(raw_icir) > 1e-6) {
    retention <- neut_icir / raw_icir
  } else {
    retention <- NA_real_
  }
  sector_retention[[fam]] <- list(family = fam,
                                    raw_icir = round(raw_icir, 4),
                                    neut_icir = round(neut_icir, 4),
                                    retention_pct = round(retention * 100, 1))
}

# Composite retention
comp_retention <- comp_eq_neut / comp_eq_raw
cat("\n[9] Sector-neut IC retention per family:\n")
retention_dt <- rbindlist(lapply(sector_retention, as.data.table), use.names = TRUE)
print(retention_dt)
cat(sprintf("\n  Composite eq-w retention: %.1f%%\n", comp_retention * 100))
rf_a4_pass <- (comp_eq_neut / comp_eq_raw) >= 0.5
cat(sprintf("  RF-A4 fix (composite ≥ 50%% retention): %s\n", if (rf_a4_pass) "PASS" else "FAIL"))

# ---- 10. Output ----
cat("[10] Saving outputs ...\n")

# Family IC per Date
write_parquet(ic_dt, file.path(OUT_DIR, "family_ic_per_date_v36.parquet"))
write_parquet(ic_dt, file.path(STAGE_DIR, "family_ic_per_date_v36.parquet"))

# ICIR results
write_parquet(icir_dt, file.path(OUT_DIR, "family_individual_ic_v36.parquet"))
write_parquet(icir_dt, file.path(STAGE_DIR, "family_individual_ic_v36.parquet"))

# Regime weighted composite IC
write_parquet(panel_alpha_rw, file.path(OUT_DIR, "alpha_regime_weighted_neut_v36.parquet"))
write_parquet(panel_alpha_rw, file.path(STAGE_DIR, "alpha_regime_weighted_neut_v36.parquet"))

# State weights (for downstream Step 5)
write_parquet(state_weights, file.path(OUT_DIR, "regime_family_weights_v36.parquet"))
write_parquet(state_weights, file.path(STAGE_DIR, "regime_family_weights_v36.parquet"))

# Three-way verdict JSON
verdict <- list(
  method = "3-way RF-A2 verdict on sector-neutralized panel",
  best_single = list(name = best_single_name, icir = best_single_icir),
  equal_w_composite_raw = list(name = "F_composite", icir = comp_eq_raw),
  equal_w_composite_neut = list(name = "F_composite_neut", icir = comp_eq_neut),
  regime_w_composite_neut = list(name = "alpha_rw_neut", icir = comp_rw_neut,
                                  t_nw_lag6 = round(t_nw_rw, 3)),
  rf_a2_eqw_neut_passes = rf_a2_eqw_neut_pass,
  rf_a2_rw_neut_passes = rf_a2_rw_neut_pass,
  rf_a2_overall_pass = rf_a2_pass,
  rf_a4_composite_retention_pct = round(comp_retention * 100, 1),
  rf_a4_pass = rf_a4_pass,
  per_family_sector_retention = sector_retention,
  state_specific_pct = round(state_specific_pct * 100, 1),
  fallback_pct = round(fallback_pct * 100, 1),
  fallback_target_lt_30 = fallback_pct < 0.30,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(verdict, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "three_way_ic_comparison_v36.json"))

cat("\n[3-Way IC v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
cat("\n=== v3.6 GRADUATION VERDICT ===\n")
cat(sprintf("  RF-A2 (composite >= single)        : %s\n", if (rf_a2_pass) "PASS" else "FAIL"))
cat(sprintf("  RF-A4 (composite retention >= 50%%) : %s (%.1f%%)\n", if (rf_a4_pass) "PASS" else "FAIL", comp_retention * 100))
cat(sprintf("  Fallback < 30%%                     : %s (%.1f%%)\n", if (fallback_pct < 0.30) "PASS" else "FAIL", fallback_pct * 100))
