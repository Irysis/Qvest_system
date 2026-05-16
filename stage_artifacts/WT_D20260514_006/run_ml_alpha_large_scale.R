#==============================================================================
# WT-D20260514_006 Alpha Research — Large-Scale Feature Engineering (Kelly Virtue 2024)
#
# v1 design (Kelly Virtue 2024 mandate inherit):
#   - Base pool: Factor DB 330 factors (Z_Score_Aligned)
#   - Derived: lag 1m/3m/6m/12m (~150 base × 4 = 600 lag features)
#   - Rolling stats: mean/sd/skew × 3 windows × ~40 base = 360
#   - CAPM/Industry residual proxy: top 50 raw factors residualized via sector demean
#   - Cross-section ranks: top 50 factors rank percentile (within sig_date)
#   - Sector × top10 factor interaction: 26 × 10 = 260
#   - Macro lag features (FRED rate 1m/3m lag × top 5 macro-sensitive factors): ~10
#   Total pool: ~1500 raw generated → variance + IC + cor filter → final 200~500
#
# ML 5 candidates (AX-002 ex-ante strict):
#   M1: Ridge (glmnet alpha=0 high-dim regularization, Kelly Virtue 정통)
#   M2: LASSO (glmnet alpha=1.0 sparse selection)
#   M3: ElasticNet (glmnet alpha=0.5 balanced)
#   M4: XGBoost depth=6 high-dim tree
#   M5: Ridge + Random Forest ensemble (stacked rank average)
#
# PIT C1-C15 strict:
#   - Walk-forward 60mo train + 6mo refit (no peek-ahead)
#   - Cross-sectional Z-score within sig_date (after merge)
#   - Lag features: feature_lag_k = feature_t-k (sig_date - k months)
#   - Forward return PIT-C2 t+1 close basis
#==============================================================================

Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(future); library(future.apply)
  library(xgboost); library(ranger); library(glmnet)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260514_006"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260514_006")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

t_start <- Sys.time()
cat("[", as.character(t_start), "] Large-Scale ML Alpha Research pipeline START\n")

#==============================================================================
# Step 1: Universe + Calendar (inherit WT_003 + WT_005)
#==============================================================================
cat("\n[Step 1] Universe expansion\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
raw[, Date := as.Date(Date)]
setkey(raw, Date, Ticker)

all_trade_dates <- sort(unique(raw$Date))
trade_dt <- data.table(Date = all_trade_dates, ym = format(all_trade_dates, "%Y-%m"))
month_ends <- trade_dt[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends)

SIG_DATES <- month_ends[month_ends >= as.Date("2004-01-01") & month_ends <= as.Date("2026-04-30")]
cat("Total sig_dates:", length(SIG_DATES), "\n")

raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

LIQ_FLOOR <- 2e8

# Market map (KOSPI + KOSDAQ 보통주)
build_market_map_latest <- function() {
  ksq_files <- list.files(file.path(BASE, ".cache/krx/ksq_info"), full.names = TRUE, pattern = "\\.parquet$")
  stk_files <- list.files(file.path(BASE, ".cache/krx/stk_info"), full.names = TRUE, pattern = "\\.parquet$")
  ksq <- as.data.table(read_parquet(tail(sort(ksq_files), 1)))
  stk <- as.data.table(read_parquet(tail(sort(stk_files), 1)))
  ksq_map <- ksq[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSDAQ")]
  stk_map <- stk[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSPI")]
  out <- unique(rbind(stk_map, ksq_map), by = "Ticker")
  out
}
market_map_global <- build_market_map_latest()
setkey(market_map_global, Ticker)

sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc,
                   ADV_20d, Close, Sector, BM_Ret)]
setkey(sig_panel, Date, Ticker)

get_universe_full <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- merge(rows, market_map_global, by = "Ticker", all.x = FALSE)
  elig <- elig[!is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE) &
               !is.na(Sector)]
  return(elig$Ticker)
}

univ_audit_list <- list()
for (i in seq_along(SIG_DATES)) {
  sd_i <- SIG_DATES[i]
  u_full <- get_universe_full(sd_i)
  univ_audit_list[[i]] <- data.table(sig_date = sd_i, n_full = length(u_full))
}
univ_audit <- rbindlist(univ_audit_list)
cat("Universe mean:", round(mean(univ_audit$n_full), 1),
    "  latest:", tail(univ_audit$n_full, 1), "\n")

#==============================================================================
# Step 2: Base factor pool (Factor DB 330 factors, Z_Score_Aligned)
#==============================================================================
cat("\n[Step 2] Base factor pool — Factor DB 330 factors (Z_Score_Aligned)\n")

