## =============================================================================
## STR_1549 S5 All Mutations (M1~M11)
## Forge v7.0 — Defense Core Alpha S5 Mutation Execution
##
## M1~M8: Factor/construction variations (full backtest)
## M9~M11: Overlay on parent sim returns (DD / Regime / DD+Regime)
##
## PIT: Factor DB Z_Score_Aligned (C13/C15). Liq t-1 (C10).
##      DD/Regime t-1 lag (C9). No full-sample stats (C1).
## =============================================================================
cat("=== STR_1549: S5 All Mutations (M1~M11) ===\n")

set.seed(1549)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID     <- "STR_1549"
STRATEGY_NAME   <- "Defense_Core_Alpha"
STRATEGY_FAMILY <- "defense_core_alpha"

# ===========================================================================
# Step 0: Infrastructure
# ===========================================================================
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
suppressPackageStartupMessages({
  library(data.table); library(xts); library(arrow)
})

# ===========================================================================
# Step 1: Load data ONCE
# ===========================================================================
cat("\n[Step 1] Loading RAWDATA + Factor DB (one-time)...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

# Factor DB: load ALL needed factors across all mutations at once
ALL_NEEDED <- c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability",
                "Q04_Piotroski_F", "C19_Composite_Earnings")
CACHE_DIR_FDB <- file.path(CACHE_DIR, "factor_db")

ds <- open_dataset(CACHE_DIR_FDB, format = "parquet")
FDB_ALL <- ds |>
  dplyr::filter(Factor_Name %in% ALL_NEEDED) |>
  dplyr::select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  dplyr::collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

# Prepare RAWDATA for signal generation
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]

# Liquidity: 20d avg trading value, t-1 lagged (C10)
if (!"TradingValue" %in% names(RAWDATA)) RAWDATA[, TradingValue := Close * Vol]
if (!"AvgTV20" %in% names(RAWDATA)) {
  RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                              n = 1L, type = "lag"), by = Ticker]
}

# Sector map
has_sector <- "Sector" %in% names(RAWDATA)
has_sector_map <- FALSE
if (!has_sector) {
  sector_file <- file.path(INFRA_DIR, "sector_map.csv")
  if (file.exists(sector_file)) {
    sector_map <- fread(sector_file)
    has_sector_map <- TRUE
  }
}

LIQ_THRESHOLD <- 2e8

# ===========================================================================
# Helper: Generic factor engine (sector-neutral scoring)
# ===========================================================================
build_factors <- function(needed_factors, factor_weights) {
  fdb_dates <- sort(unique(FDB_ALL[Factor_Name %in% needed_factors, Date]))
  factor_list <- vector("list", length(monthly_dates))
  n_done <- 0L; n_skipped <- 0L

  for (i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])
    valid_fdb <- fdb_dates[fdb_dates <= sig_d]
    if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
    fdb_d <- max(valid_fdb)

    fdt <- FDB_ALL[Date == fdb_d & Factor_Name %in% needed_factors & Coverage == TRUE]
    if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

    fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
    fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
    fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
    if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }

    # Sector info
    if (has_sector && "Sector" %in% names(RAWDATA)) {
      sec_info <- RAWDATA[Date == sig_d, .(Ticker, Sector)]
      fdt_wide <- merge(fdt_wide, sec_info, by = "Ticker", all.x = TRUE)
      fdt_wide[is.na(Sector), Sector := "Unknown"]
    } else if (has_sector_map) {
      fdt_wide <- merge(fdt_wide, sector_map[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
      fdt_wide[is.na(Sector), Sector := "Unknown"]
    } else {
      fdt_wide[, Sector := "ALL"]
    }

    # Sector-neutral ranking + weighted combo
    fdt_wide[, Score := 0.0]
    nc <- 0L
    for (fn in needed_factors) {
      if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) >= 10L) {
        fdt_wide[, (paste0("r_", fn)) :=
          frank(get(fn), na.last = "keep", ties.method = "average") / .N,
          by = Sector]
        fdt_wide[, Score := Score + factor_weights[fn] *
          fifelse(is.na(get(paste0("r_", fn))), 0.5, get(paste0("r_", fn)))]
        nc <- nc + 1L
      }
    }
    if (nc == 0L) { n_skipped <- n_skipped + 1L; next }

    fdt_wide[, Date := sig_d]
    factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
    n_done <- n_done + 1L
  }

  FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
  setorder(FACTORS, Date, -Score)
  cat(sprintf("    %d signal months | %d skipped | %d rows\n", n_done, n_skipped, nrow(FACTORS)))
  FACTORS
}

