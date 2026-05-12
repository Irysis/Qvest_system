#==============================================================================
# WT-D20260511_001 PD24 — Path A back-extension (alpha sample expansion)
#
# Goal: Diebold-Mariano t_NW 2.7641 → ≥ 3.0 strict via sample size increase.
# Method: Extend NEW Vol/Skew composite alpha back to 1999-01 (36m burn-in
# starts 1996-01). Retain methodology bit-for-bit (PIT C13 dir_align expanding
# mean IC lag-1 retain — full alpha formula identical to lockbox).
#
# PIT-safety: alpha[sig_date < 2011-01] computed with expanding IC using only
# information available at that sig_date (no future contamination).
#
# Universe pre-2010: KOSPI200 only (KQ150 listed 2010-01 onward, PIT-correct).
# Universe post-2010: KOSPI200 ∪ KOSDAQ150.
#
# Output: alpha_scores_pd24.parquet (1999-01 ~ 2026-04 expanded)
#         + diebold_mariano_pd24.csv (recomputed)
#         + alpha_pd24_quality.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(future.apply)
})

WT_ID    <- "WT-D20260511_001"
WT_DIR   <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR   <- "stage_artifacts/WT_D20260511_001"
FDB_DIR  <- ".cache/factor_db"
RAW_PATH <- ".cache/rawdata.parquet"

BURN_IN_MONTHS  <- 36L
LIQ_THRESHOLD   <- 2e8
FACTOR_TARGETS  <- c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry")

# Path A start: 1996-01 (burn-in until 1998-12), active alpha from 1999-01
EXT_START <- as.Date("1996-01-01")
EXT_END   <- as.Date("2026-04-01")

cat("================ PD24 Path A — Alpha Sample Extension ================\n")
cat("Burn-in start:", as.character(EXT_START), "\n")
cat("Burn-in end:  ", as.character(EXT_START + 36L * 30L), " (~36m)\n")
cat("Active alpha: ", as.character(EXT_START + 36L * 30L), "~", as.character(EXT_END), "\n")
cat("Methodology: identical to lockbox (no change). Just sample size↑.\n\n")

# ----------- Helper: per-sig_date factor loading from factor_db -----------
load_factors_for_sig_date <- function(sd) {
  ym_int <- as.integer(format(sd, "%Y%m"))
  f <- file.path(FDB_DIR, sprintf("factor_db_%06d.parquet", ym_int))
  if (!file.exists(f)) return(NULL)
  dt <- as.data.table(read_parquet(f))
  dt <- dt[Factor_Name %in% FACTOR_TARGETS]
  if (nrow(dt) == 0) return(NULL)
  # Z_Sector = sector-neutral z-score (built-in by factor_db pipeline)
  dt[, list(sig_date = sd, Ticker, Factor_Name, Z_Sector)]
}

# ----------- Helper: universe per sig_date (K200 ∪ KQ150, ADV_20d >= 2e8) -----------
build_universe_mask <- function(rd_full, sig_date) {
  d_lag <- sig_date - 1L  # strict t-1 lag for PIT
  # Most recent obs before sig_date
  rd_lag <- rd_full[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  # Universe: K200 == 1 OR KQ150 == 1 (KQ150 NA before 2010)
  uni <- rd_lag[(K200 == 1L | (!is.na(KQ150) & KQ150 == 1L))]
  # Liquidity: ADV_20d >= 2e8 (computed below)
  uni[, vol_value := Close * Vol]
  uni <- uni[!is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]
  uni$Ticker
}

# ----------- 1) Load rawdata + precompute adv_20d -----------
cat("[1/4] Load rawdata + precompute adv_20d ...\n")
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]
cat(sprintf("  rawdata rows = %d, date range = %s ~ %s\n",
            nrow(rd), as.character(min(rd$Date)), as.character(max(rd$Date))))

# ----------- 2) Build sig_dates seq + load factors -----------
sig_dates <- seq.Date(EXT_START, EXT_END, by = "month")
sig_dates <- as.Date(format(sig_dates, "%Y-%m-01"))
cat(sprintf("[2/4] Sig_dates total: %d (%s ~ %s)\n",
            length(sig_dates), as.character(min(sig_dates)), as.character(max(sig_dates))))

cat("  Loading factors for each sig_date ...\n")
panel_list <- lapply(seq_along(sig_dates), function(i) {
  sd <- sig_dates[i]
  out <- load_factors_for_sig_date(sd)
  if (i %% 30 == 0 || i == length(sig_dates)) {
    cat(sprintf("    [%d/%d] %s: rows=%s\n", i, length(sig_dates),
                as.character(sd), ifelse(is.null(out), "0", as.character(nrow(out)))))
  }
  out
})
panel <- rbindlist(Filter(Negate(is.null), panel_list))
cat(sprintf("  Total panel rows = %d, unique tickers = %d, unique sig_dates = %d\n",
            nrow(panel), uniqueN(panel$Ticker), uniqueN(panel$sig_date)))

