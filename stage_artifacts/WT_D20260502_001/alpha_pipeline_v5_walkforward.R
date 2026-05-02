#==============================================================================
# WT-D20260502_001 Alpha Pipeline v5 — Walk-Forward Validation (Codex C3 ACCEPT)
#
# Addresses Codex concerns:
#   C1 (RF-A7): multi-sig-date alpha_scores.parquet (≥60 sig_dates) — ACCEPT
#   C2:        composite-level monotonicity (not factor-level mean) — PARTIAL
#   C3 (RF-A6): walk-forward factor selection + regime + ICIR weights — ACCEPT
#   C4:        AX-001 defense ratio strengthen disclosure — PARTIAL
#   C7 (RF-A4): pre/post sector neutralization comparison — ACCEPT
#   C8 (RF-A5): historical top-decile ADV20 — ACCEPT
#
# Walk-forward design:
#   - Train window: 36 months rolling
#   - OOS test: 1 month forward (each sig_date)
#   - At each sig_date: select factors with NW_t >= 2.5 in training period
#                       compute ICIR weights from training period
#                       apply to OOS month
#                       record OOS IC + OOS LS return
#   - Effective starting OOS sig_date: 2011-01 (first 36m + 2008-2010 burn-in)
#
# Outputs:
#   alpha_scores.parquet (multi-sig-date schedule)
#   alpha_validation.json (walk-forward diagnostics + new audits)
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ, ".cache")

req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))
LIQ_THRESHOLD <- as.numeric(req$universe_definition$liquidity_min_won_20d_avg)

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# Load v2 state (panel + factor data)
v2 <- readRDS(file.path(SA_DIR, "alpha_pipeline_v2_state.rds"))
panel <- v2$panel
months_seq <- v2$months_seq

cat("\n==== WT-D20260502_001 Alpha Pipeline v5 (Walk-Forward) ====\n")
cat(sprintf("Total sig_dates: %d (%s to %s)\n",
            length(months_seq), min(months_seq), max(months_seq)))

# Universe of candidates (5 primary Quality + 2 aux skewness)
ALL_CANDIDATES <- c("Q07_Earnings_Stability", "Q33_Earnings_Persistence",
                    "Q25_Ohlson_O", "Q35_CashBased_OpProf", "Q08_Composite_Quality",
                    "D43_Skewness", "R13_NCSKEW")

# Winsorize panel
winsor_panel <- copy(panel)
for (f in ALL_CANDIDATES) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}
analysis_panel <- winsor_panel[eligible == TRUE & !is.na(fwd_ret)]

# IC computation helper (Spearman per sig_date)
compute_ic_by_date <- function(dt, factor_col) {
  if (!factor_col %in% colnames(dt)) return(data.table(sig_date = as.Date(NA), ic = NA_real_))
  dt[!is.na(get(factor_col)) & !is.na(fwd_ret),
     .(ic = if (.N >= 30) cor(get(factor_col), fwd_ret, method = "spearman") else NA_real_),
     by = sig_date][!is.na(ic)]
}

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

#=== Walk-forward params ======================================================
TRAIN_WINDOW <- 36L  # months
NW_THRESHOLD <- 2.5  # factor selection threshold (looser than 3.0 for inclusion)
SELECT_TOP_K <- 4L   # cap selection at top-4 by ICIR (parsimony)

# Pre-compute factor IC time series for ALL candidates (full panel)
cat("Computing factor IC time series for all candidates...\n")
factor_ic_panels <- list()
for (f in ALL_CANDIDATES) {
  ic_dt <- compute_ic_by_date(analysis_panel, f)
  if (nrow(ic_dt) > 0) {
    ic_dt[, factor := f]
    factor_ic_panels[[f]] <- ic_dt
  }
}
factor_ic_long <- rbindlist(factor_ic_panels, fill = TRUE)
setkey(factor_ic_long, factor, sig_date)

cat(sprintf("Factor IC panel: %d rows × %d unique factors × %d sig_dates\n",
            nrow(factor_ic_long), uniqueN(factor_ic_long$factor),
            uniqueN(factor_ic_long$sig_date)))

