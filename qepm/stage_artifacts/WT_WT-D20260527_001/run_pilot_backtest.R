#==============================================================================
# DM-TC Pilot Backtest — WT-D20260527_001 Alpha Research
#
# Generate monthly alpha scores using DM-TC framework, then compute
# Rank IC / ICIR / Harvey t / monotonicity for the in-sample window.
#
# Window: 2017-01-31 ~ 2026-04-30 (m-1 fwd return)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

source("02_Infrastructure/backtest_harness.R")
source("qepm/stage_artifacts/WT_WT-D20260527_001/dm_tc_factor_engine.R")

cat("\n[STEP 1] Loading data...\n")
r <- load_rawdata(use_cache = TRUE)
RAW <- r$RAWDATA
BM <- r$BM_DT
BM[, Date := as.Date(Date)]

# Sub-period KR universe restriction
RAW <- RAW[Date >= as.Date("2014-01-01") & Date <= as.Date("2026-05-31"),
           .(Date, Ticker, Close, Vol, K200, KQ150,
             AdminStock, TradingHalt, UnfaithfulDisc, Size, Ret)]
cat("RAWDATA filtered rows:", nrow(RAW), "\n")
cat("BM rows:", nrow(BM), "\n")

cat("\n[STEP 2] Loading P3/P4 forecasts...\n")
p4 <- load_p4_forecasts()
cat("P4 rows:", nrow(p4), " | range:", as.character(min(p4$Date)), "to", as.character(max(p4$Date)), "\n")

cat("\n[STEP 3] Classifying market state (expanding-window quantiles)...\n")
state_dt <- classify_market_state(p4, min_history = 252L)
cat("State summary (continuous in [-1, 1]):\n")
print(summary(state_dt$state))

cat("\n[STEP 4] Build monthly sig_dates (month-end of trading calendar)...\n")
# Use last trading day of each month from BM_DT (KOSPI200 calendar)
BM[, ym := format(Date, "%Y-%m")]
monthly_eom <- BM[, .(eom = max(Date)), by = ym]
sig_dates <- monthly_eom[eom >= as.Date("2017-01-01") & eom <= as.Date("2026-04-30"), eom]
sig_dates <- sort(unique(sig_dates))
cat("Sig dates:", length(sig_dates), " | first:", as.character(sig_dates[1]),
    " | last:", as.character(tail(sig_dates, 1)), "\n")

cat("\n[STEP 5] Generate alpha panel (sequential, ~30s for 112 sig_dates)...\n")
setkey(RAW, Date, Ticker)

t_start <- Sys.time()
alpha_results <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd <- as.Date(sig_dates[i])
  a <- tryCatch(
    compute_alpha_vector(RAW, BM, state_dt, sd),
    error = function(e) {
      cat("[", as.character(sd), "] err: ", e$message, "\n")
      data.table(Date = sd, Ticker = character(0), alpha = numeric(0))
    }
  )
  alpha_results[[i]] <- a
  if (i %% 20 == 0 || i == length(sig_dates)) {
    cat(sprintf("  [%3d/%d] %s | state=%.3f | n_alpha=%d\n",
                i, length(sig_dates), sd,
                if(nrow(a)>0) a$S_t[1] else NA_real_,
                sum(!is.na(a$alpha))))
  }
}
elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
cat(sprintf("Time: %.1fs\n", elapsed))

alpha_panel <- rbindlist(alpha_results, fill = TRUE)
cat("Alpha panel rows:", nrow(alpha_panel), "\n")
cat("S_t range:", round(min(alpha_panel$S_t, na.rm=T),3), "to",
    round(max(alpha_panel$S_t, na.rm=T),3), "\n")

cat("\n[STEP 6] Save raw alpha panel...\n")
out_dir <- "qepm/stage_artifacts/WT_WT-D20260527_001"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write_parquet(alpha_panel, file.path(out_dir, "alpha_scores.parquet"))
cat("Saved:", file.path(out_dir, "alpha_scores.parquet"), "\n")