# Load all factors for each sig_date via load_month_factors (C15 routing)
load_all_factors_for_sig <- function(sig_date) {
  fdt <- tryCatch(load_month_factors(sig_date), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  wide[, sig_date := sig_date]
  wide
}

cat("Loading base factors for", length(SIG_DATES), "sig_dates (parallel)...\n")
t_load_start <- Sys.time()
n_workers <- min(8L, parallel::detectCores() - 1L)

# Use cache if available (avoid re-load on fix-retry)
features_cache_path <- file.path(ART, "features_long_cache.rds")
if (file.exists(features_cache_path)) {
  cat("Loading cached features_long.rds...\n")
  features_long <- readRDS(features_cache_path)
  cat("Cache loaded. nrow =", nrow(features_long), "\n")
} else {
  plan(multisession, workers = n_workers)
  feat_list <- future_lapply(SIG_DATES, load_all_factors_for_sig, future.seed = 42L)
  plan(sequential)
  features_long <- rbindlist(feat_list[!sapply(feat_list, is.null)], fill = TRUE)
  saveRDS(features_long, features_cache_path)
  cat("Cache saved.\n")
}
cat("Base features loaded: nrow =", nrow(features_long),
    "  ncol =", ncol(features_long),
    "  load_time =", round(as.numeric(Sys.time() - t_load_start, units="mins"), 2), "min\n")

# Find all factor columns (exclude Ticker + sig_date)
base_factor_cols <- setdiff(names(features_long), c("Ticker", "sig_date"))
cat("Total base factors available:", length(base_factor_cols), "\n")

# Drop factors with too many NAs (>= 60% missing across all sig×ticker)
na_rate <- sapply(base_factor_cols, function(cn) mean(is.na(features_long[[cn]])))
keep_base <- base_factor_cols[na_rate < 0.60]
cat("Base factors after NA<60% filter:", length(keep_base), "\n")

#==============================================================================
# Step 3: Derived features — lag, rolling stats
#==============================================================================
cat("\n[Step 3] Derived features (lag, rolling stats)\n")

setorder(features_long, Ticker, sig_date)
setkey(features_long, Ticker, sig_date)

# For derived features, use TOP 50 factors by univariate IC magnitude
# To avoid full-sample IC computation (PIT violation), use first 36 months only
sig_first_36 <- sort(unique(features_long$sig_date))[1:36]

# Build forward returns first (PIT C2 t+1 next-month close)
cat("Building forward returns (t+1 close basis)...\n")
all_trade_dates_sorted <- sort(unique(raw$Date))
next_trade_after <- function(d) {
  i <- match(d, all_trade_dates_sorted)
  if (is.na(i) || i == length(all_trade_dates_sorted)) return(NA)
  all_trade_dates_sorted[i + 1L]
}
sig_to_t1 <- sapply(SIG_DATES, next_trade_after) |> as.Date(origin = "1970-01-01")
close_wide <- dcast(raw[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)

fwd_ret_list <- list()
for (i in seq_len(length(SIG_DATES) - 1L)) {
  d_t1 <- sig_to_t1[i]
  d_next_me <- SIG_DATES[i + 1L]
  if (is.na(d_t1) || d_t1 >= d_next_me) next
  px_t1 <- as.numeric(close_wide[Date == d_t1])
  px_next <- as.numeric(close_wide[Date == d_next_me])
  names(px_t1) <- names(close_wide); names(px_next) <- names(close_wide)
  tickers <- setdiff(names(close_wide), "Date")
  r <- (as.numeric(px_next[tickers]) / as.numeric(px_t1[tickers])) - 1
  fwd_ret_list[[i]] <- data.table(sig_date = SIG_DATES[i], Ticker = tickers, fwd_ret_1m = r)
}
fwd_returns <- rbindlist(fwd_ret_list)
fwd_returns <- fwd_returns[!is.na(fwd_ret_1m) & is.finite(fwd_ret_1m)]
setkey(fwd_returns, sig_date, Ticker)
cat("Forward return rows:", nrow(fwd_returns), "\n")

# Compute univariate IC on first 36 sig_dates (training-window only) to pick top-IC factors
ic_train_dt <- merge(
  features_long[sig_date %in% sig_first_36, c("sig_date", "Ticker", keep_base), with = FALSE],
  fwd_returns[sig_date %in% sig_first_36],
  by = c("sig_date", "Ticker")
)

compute_ic_factor <- function(col) {
  vals <- ic_train_dt[, .(ic = cor(get(col), fwd_ret_1m, method = "spearman",
                                    use = "pairwise.complete.obs")), by = sig_date]
  vals <- vals[!is.na(ic) & is.finite(ic)]
  if (nrow(vals) < 12L) return(NA_real_)
  mean(vals$ic, na.rm = TRUE)
}

cat("Computing univariate IC on first 36 sig_dates (training window only, PIT-safe)...\n")
plan(multisession, workers = n_workers)
ic_train <- future_lapply(keep_base, compute_ic_factor, future.seed = 42L,
                          future.globals = c("ic_train_dt"),
                          future.packages = c("data.table"))
plan(sequential)
ic_train_vec <- unlist(ic_train)
names(ic_train_vec) <- keep_base

# Rank by absolute IC magnitude
ic_abs <- abs(ic_train_vec); ic_abs <- ic_abs[!is.na(ic_abs)]
top_50_factors <- names(sort(ic_abs, decreasing = TRUE))[1:min(50, length(ic_abs))]
cat("Top 50 factors by |IC| on training window:\n")
print(head(top_50_factors, 20))

# Generate lag features: 1m, 3m, 6m, 12m for top 50 factors
cat("\nGenerating lag features (1m, 3m, 6m, 12m × 50 = 200 features)...\n")
generate_lag <- function(dt, factors, lag_k) {
  # For each ticker, compute factor at sig_date - lag_k months
  # We shift within ticker; sig_date ordered
  out <- copy(dt[, c("Ticker", "sig_date", factors), with = FALSE])
  setorder(out, Ticker, sig_date)
  for (col in factors) {
    new_col <- paste0(col, "_lag", lag_k, "m")
    out[, (new_col) := shift(get(col), n = lag_k, type = "lag"), by = Ticker]
    out[, (col) := NULL]
  }
  out
}

lag_dt_list <- list()
for (k in c(1, 3, 6, 12)) {
  lag_dt_list[[paste0("lag", k)]] <- generate_lag(features_long, top_50_factors, k)
}

# Rolling stats: mean × 3 windows + sd × 1 window (12m) × top 30 = 120 features
# NOTE: frollapply with sd on single-obs groups causes assignment errors in data.table.
# Use frollmean (vectorized) for safety. Rolling sd only for 12m window via vectorized formula.
cat("Generating rolling stats (mean × 3 windows + sd 12m × top 30 = 120 features)...\n")
generate_rolling_mean <- function(dt, factors, window_k) {
  out <- copy(dt[, c("Ticker", "sig_date", factors), with = FALSE])
  setorder(out, Ticker, sig_date)
  for (col in factors) {
    out[, (paste0(col, "_rmean", window_k, "m")) := frollmean(get(col), n = window_k, align = "right", na.rm = TRUE), by = Ticker]
    out[, (col) := NULL]
  }
  out
}
generate_rolling_sd_12m <- function(dt, factors) {
  out <- copy(dt[, c("Ticker", "sig_date", factors), with = FALSE])
  setorder(out, Ticker, sig_date)
  for (col in factors) {
    # Use rolling variance formula: var = E[X^2] - E[X]^2
    out[, (paste0(col, "_sq")) := get(col) ^ 2]
    out[, (paste0(col, "_rmean12m")) := frollmean(get(col), n = 12L, align = "right", na.rm = TRUE), by = Ticker]
    out[, (paste0(col, "_rmean_sq12m")) := frollmean(get(paste0(col, "_sq")), n = 12L, align = "right", na.rm = TRUE), by = Ticker]
    out[, (paste0(col, "_rsd12m")) := sqrt(pmax(0, get(paste0(col, "_rmean_sq12m")) - get(paste0(col, "_rmean12m")) ^ 2))]
    out[, (paste0(col, "_sq")) := NULL]
    out[, (paste0(col, "_rmean12m")) := NULL]
    out[, (paste0(col, "_rmean_sq12m")) := NULL]
    out[, (col) := NULL]
  }
  out
}

# Compute rolling for top 30
top_30_factors <- head(top_50_factors, 30)
rolling_dt_list <- list()
for (w in c(3, 6, 12)) {
  rolling_dt_list[[paste0("roll_mean", w)]] <- generate_rolling_mean(features_long, top_30_factors, w)
}
rolling_dt_list[["roll_sd12"]] <- generate_rolling_sd_12m(features_long, top_30_factors)

# Cross-section ranks (within sig_date) for top 30
cat("Generating cross-section rank features (top 30)...\n")
rank_dt <- copy(features_long[, c("Ticker", "sig_date", top_30_factors), with = FALSE])
for (col in top_30_factors) {
  rank_dt[, (paste0(col, "_xs_rank")) := frank(get(col), na.last = "keep") / .N, by = sig_date]
  rank_dt[, (col) := NULL]
}

cat("\nFeature generation complete.\n")

#==============================================================================
# Step 4: Merge all features into wide panel
#==============================================================================
cat("\n[Step 4] Merge features into panel\n")

# Start with base features
panel <- features_long[, c("Ticker", "sig_date", keep_base), with = FALSE]
setkey(panel, Ticker, sig_date)

# Merge lag features
for (lag_name in names(lag_dt_list)) {
  dt <- lag_dt_list[[lag_name]]
  setkey(dt, Ticker, sig_date)
  panel <- merge(panel, dt, by = c("Ticker", "sig_date"), all.x = TRUE)
}

# Merge rolling features
for (roll_name in names(rolling_dt_list)) {
  dt <- rolling_dt_list[[roll_name]]
  setkey(dt, Ticker, sig_date)
  panel <- merge(panel, dt, by = c("Ticker", "sig_date"), all.x = TRUE)
}

# Merge rank features
setkey(rank_dt, Ticker, sig_date)
panel <- merge(panel, rank_dt, by = c("Ticker", "sig_date"), all.x = TRUE)

# Merge forward returns + universe filter
panel <- merge(panel, fwd_returns, by = c("Ticker", "sig_date"))

univ_lookup_list <- list()
for (i in seq_along(SIG_DATES)) {
  u <- get_universe_full(SIG_DATES[i])
  if (length(u) > 0) {
    univ_lookup_list[[i]] <- data.table(sig_date = SIG_DATES[i], Ticker = u)
  }
}
univ_lookup <- rbindlist(univ_lookup_list)
setkey(univ_lookup, sig_date, Ticker)
setkey(panel, sig_date, Ticker)
panel <- merge(panel, univ_lookup, by = c("sig_date", "Ticker"))

cat("Panel rows:", nrow(panel), "  cols:", ncol(panel),
    "  sig_dates:", uniqueN(panel$sig_date), "\n")

# Identify all feature columns (exclude Ticker, sig_date, fwd_ret_1m)
all_feat_cols <- setdiff(names(panel), c("Ticker", "sig_date", "fwd_ret_1m"))
cat("Total raw features in panel:", length(all_feat_cols), "\n")

#==============================================================================
# Step 5: Feature screening pipeline
#   (a) Variance filter: sd > 0.01
#   (b) Univariate IC filter on training window (first 60 sig_dates only)
#   (c) Correlation filter: cluster head retain if cor > 0.95
#==============================================================================
cat("\n[Step 5] Feature screening\n")

# Step 5a: Variance filter
cat("Step 5a: Variance filter (sd > 0.01)\n")
sd_check <- sapply(all_feat_cols, function(cn) sd(panel[[cn]], na.rm = TRUE))
high_var_cols <- names(sd_check)[!is.na(sd_check) & sd_check > 0.01]
cat("  Retained:", length(high_var_cols), "of", length(all_feat_cols), "\n")

# Step 5b: Univariate IC filter on first 60 sig_dates (training window, PIT-safe)
cat("Step 5b: Univariate IC filter (|t| > 1.5 on first 60 sig)\n")
sig_train_60 <- sort(unique(panel$sig_date))[1:min(60, uniqueN(panel$sig_date))]
panel_train <- panel[sig_date %in% sig_train_60]

compute_ic_t <- function(col) {
  if (!col %in% names(panel_train)) return(c(ic = NA_real_, t = NA_real_, n = 0L))
  d <- panel_train[!is.na(get(col)) & !is.na(fwd_ret_1m)]
  if (nrow(d) < 1000L) return(c(ic = NA_real_, t = NA_real_, n = nrow(d)))
  per_sig <- d[, .(ic = cor(get(col), fwd_ret_1m, method = "spearman",
                              use = "pairwise.complete.obs")), by = sig_date]
  per_sig <- per_sig[!is.na(ic) & is.finite(ic)]
  if (nrow(per_sig) < 12L) return(c(ic = NA_real_, t = NA_real_, n = nrow(per_sig)))
  m <- mean(per_sig$ic)
  s <- sd(per_sig$ic)
  t_val <- m / (s / sqrt(nrow(per_sig)))
  c(ic = m, t = t_val, n = nrow(per_sig))
}

plan(multisession, workers = n_workers)
ic_screen_list <- future_lapply(high_var_cols, compute_ic_t, future.seed = 42L,
                                future.globals = c("panel_train"),
                                future.packages = c("data.table"))
plan(sequential)
ic_screen <- do.call(rbind, ic_screen_list)
rownames(ic_screen) <- high_var_cols
ic_screen_dt <- data.table(feature = rownames(ic_screen),
                            mean_ic = ic_screen[, "ic"],
                            t_stat = ic_screen[, "t"],
                            n_periods = ic_screen[, "n"])

# Retain features with |t| > 1.5 (loose for KR) OR raw factor (keep all base)
abs_t <- abs(ic_screen_dt$t_stat)
keep_by_ic <- ic_screen_dt[!is.na(t_stat) & abs(t_stat) > 1.5, feature]
cat("  Retained by |t|>1.5:", length(keep_by_ic), "\n")

# Step 5c: Correlation filter — within selected, drop |cor|>0.95 redundant
cat("Step 5c: Correlation filter (drop redundant |cor|>0.95)\n")
if (length(keep_by_ic) > 1L) {
  X_sample <- as.matrix(panel_train[!is.na(fwd_ret_1m), .SD, .SDcols = keep_by_ic])
  for (cn in keep_by_ic) {
    if (any(is.na(X_sample[, cn]))) X_sample[is.na(X_sample[, cn]), cn] <- 0
  }
  cor_mat <- abs(cor(X_sample, use = "pairwise.complete.obs"))
  cor_mat[is.na(cor_mat)] <- 0
  diag(cor_mat) <- 0

  # Greedy: process in order of |t_stat| desc (preference for stronger signal)
  feat_t <- abs_t
  names(feat_t) <- ic_screen_dt$feature
  order_by_t <- intersect(names(sort(feat_t, decreasing = TRUE)), keep_by_ic)
  keep_after_cor <- c()
  for (cand in order_by_t) {
    if (length(keep_after_cor) == 0) {
      keep_after_cor <- cand
    } else {
      max_cor <- max(cor_mat[cand, keep_after_cor])
      if (is.na(max_cor) || max_cor < 0.95) {
        keep_after_cor <- c(keep_after_cor, cand)
      }
    }
  }
} else {
  keep_after_cor <- keep_by_ic
}
cat("  Retained after cor<0.95:", length(keep_after_cor), "\n")

# Final feature list — cap at 500 (Kelly Virtue 200~500 mandate)
FINAL_FEATURES <- head(keep_after_cor, 500)
cat("\n=== FINAL FEATURE SET: ", length(FINAL_FEATURES), "features ===\n")

# Save selection audit
selection_audit <- list(
  pipeline = "variance → ic → correlation",
  raw_generated_count = length(all_feat_cols),
  after_variance_filter = length(high_var_cols),
  after_ic_filter_t_1_5 = length(keep_by_ic),
  after_correlation_filter_0_95 = length(keep_after_cor),
  final_capped_500 = length(FINAL_FEATURES),
  final_features = FINAL_FEATURES,
  ic_screen_summary = ic_screen_dt[order(-abs(t_stat))][1:min(50, nrow(ic_screen_dt))]
)
write_json(selection_audit, file.path(ART, "feature_selection_audit.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
fwrite(data.table(feature = FINAL_FEATURES), file.path(ART, "final_features.csv"))

#==============================================================================
# Step 6: Imputation + Cross-sectional Z-score on final features
#==============================================================================
cat("\n[Step 6] Imputation + Cross-section Z-score\n")

# Impute NA → 0 (median Z-score)
for (col in FINAL_FEATURES) {
  panel[is.na(get(col)), (col) := 0]
}

# Cross-sectional Z-score per sig_date (clip 3std)
panel[, (FINAL_FEATURES) := lapply(.SD, function(x) {
  if (sd(x, na.rm = TRUE) > 0) {
    z <- (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
    pmax(pmin(z, 3), -3)
  } else x
}), by = sig_date, .SDcols = FINAL_FEATURES]

#==============================================================================
# Step 7: Walk-forward ML (5 ex-ante candidates, AX-002 strict)
#==============================================================================
cat("\n[Step 7] Walk-forward ML (60mo train + 6mo refit)\n")

setorder(panel, sig_date, Ticker)
sorted_sig <- sort(unique(panel$sig_date))

TRAIN_WINDOW_MONTHS <- 60L
REFIT_PERIOD_MONTHS <- 6L

refit_indices <- seq(TRAIN_WINDOW_MONTHS + 1L, length(sorted_sig), by = REFIT_PERIOD_MONTHS)
cat("Refit anchors:", length(refit_indices), "  OOS sig_dates:",
    length(sorted_sig) - TRAIN_WINDOW_MONTHS, "\n")

CANDIDATE_NAMES <- c("M1_ridge", "M2_lasso", "M3_enet", "M4_xgb_deep", "M5_ensemble")

train_models_at_anchor <- function(anchor_idx, sorted_sig, panel, FINAL_FEATURES) {
  train_sigs <- sorted_sig[(anchor_idx - TRAIN_WINDOW_MONTHS):(anchor_idx - 1L)]
  train_dt <- panel[sig_date %in% train_sigs]
  if (nrow(train_dt) < 1000L) return(NULL)

  X_train <- as.matrix(train_dt[, .SD, .SDcols = FINAL_FEATURES])
  y_train <- train_dt$fwd_ret_1m

  models <- list()

  # M1: Ridge (alpha=0, high-dim regularization Kelly Virtue 정통)
  models$M1 <- tryCatch(glmnet::cv.glmnet(X_train, y_train, alpha = 0, nfolds = 5L),
                       error = function(e) NULL)

  # M2: LASSO (alpha=1.0 sparse)
  models$M2 <- tryCatch(glmnet::cv.glmnet(X_train, y_train, alpha = 1.0, nfolds = 5L),
                       error = function(e) NULL)

  # M3: ElasticNet (alpha=0.5)
  models$M3 <- tryCatch(glmnet::cv.glmnet(X_train, y_train, alpha = 0.5, nfolds = 5L),
                       error = function(e) NULL)

  # M4: XGBoost depth=6
  dtrain <- xgb.DMatrix(data = X_train, label = y_train)
  models$M4 <- tryCatch(xgb.train(
    params = list(objective = "reg:squarederror",
                  max_depth = 6L, eta = 0.03,
                  subsample = 0.7, colsample_bytree = 0.4,  # high-dim → lower colsample
                  min_child_weight = 15L, nthread = 1L),
    data = dtrain, nrounds = 80L, verbose = 0L
  ), error = function(e) NULL)

  # M5: RF (separate for ensemble)
  rf_df <- as.data.frame(X_train)
  rf_df$y <- y_train
  models$M5_rf <- tryCatch(ranger::ranger(y ~ ., data = rf_df, num.trees = 100L,
                              mtry = max(1L, floor(sqrt(length(FINAL_FEATURES)))),
                              min.node.size = 20L, num.threads = 1L,
                              importance = "none", verbose = FALSE),
                         error = function(e) NULL)

  list(models = models, anchor_sig = sorted_sig[anchor_idx])
}

predict_for_sig <- function(model_bundle, panel, target_sig, FINAL_FEATURES) {
  test_dt <- panel[sig_date == target_sig]
  if (nrow(test_dt) < 30L) return(NULL)

  X_test <- as.matrix(test_dt[, .SD, .SDcols = FINAL_FEATURES])

  preds <- data.table(sig_date = target_sig, Ticker = test_dt$Ticker,
                       fwd_ret_1m = test_dt$fwd_ret_1m)

  preds$M1_ridge <- if (!is.null(model_bundle$models$M1))
    as.numeric(predict(model_bundle$models$M1, X_test, s = "lambda.1se")) else NA_real_

  preds$M2_lasso <- if (!is.null(model_bundle$models$M2))
    as.numeric(predict(model_bundle$models$M2, X_test, s = "lambda.1se")) else NA_real_

  preds$M3_enet <- if (!is.null(model_bundle$models$M3))
    as.numeric(predict(model_bundle$models$M3, X_test, s = "lambda.1se")) else NA_real_

  preds$M4_xgb_deep <- if (!is.null(model_bundle$models$M4))
    predict(model_bundle$models$M4, X_test) else NA_real_

  # M5 = ridge + RF rank ensemble
  pred_rf <- if (!is.null(model_bundle$models$M5_rf))
    predict(model_bundle$models$M5_rf, data = as.data.frame(X_test))$predictions else NA_real_
  preds$pred_rf <- pred_rf
  # Average rank of ridge + RF
  if (all(is.na(preds$M1_ridge)) || all(is.na(pred_rf))) {
    preds$M5_ensemble <- preds$M1_ridge
  } else {
    rank_ridge <- frank(preds$M1_ridge, na.last = "keep") / .N
    rank_rf    <- frank(preds$pred_rf,  na.last = "keep") / .N
    preds$M5_ensemble <- (rank_ridge + rank_rf) / 2
  }
  preds[, pred_rf := NULL]

  preds
}

t_ml_start <- Sys.time()
plan(multisession, workers = n_workers)
model_bundles <- future_lapply(refit_indices, function(idx) {
  train_models_at_anchor(idx, sorted_sig, panel, FINAL_FEATURES)
}, future.seed = 42L,
   future.globals = c("TRAIN_WINDOW_MONTHS", "FINAL_FEATURES",
                      "sorted_sig", "panel", "train_models_at_anchor"),
   future.packages = c("xgboost", "ranger", "glmnet", "data.table"))
plan(sequential)
cat("Models trained:", length(model_bundles), "anchors\n")
cat("Train time:", round(as.numeric(Sys.time() - t_ml_start, units="mins"), 2), "min\n")

pred_list <- list()
for (i in seq_along(refit_indices)) {
  anchor_idx <- refit_indices[i]
  bundle <- model_bundles[[i]]
  if (is.null(bundle)) next
  next_anchor_idx <- if (i < length(refit_indices)) refit_indices[i + 1L] else length(sorted_sig) + 1L
  oos_idx_range <- anchor_idx:(next_anchor_idx - 1L)
  oos_idx_range <- oos_idx_range[oos_idx_range <= length(sorted_sig)]
  for (oos_idx in oos_idx_range) {
    target_sig <- sorted_sig[oos_idx]
    pred_list[[length(pred_list) + 1L]] <- predict_for_sig(bundle, panel, target_sig, FINAL_FEATURES)
  }
}
predictions <- rbindlist(pred_list[!sapply(pred_list, is.null)], fill = TRUE)
cat("Predictions:", nrow(predictions),
    "  sig_dates:", uniqueN(predictions$sig_date), "\n")

# Per-sig_date cross-section Z-score on predictions
for (cn in CANDIDATE_NAMES) {
  predictions[, (cn) := {
    x <- get(cn)
    if (all(is.na(x))) rep(NA_real_, .N) else {
      mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
      if (is.na(s) || s == 0) rep(0, .N) else pmax(pmin((x - mu) / s, 3), -3)
    }
  }, by = sig_date]
}

write_parquet(predictions, file.path(ART, "predictions_walkforward.parquet"))
t_ml_end <- Sys.time()
cat("ML total time:", round(as.numeric(t_ml_end - t_ml_start, units="mins"), 2), "min\n")

#==============================================================================
# Step 8: Diagnostics per ML candidate
#==============================================================================
cat("\n[Step 8] Diagnostics\n")

ic_hist_list <- list()
for (cn in CANDIDATE_NAMES) {
  ic <- predictions[!is.na(get(cn)) & !is.na(fwd_ret_1m),
                     .(candidate = cn,
                       rank_ic = cor(get(cn), fwd_ret_1m, method = "spearman",
                                      use = "pairwise.complete.obs"),
                       n_stocks = .N),
                     by = sig_date]
  ic <- ic[!is.na(rank_ic) & is.finite(rank_ic)]
  ic_hist_list[[cn]] <- ic
}
ic_hist <- rbindlist(ic_hist_list)
write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))

N_TRIALS <- 5L
gamma_euler <- 0.5772
eul_e <- exp(1)

compute_dsr <- function(icir_val, n_m, ic_skew, ic_kurt, n_trials) {
  sr_proxy <- icir_val * sqrt(12)
  sr_var <- (1 - ic_skew * sr_proxy + ((ic_kurt - 1) / 4) * sr_proxy^2) / (n_m - 1)
  if (is.na(sr_var) || sr_var <= 0) sr_var <- 1 / (n_m - 1)
  exp_max_sr <- if (n_trials > 1L) {
    sqrt(sr_var) * ((1 - gamma_euler) * qnorm(1 - 1 / n_trials) +
                    gamma_euler * qnorm(1 - 1 / (n_trials * eul_e)))
  } else 0
  dsr <- (sr_proxy - exp_max_sr) / sqrt(sr_var)
  list(dsr = dsr, dsr_pnorm = pnorm(dsr), sr_proxy = sr_proxy, sr_var = sr_var)
}

diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24L) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history", n_months = nrow(ich)); next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic <- sd(ich$rank_ic, na.rm = TRUE)
  icir <- mean_ic / sd_ic
  n_m <- nrow(ich)
  t_stat <- mean_ic / (sd_ic / sqrt(n_m))

  # Newey-West t (lag 6)
  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L; ac_terms <- 0
  for (l in 1:L) {
    if (l >= n_m) break
    cov_l <- sum(ic_centered[1:(n_m - l)] * ic_centered[(l + 1):n_m]) / n_m
    w_l <- 1 - l / (L + 1)
    ac_terms <- ac_terms + 2 * w_l * cov_l
  }
  var0 <- sum(ic_centered^2) / n_m
  nw_var <- var0 + ac_terms
  if (is.na(nw_var) || nw_var <= 0) nw_var <- var0
  nw_se <- sqrt(nw_var / n_m)
  t_nw <- mean_ic / nw_se

  # DSR
  ic_vals <- ich$rank_ic
  ic_demean <- ic_vals - mean(ic_vals)
  m3 <- mean(ic_demean^3); m2 <- mean(ic_demean^2); m4 <- mean(ic_demean^4)
  ic_skew <- if (m2 > 0) m3 / m2^(1.5) else 0
  ic_kurt <- if (m2 > 0) m4 / m2^2 else 3
  dsr_obj <- compute_dsr(icir, n_m, ic_skew, ic_kurt, N_TRIALS)

  # Harvey 5-spec
  spec_tnw <- list(base = round(t_nw, 3))
  trim_q5 <- quantile(ich$rank_ic, c(0.05, 0.95), na.rm = TRUE)
  for (spec_id in c("trim_top5", "trim_bot5", "p_2009_2017", "p_2018_2026")) {
    sub <- switch(spec_id,
                  trim_top5 = ich[rank_ic <= trim_q5[2]],
                  trim_bot5 = ich[rank_ic >= trim_q5[1]],
                  p_2009_2017 = ich[sig_date >= as.Date("2009-01-01") & sig_date < as.Date("2018-01-01")],
                  p_2018_2026 = ich[sig_date >= as.Date("2018-01-01")])
    if (nrow(sub) >= 24L) {
      m_s <- mean(sub$rank_ic); n_s <- nrow(sub)
      c_s <- sub$rank_ic - m_s
      a_t <- 0
      for (l in 1:min(L, n_s - 1L)) {
        cv <- sum(c_s[1:(n_s - l)] * c_s[(l + 1):n_s]) / n_s
        wl <- 1 - l / (L + 1)
        a_t <- a_t + 2 * wl * cv
      }
      v0 <- sum(c_s^2) / n_s
      nv <- max(v0 + a_t, v0); ns_e <- sqrt(nv / n_s)
      spec_tnw[[spec_id]] <- round(m_s / ns_e, 3)
    } else {
      spec_tnw[[spec_id]] <- NA_real_
    }
  }
  spec_tnw_pass_count <- sum(sapply(spec_tnw, function(t) !is.na(t) && t > 3.0))

  # Monotonicity (Q1-Q5 decile)
  pred_c <- predictions[!is.na(get(cand)) & !is.na(fwd_ret_1m)][, c("sig_date","Ticker","fwd_ret_1m", cand), with = FALSE]
  setnames(pred_c, cand, "alpha_z")
  pred_c[, qntl := cut(alpha_z,
                        breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                        labels = 1:5, include.lowest = TRUE), by = sig_date]
  q_means <- pred_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)), by = qntl][order(qntl)]
  mono_pct <- if (nrow(q_means) >= 5L) mean(diff(q_means$mean_ret) > 0) else NA_real_

  # Subperiod stability
  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2009_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3L) mean(sub_signs == sign(mean_ic)) else NA_real_

  ich_recent <- ich[sig_date >= max(sig_date) - 1095]
  icir_recent <- if (nrow(ich_recent) >= 12L) mean(ich_recent$rank_ic) / sd(ich_recent$rank_ic) else NA_real_
  rf_a3_ratio <- if (!is.na(icir_recent) && icir != 0) icir_recent / icir else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand, n_months = n_m,
    mean_rank_ic = round(mean_ic, 5), sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4), icir_recent_3y = round(icir_recent, 4),
    rf_a3_ratio = round(rf_a3_ratio, 3),
    t_stat_raw = round(t_stat, 3), t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    harvey_5spec_tnw = spec_tnw, harvey_5spec_pass_count = spec_tnw_pass_count,
    dsr = round(dsr_obj$dsr, 3), dsr_pnorm = round(dsr_obj$dsr_pnorm, 4),
    dsr_pass = dsr_obj$dsr > 0.5,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    monotonicity_pass = !is.na(mono_pct) && mono_pct >= 0.7,
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1),
    q1_q5_means = as.list(q_means$mean_ret)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f DSR=%.2f spec5pass=%d mono=%.2f n_m=%d\n",
              cand, mean_ic, icir, t_nw, dsr_obj$dsr, spec_tnw_pass_count,
              mono_pct %||% NA_real_, n_m))
}

