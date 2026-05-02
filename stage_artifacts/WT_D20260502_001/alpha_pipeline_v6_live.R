#==============================================================================
# v6: Generate LIVE alpha at 2026-04-30 (no fwd_ret available yet) — appended
# to walk-forward alpha_schedule. This is the as_of_date alpha vector.
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ, ".cache")

req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))
state5 <- readRDS(file.path(SA_DIR, "alpha_pipeline_v5_state.rds"))
v2 <- readRDS(file.path(SA_DIR, "alpha_pipeline_v2_state.rds"))

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# Same NW_t function
nw_t_stat <- function(ic_vec, lag = 3) {
  m <- length(ic_vec); ic_vec <- ic_vec[!is.na(ic_vec)]; m <- length(ic_vec)
  if (m < 5) return(NA_real_)
  mu <- mean(ic_vec); v0 <- mean((ic_vec - mu)^2)
  bw <- min(lag, floor(m/4))
  if (bw >= 1) {
    s <- 0
    for (l in 1:bw) {
      w_l <- 1 - l / (bw + 1)
      cov_l <- mean((ic_vec[1:(m - l)] - mu) * (ic_vec[(l + 1):m] - mu))
      s <- s + 2 * w_l * cov_l
    }
    nw_var <- v0 + s
  } else { nw_var <- v0 }
  nw_se <- sqrt(max(nw_var, 1e-12) / m)
  mu / nw_se
}

panel <- v2$panel
months_seq <- v2$months_seq

# Latest sig_date is 2026-04-30
as_of_date <- as.Date(req$as_of_date)
live_sig <- max(months_seq[months_seq <= as_of_date])
cat(sprintf("Live alpha sig_date: %s (as_of=%s)\n", live_sig, as_of_date))

ALL_CANDIDATES <- c("Q07_Earnings_Stability", "Q33_Earnings_Persistence",
                    "Q25_Ohlson_O", "Q35_CashBased_OpProf", "Q08_Composite_Quality",
                    "D43_Skewness", "R13_NCSKEW")
TRAIN_WINDOW <- 36L
NW_THRESHOLD <- 2.5
SELECT_TOP_K <- 4L

#=== Get training factor IC at live_sig ========================================
# Re-load IC time series for ALL candidates
winsor_panel <- copy(panel)
for (f in ALL_CANDIDATES) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}
analysis_panel <- winsor_panel[eligible == TRUE & !is.na(fwd_ret)]

compute_ic_by_date <- function(dt, factor_col) {
  if (!factor_col %in% colnames(dt)) return(data.table())
  dt[!is.na(get(factor_col)) & !is.na(fwd_ret),
     .(ic = if (.N >= 30) cor(get(factor_col), fwd_ret, method = "spearman") else NA_real_),
     by = sig_date][!is.na(ic)]
}

factor_ic_panels <- list()
for (f in ALL_CANDIDATES) {
  ic_dt <- compute_ic_by_date(analysis_panel, f)
  if (nrow(ic_dt) > 0) {
    ic_dt[, factor := f]
    factor_ic_panels[[f]] <- ic_dt
  }
}
factor_ic_long <- rbindlist(factor_ic_panels, fill = TRUE)
sig_dates_sorted <- sort(unique(factor_ic_long$sig_date))

# Training window for live_sig: 36 months prior to live_sig (excluding live_sig)
# But fwd_ret for live_sig is unavailable, so live_sig itself isn't in IC panel.
# Use last 36 months of IC data (which is months ≤ live_sig with fwd_ret available)
train_dates <- tail(sig_dates_sorted[sig_dates_sorted < live_sig], TRAIN_WINDOW)
cat(sprintf("Training window: %s to %s (%d months)\n",
            min(train_dates), max(train_dates), length(train_dates)))

# Per-factor stats
train_stats <- data.table()
for (f in ALL_CANDIDATES) {
  fic <- factor_ic_long[factor == f & sig_date %in% train_dates, ic]
  if (length(fic) < 12) next
  ic_mean <- mean(fic, na.rm = TRUE)
  ic_std <- sd(fic, na.rm = TRUE)
  icir <- ic_mean / ic_std
  nw_t <- nw_t_stat(fic)
  train_stats <- rbind(train_stats, data.table(
    factor = f, ic_mean = ic_mean, icir = icir, nw_t = nw_t, n_train = length(fic)
  ))
}

cat("\nTraining stats at live_sig:\n")
print(train_stats[order(-icir)])

# Selection
selected <- train_stats[nw_t >= NW_THRESHOLD & ic_mean > 0]
if (nrow(selected) == 0) {
  selected <- train_stats[ic_mean > 0][order(-icir)][1:min(2L, .N)]
}
selected <- selected[order(-abs(icir))][1:min(SELECT_TOP_K, .N)]
selected[, weight := abs(icir) / sum(abs(icir))]

cat("\nSelected factors for live alpha:\n")
print(selected)