#==============================================================================
# [STEP 7] Compute Rank IC vs 1M-forward return
#==============================================================================
cat("\n[STEP 7] Computing Rank IC...\n")

# Build 1M-forward returns from RAW for each (sig_date, Ticker)
sig_dates_dt <- data.table(Date = sig_dates, sig_idx = seq_along(sig_dates))
# Next sig_date close vs current sig_date close → 1M return
# For each ticker on each sig_date: fwd = Close[next_sig] / Close[sig] - 1

# Pivot Close
close_dt <- RAW[Date %in% sig_dates, .(Date, Ticker, Close)]
setkey(close_dt, Ticker, Date)

# Get next sig_date for each
sig_pairs <- data.table(sig_date = sig_dates[-length(sig_dates)],
                        next_sig = sig_dates[-1])

fwd_list <- list()
for (i in seq_len(nrow(sig_pairs))) {
  sd <- sig_pairs$sig_date[i]
  nd <- sig_pairs$next_sig[i]
  curr <- close_dt[Date == sd, .(Ticker, Close_t = Close)]
  next_ <- close_dt[Date == nd, .(Ticker, Close_t1 = Close)]
  m <- merge(curr, next_, by = "Ticker")
  m[, fwd_ret := Close_t1 / Close_t - 1]
  m[, Date := sd]
  fwd_list[[i]] <- m[, .(Date, Ticker, fwd_ret)]
}
fwd_panel <- rbindlist(fwd_list)

# Join with alpha
joined <- alpha_panel[fwd_panel, on = c("Date", "Ticker"), nomatch = NULL]
joined <- joined[!is.na(alpha) & !is.na(fwd_ret) & is.finite(alpha) & is.finite(fwd_ret)]
cat("Joined rows:", nrow(joined), "\n")

# Per-month Rank IC + state bucket
joined[, state_bucket := fcase(
  S_t >= 0.5, "Bear (S_t>=0.5)",
  S_t <= -0.5, "Bull (S_t<=-0.5)",
  default = "Neutral (-0.5<S_t<0.5)"
)]

ic_by_month <- joined[, .(
  rank_ic = if(.N >= 30) cor(alpha, fwd_ret, method = "spearman") else NA_real_,
  n_stocks = .N,
  S_t = S_t[1],
  state_bucket = state_bucket[1]
), by = Date][!is.na(rank_ic)]

cat("\nIC by month sample (head 6 + tail 6):\n")
print(head(ic_by_month, 6))
print(tail(ic_by_month, 6))

mean_ic <- mean(ic_by_month$rank_ic, na.rm = TRUE)
sd_ic <- sd(ic_by_month$rank_ic, na.rm = TRUE)
icir <- mean_ic / sd_ic
n_months <- nrow(ic_by_month)

# Newey-West unadjusted: t = mean / SE = mean / (sd/sqrt(n))
t_naive <- mean_ic / (sd_ic / sqrt(n_months))
# Harvey-Liu-Zhu correction: K=3 tail-sens factors tested → t_adj = t_naive / sqrt(K)
K_factors <- 3L
hlz_factor <- sqrt(K_factors)
t_harvey <- t_naive / hlz_factor

cat("\n==== IC SUMMARY (full window, all signed states) ====\n")
cat(sprintf("Mean rank IC:    %.4f\n", mean_ic))
cat(sprintf("SD rank IC:      %.4f\n", sd_ic))
cat(sprintf("ICIR:            %.4f\n", icir))
cat(sprintf("N months:        %d\n", n_months))
cat(sprintf("Naive t-stat:    %.4f\n", t_naive))
cat(sprintf("Harvey t-stat (K=%d): %.4f\n", K_factors, t_harvey))

cat("\n==== IC BY STATE BUCKET ====\n")
state_summary <- ic_by_month[, .(
  n_months = .N,
  mean_ic = mean(rank_ic, na.rm = TRUE),
  sd_ic = sd(rank_ic, na.rm = TRUE),
  icir = mean(rank_ic, na.rm = TRUE) / sd(rank_ic, na.rm = TRUE),
  share_pos = mean(rank_ic > 0)
), by = state_bucket]
print(state_summary)