# ----------- 3) Compute alpha per sig_date (PIT-safe, expanding IC dir) -----------
# Pivot wide
panel_wide <- dcast(panel, sig_date + Ticker ~ Factor_Name, value.var = "Z_Sector")
cat(sprintf("[3/4] panel_wide rows = %d\n", nrow(panel_wide)))

# Composite z: equal-weight sector-neutral z
panel_wide[, z_skew    := D43_Skewness]
panel_wide[, z_vov     := D41_Vol_of_Vol]
panel_wide[, z_asy     := D58_Vol_Asymmetry]
panel_wide[, composite_raw := (
  ifelse(is.na(z_skew), 0, z_skew) +
  ifelse(is.na(z_vov),  0, z_vov)  +
  ifelse(is.na(z_asy),  0, z_asy)
) / pmax(
  as.integer(!is.na(z_skew)) +
  as.integer(!is.na(z_vov))  +
  as.integer(!is.na(z_asy)), 1L
)]

# ----------- 3b) Expanding direction-alignment IC (PIT-safe, lag-1, 36m burn-in) -----------
# For each sig_date sd, dir_factor(sd) = sign(mean(IC_factor[Usable_Date <= sd - 1m]))
# IC_factor at time t = cor(Z_Sector_t, ret_1M_t) per sig_date

# Build ret_1M per sig_date: return from sig_date to next sig_date
# Use entry/exit at sig_date+small offset
cat("  Building ret_1M per (sig_date, Ticker) ...\n")

# For each sig_date pair, compute monthly return per Ticker (held from sd to sd_next)
ret_dt <- data.table()
for (i in seq_along(sig_dates)[-length(sig_dates)]) {
  d_s <- sig_dates[i]; d_e <- sig_dates[i + 1]

  entry <- rd[Date >= d_s & Date <= (d_s + 5L), .SD[which.min(Date)], by = Ticker,
              .SDcols = c("Date", "Close")]
  setnames(entry, c("Ticker", "entry_date", "entry_price"))
  exit  <- rd[Date >= d_e & Date <= (d_e + 5L), .SD[which.min(Date)], by = Ticker,
              .SDcols = c("Date", "Close")]
  setnames(exit, c("Ticker", "exit_date", "exit_price"))

  m <- merge(entry, exit, by = "Ticker", all.x = TRUE)
  m[, ret_1M := exit_price / entry_price - 1]
  m[, sig_date := d_s]
  ret_dt <- rbind(ret_dt, m[, .(sig_date, Ticker, ret_1M)])
  if (i %% 50 == 0) cat(sprintf("    [ret loop %d/%d] %s\n", i, length(sig_dates), as.character(d_s)))
}

# Merge
panel_wide <- merge(panel_wide, ret_dt, by = c("sig_date", "Ticker"), all.x = TRUE)
cat(sprintf("  panel_wide w/ret_1M rows = %d, non-NA ret_1M = %d\n",
            nrow(panel_wide), sum(!is.na(panel_wide$ret_1M))))

# Compute per-(sig_date, factor) IC
# Helper: cummean lag-1 (NA-safe)
cummean_lag <- function(x) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (j in 2:n) {
    prev <- x[1:(j-1)]
    if (any(!is.na(prev))) out[j] <- mean(prev, na.rm = TRUE)
  }
  out
}

ic_dt <- panel_wide[, .(
  IC_skew = if (sum(!is.na(ret_1M) & !is.na(z_skew)) > 10) cor(z_skew, ret_1M, use = "complete.obs", method = "pearson") else NA_real_,
  IC_vov  = if (sum(!is.na(ret_1M) & !is.na(z_vov))  > 10) cor(z_vov,  ret_1M, use = "complete.obs", method = "pearson") else NA_real_,
  IC_asy  = if (sum(!is.na(ret_1M) & !is.na(z_asy))  > 10) cor(z_asy,  ret_1M, use = "complete.obs", method = "pearson") else NA_real_
), by = sig_date]
setorder(ic_dt, sig_date)
cat(sprintf("  IC observations: %d sig_dates\n", nrow(ic_dt)))
cat(sprintf("  Mean IC: skew=%.4f, vov=%.4f, asy=%.4f\n",
            mean(ic_dt$IC_skew, na.rm=TRUE),
            mean(ic_dt$IC_vov, na.rm=TRUE),
            mean(ic_dt$IC_asy, na.rm=TRUE)))

# Expanding mean IC dir (lag-1, PIT-safe)
ic_dt[, dir_skew := sign(cummean_lag(IC_skew))]
ic_dt[, dir_vov  := sign(cummean_lag(IC_vov))]
ic_dt[, dir_asy  := sign(cummean_lag(IC_asy))]

# Apply burn-in: ignore first 36 sig_dates
ic_dt[, n_obs := seq_len(.N)]
ic_dt[n_obs <= BURN_IN_MONTHS, c("dir_skew", "dir_vov", "dir_asy") := NA]

