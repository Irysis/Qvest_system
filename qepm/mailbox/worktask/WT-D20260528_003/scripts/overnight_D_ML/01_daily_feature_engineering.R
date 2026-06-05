#==============================================================================
# WT-D20260528_003 Hypothesis D — ML Daily-Informed Monthly Model
# Step 1: Daily Factor DB → Monthly Snapshot Panel (PIT-clean)
#
# Philosophy (도훈 spec):
#   일간 데이터를 이용해 다양한 rolling feature를 만들고,
#   이를 월간 리밸런싱 시점의 스냅샷으로 압축해서 학습.
#
# Pipeline:
#   1. Load 298 daily factors (1990-2026.05) → 13.9M rows
#   2. Universe filter per sig_date (K200 ∪ KQ150 + LIQ 2e8)
#   3. Feature engineering (Block 1-5):
#        Block 1: rolling moments (mean/std/skew/kurt/zscore × 5/21/60/120d)
#        Block 2: rank dynamics (rank_pct, rank_change, velocity, vol)
#        Block 3: tail / extreme behavior (DD, runup, extreme count)
#        Block 4: cross-factor interactions (selective, academic-grounded)
#        Block 5: macro context (lag 1 strict)
#   4. Monthly snapshot at sig_date t (using daily data up to t-1 strict)
#   5. Forward 1M log return label (winsorize 99.5%)
#
# PIT C1 strict: All rolling computed with daily data <= sig_date - 1 day
# Lockbox: sig_date <= 2023-12-22 (alpha-research lockbox-scope.md)
# Cycle 51 shift: positive n + type label only (no n=-H + lead)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

# ---- Paths ----
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

WT_ID    <- "WT-D20260528_003"
HYP_TAG  <- "overnight_D_ML"
OUT_DIR  <- file.path("stage_artifacts", "WT_D20260528_003_overnight_D_ML")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

SIG_CUTOFF    <- as.Date("2023-12-22")  # PIT lockbox (alpha-research scope)
LIQ_THRESHOLD <- 2e8                    # 도훈 mandate
DAILY_DB_DIR  <- ".cache/factor_db_daily"

# ---- Step 1: build month-end sig_date list ----
cat(sprintf("[%s] Step 1 — sig_date schedule\n", format(Sys.time(), "%H:%M:%S")))

avail <- list.files(DAILY_DB_DIR, pattern = "^fdb_daily_\\d{6}\\.parquet$")
ym_avail <- gsub("fdb_daily_(\\d{6})\\.parquet", "\\1", avail)
ym_avail <- sort(ym_avail)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
raw[, YM   := format(Date, "%Y%m")]

month_ends <- raw[, .(Date = max(Date)), by = YM]
setkey(month_ends, YM)

sig_dates <- month_ends[YM %in% ym_avail & Date <= SIG_CUTOFF, sort(Date)]
sig_dates <- sig_dates[sig_dates >= as.Date("2008-01-01")]   # KOSDAQ150 활성 시점
cat(sprintf("  sig_dates total: %d  first: %s  last: %s\n",
    length(sig_dates), as.character(sig_dates[1]), as.character(sig_dates[length(sig_dates)])))

# ---- Step 2: universe filter per sig_date (K200 ∪ KQ150 + LIQ 2e8) ----
cat(sprintf("[%s] Step 2 — universe filter (K200 ∪ KQ150, LIQ 20d >= 2e8)\n", format(Sys.time(), "%H:%M:%S")))

raw[, TV := Close * Vol]
setorder(raw, Ticker, Date)
raw[, TV_20d := frollmean(TV, n = 20L, na.rm = TRUE), by = Ticker]

build_universe <- function(sd) {
  snap <- raw[Date == sd]
  if (nrow(snap) == 0) return(character(0))
  uni <- snap[(K200 == TRUE | KQ150 == TRUE) &
              TV_20d >= LIQ_THRESHOLD &
              AdminStock == FALSE &
              TradingHalt == FALSE &
              UnfaithfulDisc == FALSE,
              Ticker]
  unique(uni)
}

uni_list <- lapply(sig_dates, build_universe)
names(uni_list) <- as.character(sig_dates)
uni_size <- sapply(uni_list, length)
cat(sprintf("  Universe size: min=%d med=%d max=%d\n",
    min(uni_size), as.integer(median(uni_size)), max(uni_size)))

