## STR_1417: ESBR + HRP + TC + DD 6/20 Brake
## References: Lopez de Prado (2016) "Building Diversified Portfolios" +
##             Garleanu & Pedersen (2013) "Dynamic Trading with Predictable Returns"
## Family: esbr_hrp
## Bucket: exploit
##
## Core Idea:
##   STR_1405 ESBR Pure got Grade A (SR 1.111, CAGR 18.9%, MDD 31.6%).
##   But MDD 31.6% exceeds 25% target. HRP+TC reduced MDD by 22pp in STR_1390.
##   This strategy applies HRP+TC mechanics to ESBR single-factor selection:
##   - Factor: C04_ESBR Z_Score_Aligned ONLY (no composite)
##   - Top 30 stocks by ESBR score
##   - HRP weights (ward.D2, 60d rolling, inverse-var, 10% cap)
##   - Turnover constraint: w_new = 0.5*w_hrp + 0.5*w_old (Garleanu-Pedersen)
##   - DD brake 6/20/20 (t-1 lagged) as sole overlay
##   - NO regime, NO VT
##   - Monthly rebal, 15bps, liq >= 2e8
##
## PIT: Factor DB Z_Score_Aligned via load_month_factors() (C15 compliant).
##      60d rolling returns for HRP cov -- no full-sample stats (C1).
##      Turnover constraint uses only current HRP target + previous portfolio.
##      Liquidity t-1 lagged (C10). DD brake t-1 lagged (C9).
##      C1-C15 compliant.
cat("=== STR_1417: ESBR + HRP + TC + DD 6/20 Brake ===\n")
cat("## Core: C04_ESBR only, top 30, HRP weights, 50% TC blend, DD 6/20/20 (t-1)\n")

set.seed(1417)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "ESBR_HRP_TC_DD620"
STRATEGY_ID     <- "STR_1417"
STRATEGY_FAMILY <- "esbr_hrp"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Infrastructure
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure"
  )
}

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
library(data.table); library(xts); library(arrow)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Step 1: Load RAWDATA
# ============================================================================
cat("[Step 1] Loading RAWDATA...\n")
LIQ_THRESHOLD   <- 2e8
N_TOTAL         <- 30L
BLEND_ALPHA     <- 0.50    # Garleanu-Pedersen: w_new = alpha*w_target + (1-alpha)*w_old
COMMISSION      <- 0.0015  # 15bps
HRP_NDAYS       <- 60L     # 60d rolling correlation for HRP
HRP_MAX_W       <- 0.10    # 10% individual weight cap
DD_START        <- 0.06    # DD brake starts at 6%
DD_FULL         <- 0.20    # DD brake full at 20%
DD_MIN_EXP      <- 0.20    # 20% floor exposure

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
rm(res); gc(verbose = FALSE)

# ============================================================================
# Step 2: Factor Engine -- ESBR ONLY via Factor DB (C15)
# ============================================================================
cat("[Step 2] Factor engine: C04_ESBR single factor via load_month_factors()...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

TARGET_FACTOR <- "C04_ESBR"

# Get all available signal dates from Factor DB
fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
fdb_ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", fdb_files)
fdb_dates <- sort(as.Date(paste0(fdb_ym, "01"), format = "%Y%m%d"))

cat(sprintf("  Factor DB: %d months available (%s ~ %s)\n",
            length(fdb_ym), min(fdb_ym), max(fdb_ym)))

# Prepare liquidity: t-1 lagged 20-day avg trading value (C10)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# Map each factor_db month to the closest RAWDATA signal date
RAWDATA[, YM := format(Date, "%Y%m")]
signal_date_map <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
setkey(signal_date_map, YM)

# Main factor scoring loop
factor_list  <- list()
n_done <- 0L; n_skipped <- 0L

for (ym_tag in fdb_ym) {
  sig_info <- signal_date_map[YM == ym_tag]
  if (nrow(sig_info) == 0) { n_skipped <- n_skipped + 1L; next }
  sig_d <- sig_info$Signal_Date

  # Load aligned factors via connector (C15 compliant)
  fdb_snap <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) { cat("[FDB]", ym_tag, e$message, "\n"); NULL }
  )
  if (is.null(fdb_snap) || nrow(fdb_snap) == 0) { n_skipped <- n_skipped + 1L; next }

  # Filter to ESBR only
  fdb_snap <- fdb_snap[Factor_Name == TARGET_FACTOR]
  if (nrow(fdb_snap) == 0) { n_skipped <- n_skipped + 1L; next }

  # Rename for simplicity
  setnames(fdb_snap, "Z_Score_Aligned", "Score")

  # Merge liquidity (t-1 lagged, C10)
  liq_snap <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdb_snap <- merge(fdb_snap, liq_snap, by = "Ticker", all.x = TRUE)

  # Liquidity filter: >= 2e8
  fdb_snap <- fdb_snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdb_snap) < N_TOTAL) { n_skipped <- n_skipped + 1L; next }

  # Select top N_TOTAL by ESBR score
  setorder(fdb_snap, -Score)
  sel <- head(fdb_snap[!is.na(Score) & is.finite(Score)], N_TOTAL)
  if (nrow(sel) < 10) { n_skipped <- n_skipped + 1L; next }

  sel[, Date := sig_d]
  factor_list[[length(factor_list) + 1L]] <- sel[, .(Date, Ticker, Score)]
  n_done <- n_done + 1L

  if (n_done %% 30 == 0 || n_done <= 3) {
    cat(sprintf("  [%d/%d skip] %s  n_stock=%d  top=%.3f  pool=%d\n",
                n_done, n_skipped, sig_d, nrow(sel), sel$Score[1], nrow(fdb_snap)))
  }
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)