#=== Walk-forward: per OOS month, select factors + compute weights from training ===
sig_dates_sorted <- sort(unique(factor_ic_long$sig_date))
oos_start_idx <- TRAIN_WINDOW + 1L  # start OOS at month 37
if (oos_start_idx > length(sig_dates_sorted)) {
  stop("Not enough sig_dates for walk-forward TRAIN_WINDOW=", TRAIN_WINDOW)
}
oos_dates <- sig_dates_sorted[oos_start_idx:length(sig_dates_sorted)]
cat(sprintf("Walk-forward: %d OOS months from %s to %s (TRAIN_WINDOW=%d)\n",
            length(oos_dates), min(oos_dates), max(oos_dates), TRAIN_WINDOW))

# Function to run walk-forward at one OOS date
walk_forward_step <- function(oos_date) {
  train_dates <- sig_dates_sorted[sig_dates_sorted < oos_date &
                                   sig_dates_sorted >= (sig_dates_sorted[which(sig_dates_sorted == oos_date)] - 36 * 31)]
  if (length(train_dates) < TRAIN_WINDOW - 5) {
    return(list(oos_date = oos_date, status = "INSUFFICIENT_TRAIN", n_train = length(train_dates)))
  }
  # Build per-factor stats from training period
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
  # Selection: NW_t >= 2.5 + ic_mean > 0 + top-K by |ICIR|
  selected <- train_stats[nw_t >= NW_THRESHOLD & ic_mean > 0]
  if (nrow(selected) == 0) {
    # Fallback: top-2 by ICIR (positive) regardless of NW threshold
    selected <- train_stats[ic_mean > 0][order(-icir)][1:min(2L, .N)]
  }
  selected <- selected[order(-abs(icir))][1:min(SELECT_TOP_K, .N)]

  # ICIR weights
  selected[, weight := abs(icir) / sum(abs(icir))]

  # Apply to OOS data
  oos_panel <- analysis_panel[sig_date == oos_date]
  if (nrow(oos_panel) == 0) {
    return(list(oos_date = oos_date, status = "NO_OOS_DATA"))
  }
  selected_factors <- selected$factor
  oos_panel[, alpha_oos := 0]
  for (i in seq_len(nrow(selected))) {
    f <- selected$factor[i]
    w <- selected$weight[i]
    if (f %in% colnames(oos_panel)) {
      oos_panel[, alpha_oos := alpha_oos + fifelse(is.na(get(f)), 0, get(f)) * w]
    }
  }
  # NA handling: if zero factors available for ticker, NA
  n_avail <- oos_panel[, rowSums(!is.na(.SD)), .SDcols = selected_factors]
  oos_panel[n_avail == 0, alpha_oos := NA_real_]

  # OOS IC
  oos_ic <- if (sum(!is.na(oos_panel$alpha_oos) & !is.na(oos_panel$fwd_ret)) >= 30) {
    cor(oos_panel$alpha_oos, oos_panel$fwd_ret, method = "spearman",
        use = "pairwise.complete.obs")
  } else { NA_real_ }

  # OOS LS portfolio (top-bot quintile)
  if (sum(!is.na(oos_panel$alpha_oos)) >= 30) {
    oos_panel[, q_bin := cut(alpha_oos,
                              breaks = quantile(alpha_oos, probs = seq(0, 1, 0.2), na.rm = TRUE),
                              include.lowest = TRUE, labels = FALSE)]
    ls_top <- mean(oos_panel[q_bin == 5, fwd_ret], na.rm = TRUE)
    ls_bot <- mean(oos_panel[q_bin == 1, fwd_ret], na.rm = TRUE)
    ls_ret <- ls_top - ls_bot
  } else {
    ls_top <- NA; ls_bot <- NA; ls_ret <- NA
  }

  # OOS bad-state info
  bad_state <- as.logical(oos_panel[1, def_C_bad])

  list(
    oos_date = oos_date,
    status = "OK",
    n_train = nrow(train_stats),
    selected_factors = selected_factors,
    weights = setNames(selected$weight, selected_factors),
    oos_ic = oos_ic,
    oos_ls_ret = ls_ret,
    oos_ls_top = ls_top,
    oos_ls_bot = ls_bot,
    oos_n = nrow(oos_panel),
    bad_state = bad_state,
    oos_panel = oos_panel[, .(sig_date, Ticker, alpha_oos, fwd_ret, def_C_bad)]
  )
}