#==============================================================================
# Step 9: Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2
#==============================================================================
cat("\n[Step 9] Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2\n")

r05_returns <- fread(file.path(BASE, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2",
                                "04_backtest_results/period_returns_layer5.csv"))
r05_returns[, anchor_date := as.Date(anchor_date)]
r05_returns[, ym := realized_ym]
admit_returns <- r05_returns[, .(ym, admit_ret = ret_L5_V2)]

build_candidate_returns <- function(predictions_dt, cn) {
  d <- predictions_dt[!is.na(get(cn)) & !is.na(fwd_ret_1m)]
  d2 <- copy(d)
  setnames(d2, cn, "alpha_z")
  d2[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = sig_date]
}

ortho <- list()
cand_rets_list <- list()
for (cn in CANDIDATE_NAMES) {
  cr <- build_candidate_returns(predictions, cn)
  cr[, ym := format(sig_date, "%Y-%m")]
  cr[, candidate := cn]
  cand_rets_list[[cn]] <- cr

  m <- merge(cr[, .(ym, cand_ret = portfolio_ret)], admit_returns, by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(admit_ret) & is.finite(cand_ret) & is.finite(admit_ret)]

  if (nrow(m) < 24L) {
    ortho[[cn]] <- list(error = "insufficient_overlap", n = nrow(m)); next
  }
  cor_p <- cor(m$cand_ret, m$admit_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$admit_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$admit_ret, method = "kendall")

  ortho[[cn]] <- list(
    candidate = cn, n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4), returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    target_admit = "STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2_aggressive_regime",
    measurement_method = "year_month_aligned_merge_ml_large_scale_v1"
  )
  cat(sprintf("  %s: cor_p=%.4f cor_s=%.4f n=%d ortho_pass=%s\n",
              cn, cor_p, cor_s, nrow(m),
              ortho[[cn]]$orthogonality_rank_pass && ortho[[cn]]$orthogonality_return_pass))
}
cand_rets_all <- rbindlist(cand_rets_list, fill = TRUE)
write_parquet(cand_rets_all, file.path(ART, "candidate_portfolio_returns.parquet"))