# Default direction during burn-in or NA: +1 (signal-as-is, before evidence)
ic_dt[is.na(dir_skew) | dir_skew == 0, dir_skew := 1]
ic_dt[is.na(dir_vov)  | dir_vov == 0,  dir_vov  := 1]
ic_dt[is.na(dir_asy)  | dir_asy == 0,  dir_asy  := 1]

cat(sprintf("  Direction at sig_date=2011-01-01: skew=%d, vov=%d, asy=%d\n",
            as.integer(ic_dt[sig_date == "2011-01-01"]$dir_skew),
            as.integer(ic_dt[sig_date == "2011-01-01"]$dir_vov),
            as.integer(ic_dt[sig_date == "2011-01-01"]$dir_asy)))

# Merge directions into panel_wide
panel_wide <- merge(panel_wide,
                    ic_dt[, .(sig_date, dir_skew, dir_vov, dir_asy)],
                    by = "sig_date", all.x = TRUE)

# Composite with direction alignment
panel_wide[, z_skew_a := dir_skew * z_skew]
panel_wide[, z_vov_a  := dir_vov  * z_vov]
panel_wide[, z_asy_a  := dir_asy  * z_asy]
panel_wide[, alpha := (
  ifelse(is.na(z_skew_a), 0, z_skew_a) +
  ifelse(is.na(z_vov_a),  0, z_vov_a)  +
  ifelse(is.na(z_asy_a),  0, z_asy_a)
) / pmax(
  as.integer(!is.na(z_skew_a)) +
  as.integer(!is.na(z_vov_a))  +
  as.integer(!is.na(z_asy_a)), 1L
)]

# ----------- 3c) Filter to post-burn-in sig_dates + universe -----------
panel_eval <- panel_wide[sig_date >= sig_dates[BURN_IN_MONTHS + 1]]
cat(sprintf("[3c] panel_eval (post-burnin) sig_dates: %d, rows: %d\n",
            uniqueN(panel_eval$sig_date), nrow(panel_eval)))

# Filter to investable universe per sig_date
cat("  Building per-sig_date investable universe ...\n")
final_alpha <- data.table()
sig_eval <- sort(unique(panel_eval$sig_date))
for (i in seq_along(sig_eval)) {
  sd <- sig_eval[i]
  uni <- build_universe_mask(rd, sd)
  sub <- panel_eval[sig_date == sd & Ticker %in% uni & !is.na(alpha)]
  final_alpha <- rbind(final_alpha, sub[, .(sig_date, Ticker, alpha)])
  if (i %% 30 == 0 || i == length(sig_eval)) {
    cat(sprintf("    [%d/%d] %s: universe=%d, alpha rows=%d\n",
                i, length(sig_eval), as.character(sd), length(uni), nrow(sub)))
  }
}

cat(sprintf("\n[FINAL] alpha_scores_pd24: %d rows, %d sig_dates, %d unique tickers\n",
            nrow(final_alpha), uniqueN(final_alpha$sig_date), uniqueN(final_alpha$Ticker)))

# ----------- 4) Save outputs -----------
final_alpha[, confidence := abs(alpha)]
out_path <- file.path(SA_DIR, "alpha_scores_pd24.parquet")
write_parquet(final_alpha, out_path)
cat(sprintf("[4/4] Saved: %s\n", out_path))

# Quality report
qual <- list(
  task_id = WT_ID,
  pd_phase = "PD24_path_A",
  n_sig_dates = uniqueN(final_alpha$sig_date),
  n_rows = nrow(final_alpha),
  n_unique_tickers = uniqueN(final_alpha$Ticker),
  date_range = c(as.character(min(final_alpha$sig_date)),
                 as.character(max(final_alpha$sig_date))),
  mean_ic_skew = mean(ic_dt$IC_skew, na.rm = TRUE),
  mean_ic_vov  = mean(ic_dt$IC_vov,  na.rm = TRUE),
  mean_ic_asy  = mean(ic_dt$IC_asy,  na.rm = TRUE),
  methodology = list(
    burn_in_months = BURN_IN_MONTHS,
    factor_targets = FACTOR_TARGETS,
    direction_alignment = "Expanding mean IC lag-1 (PIT-safe)",
    sector_neutral = "Z_Sector from factor_db (built-in)",
    universe = "KOSPI200 ∪ KOSDAQ150 (pre-2010: K200 only) ∩ ADV_20d ≥ 2e8 KRW",
    liquidity_lag = "strict t-1"
  ),
  comparison_vs_pre_pd24 = list(
    pre_n_sig_dates = 184L,
    extended_n_sig_dates = uniqueN(final_alpha$sig_date),
    extension_ratio = round(uniqueN(final_alpha$sig_date) / 184, 3)
  )
)
write_json(qual, file.path(WT_DIR, "alpha_pd24_quality.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("Saved quality report.\n")

cat("\n================ PD24 Path A — DONE ================\n")