# Run walk-forward in parallel
cat("Running walk-forward (parallel)...\n")
n_workers <- min(8L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

wf_results <- future_lapply(oos_dates, walk_forward_step,
                             future.globals = c("ALL_CANDIDATES", "factor_ic_long",
                                                 "sig_dates_sorted", "TRAIN_WINDOW",
                                                 "NW_THRESHOLD", "SELECT_TOP_K",
                                                 "analysis_panel", "nw_t_stat"),
                             future.packages = c("data.table"))
plan(sequential)

# Aggregate
wf_summary <- rbindlist(lapply(wf_results, function(r) {
  if (r$status != "OK") return(NULL)
  data.table(
    sig_date = r$oos_date,
    oos_ic = r$oos_ic,
    oos_ls_ret = r$oos_ls_ret,
    n_factors = length(r$selected_factors),
    factors_str = paste(r$selected_factors, collapse = "+"),
    bad_state = r$bad_state
  )
}), fill = TRUE)

cat(sprintf("\nWalk-forward results: %d OOS months\n", nrow(wf_summary)))
cat(sprintf("OOS rank IC: mean=%.4f sd=%.4f ICIR=%.3f n_pos/n=%d/%d (%.1f%%)\n",
            mean(wf_summary$oos_ic, na.rm = TRUE),
            sd(wf_summary$oos_ic, na.rm = TRUE),
            mean(wf_summary$oos_ic, na.rm = TRUE) / sd(wf_summary$oos_ic, na.rm = TRUE),
            sum(wf_summary$oos_ic > 0, na.rm = TRUE),
            sum(!is.na(wf_summary$oos_ic)),
            100 * mean(wf_summary$oos_ic > 0, na.rm = TRUE)))

oos_nw_t <- nw_t_stat(wf_summary$oos_ic)
cat(sprintf("OOS NW-t (lag=3): %.4f\n", oos_nw_t))

# OOS LS portfolio annualized
oos_ls_sr_full <- mean(wf_summary$oos_ls_ret, na.rm = TRUE) /
                   sd(wf_summary$oos_ls_ret, na.rm = TRUE) * sqrt(12)
oos_ls_sr_bad <- {
  bad_sub <- wf_summary[bad_state == TRUE & !is.na(oos_ls_ret)]
  if (nrow(bad_sub) > 5) {
    mean(bad_sub$oos_ls_ret) / sd(bad_sub$oos_ls_ret) * sqrt(12)
  } else { NA }
}
cat(sprintf("OOS LS annualized SR: full=%.3f bad-state=%.3f\n",
            oos_ls_sr_full, oos_ls_sr_bad))

# OOS Conditional IC (bad vs normal)
ic_oos_bad <- mean(wf_summary[bad_state == TRUE, oos_ic], na.rm = TRUE)
ic_oos_norm <- mean(wf_summary[bad_state == FALSE, oos_ic], na.rm = TRUE)
ratio_oos <- ic_oos_bad / abs(ic_oos_norm)
n_bad_oos <- sum(wf_summary$bad_state == TRUE & !is.na(wf_summary$oos_ic))
cat(sprintf("OOS Conditional IC: bad=%.4f (n=%d) norm=%.4f ratio=%.2f\n",
            ic_oos_bad, n_bad_oos, ic_oos_norm, ratio_oos))

# Subperiod stability (OOS)
wf_summary[, subp := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2011-2013",
  sig_date < as.Date("2020-01-01"), "P2_2014-2019",
  default = "P3_2020-2026"
)]
sub_stats_oos <- wf_summary[, .(
  ic_mean = mean(oos_ic, na.rm = TRUE),
  n = .N,
  pos_share = mean(oos_ic > 0, na.rm = TRUE)
), by = subp]
cat("\nOOS subperiod stability:\n")
print(sub_stats_oos)
sub_stab_oos <- mean(sub_stats_oos$ic_mean > 0, na.rm = TRUE)
cat(sprintf("OOS subperiod stability score: %.2f\n", sub_stab_oos))

# Factor selection frequency over walk-forward
factor_selections <- unlist(lapply(wf_results, function(r) {
  if (r$status == "OK") r$selected_factors else NULL
}))
selection_freq <- table(factor_selections)
cat("\nFactor selection frequency (walk-forward):\n")
print(sort(selection_freq, decreasing = TRUE))