# Clean up temporary columns
for (col in c("TradingValue", "AvgTV20", "YM")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)

cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d done | %d skipped\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_done, n_skipped))
if (nrow(FACTORS) == 0) stop("No factors generated -- aborting.")

stopifnot(is.data.table(FACTORS),
          all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
          nrow(FACTORS) > 0)

# ============================================================================
# Step 3: Custom HRP + Turnover-Constrained Simulation
# ============================================================================
cat(sprintf(paste0(
  "\n[Step 3] HRP + Turnover-Constrained backtest (NO regime, NO VT)\n",
  "  HRP: ward.D2, %dd rolling, inv-var bisection, %.0f%% cap\n",
  "  Turnover: alpha=%.2f (50%% blend w/ previous)\n",
  "  DD brake: start=%.0f%%, full=%.0f%%, floor=%.0f%% (t-1 lagged)\n",
  "  N=%d, commission=%.0fbps, liq>=%.0f\n"),
  HRP_NDAYS, HRP_MAX_W * 100, BLEND_ALPHA,
  DD_START * 100, DD_FULL * 100, DD_MIN_EXP * 100,
  N_TOTAL, COMMISSION * 1e4, 2e8))

RAWDATA <- copy(RAWDATA_ORIG)
setorder(RAWDATA, Ticker, Date)
all_dates    <- sort(unique(RAWDATA$Date))
signal_dates <- sort(unique(FACTORS$Date))

# Map signal dates to execution dates (next trading day)
exec_map <- data.table(
  Signal_Date = signal_dates,
  Exec_Date = sapply(signal_dates, function(sd) {
    ed <- get_execution_date(sd, all_dates)
    if (is.na(ed)) NA_real_ else as.numeric(ed)
  })
)
exec_map[, Exec_Date := as.Date(Exec_Date, origin = "1970-01-01")]
exec_map <- exec_map[!is.na(Exec_Date)]
exec_date_set <- sort(exec_map$Exec_Date)

# Build return lookup for HRP covariance computation (wide matrix per date)
cat("  Building return matrix for HRP...\n")
ret_wide <- dcast(RAWDATA[, .(Date, Ticker, Ret)], Date ~ Ticker, value.var = "Ret")
ret_dates <- ret_wide$Date
ret_mat_all <- as.matrix(ret_wide[, -1])
rownames(ret_mat_all) <- as.character(ret_dates)

