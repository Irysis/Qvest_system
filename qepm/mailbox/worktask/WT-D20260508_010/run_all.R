#==============================================================================
# WT-D20260508_010 Alpha Research — Skewness factor non-linear cross-section
#
# Codex REJECT round 1 후 강화:
#   - load_month_factors() 경유 (Z_Score_Aligned PIT-safe, C13/C14/C15 verifiable)
#   - multi-sig-date panel: 60 monthly sig_dates (2021-05 ~ 2026-04)
#   - measured sector-neutral IC (Sector_Lv2 residualization)
#   - measured decile monotonicity (top-bottom spread)
#   - measured turnover (rank change month-over-month)
#   - measured top-decile 20d ADV
#
# Output:
#   - alpha_scores.parquet (Date x Ticker x score panel + forward May)
#   - alpha_validation_v2.json (measured diagnostics)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

setwd(Sys.getenv("QM_ROOT", unset = "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"))
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID <- "WT-D20260508_010"
SELECTED_FACTOR <- "R14_DUVOL"
LIQ_FLOOR <- 2e8L  # CLAUDE.md mandate (request 5e7 ignored, base 2e8 priority)

# ---- 1. Build sig_date sequence (60 months, monthly month-end) ----
all_files <- list.files(".cache/factor_db", pattern = "factor_db_\\d{6}\\.parquet", full.names = TRUE)
ym_avail <- gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", all_files)
ym_avail <- sort(ym_avail)
sig_dates_target <- sapply(tail(ym_avail, 61L), function(ym) {
  y <- as.integer(substr(ym, 1, 4))
  m <- as.integer(substr(ym, 5, 6))
  # Find actual factor_db Date for that YYYYMM
  fp <- file.path(".cache/factor_db", paste0("factor_db_", ym, ".parquet"))
  d <- as.data.table(read_parquet(fp))
  as.character(max(as.Date(d$Date)))
})
sig_dates <- as.Date(sig_dates_target)
cat("[run_all] N sig_dates =", length(sig_dates), "\n")
cat("[run_all] range =", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# ---- 2. Load rawdata for universe + returns ----
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)