# ---- Step 3: forward 1M log return label (winsorize 99.5%) ----
cat(sprintf("[%s] Step 3 — forward 1M log return label\n", format(Sys.time(), "%H:%M:%S")))

me_seq <- month_ends[YM %in% ym_avail, Date]
me_seq <- sort(me_seq)

build_fwd_ret <- function(sd) {
  next_me <- me_seq[me_seq > sd][1]
  if (is.na(next_me)) return(NULL)
  snap_now  <- raw[Date == sd,      .(Ticker, P0 = Close)]
  snap_next <- raw[Date == next_me, .(Ticker, P1 = Close)]
  m <- merge(snap_now, snap_next, by = "Ticker", all = FALSE)
  m[, log_ret_1m := log(P1 / P0)]
  m[, sig_date := sd]
  m[, .(sig_date, Ticker, log_ret_1m)]
}

fwd_ret_list <- lapply(sig_dates, build_fwd_ret)
fwd_ret <- rbindlist(fwd_ret_list, fill = TRUE)
fwd_ret <- fwd_ret[!is.na(log_ret_1m)]

# Winsorize 99.5%
qlo <- quantile(fwd_ret$log_ret_1m, 0.005, na.rm = TRUE)
qhi <- quantile(fwd_ret$log_ret_1m, 0.995, na.rm = TRUE)
fwd_ret[, log_ret_1m_w := pmin(pmax(log_ret_1m, qlo), qhi)]
cat(sprintf("  Forward 1M log return — n=%d  Winsorize [%.4f, %.4f]\n",
    nrow(fwd_ret), qlo, qhi))

# ---- Step 4: Feature selection — selective daily factors (curse of dim avoidance) ----
# Strategy: select ~30 academically-validated daily factors from 298
# (focusing on momentum, volatility, liquidity, tail risk, growth — proven KR alpha pillars)
SEL_FACTORS <- c(
  # Momentum (8)
  "M01_Mom_12_1", "M02_Mom_6_1", "M03_Mom_3_1", "M04_Mom_1",
  "M11_ST_Reversal", "M13_VolAdj_Mom", "M22_Max_Return", "M29_Mom_5d",
  # Defense / Risk (8)
  "D01_IdioVol", "D02_Beta", "D03_RealVol", "D04_Downside_Beta",
  "D43_Skewness", "D44_Kurtosis", "D45_Downside_Dev", "D50_MaxDrawdown",
  # Liquidity / Microstructure (6)
  "L01_Amihud", "L02_Turnover", "L05_Dollar_Volume",
  "L13_Vol_Variance_Ratio", "L33_AbsRet_Vol_Corr", "L44_Vol_Ret_Asymmetry",
  # Value (3)
  "V01_BM", "V02_EP", "V10_FCF_Yield",
  # Quality (3)
  "Q02_ROE", "Q03_ROA", "Q08_Composite_Quality",
  # Size (2)
  "S01_Size", "L26_Log_MktCap",
  # Regime context (3)
  "RE_MRS", "RE_VIX_z", "RE_TS_z"
)
cat(sprintf("  Selected base factors: %d\n", length(SEL_FACTORS)))

# ---- Step 5: Load daily factor data for selected factors (efficient) ----
cat(sprintf("[%s] Step 5 — loading daily factor data (%d factors)\n",
    format(Sys.time(), "%H:%M:%S"), length(SEL_FACTORS)))

# We need ~180-day lookback before earliest sig_date for 120d rolling
earliest_sd <- min(sig_dates)
lookback_start <- earliest_sd - 250  # ~250 calendar days = ~180 trading days

# Find relevant months
parquet_paths <- file.path(DAILY_DB_DIR, paste0("fdb_daily_", ym_avail, ".parquet"))
parquet_paths <- parquet_paths[file.exists(parquet_paths)]