#=== Apply to LIVE cross-section at live_sig ===================================
# Use coverage_min=0.15 to capture Q07/Q25 at fiscal year-end
fdt_live <- load_month_factors(live_sig, coverage_min = 0.15)
fdt_live <- fdt_live[Factor_Name %in% selected$factor]
fdt_live_wide <- dcast(fdt_live, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

# Eligible universe at live_sig
live_panel <- panel[sig_date == live_sig & eligible == TRUE,
                     .(Ticker, sig_date, ym, eligible,
                       def_A_bad, def_B_bad, def_C_bad,
                       FRED_MRS_lag, MSM_lag, Category_lag)]
live_panel <- merge(live_panel, fdt_live_wide, by = "Ticker", all.x = TRUE)
# Winsorize
for (f in selected$factor) {
  if (f %in% colnames(live_panel)) {
    live_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}

# Build alpha
live_panel[, alpha := 0]
for (i in seq_len(nrow(selected))) {
  f <- selected$factor[i]
  w <- selected$weight[i]
  if (f %in% colnames(live_panel)) {
    live_panel[, alpha := alpha + fifelse(is.na(get(f)), 0, get(f)) * w]
  }
}
n_avail <- live_panel[, rowSums(!is.na(.SD)), .SDcols = selected$factor]
live_panel[n_avail == 0, alpha := NA_real_]

# Coverage
cov_check <- function(row) sum(!is.na(row)) / length(row)
live_panel[, coverage := apply(.SD, 1, cov_check), .SDcols = selected$factor]

# Alpha z-score (cross-sectional)
live_panel[!is.na(alpha), alpha_z := scale(alpha)]
# Confidence
live_panel[, z_extreme := pmax(abs(alpha_z), 0)]
live_panel[, z_extreme_penalty := pmin(z_extreme / 3.0, 1.0)]
mean_icir_train <- mean(selected$icir, na.rm = TRUE)
stability_score <- max(min(mean_icir_train / 0.4, 1.0), 0.0)
live_panel[, confidence := pmax(pmin(
  coverage * 0.5 + stability_score * 0.3 + (1 - z_extreme_penalty) * 0.2, 1.0), 0.0)]

# Final alpha (scaled to expected return %)
current_bad_C <- as.logical(live_panel[1, def_C_bad])
SCALE_BAD <- 0.015
SCALE_NORMAL <- 0.005
scale_now <- ifelse(isTRUE(current_bad_C), SCALE_BAD, SCALE_NORMAL)
live_panel[!is.na(alpha_z), alpha_final := alpha_z * scale_now * confidence]
# Mean-zero
mu_a <- mean(live_panel$alpha_final, na.rm = TRUE)
live_panel[, alpha_final := alpha_final - mu_a]

cat(sprintf("\nLive alpha summary at %s:\n", live_sig))
cat(sprintf("  n_total=%d valid=%d\n", nrow(live_panel),
            sum(!is.na(live_panel$alpha))))
cat(sprintf("  alpha mean=%.6f sd=%.6f range=[%.4f, %.4f]\n",
            mean(live_panel$alpha_final, na.rm = TRUE),
            sd(live_panel$alpha_final, na.rm = TRUE),
            min(live_panel$alpha_final, na.rm = TRUE),
            max(live_panel$alpha_final, na.rm = TRUE)))
cat(sprintf("  confidence mean=%.3f sd=%.3f\n",
            mean(live_panel$confidence, na.rm = TRUE),
            sd(live_panel$confidence, na.rm = TRUE)))
cat(sprintf("  current_bad_state=%s scale_used=%.3f\n", current_bad_C, scale_now))

#=== Append to alpha_schedule ==================================================
schedule <- as.data.table(arrow::read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
cat(sprintf("\nExisting alpha_schedule: %d rows × %d sig_dates\n",
            nrow(schedule), uniqueN(schedule$sig_date)))

# Live row append
live_append <- live_panel[!is.na(alpha_final), .(
  sig_date,
  Ticker,
  alpha = alpha_final,
  fwd_ret = NA_real_,  # unknown future
  def_C_bad,
  alpha_zscore = alpha_z,
  z_extreme,
  z_extreme_penalty,
  confidence
)]

# Existing has different column structure; reconcile
common_cols <- intersect(colnames(schedule), colnames(live_append))
schedule_sub <- schedule[, ..common_cols]
live_sub <- live_append[, ..common_cols]
combined_schedule <- rbind(schedule_sub, live_sub, fill = TRUE)

cat(sprintf("Combined alpha_schedule: %d rows × %d sig_dates (added %s)\n",
            nrow(combined_schedule), uniqueN(combined_schedule$sig_date), live_sig))

arrow::write_parquet(combined_schedule, file.path(SA_DIR, "alpha_scores.parquet"))
cat("alpha_scores.parquet UPDATED with live row.\n")

# Save state
saveRDS(list(
  live_sig = live_sig,
  live_panel = live_panel,
  selected = selected,
  current_bad_C = current_bad_C,
  scale_now = scale_now,
  combined_schedule = combined_schedule,
  SCALE_BAD = SCALE_BAD,
  SCALE_NORMAL = SCALE_NORMAL,
  train_stats = train_stats
), file.path(SA_DIR, "alpha_pipeline_v6_state.rds"))

cat("\nv6 LIVE alpha COMPLETE.\n")