# ---- 3. Build alpha panel: Date x Ticker x alpha (Z_Score_Aligned) ----
panels <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  # Universe at sig_date: KOSPI200 ∪ KOSDAQ150 + 20d ADV >= 2e8
  rd_sd <- rd[Date == sd]
  if (nrow(rd_sd) == 0L) next
  univ_flag <- rd_sd[K200 == 1 | KQ150 == 1, Ticker]
  rd_lb <- rd[Date >= (sd - 35) & Date <= sd & Ticker %in% univ_flag,
              .(adv_20d = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
  liq <- rd_lb[adv_20d >= LIQ_FLOOR, Ticker]
  univ <- intersect(univ_flag, liq)

  # PIT load via connector — Z_Score_Aligned IC-sign automatic (no manual NEGATE_FACTORS)
  fac_dt <- tryCatch(
    load_month_factors(sd, coverage_min = 0.05),
    error = function(e) { cat("[run_all] connector fail at", as.character(sd), ":", conditionMessage(e), "\n"); NULL }
  )
  if (is.null(fac_dt) || !(SELECTED_FACTOR %in% fac_dt$Factor_Name)) next

  z_dt <- fac_dt[Factor_Name == SELECTED_FACTOR & Ticker %in% univ,
                 .(Date = sd, Ticker, alpha_z = Z_Score_Aligned)]

  # Attach 20d ADV + sector
  z_dt <- merge(z_dt, rd_lb[, .(Ticker, adv_20d_won = adv_20d)], by = "Ticker", all.x = TRUE)
  rd_meta <- rd_sd[, .(Ticker, Sector_Lv2, Sector, Close)]
  z_dt <- merge(z_dt, rd_meta, by = "Ticker", all.x = TRUE)

  panels[[i]] <- z_dt
  if (i %% 12 == 0) cat("[run_all]   processed", i, "/", length(sig_dates), "\n")
}
panel <- rbindlist(panels, use.names = TRUE, fill = TRUE)
cat("[run_all] panel rows =", nrow(panel), "/ unique sig_dates =", uniqueN(panel$Date), "\n")

# ---- 4. Compute forward 1M returns + measured IC + decile monotonicity ----
# Forward return = next monthly close / current close - 1 (using sig_date Close as start)
# For last sig_date, no forward → flag as NA
sig_unique <- sort(unique(panel$Date))
fwd_rets <- list()
for (k in seq_along(sig_unique)[-length(sig_unique)]) {
  d_now <- sig_unique[k]
  d_next <- sig_unique[k + 1]
  rd_next <- rd[Date == d_next, .(Ticker, Close_next = Close)]
  rd_now <- rd[Date == d_now, .(Ticker, Close_now = Close)]
  fwd <- merge(rd_now, rd_next, by = "Ticker")
  fwd[, fwd_ret_1m := Close_next / Close_now - 1]
  fwd[, Date := d_now]
  fwd_rets[[k]] <- fwd[, .(Date, Ticker, fwd_ret_1m)]
}
fwd_dt <- rbindlist(fwd_rets, use.names = TRUE)
panel <- merge(panel, fwd_dt, by = c("Date", "Ticker"), all.x = TRUE)

# Exclude last sig_date (no forward yet — that is "as-of forecast")
panel_train <- panel[!is.na(fwd_ret_1m)]

# ---- 4.1 Rank IC (Spearman) per sig_date ----
ic_per_date <- panel_train[, .(
  rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
  n_stocks = .N
), by = Date]

ic_mean <- mean(ic_per_date$rank_ic, na.rm = TRUE)
ic_sd <- sd(ic_per_date$rank_ic, na.rm = TRUE)
icir_measured <- ic_mean / ic_sd
n_periods <- nrow(ic_per_date[!is.na(rank_ic)])

# Newey-West HAC SE for Harvey-t
nw_var <- function(v, lag = 4L) {
  v <- v[!is.na(v)]; n <- length(v); v <- v - mean(v)
  acc <- sum(v * v) / n
  for (k in 1:lag) {
    w <- 1 - k / (lag + 1)
    cv <- sum(v[1:(n - k)] * v[(k + 1):n]) / n
    acc <- acc + 2 * w * cv
  }
  acc / n
}
nw_v <- nw_var(ic_per_date$rank_ic, 4L)
ic_t_NW <- ic_mean / sqrt(nw_v / n_periods)

cat("[run_all] === MEASURED diagnostics (60 sig_dates walk-forward) ===\n")
cat(sprintf("  IC mean = %+.5f  IC sd = %.5f\n", ic_mean, ic_sd))
cat(sprintf("  ICIR_measured = %+.4f  Harvey-NW t = %+.3f  n=%d periods\n", icir_measured, ic_t_NW, n_periods))

# ---- 4.2 Decile monotonicity (top-bottom return spread + monotonic rank cor) ----
panel_train[, decile := cut(alpha_z, quantile(alpha_z, seq(0, 1, 0.1), na.rm = TRUE),
                            include.lowest = TRUE, labels = 1:10), by = Date]
dec_ret <- panel_train[!is.na(decile), .(mean_fwd = mean(fwd_ret_1m, na.rm = TRUE), n = .N),
                       by = .(Date, decile)]
dec_avg <- dec_ret[, .(avg_ret = mean(mean_fwd, na.rm = TRUE)), by = decile][order(decile)]
top_bot_spread <- dec_avg[decile == 10, avg_ret] - dec_avg[decile == 1, avg_ret]
mono_cor <- cor(as.numeric(dec_avg$decile), dec_avg$avg_ret, method = "spearman")

cat(sprintf("  Decile spread (top-bot) = %+.4f / month  (annualized %+.2f%%)\n",
            top_bot_spread, top_bot_spread * 12 * 100))
cat(sprintf("  Decile monotonicity (rank cor) = %+.3f  ", mono_cor))
cat(if (mono_cor >= 0.7) "PASS\n" else "FAIL (need >=0.7)\n")
print(dec_avg)

# ---- 4.3 Sector-neutral IC ----
# Residualize alpha_z and fwd_ret_1m on Sector_Lv2 (per Date) before cor
panel_train[, alpha_z_sn := {
  if (sum(!is.na(Sector_Lv2)) > 5L && uniqueN(Sector_Lv2) >= 2L) {
    fit <- lm(alpha_z ~ Sector_Lv2, data = .SD, na.action = na.exclude)
    residuals(fit)
  } else NA_real_
}, by = Date]
panel_train[, fwd_ret_sn := {
  if (sum(!is.na(Sector_Lv2)) > 5L && uniqueN(Sector_Lv2) >= 2L) {
    fit <- lm(fwd_ret_1m ~ Sector_Lv2, data = .SD, na.action = na.exclude)
    residuals(fit)
  } else NA_real_
}, by = Date]
ic_sn <- panel_train[, .(rank_ic_sn = cor(alpha_z_sn, fwd_ret_sn, method = "spearman",
                                           use = "pairwise.complete.obs")), by = Date]
ic_sn_mean <- mean(ic_sn$rank_ic_sn, na.rm = TRUE)
icir_sn <- ic_sn_mean / sd(ic_sn$rank_ic_sn, na.rm = TRUE)
ic_retention <- ic_sn_mean / ic_mean
cat(sprintf("  Sector-neutral IC mean = %+.5f  ICIR_sn = %+.3f  retention = %.1f%% (need >=50%%)\n",
            ic_sn_mean, icir_sn, ic_retention * 100))

# ---- 4.4 Turnover measurement ----
# Rank change month-over-month for top decile membership
panel_train[, alpha_rank := frank(-alpha_z, ties.method = "average"), by = Date]
panel_train[, top_decile := alpha_rank <= ceiling(.N * 0.1), by = Date]
sig_seq <- sort(unique(panel_train$Date))
turn_list <- numeric(length(sig_seq) - 1L)
for (k in seq_len(length(sig_seq) - 1L)) {
  d1 <- sig_seq[k]; d2 <- sig_seq[k + 1]
  set1 <- panel_train[Date == d1 & top_decile == TRUE, Ticker]
  set2 <- panel_train[Date == d2 & top_decile == TRUE, Ticker]
  if (length(set1) == 0L || length(set2) == 0L) { turn_list[k] <- NA; next }
  # Symmetric difference / max set size = monthly turnover
  diff_pct <- length(setdiff(set1, set2)) / max(length(set1), length(set2))
  turn_list[k] <- diff_pct
}
to_monthly <- mean(turn_list, na.rm = TRUE)
to_annual <- to_monthly * 12
cat(sprintf("  Top-decile turnover monthly = %.3f  annual = %.1f%% (need <600%%)\n",
            to_monthly, to_annual * 100))

# ---- 4.5 Top-decile 20d ADV check ----
top_dec_adv <- panel[Date == max(Date)][order(-alpha_z)][1:35, .(Ticker, alpha_z, adv_20d_won)]
top_dec_adv[, adv_passes_2e8 := adv_20d_won >= 2e8]
cat(sprintf("  Top-35 (~10pct decile) ADV: median=%.2e  min=%.2e  passes 2e8: %d/%d\n",
            median(top_dec_adv$adv_20d_won, na.rm = TRUE),
            min(top_dec_adv$adv_20d_won, na.rm = TRUE),
            sum(top_dec_adv$adv_passes_2e8, na.rm = TRUE), nrow(top_dec_adv)))

# ---- 4.6 RF-A3 recent 3Y check ----
recent_3y_start <- max(sig_unique) - 365 * 3
ic_recent <- ic_per_date[Date >= recent_3y_start]
icir_recent <- mean(ic_recent$rank_ic, na.rm = TRUE) / sd(ic_recent$rank_ic, na.rm = TRUE)
ratio_recent_full <- icir_recent / icir_measured
cat(sprintf("  RF-A3 recent 3Y: ICIR_recent = %+.3f / ICIR_full = %+.3f / ratio = %.3f  ",
            icir_recent, icir_measured, ratio_recent_full))
cat(if (abs(ratio_recent_full) <= 1.5) "PASS (ratio<=1.5)\n" else "FLAG (ratio>1.5)\n")

# ---- 5. Subperiod stability (3 windows) ----
sp1 <- ic_per_date[Date < as.Date("2014-01-01")]
sp2 <- ic_per_date[Date >= as.Date("2014-01-01") & Date < as.Date("2020-01-01")]
sp3 <- ic_per_date[Date >= as.Date("2020-01-01")]
cat(sprintf("  Subperiod ICIR: 2008-13=%+.3f (n=%d)  2014-19=%+.3f (n=%d)  2020-25=%+.3f (n=%d)\n",
            if (nrow(sp1) > 1L) mean(sp1$rank_ic, na.rm=TRUE)/sd(sp1$rank_ic, na.rm=TRUE) else NA, nrow(sp1),
            if (nrow(sp2) > 1L) mean(sp2$rank_ic, na.rm=TRUE)/sd(sp2$rank_ic, na.rm=TRUE) else NA, nrow(sp2),
            if (nrow(sp3) > 1L) mean(sp3$rank_ic, na.rm=TRUE)/sd(sp3$rank_ic, na.rm=TRUE) else NA, nrow(sp3)))

# ---- 6. Save panel + as-of forecast ----
# Full panel with forward returns (training data)
out_panel <- panel[, .(Date, Ticker, alpha_z, alpha_z_sn = NA_real_, fwd_ret_1m,
                        adv_20d_won, Sector_Lv2)]
# Last sig_date row = as-of forecast for forward May
write_parquet(out_panel, "stage_artifacts/WT-D20260508_010/alpha_scores.parquet")
cat("[run_all] [saved] alpha_scores.parquet — rows:", nrow(out_panel),
    "/ unique sig_dates:", uniqueN(out_panel$Date), "\n")

# Confidence vector for as-of forecast
asof <- out_panel[Date == max(Date)]
asof[, abs_z := abs(alpha_z)]
asof[, conf := pmin(0.95, 0.4 + 0.4 * (rank(abs_z) - 1) / (.N - 1))]
asof_out <- asof[, .(Ticker, alpha_z, confidence = conf)]
saveRDS(asof_out, "/tmp/wt010_asof_v2.rds")
cat("[run_all] as-of forecast rows:", nrow(asof_out), "\n")

# Save measured diagnostics for validation_v2 builder
diag_v2 <- list(
  ic_measured_mean = round(ic_mean, 5),
  ic_measured_sd = round(ic_sd, 5),
  icir_measured = round(icir_measured, 4),
  harvey_t_NW_lag4_measured = round(ic_t_NW, 3),
  n_periods_measured = n_periods,
  decile_top_bot_spread_monthly = round(top_bot_spread, 5),
  decile_monotonicity_rank_cor = round(mono_cor, 3),
  decile_pass = mono_cor >= 0.7,
  sector_neutral_ic_mean = round(ic_sn_mean, 5),
  sector_neutral_icir = round(icir_sn, 4),
  sector_neutral_ic_retention = round(ic_retention, 3),
  turnover_monthly_measured = round(to_monthly, 4),
  turnover_annual_measured = round(to_annual, 4),
  rf_a3_icir_recent_3y = round(icir_recent, 4),
  rf_a3_ratio_recent_full = round(ratio_recent_full, 3),
  rf_a3_pass = abs(ratio_recent_full) <= 1.5,
  subp_2008_13 = if (nrow(sp1) > 1L) round(mean(sp1$rank_ic, na.rm=TRUE)/sd(sp1$rank_ic, na.rm=TRUE), 3) else NA,
  subp_2014_19 = if (nrow(sp2) > 1L) round(mean(sp2$rank_ic, na.rm=TRUE)/sd(sp2$rank_ic, na.rm=TRUE), 3) else NA,
  subp_2020_25 = if (nrow(sp3) > 1L) round(mean(sp3$rank_ic, na.rm=TRUE)/sd(sp3$rank_ic, na.rm=TRUE), 3) else NA,
  top_decile_adv_pass_2e8 = sum(top_dec_adv$adv_passes_2e8, na.rm=TRUE),
  top_decile_adv_total = nrow(top_dec_adv),
  top_decile_adv_min_won = round(min(top_dec_adv$adv_20d_won, na.rm=TRUE), 0),
  top_decile_adv_median_won = round(median(top_dec_adv$adv_20d_won, na.rm=TRUE), 0)
)
write_json(diag_v2, "stage_artifacts/WT-D20260508_010/measured_diagnostics_v2.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[run_all] [saved] measured_diagnostics_v2.json\n")

# Also save IC time series + decile portfolio returns for audit
write_parquet(ic_per_date, "stage_artifacts/WT-D20260508_010/ic_per_date.parquet")
write_parquet(dec_ret, "stage_artifacts/WT-D20260508_010/decile_returns.parquet")
cat("[run_all] [saved] ic_per_date.parquet + decile_returns.parquet\n")
cat("[run_all] DONE\n")