# Read only required columns (Date, Ticker, + SEL_FACTORS)
required_cols <- c("Date", "Ticker", SEL_FACTORS)
daily_list <- list()
for (pp in parquet_paths) {
  ym <- gsub(".*fdb_daily_(\\d{6})\\.parquet", "\\1", pp)
  # skip pre-lookback months
  ym_date <- as.Date(paste0(ym, "01"), "%Y%m%d")
  lookback_month_first <- as.Date(format(lookback_start, "%Y-%m-01"))
  if (ym_date < lookback_month_first) next
  # also skip post-cutoff
  if (ym_date > SIG_CUTOFF + 60) next
  tmp <- tryCatch({
    schema <- arrow::read_parquet(pp, col_select = NULL)
    avail_cols <- intersect(required_cols, names(schema))
    as.data.table(schema)[, ..avail_cols]
  }, error = function(e) NULL)
  if (!is.null(tmp) && nrow(tmp) > 0) daily_list[[ym]] <- tmp
}

if (length(daily_list) == 0) stop("No daily data loaded — check paths")

daily <- rbindlist(daily_list, fill = TRUE)
daily[, Date := as.Date(Date)]
setorder(daily, Ticker, Date)
cat(sprintf("  Daily data loaded: %d rows × %d cols\n", nrow(daily), ncol(daily)))

# ---- Step 6: Feature Engineering Block 1 — rolling moments per factor ----
cat(sprintf("[%s] Step 6 — Block 1: rolling moments (multi-horizon)\n", format(Sys.time(), "%H:%M:%S")))

# To avoid curse-of-dim: select 10 core factors for full rolling block expansion
# Other 23 factors: use cross-section z-score at sig_date only (no rolling expansion)
CORE_ROLL <- c("M01_Mom_12_1", "M04_Mom_1", "M11_ST_Reversal",
               "D01_IdioVol", "D03_RealVol", "D43_Skewness",
               "L02_Turnover", "L44_Vol_Ret_Asymmetry",
               "V02_EP", "Q02_ROE")
NON_ROLL <- setdiff(SEL_FACTORS, CORE_ROLL)
cat(sprintf("  Core (rolling): %d  Non-core (point): %d\n", length(CORE_ROLL), length(NON_ROLL)))

# Rolling functions per ticker — FAST VERSION using frollmean only
# Std computed via rolling variance identity: Var(X) = E[X^2] - (E[X])^2
# This avoids R callback overhead in frollapply (10-50x faster)

for (f in CORE_ROLL) {
  if (!(f %in% names(daily))) next

  # Step A: Mean (frollmean is C-builtin, very fast)
  daily[, paste0(f, "_mean_21d") := frollmean(get(f), n = 21L, fill = NA, align = "right", na.rm = FALSE), by = Ticker]
  daily[, paste0(f, "_mean_60d") := frollmean(get(f), n = 60L, fill = NA, align = "right", na.rm = FALSE), by = Ticker]

  # Step B: Mean of squared (for variance identity)
  daily[, .tmp_xsq := get(f) ^ 2]
  daily[, .tmp_mxsq_21 := frollmean(.tmp_xsq, n = 21L, fill = NA, align = "right", na.rm = FALSE), by = Ticker]
  daily[, .tmp_mxsq_60 := frollmean(.tmp_xsq, n = 60L, fill = NA, align = "right", na.rm = FALSE), by = Ticker]

  # Step C: Variance + std (no callback)
  mean_21 <- paste0(f, "_mean_21d")
  mean_60 <- paste0(f, "_mean_60d")
  daily[, paste0(f, "_std_21d") := sqrt(pmax(.tmp_mxsq_21 - (get(mean_21)) ^ 2, 0))]
  daily[, paste0(f, "_std_60d") := sqrt(pmax(.tmp_mxsq_60 - (get(mean_60)) ^ 2, 0))]

  # Step D: Z-score 60d
  std_60 <- paste0(f, "_std_60d")
  daily[, paste0(f, "_zscore_60d") := (get(f) - get(mean_60)) / (get(std_60) + 1e-8)]

  # Cleanup temps
  daily[, c(".tmp_xsq", ".tmp_mxsq_21", ".tmp_mxsq_60") := NULL]
}
cat(sprintf("  Block 1 done: %d new cols\n", ncol(daily) - 2 - length(SEL_FACTORS)))