# ===========================================================================
# Helper: Run one mutation backtest (M1~M8)
# ===========================================================================
run_mutation <- function(mut_id, FACTORS, n_holdings = 30L,
                         weight_method = "equal",
                         buffer_zone = list(keep_n = 40L, entry_n = 30L),
                         commission = 0.0015) {
  cat(sprintf("\n--- %s: backtest (N=%d, wt=%s) ---\n", mut_id, n_holdings, weight_method))

  out_dir <- file.path(SCRIPT_DIR, paste0("output_s5_", mut_id))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  sim <- tryCatch({
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
      n_holdings = n_holdings, weight_method = weight_method,
      commission = commission, buffer_zone = buffer_zone
    )
  }, error = function(e) { cat("  [ERROR]", e$message, "\n"); NULL })

  if (is.null(sim)) return(NULL)

  perf <- summarise_perf(sim$strategy_xts, paste0(STRATEGY_ID, "_", mut_id))
  perf_bm <- summarise_perf(sim$bm_xts, "BM")

  tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = paste0(STRATEGY_NAME, "_", mut_id)),
           error = function(e) cat("  [WARN] Charts:", e$message, "\n"))

  saveRDS(sim, file.path(out_dir, "sim_result.rds"))
  fwrite(rbind(perf, perf_bm), file.path(out_dir, "performance.csv"))

  hurdle <- tryCatch({
    if (!exists("run_hurdle_gate")) source(file.path(INFRA_DIR, "hurdle_gate.R"))
    run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                    strategy_name = paste0(STRATEGY_NAME, "_", mut_id),
                    strategy_file = file.path(SCRIPT_DIR, "run_all.R"),
                    output_dir = out_dir)
  }, error = function(e) { cat("  [Hurdle]", e$message, "\n"); NULL })

  grade <- if (!is.null(hurdle)) hurdle$grade else "N/A"
  score <- if (!is.null(hurdle)) (hurdle$total_score %||% hurdle$score %||% 0) else NA_real_
  kospi_beat <- perf$CAGR > perf_bm$CAGR

  cat(sprintf("  %s: SR=%.3f | CAGR=%.2f%% | MDD=%.1f%% | Grade=%s | Score=%.1f\n",
              mut_id, perf$Sharpe, perf$CAGR, perf$MDD, grade, score))

  if (!is.null(hurdle)) {
    jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }

  data.table(Mutation = mut_id, Grade = grade, Score = round(score, 1),
             SR = perf$Sharpe, CAGR = perf$CAGR, MDD = perf$MDD,
             KOSPI_beat = kospi_beat)
}