# Compose alpha schedule (Date × Ticker × score)
alpha_schedule_list <- lapply(wf_results, function(r) {
  if (r$status != "OK") return(NULL)
  r$oos_panel[!is.na(alpha_oos)]
})
alpha_schedule <- rbindlist(alpha_schedule_list, fill = TRUE)
alpha_schedule[, alpha := alpha_oos]
alpha_schedule[, alpha_oos := NULL]
cat(sprintf("\nAlpha schedule: %d rows × %d sig_dates\n",
            nrow(alpha_schedule), uniqueN(alpha_schedule$sig_date)))

# Add confidence_vector (per-row coverage proxy)
# At each sig_date, confidence = 0.5 * baseline + 0.5 * z_extreme_inv
alpha_schedule[, alpha_zscore := scale(alpha), by = sig_date]
alpha_schedule[, z_extreme := pmax(abs(alpha_zscore), 0)]
alpha_schedule[, z_extreme_penalty := pmin(z_extreme / 3.0, 1.0)]
alpha_schedule[, confidence := 0.5 + 0.5 * (1 - z_extreme_penalty)]

# Save schedule
arrow::write_parquet(alpha_schedule, file.path(SA_DIR, "alpha_scores.parquet"))
cat(sprintf("Saved: alpha_scores.parquet (multi-sig-date schedule)\n"))

# Composite-level monotonicity (proper, on alpha_schedule)
cat("\n==== Composite-level monotonicity (Codex C2) ====\n")
alpha_schedule[!is.na(alpha) & !is.na(fwd_ret),
               q_bin := cut(alpha, breaks = quantile(alpha, probs = seq(0, 1, 0.1), na.rm = TRUE),
                            include.lowest = TRUE, labels = FALSE),
               by = sig_date]
mono_per_date <- alpha_schedule[!is.na(q_bin),
                                 .(decile_avg_pos = cor(q_bin,
                                                          fwd_ret,
                                                          method = "spearman",
                                                          use = "pairwise.complete.obs")),
                                 by = sig_date]
mono_avg <- mean(mono_per_date$decile_avg_pos, na.rm = TRUE)
cat(sprintf("Composite monotonicity (avg decile-rank Spearman vs fwd_ret per sig_date): %.4f\n", mono_avg))

# Pooled decile-mean monotonicity
pooled_decile <- alpha_schedule[!is.na(q_bin),
                                 .(mean_ret = mean(fwd_ret, na.rm = TRUE)), by = q_bin][order(q_bin)]
pooled_mono <- if (nrow(pooled_decile) >= 8) {
  cor(pooled_decile$q_bin, pooled_decile$mean_ret, method = "spearman")
} else { NA }
cat(sprintf("Pooled decile monotonicity (single Spearman across deciles): %.4f\n", pooled_mono))

#=== RF-A4: Sector-neutralization comparison ==================================
cat("\n==== Sector-neutralization comparison (Codex C7 / RF-A4) ====\n")
# Load Sector_Lv2 from rawdata for each sig_date
rd <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "rawdata.parquet")))
rd[, Date := as.Date(Date)]
rd_month <- rd[Date %in% sig_dates_sorted, .(Date, Ticker, Sector_Lv2)]
setkey(rd_month, Date, Ticker)

alpha_with_sec <- merge(alpha_schedule[, .(sig_date, Ticker, alpha, fwd_ret)],
                         rd_month, by.x = c("sig_date", "Ticker"),
                         by.y = c("Date", "Ticker"), all.x = TRUE)

# Pre-neutralization IC (current alpha)
ic_pre <- compute_ic_by_date(alpha_with_sec, "alpha")
ic_pre_mean <- mean(ic_pre$ic, na.rm = TRUE)
ic_pre_icir <- ic_pre_mean / sd(ic_pre$ic, na.rm = TRUE)

# Sector-neutralize: subtract sector mean per (sig_date, Sector_Lv2)
alpha_with_sec[!is.na(alpha) & !is.na(Sector_Lv2),
               alpha_sec_neutral := alpha - mean(alpha, na.rm = TRUE),
               by = .(sig_date, Sector_Lv2)]
ic_post <- compute_ic_by_date(alpha_with_sec, "alpha_sec_neutral")
ic_post_mean <- mean(ic_post$ic, na.rm = TRUE)
ic_post_icir <- ic_post_mean / sd(ic_post$ic, na.rm = TRUE)

cat(sprintf("Pre-neutralization:  IC=%.4f ICIR=%.3f n=%d\n",
            ic_pre_mean, ic_pre_icir, nrow(ic_pre)))