# ---- HRP weight computation helper ----
compute_hrp_weights_local <- function(tickers, as_of_date, n_days = HRP_NDAYS,
                                       max_w = HRP_MAX_W) {
  date_idx <- which(ret_dates <= as_of_date)
  if (length(date_idx) < n_days) {
    w <- rep(1 / length(tickers), length(tickers))
    names(w) <- tickers
    return(w)
  }
  use_idx <- tail(date_idx, n_days)
  tk_cols <- which(colnames(ret_mat_all) %in% tickers)
  if (length(tk_cols) < 3) {
    w <- rep(1 / length(tickers), length(tickers))
    names(w) <- tickers
    return(w)
  }

  sub_mat <- ret_mat_all[use_idx, tk_cols, drop = FALSE]
  good_cols <- colSums(!is.na(sub_mat)) >= (n_days * 0.5)
  sub_mat <- sub_mat[, good_cols, drop = FALSE]
  survived <- colnames(sub_mat)
  if (length(survived) < 3) {
    w <- rep(1 / length(tickers), length(tickers))
    names(w) <- tickers
    return(w)
  }

  sub_mat[is.na(sub_mat)] <- 0

  cor_m <- cor(sub_mat, use = "pairwise.complete.obs")
  cor_m[is.na(cor_m)] <- 0
  dist_m <- as.dist(sqrt(0.5 * (1 - cor_m)))

  hc <- hclust(dist_m, method = "ward.D2")
  order_idx <- hc$order

  cov_m <- cov(sub_mat, use = "pairwise.complete.obs")
  cov_m[is.na(cov_m)] <- 0

  w_sub <- tryCatch({
    ws <- .hrp_bisect(cov_m, order_idx)
    ws / sum(ws)
  }, error = function(e) rep(1 / length(survived), length(survived)))
  names(w_sub) <- survived

  w_full <- rep(0, length(tickers))
  names(w_full) <- tickers
  dropped <- setdiff(tickers, survived)
  if (length(dropped) > 0) {
    for (tk in dropped) w_full[tk] <- 1 / length(tickers)
    hrp_scale <- 1 - sum(w_full)
    for (tk in survived) w_full[tk] <- w_sub[tk] * hrp_scale
  } else {
    w_full[survived] <- w_sub[survived]
  }
  w_full <- w_full / sum(w_full)

  if (any(w_full > max_w)) {
    w_full <- pmin(w_full, max_w)
    w_full <- w_full / sum(w_full)
  }
  w_full
}

# ---- Main simulation loop with HRP + turnover constraint ----
cat("  Running simulation...\n")
daily_ret_list   <- list()
current_tickers  <- character(0)
current_weights  <- numeric(0)
prev_tickers     <- character(0)
prev_weights     <- numeric(0)
turnover_log     <- list()
holdings_log     <- list()