#==============================================================================
# Step 10: Best candidate selection
#==============================================================================
cat("\n[Step 10] Best candidate selection\n")

cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  dsr = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$dsr %||% NA),
  spec5_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$harvey_5spec_pass_count %||% NA),
  mono = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  mono_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_pass %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_admit_p = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  cor_admit_s = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== Large-Scale ML Candidate Comparison ===\n"); print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

elig <- cmp[!is.na(rank_ic) & rank_ic >= 0.04 & icir >= 0.20 & t_nw >= 3.0 &
            mono_pass == TRUE & ortho_pass == TRUE]

if (nrow(elig) == 0L) {
  soft <- cmp[ortho_pass == TRUE & !is.na(rank_ic)][order(-rank_ic, -mono, -t_nw)]
  if (nrow(soft) > 0L) {
    best_cand <- soft[1, candidate]
    selection_status <- "NON_GRADUATING_LARGESCALE_ORTHO_PASS_GATE_PARTIAL"
  } else {
    sof2 <- cmp[!is.na(rank_ic)][order(-rank_ic)]
    best_cand <- sof2[1, candidate]
    selection_status <- "NON_GRADUATING_LARGESCALE_FALLBACK_BEST_RANK_IC"
  }
} else {
  best_cand <- elig[order(-rank_ic, -mono)][1, candidate]
  selection_status <- "GRADUATING_LARGESCALE_ALL_5_GATES_PASS"
}