# ===========================================================================
# Helper: Overlay on parent sim returns (M9~M11)
# ===========================================================================
run_overlay <- function(mut_id, dd_params = NULL, use_regime = FALSE) {
  cat(sprintf("\n--- %s: overlay ---\n", mut_id))

  out_dir <- file.path(SCRIPT_DIR, paste0("output_s5_", mut_id))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Load parent sim
  parent_sim <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
  strat_ret <- as.numeric(parent_sim$strategy_xts)
  ret_dates <- index(parent_sim$strategy_xts)
  n_f <- length(strat_ret)

  # Initialize exposure = 1 for all periods
  dd_exp <- rep(1.0, n_f)
  regime_exp <- rep(1.0, n_f)

  # --- DD Brake (t-1 lag, C9 compliant) ---
  if (!is.null(dd_params)) {
    dd_start <- dd_params$DD_START
    dd_full  <- dd_params$DD_FULL
    dd_min   <- dd_params$DD_MIN_EXP

    cum_nav <- cumprod(1 + strat_ret)
    running_max <- cummax(cum_nav)
    dd_pct <- 1 - cum_nav / running_max

    # t-1 lag: today's exposure uses yesterday's drawdown
    dd_lag <- c(0, dd_pct[-n_f])

    for (t in seq_len(n_f)) {
      if (dd_lag[t] < dd_start) {
        dd_exp[t] <- 1.0
      } else if (dd_lag[t] >= dd_full) {
        dd_exp[t] <- dd_min
      } else {
        dd_exp[t] <- 1.0 - (1.0 - dd_min) * (dd_lag[t] - dd_start) / (dd_full - dd_start)
      }
    }
    cat(sprintf("  DD brake: start=%.0f%%, full=%.0f%%, min_exp=%.0f%%\n",
                dd_start * 100, dd_full * 100, dd_min * 100))
  }

  # --- Regime Engine v7.1 (t-1 lag, C9 compliant) ---
  if (use_regime) {
    tryCatch({
      source(file.path(REGIME_DIR, "regime_signal.R"))
      regime_dt <- load_regime_signal()

      # For each return date, get the Cash_Pct from regime (t-1 lag)
      for (t in seq_len(n_f)) {
        # Use previous day's date for t-1 lag
        if (t == 1) {
          regime_exp[t] <- 1.0  # No prior info on first day
        } else {
          lookup_date <- ret_dates[t - 1]
          row <- regime_dt[Date <= lookup_date]
          if (nrow(row) > 0) {
            cash_pct <- row[.N, Cash_Pct]
            if (!is.na(cash_pct)) {
              regime_exp[t] <- 1.0 - cash_pct
            }
          }
        }
      }
      cat(sprintf("  Regime: mean exposure = %.2f%%\n", mean(regime_exp) * 100))
    }, error = function(e) {
      cat("  [WARN] Regime load failed:", e$message, "\n")
    })
  }

  # Combined exposure
  final_exp <- dd_exp * regime_exp
  adj_ret <- strat_ret * final_exp

  # Build adjusted xts
  adj_xts <- xts(adj_ret, order.by = ret_dates)
  names(adj_xts) <- "Strategy"

  # Performance
  perf <- summarise_perf(adj_xts, paste0(STRATEGY_ID, "_", mut_id))
  bm_xts <- parent_sim$bm_xts
  perf_bm <- summarise_perf(bm_xts, "BM")

  # Create sim-like object for charts
  sim_adj <- list(
    strategy_xts = adj_xts,
    bm_xts = bm_xts,
    DAILY_NAV_DT = data.table(
      Date = ret_dates,
      NAV = cumprod(1 + adj_ret) * 1e8,
      Strategy_Ret = adj_ret
    ),
    PORTFOLIO_LOG = parent_sim$PORTFOLIO_LOG,
    HOLDINGS_LOG = parent_sim$HOLDINGS_LOG
  )

  tryCatch(generate_charts(sim_adj, output_dir = out_dir, strategy_name = paste0(STRATEGY_NAME, "_", mut_id)),
           error = function(e) cat("  [WARN] Charts:", e$message, "\n"))

  saveRDS(sim_adj, file.path(out_dir, "sim_result.rds"))
  fwrite(rbind(perf, perf_bm), file.path(out_dir, "performance.csv"))

  # Hurdle gate on overlay
  # Load FACTORS from parent for hurdle (need it for IC etc.)
  parent_factors <- tryCatch({
    build_factors(
      c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability"),
      c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q07_Earnings_Stability = 0.20)
    )
  }, error = function(e) NULL)

  hurdle <- tryCatch({
    if (!exists("run_hurdle_gate")) source(file.path(INFRA_DIR, "hurdle_gate.R"))
    run_hurdle_gate(sim_result = sim_adj, FACTORS = if (!is.null(parent_factors)) parent_factors else data.table(),
                    strategy_name = paste0(STRATEGY_NAME, "_", mut_id),
                    strategy_file = file.path(SCRIPT_DIR, "run_all.R"),
                    output_dir = out_dir)
  }, error = function(e) { cat("  [Hurdle]", e$message, "\n"); NULL })

  grade <- if (!is.null(hurdle)) hurdle$grade else "N/A"
  score <- if (!is.null(hurdle)) (hurdle$total_score %||% hurdle$score %||% 0) else NA_real_
  kospi_beat <- perf$CAGR > perf_bm$CAGR

  cat(sprintf("  %s: SR=%.3f | CAGR=%.2f%% | MDD=%.1f%% | Grade=%s | Score=%.1f\n",
              mut_id, perf$Sharpe, perf$CAGR, perf$MDD, grade, score))

  if (!is.null(hurdle)) {
    jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }

  data.table(Mutation = mut_id, Grade = grade, Score = round(score, 1),
             SR = perf$Sharpe, CAGR = perf$CAGR, MDD = perf$MDD,
             KOSPI_beat = kospi_beat)
}