for (d in all_dates) {
  d <- as.Date(d)

  if (d %in% exec_date_set) {
    sig_d <- exec_map[Exec_Date == d, Signal_Date]
    if (length(sig_d) == 0) next
    sig_d <- sig_d[1]

    sel <- FACTORS[Date == sig_d]
    setorder(sel, -Score)
    sel <- head(sel, N_TOTAL)
    target_tickers <- sel$Ticker

    exec_prices <- RAWDATA[Ticker %in% target_tickers & Date == d, .(Ticker, Close)]
    exec_prices <- exec_prices[!is.na(Close) & Close > 0]
    target_tickers <- exec_prices$Ticker

    if (length(target_tickers) < 5) next

    # ---- HRP target weights (60d rolling, ward.D2, inv-var, 10% cap) ----
    w_hrp <- compute_hrp_weights_local(target_tickers, as_of_date = sig_d)

    # ---- Garleanu-Pedersen Turnover Constraint ----
    if (length(prev_tickers) > 0 && length(prev_weights) > 0) {
      all_tk <- union(names(w_hrp), prev_tickers)

      w_old_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_old_full[prev_tickers] <- prev_weights

      w_tgt_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_tgt_full[names(w_hrp)] <- w_hrp

      w_blended <- BLEND_ALPHA * w_tgt_full + (1 - BLEND_ALPHA) * w_old_full

      # Remove near-zero positions (< 0.5%)
      w_blended <- w_blended[w_blended > 0.005]

      # HARD CAP: keep only top N_TOTAL (30) by blended weight
      if (length(w_blended) > N_TOTAL) {
        w_blended <- sort(w_blended, decreasing = TRUE)
        w_blended <- w_blended[1:N_TOTAL]
      }

      if (length(w_blended) > 0 && sum(w_blended) > 0) {
        w_blended <- w_blended / sum(w_blended)
      } else {
        w_blended <- w_hrp
      }

      # Enforce 10% cap after blending
      if (any(w_blended > HRP_MAX_W)) {
        w_blended <- pmin(w_blended, HRP_MAX_W)
        w_blended <- w_blended / sum(w_blended)
      }

      # Compute turnover for cost
      all_tk2 <- union(names(w_blended), prev_tickers)
      w_old_for_to <- setNames(rep(0, length(all_tk2)), all_tk2)
      w_old_for_to[prev_tickers] <- prev_weights
      w_new_for_to <- setNames(rep(0, length(all_tk2)), all_tk2)
      w_new_for_to[names(w_blended)] <- w_blended
      dollar_turnover <- sum(abs(w_new_for_to - w_old_for_to)) / 2
      turnover_cost <- dollar_turnover * COMMISSION * 2  # round-trip

      current_tickers <- names(w_blended)
      current_weights <- as.numeric(w_blended)
      names(current_weights) <- current_tickers

      turnover_log[[as.character(d)]] <- data.table(
        Date = d, Turnover = dollar_turnover, N_Holdings = length(current_tickers)
      )
    } else {
      # First rebalance: just use HRP target weights
      current_tickers <- names(w_hrp)
      current_weights <- as.numeric(w_hrp)
      names(current_weights) <- current_tickers
      turnover_cost <- COMMISSION
      turnover_log[[as.character(d)]] <- data.table(
        Date = d, Turnover = 1.0, N_Holdings = length(current_tickers)
      )
    }

    prev_tickers <- current_tickers
    prev_weights <- current_weights

    holdings_log[[as.character(d)]] <- data.table(
      Exec_Date = d,
      Signal_Date = sig_d,
      Ticker = current_tickers,
      Weight = current_weights
    )
  }

  if (length(current_tickers) == 0) next

  day_rets <- RAWDATA[Date == d & Ticker %in% current_tickers, .(Ticker, Ret)]
  if (nrow(day_rets) == 0) next

  w_day <- current_weights[match(day_rets$Ticker, current_tickers)]
  valid <- !is.na(w_day) & !is.na(day_rets$Ret)
  if (sum(valid) == 0) next

  w_valid <- w_day[valid]
  w_valid <- w_valid / sum(w_valid)
  port_ret <- sum(w_valid * day_rets$Ret[valid])

  # Subtract turnover cost on rebalance day
  if (d %in% exec_date_set && exists("turnover_cost") && turnover_cost > 0) {
    port_ret <- port_ret - turnover_cost
    turnover_cost <- 0
  }

  daily_ret_list[[as.character(d)]] <- data.table(Date = d, Ret = port_ret)
}

daily_ret_dt <- rbindlist(daily_ret_list)
setorder(daily_ret_dt, Date)

turnover_dt <- rbindlist(turnover_log)
holdings_dt <- rbindlist(holdings_log)

cat(sprintf("  HRP+TC portfolio: %d days (%s ~ %s)\n",
            nrow(daily_ret_dt), min(daily_ret_dt$Date), max(daily_ret_dt$Date)))
cat(sprintf("  Avg turnover per rebal: %.1f%% | Avg holdings: %.1f\n",
            mean(turnover_dt$Turnover, na.rm = TRUE) * 100,
            mean(turnover_dt$N_Holdings, na.rm = TRUE)))

max_holdings <- holdings_dt[, .N, by = Exec_Date][, max(N)]
cat(sprintf("  Max holdings in any rebal: %d (limit: 30)\n", max_holdings))
if (max_holdings > 30) warning("[VIOLATION] 30-stock limit breached! Max=", max_holdings)

# ============================================================================
# Step 3b: Also run EW baseline for comparison (same as STR_1405)
# ============================================================================
cat("\n[Step 3b] Running EW baseline for comparison...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_base <- run_monthly_simulation(
  RAWDATA, BM_DT_ORIG, FACTORS,
  n_holdings    = N_TOTAL,
  weight_method = "equal",
  commission    = COMMISSION,
  vol_target    = NULL,
  buffer_zone   = list(keep_n = 40L, entry_n = 25L)
)

# ============================================================================
# Step 4: DD Brake overlay 6/20/20 (t-1 lagged, C2/C9)
# ============================================================================
cat(sprintf("\n[Step 4] DD Brake overlay (t-1 lagged, start=%.0f%%, full=%.0f%%, floor=%.0f%%)\n",
            DD_START * 100, DD_FULL * 100, DD_MIN_EXP * 100))
raw_ret   <- daily_ret_dt$Ret
raw_dates <- daily_ret_dt$Date
n_f       <- length(raw_ret)

nav_dd <- cumprod(1 + raw_ret)
dd_pct <- 1 - nav_dd / cummax(nav_dd)