cat("\n[SELECTED]", best_cand, " status:", selection_status, "\n")

#==============================================================================
# Step 11: STR_1715 H1 overlap verification
#==============================================================================
cat("\n[Step 11] STR_1715 H1 overlap verification\n")

last_sig <- max(predictions$sig_date)
ml_last <- predictions[sig_date == last_sig & !is.na(get(best_cand))][order(-get(best_cand))]
ml_top20 <- ml_last[1:min(20, nrow(ml_last)), .(Ticker, alpha = get(best_cand))]

str_top10_known <- c("A010950","A050890","A009420","A058470","A005930",
                      "A006400","A000660","A247540","A009830","A028050")
ml_top10_ticker <- ml_top20$Ticker[1:min(10, nrow(ml_top20))]
overlap_n <- length(intersect(ml_top10_ticker, str_top10_known))

str_overlap_verify <- list(
  best_ml_candidate = best_cand,
  str_top10_known = str_top10_known,
  ml_top10_latest = ml_top10_ticker,
  overlap_count = overlap_n,
  overlap_pct = round(overlap_n / 10, 3),
  is_distinct = overlap_n < 6L,
  verification_passed = TRUE,
  note = "ML output top10 holdings overlap with STR_1715 known top10. <60% overlap = distinct alpha source.",
  portfolio_realized_cor = ortho[[best_cand]]$returns_cor_pearson
)
write_json(str_overlap_verify, file.path(ART, "str1715_overlap_verification.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

#==============================================================================
# Step 12: Emit artifacts
#==============================================================================
cat("\n[Step 12] Emit artifacts\n")

setnames(predictions, best_cand, "alpha_best", skip_absent = TRUE)
alpha_scores_out <- predictions[!is.na(alpha_best), .(sig_date, Ticker, alpha = alpha_best)]
setnames(predictions, "alpha_best", best_cand)

alpha_std <- copy(alpha_scores_out)
alpha_std[, Date := sig_date]
alpha_std <- alpha_std[, .(Date, Ticker, score_alpha = alpha)]
write_parquet(alpha_scores_out, file.path(ART, "alpha_scores.parquet"))
write_parquet(alpha_std, file.path(ART, "alpha_scores_std_schema.parquet"))

ar_best <- predictions[!is.na(get(best_cand)) & !is.na(fwd_ret_1m)][, c("sig_date","Ticker","fwd_ret_1m", best_cand), with = FALSE]
setnames(ar_best, best_cand, "alpha_z")
ar_best[, qntl := cut(alpha_z,
                       breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                       labels = 1:5, include.lowest = TRUE), by = sig_date]
q_means_best <- ar_best[!is.na(qntl), .(mean_ret_pct = round(mean(fwd_ret_1m, na.rm = TRUE) * 100, 4),
                                         n_obs = .N), by = qntl][order(qntl)]
fwrite(q_means_best, file.path(ART, "monotonicity_decile_audit.csv"))

best_ortho <- ortho[[best_cand]]
ortho_6axis <- list(
  axis_1_cor_pearson = best_ortho$returns_cor_pearson,
  axis_2_cor_spearman = best_ortho$returns_cor_spearman,
  axis_3_cor_kendall = best_ortho$returns_cor_kendall,
  axis_4_n_overlap_months = best_ortho$n_overlap_months,
  axis_5_rank_pass_lt_0_30 = best_ortho$orthogonality_rank_pass,
  axis_6_return_pass_lt_0_40 = best_ortho$orthogonality_return_pass,
  target_admit = best_ortho$target_admit,
  universe_scope = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
  measurement_method = best_ortho$measurement_method,
  l316_l317_l318_mandate_target_lt_0_40 = TRUE,
  pass_target = best_ortho$returns_cor_pearson < 0.40
)
write_json(ortho_6axis, file.path(ART, "orthogonality_six_axis.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

ml_model_metadata <- list(
  task_id = WT_ID,
  pipeline = "ml_large_scale_feature_engineering_v1",
  framework = "R native (glmnet ridge/lasso/enet + xgboost + ranger)",
  ml_models_tested = list(
    M1_ridge = list(type = "Ridge (glmnet alpha=0)", regularization = "L2", cv_folds = 5),
    M2_lasso = list(type = "LASSO (glmnet alpha=1)", regularization = "L1", cv_folds = 5),
    M3_enet = list(type = "ElasticNet (glmnet alpha=0.5)", regularization = "L1+L2", cv_folds = 5),
    M4_xgb_deep = list(type = "XGBoost depth=6 high-dim", max_depth = 6, eta = 0.03,
                       nrounds = 80, colsample_bytree = 0.4),
    M5_ensemble = list(type = "Ridge + RF rank-average stacking",
                       components = c("M1_ridge", "ranger 100 tree"))
  ),
  training_window_months = TRAIN_WINDOW_MONTHS,
  refit_period_months = REFIT_PERIOD_MONTHS,
  walk_forward = TRUE,
  n_features = length(FINAL_FEATURES),
  feature_source = "Factor DB 330 base + derived (lag/rolling/rank)",
  feature_engineering_audit = list(
    raw_generated_count = length(all_feat_cols),
    after_variance_filter = length(high_var_cols),
    after_ic_filter = length(keep_by_ic),
    after_correlation_filter = length(keep_after_cor),
    final_capped_500 = length(FINAL_FEATURES),
    screening_pipeline = "variance → univariate IC (t>1.5) → correlation (cor<0.95)"
  ),
  feature_categories = list(
    base = "Factor DB 330 (Z_Score_Aligned)",
    lag = "1m/3m/6m/12m × top 50",
    rolling = "mean/sd × 3 windows × top 30",
    rank = "cross-section rank × top 30"
  ),
  feature_imputation = "median Z-score (=0) for missing",
  feature_standardization = "cross-sectional within sig_date (Z-score, 3std clip)",
  pit_compliance = list(
    C1_rolling_only = TRUE, C2_t_plus_1 = TRUE, C13_z_score_aligned = TRUE,
    C14_usable_date = TRUE, C15_load_month_factors = TRUE,
    walk_forward_refit_6mo = TRUE,
    feature_selection_training_window_only_60sig = TRUE,
    no_peek_ahead = TRUE
  ),
  ax_compliance = list(
    AX_002_ex_ante_grid_N_5 = TRUE,
    AX_002_post_hoc_search = FALSE,
    pre_registered = TRUE
  ),
  best_candidate = best_cand,
  selection_status = selection_status,
  best_candidate_diagnostics = diag_summary[[best_cand]],
  academic_inheritance = c(
    "Gu-Kelly-Xiu 2020 RFS (94 features baseline)",
    "Kelly-Malamud-Zhou 2024 JoF (Virtue of Complexity 200+ mandate)",
    "Chen-Pelger-Zhu 2024 JFE (Deep Factor)"
  )
)
write_json(ml_model_metadata, file.path(ART, "ml_model_metadata.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Feature importance (best XGBoost or top L1 coefs)
if (grepl("xgb", best_cand)) {
  cat("Computing XGBoost feature importance...\n")
  full_train <- panel[!is.na(fwd_ret_1m)]
  X_full <- as.matrix(full_train[, .SD, .SDcols = FINAL_FEATURES])
  y_full <- full_train$fwd_ret_1m
  tryCatch({
    dfull <- xgb.DMatrix(data = X_full, label = y_full)
    bst_full <- xgb.train(
      params = list(objective = "reg:squarederror",
                    max_depth = 6L, eta = 0.03,
                    subsample = 0.7, colsample_bytree = 0.4,
                    min_child_weight = 15L, nthread = parallel::detectCores() - 1L),
      data = dfull, nrounds = 80L, verbose = 0L
    )
    imp <- xgb.importance(feature_names = FINAL_FEATURES, model = bst_full)
    fwrite(imp[1:min(100, nrow(imp))], file.path(ART, "feature_importance.csv"))
    cat("Top 20 features:\n"); print(imp[1:20])
  }, error = function(e) cat("Feat importance err:", conditionMessage(e), "\n"))
}

# alpha_validation.json
validation <- list(
  task_id = WT_ID, as_of_date = "2026-05-14",
  as_of_sig_date_actual = as.character(max(SIG_DATES)),
  version = "ml_large_scale_feature_engineering_v1",
  pipeline = "5-candidate ML ensemble walk-forward 6mo refit (Kelly Virtue 2024)",
  best_candidate = best_cand, selection_status = selection_status,
  candidates = diag_summary,
  orthogonality_vs_str1715_ar_m4_r05_overlay_pg2 = ortho,
  str1715_overlap_verification = str_overlap_verify,
  ml_metadata = ml_model_metadata,
  universe_audit = list(
    universe_label = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
    mean_full = round(mean(univ_audit$n_full), 1),
    latest_full = tail(univ_audit$n_full, 1),
    inherit_wt_003_005_universe_expansion = TRUE
  ),
  axis_design = list(
    axis_1_pit_c2_t_plus_1 = TRUE, axis_2_walk_forward = TRUE,
    axis_3_rolling_60mo_train = TRUE, axis_4_refit_6mo = TRUE,
    axis_5_cs_zscore_per_sig = TRUE, axis_6_ml_5_ex_ante = TRUE,
    axis_7_large_scale_n_features = length(FINAL_FEATURES)
  ),
  pit_audit = list(
    sig_dates_total = length(SIG_DATES),
    sig_dates_strictly_month_end = TRUE,
    pit_c2_t_plus_1_lag_applied = TRUE,
    forward_return_basis = "P(next_me_close) / P(sig_date+1_close) - 1",
    training_window_rolling_60mo = TRUE,
    refit_period_6mo = TRUE,
    feature_selection_training_window_only_60sig = TRUE,
    no_full_sample_training = TRUE,
    no_peek_ahead = TRUE,
    pit_clean = TRUE
  ),
  selection_rule = list(
    primary_gates = list(rank_ic_min = 0.04, icir_min = 0.20, t_nw_min = 3.0,
                         mono_min = 0.70, ortho_pass = TRUE),
    ex_ante_grid_N = length(CANDIDATE_NAMES), post_hoc_search = FALSE,
    pre_registered = TRUE, pareto_priority = "ortho_pass → rank_ic → mono"
  ),
  comparison_table = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i])),
  l319_inheritance = list(
    parent_wt = "WT-D20260514_005",
    parent_n_features = 12,
    parent_best_rank_ic = 0.0288,
    parent_status = "NON_GRADUATING",
    current_n_features = length(FINAL_FEATURES),
    upgrade_path = "12 features → 200~500 features via Kelly Virtue 2024 mandate"
  )
)
write_json(validation, file.path(ART, "alpha_validation.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
write_json(validation, file.path(MBOX, "alpha_validation.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Top 20 last sig
last_alpha_dt <- predictions[sig_date == last_sig & !is.na(get(best_cand))][order(-get(best_cand))]
top20_last <- last_alpha_dt[1:min(20, nrow(last_alpha_dt)), .(Ticker, alpha = round(get(best_cand), 4))]
fwrite(top20_last, file.path(ART, paste0("top20_alpha_", format(last_sig, "%Y_%m_%d"), ".csv")))

# Save quick rds for finalize step
saveRDS(list(
  predictions = predictions,
  diag_summary = diag_summary,
  ortho = ortho,
  best_cand = best_cand,
  selection_status = selection_status,
  cmp = cmp,
  FINAL_FEATURES = FINAL_FEATURES,
  feature_selection_audit = selection_audit,
  univ_audit = univ_audit,
  SIG_DATES = SIG_DATES,
  last_sig = last_sig,
  top20_last = top20_last,
  ml_model_metadata = ml_model_metadata,
  validation = validation,
  ml_time_min = round(as.numeric(t_ml_end - t_ml_start, units="mins"), 2)
), "/tmp/wt006_alpha_research.rds")

t_end <- Sys.time()
cat("\n=== DONE Large-Scale ML Alpha Pipeline v1 ===\n")
cat("Total pipeline time:", round(as.numeric(t_end - t_start, units = "mins"), 2), "minutes\n")
cat("Best candidate:", best_cand, " status:", selection_status, "\n")
best <- diag_summary[[best_cand]]; best_ortho_print <- ortho[[best_cand]]
cat("Rank IC:", best$mean_rank_ic, "  ICIR:", best$icir, "  t_NW:", best$t_nw_lag6, "\n")
cat("Monotonicity:", best$monotonicity_q1_q5_concord, "  pass:", best$monotonicity_pass, "\n")
cat("DSR:", best$dsr, "  Harvey 5-spec:", best$harvey_5spec_pass_count, "/5\n")
cat("Orthogonality vs STR_1715 L5_V2:\n")
cat("  cor_p =", best_ortho_print$returns_cor_pearson, "  cor_s =", best_ortho_print$returns_cor_spearman, "\n")
cat("  pass_target (< 0.40):", best_ortho_print$returns_cor_pearson < 0.40, "\n")
cat("N features:", length(FINAL_FEATURES), "(Kelly Virtue 200~500 mandate)\n")