# Subperiod stability
cat("\n==== SUBPERIOD STABILITY ====\n")
ic_by_month[, period := fcase(
  Date < as.Date("2019-01-01"), "P1_2017_2018",
  Date < as.Date("2022-01-01"), "P2_2019_2021",
  default = "P3_2022_2026"
)]
sp <- ic_by_month[, .(
  n_months = .N,
  mean_ic = mean(rank_ic, na.rm = TRUE),
  icir = mean(rank_ic, na.rm = TRUE) / sd(rank_ic, na.rm = TRUE),
  share_pos = mean(rank_ic > 0)
), by = period]
print(sp)

#==============================================================================
# [STEP 8] Quintile monotonicity (only non-zero alpha periods)
#==============================================================================
cat("\n[STEP 8] Quintile monotonicity...\n")
mono_list <- list()
for (sd in unique(joined$Date)) {
  sub <- joined[Date == sd]
  if (nrow(sub) < 50) next
  sub[, qtile := cut(alpha, quantile(alpha, 0:5/5, na.rm = TRUE),
                     labels = 1:5, include.lowest = TRUE)]
  q_ret <- sub[, .(q_ret = mean(fwd_ret, na.rm = TRUE)), by = qtile]
  q_ret[, Date := sd]
  mono_list[[as.character(sd)]] <- q_ret
}
mono_panel <- rbindlist(mono_list, fill = TRUE)
mono_avg <- mono_panel[, .(mean_q_ret = mean(q_ret, na.rm = TRUE), n = .N),
                       by = qtile][order(qtile)]
print(mono_avg)

# Monotonicity score (Spearman 1..5 vs avg ret)
mono_score <- if (nrow(mono_avg) == 5) {
  cor(as.integer(mono_avg$qtile), mono_avg$mean_q_ret, method = "spearman")
} else NA_real_
cat(sprintf("\nMonotonicity (Spearman q vs avg fwd ret): %.4f\n", mono_score))

#==============================================================================
# [STEP 9] Save validation summary
#==============================================================================
cat("\n[STEP 9] Save validation summary...\n")
validation <- list(
  task_id = "WT-D20260527_001",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  alpha_panel = list(
    n_rows = nrow(alpha_panel),
    n_sig_dates = length(unique(alpha_panel$Date)),
    n_unique_tickers = length(unique(alpha_panel$Ticker)),
    s_t_range = list(min = round(min(alpha_panel$S_t, na.rm = TRUE), 3),
                     max = round(max(alpha_panel$S_t, na.rm = TRUE), 3),
                     mean = round(mean(alpha_panel$S_t, na.rm = TRUE), 3))
  ),
  ic_overall = list(
    mean_rank_ic = round(mean_ic, 4),
    sd_rank_ic = round(sd_ic, 4),
    icir = round(icir, 4),
    n_months = n_months,
    t_naive = round(t_naive, 4),
    t_harvey_3factor = round(t_harvey, 4)
  ),
  ic_by_state = as.list(state_summary),
  subperiod_stability = as.list(sp),
  monotonicity = list(
    q1_ret = if(nrow(mono_avg) >= 1) mono_avg[qtile == 1, mean_q_ret] else NA,
    q5_ret = if(nrow(mono_avg) >= 5) mono_avg[qtile == 5, mean_q_ret] else NA,
    q5_minus_q1 = if(nrow(mono_avg) >= 5) (mono_avg[qtile == 5, mean_q_ret] - mono_avg[qtile == 1, mean_q_ret]) else NA,
    spearman_score = round(mono_score, 4)
  )
)

write_json(validation, file.path(out_dir, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("Saved:", file.path(out_dir, "alpha_validation.json"), "\n")

# Save IC time series
write_parquet(ic_by_month, file.path(out_dir, "ic_by_month.parquet"))
write_parquet(mono_panel, file.path(out_dir, "monotonicity_panel.parquet"))

cat("\n========== PILOT COMPLETE ==========\n")