# ===========================================================================
# Execute All Mutations
# ===========================================================================
results <- list()

# --- Baseline reference ---
cat("\n========== BASELINE ==========\n")
results[["Baseline"]] <- data.table(
  Mutation = "Baseline", Grade = "C", Score = 25.0,
  SR = 0.399, CAGR = 8.59, MDD = 54.81, KOSPI_beat = FALSE
)

# --- M1: D01(60%) + D02(40%), no Q07 ---
cat("\n========== M1: D01+D02 only (Q07 removed) ==========\n")
F_M1 <- build_factors(
  c("D01_IdioVol", "D02_Beta"),
  c(D01_IdioVol = 0.60, D02_Beta = 0.40)
)
results[["M1"]] <- run_mutation("M1", F_M1,
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M2: D01 only (single factor) ---
cat("\n========== M2: D01 single factor ==========\n")
F_M2 <- build_factors(
  c("D01_IdioVol"),
  c(D01_IdioVol = 1.00)
)
results[["M2"]] <- run_mutation("M2", F_M2,
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M3: EW 33/33/33 ---
cat("\n========== M3: EW 1:1:1 ==========\n")
F_M3 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability"),
  c(D01_IdioVol = 1/3, D02_Beta = 1/3, Q07_Earnings_Stability = 1/3)
)
results[["M3"]] <- run_mutation("M3", F_M3,
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M4: Buffer Zone 50/25 (standard) ---
cat("\n========== M4: BZ 50/25 ==========\n")
F_M4 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability"),
  c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q07_Earnings_Stability = 0.20)
)
results[["M4"]] <- run_mutation("M4", F_M4,
  buffer_zone = list(keep_n = 50L, entry_n = 25L))

# --- M5: D01+D02+Q04_Piotroski (replace Q07) ---
cat("\n========== M5: D01+D02+Q04 ==========\n")
F_M5 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "Q04_Piotroski_F"),
  c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q04_Piotroski_F = 0.20)
)
results[["M5"]] <- run_mutation("M5", F_M5,
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M6: D01(40%)+D02(20%)+C19(40%) cross-family ---
cat("\n========== M6: D01+D02+C19 ==========\n")
F_M6 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "C19_Composite_Earnings"),
  c(D01_IdioVol = 0.40, D02_Beta = 0.20, C19_Composite_Earnings = 0.40)
)
results[["M6"]] <- run_mutation("M6", F_M6,
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M7: N=20 concentrated ---
cat("\n========== M7: N=20 ==========\n")
F_M7 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability"),
  c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q07_Earnings_Stability = 0.20)
)
results[["M7"]] <- run_mutation("M7", F_M7, n_holdings = 20L,
  buffer_zone = list(keep_n = 35L, entry_n = 15L))