# ---- Step 7: Snapshot at sig_date (t-1 lag strict) ----
cat(sprintf("[%s] Step 7 — Monthly snapshot at sig_date (t-1 lag strict)\n", format(Sys.time(), "%H:%M:%S")))

# For each sig_date, take snapshot of all features at sig_date (the daily data on sig_date is t-1 PIT since computed up to and including sig_date)
# CORRECTION: We use Date == sig_date snapshot. The features at sig_date are computed using daily data INCLUDING sig_date (sig_date close prices).
# To be strict PIT: features must be computed using data <= sig_date - 1 trading day.
# Approach: shift daily features by 1 day (use yesterday's snapshot as today's feature).

# Find the trading day prior to each sig_date
all_trade_days <- sort(unique(daily$Date))
cat(sprintf("  Daily Date range: %s -> %s  (%d unique days)\n",
    as.character(min(all_trade_days)), as.character(max(all_trade_days)), length(all_trade_days)))

sig_to_lag_map <- sapply(sig_dates, function(sd) {
  prev_days <- all_trade_days[all_trade_days < sd]
  if (length(prev_days) == 0) return(NA_character_)
  as.character(max(prev_days))
})
n_mapped <- sum(!is.na(sig_to_lag_map))
cat(sprintf("  Mapped %d / %d sig_dates to t-1 trading days\n", n_mapped, length(sig_dates)))
if (n_mapped > 0) {
  first_lag <- sig_to_lag_map[which(!is.na(sig_to_lag_map))[1]]
  cat(sprintf("  First sig→lag: %s -> %s\n", as.character(sig_dates[which(!is.na(sig_to_lag_map))[1]]), first_lag))
}

# Set key for faster filter
setkey(daily, Date, Ticker)

# Build snapshot panel — vectorized via merge
sig_lag_dt <- data.table(
  sig_date = sig_dates,
  lag_date = as.Date(sig_to_lag_map)
)
sig_lag_dt <- sig_lag_dt[!is.na(lag_date)]

# Build all (lag_date, Ticker) pairs to filter daily
snap_keys <- data.table()
for (i in seq_len(nrow(sig_lag_dt))) {
  sd <- sig_lag_dt$sig_date[i]
  ld <- sig_lag_dt$lag_date[i]
  uni_now <- uni_list[[as.character(sd)]]
  if (length(uni_now) == 0) next
  snap_keys <- rbind(snap_keys,
    data.table(sig_date = sd, lag_date = ld, Ticker = uni_now))
}
cat(sprintf("  snap_keys: %d (sig_date, lag_date, Ticker) tuples\n", nrow(snap_keys)))

if (nrow(snap_keys) == 0) {
  cat("WARN: No snap_keys built — universe filter or lag_date mapping failed\n")
  cat(sprintf("  uni_list non-empty count: %d / %d\n",
      sum(sapply(uni_list, length) > 0), length(uni_list)))
}

# Filter daily by (Date, Ticker) match
setnames(snap_keys, "lag_date", "Date")
snap_panel <- merge(daily, snap_keys[, .(sig_date, Date, Ticker)],
  by = c("Date", "Ticker"), all.x = FALSE, all.y = TRUE)
snap_panel[, Date := NULL]  # drop daily Date
cat(sprintf("  Snapshot panel: %d rows × %d cols\n", nrow(snap_panel), ncol(snap_panel)))

# ---- Step 8: Block 2 — rank dynamics (cross-section) ----
cat(sprintf("[%s] Step 8 — Block 2: rank dynamics (cross-section)\n", format(Sys.time(), "%H:%M:%S")))

# For each sig_date, compute cross-section percentile rank for core factors
for (f in CORE_ROLL) {
  if (!(f %in% names(snap_panel))) next
  snap_panel[, paste0(f, "_rank_pct") := frank(get(f), ties.method = "average", na.last = "keep") / .N, by = sig_date]
}

# Rank change: previous sig_date vs current
setorder(snap_panel, Ticker, sig_date)
for (f in CORE_ROLL) {
  rank_col <- paste0(f, "_rank_pct")
  if (!(rank_col %in% names(snap_panel))) next
  snap_panel[, paste0(f, "_rank_change") := get(rank_col) - shift(get(rank_col), n = 1L, type = "lag"), by = Ticker]
}