# t-1 lag: use YESTERDAY's DD to decide TODAY's exposure (C9 compliant)
dd_pct_lagged <- c(0, dd_pct[-n_f])
dd_exp_lagged <- ifelse(dd_pct_lagged <= DD_START, 1.0,
                 ifelse(dd_pct_lagged >= DD_FULL, DD_MIN_EXP,
                        pmax(DD_MIN_EXP,
                             1.0 - (dd_pct_lagged - DD_START) / (DD_FULL - DD_START) * (1.0 - DD_MIN_EXP))))

final_ret <- raw_ret * dd_exp_lagged
cat(sprintf("  DD Brake active: %.1f%% of days (mean exposure=%.3f)\n",
            mean(dd_exp_lagged < 1.0) * 100, mean(dd_exp_lagged)))

# ============================================================================
# Step 5: Final assembly
# ============================================================================
cat("\n[Step 5] Final assembly (ESBR + HRP + TC + DD brake)...\n")
combined_xts <- xts(final_ret, order.by = raw_dates)
names(combined_xts) <- "Strategy"

sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(
  Date         = raw_dates,
  NAV          = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)
sim$HOLDINGS_LOG <- holdings_dt

# ============================================================================
# Step 6: Performance + Analysis + Hurdle Gate
# ============================================================================
cat("\n[Step 6] Validation & Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_hrp_tc <- summarise_perf(sim$strategy_xts, "ESBR_HRP_TC_DD620")
perf_ew     <- summarise_perf(sim_base$strategy_xts, "ESBR_EW_Baseline")
perf_bm     <- summarise_perf(sim$bm_xts, "Benchmark_K200")

cat(sprintf("\n  %s Results:\n", STRATEGY_ID))
cat(sprintf("  [ESBR+HRP+TC DD620] CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf_hrp_tc$CAGR, perf_hrp_tc$Sharpe, perf_hrp_tc$MDD))
cat(sprintf("  [ESBR EW Baseline]  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf_ew$CAGR, perf_ew$Sharpe, perf_ew$MDD))
cat(sprintf("  [BM]                CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

perf_all <- rbind(perf_hrp_tc, perf_ew, perf_bm)
print(perf_all)

# Delta analysis vs STR_1405
cat(sprintf("\n[Delta vs STR_1405 (SR=1.111, CAGR=18.9%%, MDD=31.6%%)] HRP+TC applied\n"))
cat(sprintf("[Delta ESBR+HRP+TC vs EW Baseline] Sharpe %+.3f | CAGR %+.2f%% | MDD %+.1f%%\n",
            perf_hrp_tc$Sharpe - perf_ew$Sharpe,
            perf_hrp_tc$CAGR - perf_ew$CAGR,
            perf_hrp_tc$MDD - perf_ew$MDD))
cat(sprintf("  Avg turnover (TC): %.1f%% per rebal\n",
            mean(turnover_dt$Turnover, na.rm = TRUE) * 100))

# Save outputs
fwrite(turnover_dt, file.path(output_dir, "turnover_log.csv"))
fwrite(holdings_dt, file.path(output_dir, "holdings_log.csv"))
generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(perf_all, file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT_ORIG, output_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN] strategy_analyzer:", e$message, "\n"))

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(
    sim_result    = sim,
    FACTORS       = FACTORS,
    strategy_name = STRATEGY_NAME,
    strategy_file = file.path(SCRIPT_DIR, "run_all.R"),
    output_dir    = output_dir
  )
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

if (!is.null(hurdle)) {
  cat(sprintf("\n  Grade: %s | Score: %.1f | Verdict: %s\n",
              hurdle$grade,
              hurdle$total_score %||% hurdle$score %||% 0,
              if (isTRUE(hurdle$pass)) "PASS" else "FAIL"))
  jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
}

# ============================================================================
# Step 7: Telegram + Auto-commit
# ============================================================================
cat("\n[Step 7] Telegram + QEPM commit...\n")
tryCatch({
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

# Telegram commentary
tryCatch({
  grade_str <- if (!is.null(hurdle)) hurdle$grade else "?"
  score_str <- if (!is.null(hurdle)) sprintf("%.1f",
    hurdle$total_score %||% hurdle$score %||% 0) else "?"
  msg <- paste0(
    "STR_1417: ESBR + HRP + TC + DD 6/20 Brake\n",
    "C04_ESBR single-factor + HRP (ward.D2, 60d, inv-var, 10% cap)\n",
    "Turnover constraint: 50% blend (Garleanu-Pedersen)\n",
    "DD brake 6/20/20 (t-1 lagged)\n",
    sprintf("[ESBR+HRP+TC DD620] CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_hrp_tc$CAGR, perf_hrp_tc$Sharpe, perf_hrp_tc$MDD),
    sprintf("[ESBR EW baseline]  CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_ew$CAGR, perf_ew$Sharpe, perf_ew$MDD),
    sprintf("vs STR_1405 (SR=1.111, CAGR=18.9%%, MDD=31.6%%): HRP+TC applied\n"),
    sprintf("Avg TO: %.1f%% | Grade: %s (Score: %s)",
            mean(turnover_dt$Turnover, na.rm = TRUE) * 100, grade_str, score_str)
  )
  tg_send(msg)
}, error = function(e) cat("[TG commentary]", e$message, "\n"))

# QEPM auto-commit
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qepm_hybrid <- file.path(dirname(dirname(dirname(SCRIPT_DIR))),
                             "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qepm_hybrid)) {
      source(qepm_hybrid)
      if (exists("hybrid_commit")) {
        hybrid_commit(
          strategy_name  = STRATEGY_ID,
          family         = STRATEGY_FAMILY,
          hurdle_result  = hurdle,
          artifact_paths = list(output_dir)
        )
        cat("[QEPM] hybrid_commit() complete\n")
      }
    }
  }, error = function(e) cat("[QEPM] auto-commit:", e$message, "\n"))
}

# Save result JSON
tryCatch({
  output_json <- list(
    strategy_id   = STRATEGY_ID,
    strategy_name = "ESBR + HRP + TC + DD 6/20 Brake",
    references    = c("Lopez de Prado (2016)", "Garleanu & Pedersen (2013)"),
    method        = "ESBR_HRP_TC_DD620",
    factors       = "C04_ESBR",
    blend_alpha   = BLEND_ALPHA,
    n_holdings    = N_TOTAL,
    weight_method = "HRP_blended",
    hrp_params    = list(n_days = HRP_NDAYS, max_w = HRP_MAX_W,
                         cluster = "ward.D2", alloc = "inv_var"),
    overlays      = list(dd_start = DD_START, dd_full = DD_FULL,
                         dd_floor = DD_MIN_EXP,
                         vt = "NONE", regime = "NONE"),
    commission    = COMMISSION,
    avg_turnover  = mean(turnover_dt$Turnover, na.rm = TRUE),
    max_holdings  = max_holdings,
    base_comparison = list(
      str_1405 = list(SR = 1.111, CAGR = 18.9, MDD = 31.6,
                      note = "ESBR Pure EW + DD 6/20"),
      str_1417 = list(change = "HRP+TC applied to reduce MDD while preserving ESBR alpha")
    ),
    performance   = list(
      esbr_hrp_tc = as.list(perf_hrp_tc),
      esbr_ew     = as.list(perf_ew),
      bm          = as.list(perf_bm)
    ),
    hurdle = tryCatch(list(
      grade = hurdle$grade,
      score = hurdle$total_score %||% hurdle$score %||% 0,
      pass  = hurdle$pass
    ), error = function(e) list(grade = "?", score = 0, pass = FALSE)),
    generated  = as.character(Sys.time()),
    pit_status = paste0(
      "CLEAN - C04_ESBR Z_Score_Aligned via load_month_factors() (C15). ",
      "HRP uses 60d rolling returns only (C1 no full-sample). ",
      "Turnover constraint uses only prev portfolio + current HRP target. ",
      "Liquidity t-1 lagged (C10). DD Brake t-1 lagged (C9). ",
      "NO VT overlay. NO regime overlay. No full-sample stats anywhere."
    )
  )
  jsonlite::write_json(output_json, file.path(SCRIPT_DIR, "result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  cat("  result.json saved.\n")
}, error = function(e) cat("[JSON]", e$message, "\n"))

cat(sprintf("\n=== %s Complete. ===\n", STRATEGY_ID))
if (!is.null(hurdle)) {
  cat(sprintf("  Verdict: %s (Score: %.1f)\n",
              if (isTRUE(hurdle$pass)) "PASS" else "FAIL",
              hurdle$total_score %||% hurdle$score %||% 0))
}