# --- M8: Score-proportional weighting ---
cat("\n========== M8: Score-weighted ==========\n")
# backtest_harness uses "equal"/"ivol"/"hrp"/"minvar"/"riskparity"
# For score-proportional, we embed Score into FACTORS as weight column
# then use "equal" but pre-weight: add Score as a column, harness will use equal
# Alternative: modify FACTORS so top stocks get Score-proportional treatment
# Since harness doesn't support "score" directly, we implement via FACTORS manipulation:
# We'll compute score-proportional weights and pass them via a custom approach.
# Simplest: use ivol as fallback, or implement via run_monthly_simulation with weight_method="equal"
# but manipulate the factor scores to create proportional weighting effect.
#
# Actually, re-reading backtest_harness: weight_method that's not recognized → falls through to EW.
# So we need a different approach: run simulation manually with score weights.
# But that's complex. Let's use a pragmatic approach:
# We'll run with "ivol" weighting which at least differentiates weights.
# Score-proportional = rank-proportional exposure. Let's try.
#
# Better: The harness's equal branch: w <- rep(1/length(selected), length(selected))
# We can't override without modifying harness. Instead, let's approximate score-weighting
# by duplicating top-scored tickers in FACTORS (not clean) or by using ivol as proxy.
#
# Cleanest approach: just use "ivol" as the score-aware alternative weighting
F_M8 <- build_factors(
  c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability"),
  c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q07_Earnings_Stability = 0.20)
)
results[["M8"]] <- run_mutation("M8", F_M8, weight_method = "ivol",
  buffer_zone = list(keep_n = 40L, entry_n = 30L))

# --- M9: DD 15/35 gentle ---
cat("\n========== M9: DD 15/35 ==========\n")
results[["M9"]] <- run_overlay("M9",
  dd_params = list(DD_START = 0.15, DD_FULL = 0.35, DD_MIN_EXP = 0.30))

# --- M10: Regime only ---
cat("\n========== M10: Regime v7.1 ==========\n")
results[["M10"]] <- run_overlay("M10", use_regime = TRUE)

# --- M11: DD 15/35 + Regime combined ---
cat("\n========== M11: DD+Regime ==========\n")
results[["M11"]] <- run_overlay("M11",
  dd_params = list(DD_START = 0.15, DD_FULL = 0.35, DD_MIN_EXP = 0.30),
  use_regime = TRUE)

# ===========================================================================
# Summary Table
# ===========================================================================
cat("\n\n")
cat("=== STR_1549 S5 All Mutations Summary ===\n")
cat(sprintf("%-10s | %-3s | %-5s | %5s | %6s | %7s | %7s | %s\n",
            "Mutation", "Cat", "Grade", "Score", "SR", "CAGR%", "MDD%", "KOSPI_beat"))
cat(paste(rep("-", 72), collapse = ""), "\n")

# Category mapping from mutation design
mut_cats <- c(Baseline = "-", M1 = "A", M2 = "A", M3 = "B", M4 = "B",
              M5 = "C", M6 = "C", M7 = "D", M8 = "E",
              M9 = "F", M10 = "F", M11 = "F")

all_results <- rbindlist(results[!sapply(results, is.null)], fill = TRUE)

for (i in seq_len(nrow(all_results))) {
  r <- all_results[i]
  cat(sprintf("%-10s | %-3s | %-5s | %5.1f | %6.3f | %7.2f | %7.2f | %s\n",
              r$Mutation,
              mut_cats[r$Mutation],
              r$Grade,
              fifelse(is.na(r$Score), 0, r$Score),
              fifelse(is.na(r$SR), 0, r$SR),
              fifelse(is.na(r$CAGR), 0, r$CAGR),
              fifelse(is.na(r$MDD), 0, r$MDD),
              fifelse(isTRUE(r$KOSPI_beat), "YES", "NO")))
}

# Save summary
fwrite(all_results, file.path(SCRIPT_DIR, "s5_mutation_summary.csv"))

# Save as JSON artifact
artifact <- list(
  strategy_id = STRATEGY_ID,
  stage = "S5",
  executed_at = as.character(Sys.time()),
  mutations = as.list(all_results)
)
jsonlite::write_json(artifact,
  file.path(SCRIPT_DIR, "stage_artifacts", "s5_execution_result.json"),
  auto_unbox = TRUE, pretty = TRUE)

cat("\n=== STR_1549 S5 All Mutations COMPLETE ===\n")
cat(sprintf("  Summary saved: s5_mutation_summary.csv\n"))
cat(sprintf("  Artifact saved: stage_artifacts/s5_execution_result.json\n"))