cat(sprintf("Post-neutralization: IC=%.4f ICIR=%.3f n=%d\n",
            ic_post_mean, ic_post_icir, nrow(ic_post)))
retention <- ic_post_mean / ic_pre_mean
cat(sprintf("IC retention: %.1f%% (target >50%%)\n", 100 * retention))

#=== RF-A5: Historical top-decile ADV20 validation ============================
cat("\n==== Historical top-decile ADV20 (Codex C8 / RF-A5) ====\n")
rd[, TV := Close * Vol]
setkey(rd, Ticker, Date)
rd[, ADV20 := frollmean(TV, 20, fill = NA, na.rm = TRUE), by = Ticker]
adv_panel <- rd[Date %in% sig_dates_sorted, .(Date, Ticker, ADV20)]
setnames(adv_panel, "Date", "sig_date")

alpha_with_adv <- merge(alpha_schedule[, .(sig_date, Ticker, alpha, fwd_ret)],
                         adv_panel, by = c("sig_date", "Ticker"), all.x = TRUE)
alpha_with_adv[, q_bin := cut(alpha,
                                breaks = quantile(alpha, probs = seq(0, 1, 0.1), na.rm = TRUE),
                                include.lowest = TRUE, labels = FALSE),
                by = sig_date]
adv_check <- alpha_with_adv[q_bin == 10,
                              .(top_decile_adv_pct50 = quantile(ADV20, 0.50, na.rm = TRUE),
                                top_decile_adv_pct25 = quantile(ADV20, 0.25, na.rm = TRUE),
                                pct_above_2e8 = mean(ADV20 >= 2e8, na.rm = TRUE),
                                pct_above_5e7 = mean(ADV20 >= 5e7, na.rm = TRUE),
                                n = .N), by = sig_date]
cat("Top decile ADV20 statistics over walk-forward sig_dates:\n")
cat(sprintf("  Median of decile median ADV20: %.2e KRW\n", median(adv_check$top_decile_adv_pct50, na.rm = TRUE)))
cat(sprintf("  Median of decile 25th pct ADV20: %.2e KRW\n", median(adv_check$top_decile_adv_pct25, na.rm = TRUE)))
cat(sprintf("  Avg %% top decile above 2e8 KRW: %.1f%%\n",
            100 * mean(adv_check$pct_above_2e8, na.rm = TRUE)))
cat(sprintf("  Avg %% top decile above 5e7 KRW: %.1f%%\n",
            100 * mean(adv_check$pct_above_5e7, na.rm = TRUE)))

#=== Save consolidated v5 walk-forward state ==================================
cat("\n==== Saving v5 state ====\n")

# Build alpha vector for current as_of_date (latest OOS)
last_oos <- max(wf_summary$sig_date)
last_alpha <- alpha_schedule[sig_date == last_oos]
cat(sprintf("Last OOS sig_date: %s, alpha vector size: %d\n",
            last_oos, nrow(last_alpha)))

saveRDS(list(
  wf_summary = wf_summary,
  wf_results = wf_results,
  alpha_schedule = alpha_schedule,
  oos_dates = oos_dates,
  TRAIN_WINDOW = TRAIN_WINDOW,
  NW_THRESHOLD = NW_THRESHOLD,
  SELECT_TOP_K = SELECT_TOP_K,
  oos_nw_t = oos_nw_t,
  oos_ls_sr_full = oos_ls_sr_full,
  oos_ls_sr_bad = oos_ls_sr_bad,
  ic_oos_bad = ic_oos_bad,
  ic_oos_norm = ic_oos_norm,
  ratio_oos = ratio_oos,
  sub_stab_oos = sub_stab_oos,
  sub_stats_oos = sub_stats_oos,
  selection_freq = as.list(selection_freq),
  ic_pre_mean = ic_pre_mean, ic_pre_icir = ic_pre_icir,
  ic_post_mean = ic_post_mean, ic_post_icir = ic_post_icir,
  retention = retention,
  adv_check = adv_check,
  mono_avg = mono_avg, pooled_mono = pooled_mono,
  last_oos = last_oos,
  last_alpha = last_alpha
), file.path(SA_DIR, "alpha_pipeline_v5_state.rds"))

cat("\nWalk-forward v5 COMPLETE.\n")