# ---- Step 9: Block 4 — cross-factor interactions (selective) ----
cat(sprintf("[%s] Step 9 — Block 4: cross-factor interactions\n", format(Sys.time(), "%H:%M:%S")))

# Z-score normalize for interaction
zscore_xs <- function(x) {
  mu <- mean(x, na.rm = TRUE)
  sd <- sd(x, na.rm = TRUE)
  if (is.na(sd) || sd == 0) return(rep(0, length(x)))
  (x - mu) / sd
}

# Cross-section z-score per sig_date for interaction inputs
for (f in c("V01_BM", "V02_EP", "M01_Mom_12_1", "M02_Mom_6_1", "Q08_Composite_Quality",
            "D02_Beta", "D43_Skewness", "D44_Kurtosis", "M22_Max_Return", "L02_Turnover")) {
  if (!(f %in% names(snap_panel))) next
  snap_panel[, paste0(f, "_zxs") := zscore_xs(get(f)), by = sig_date]
}

# Academic interactions
if (all(c("V01_BM_zxs", "M01_Mom_12_1_zxs") %in% names(snap_panel)))
  snap_panel[, int_value_mom := V01_BM_zxs * M01_Mom_12_1_zxs]
if (all(c("Q08_Composite_Quality_zxs", "D02_Beta_zxs") %in% names(snap_panel)))
  snap_panel[, int_quality_lowbeta := Q08_Composite_Quality_zxs * (-D02_Beta_zxs)]
if (all(c("D43_Skewness_zxs", "M22_Max_Return_zxs") %in% names(snap_panel)))
  snap_panel[, int_skew_max := D43_Skewness_zxs * M22_Max_Return_zxs]
if (all(c("D44_Kurtosis_zxs", "L02_Turnover_zxs") %in% names(snap_panel)))
  snap_panel[, int_kurt_turn := D44_Kurtosis_zxs * L02_Turnover_zxs]

# ---- Step 10: Merge forward return label ----
cat(sprintf("[%s] Step 10 — merge forward 1M log return label\n", format(Sys.time(), "%H:%M:%S")))

panel <- merge(snap_panel, fwd_ret[, .(sig_date, Ticker, log_ret_1m_w)],
               by = c("sig_date", "Ticker"), all.x = FALSE, all.y = FALSE)
cat(sprintf("  Final panel: %d rows × %d cols (with label)\n", nrow(panel), ncol(panel)))

# Sector for neutralization (optional ML feature)
sector_dt <- raw[, .(Ticker, Date, Sector_Lv2)]
sector_dt <- sector_dt[, .SD[.N], by = Ticker]  # most recent sector per ticker
panel <- merge(panel, sector_dt[, .(Ticker, Sector_Lv2)], by = "Ticker", all.x = TRUE)

# ---- Step 11: Save ----
cat(sprintf("[%s] Step 11 — saving panel\n", format(Sys.time(), "%H:%M:%S")))
out_panel <- file.path(OUT_DIR, "ml_panel_train.parquet")
write_parquet(panel, out_panel)
cat(sprintf("  Saved: %s (%d rows × %d cols)\n", out_panel, nrow(panel), ncol(panel)))

# Feature column list (for ML downstream)
feature_cols <- setdiff(names(panel),
  c("sig_date", "Ticker", "log_ret_1m_w", "Sector_Lv2"))
cat(sprintf("  Feature cols: %d\n", length(feature_cols)))

writeLines(feature_cols, file.path(OUT_DIR, "feature_cols.txt"))

# Save sig_date list for downstream Python
saveRDS(list(
  sig_dates = sig_dates,
  feature_cols = feature_cols,
  uni_size = uni_size,
  panel_rows = nrow(panel),
  build_time_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
), file.path(OUT_DIR, "panel_meta.rds"))

# Also save JSON for Python
write_json(list(
  sig_date_first = as.character(min(sig_dates)),
  sig_date_last  = as.character(max(sig_dates)),
  sig_date_count = length(sig_dates),
  feature_cols_n = length(feature_cols),
  panel_rows = nrow(panel),
  build_time_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
), file.path(OUT_DIR, "panel_summary.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n=== Step 1 COMPLETE — elapsed %.2f min ===\n",
    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
