#==============================================================================
# Factor DB Builder — Central Orchestrator
# Version: 1.0.0
#
# Computes and stores standardized factors for the entire universe.
# Each compute_*.R module returns data.table(Ticker, Factor_Name, Raw_Value)
# for one category. This builder combines them, adds Z_Score/Z_Sector/Rank_Pct,
# and saves to .cache/factor_db/factor_db_YYYYMM.parquet.
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/factor_db_builder.R")
#   build_factor_db("2026-02-28")                   # one date
#   build_factor_db_monthly("2020-01-01","2026-02-28")  # batch
#   dt <- load_factor_db("2026-02-28")              # load cached
#   ic <- get_factor_ic("V01_BM", 60)               # IC history
#   update_factor_db_daily()                         # cron hook
#
# PIT Rules:
#   - Fundamentals: Factor_Date <= sig_date (most recent per Ticker×Item)
#   - Consensus: Date <= sig_date (most recent per Ticker)
#   - Price/Volume: Date <= sig_date
#   - All z-scores: CROSS-SECTIONAL at sig_date (NOT time-series)
#==============================================================================

# ─── Self-locate & source config ────────────────────────────────────────────
.self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db")
    else file.path(
      Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
      "02_Infrastructure", "factor_db"
    )
  }
)

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(.self_dir), "config.R"))
}

# ─── Packages ────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ─── Constants ───────────────────────────────────────────────────────────────
FACTOR_DB_DIR    <- file.path(CACHE_DIR, "factor_db")
FACTOR_IC_PATH   <- file.path(FACTOR_DB_DIR, "factor_ic_history.parquet")
FACTOR_REG_PATH  <- file.path(FACTOR_DB_DIR, "factor_registry.json")
COMPUTE_MOD_DIR  <- file.path(FUNC_PATH, "factor_db")

# Ensure output directory exists
if (!dir.exists(FACTOR_DB_DIR)) {
  dir.create(FACTOR_DB_DIR, recursive = TRUE, showWarnings = FALSE)
}

cat("[factor_db_builder] Loaded. FACTOR_DB_DIR:", FACTOR_DB_DIR, "\n")

#==============================================================================
# v54 Gate 13.1 — build_hash helpers
#==============================================================================

#' Write build_hash.txt to FACTOR_DB_DIR (timestamp + git short hash).
#' Called at end of build_factor_db() and build_factor_db_monthly().
.write_build_hash <- function() {
  tryCatch({
    git_rev <- tryCatch(
      system("git rev-parse --short HEAD", intern = TRUE, ignore.stderr = TRUE),
      error = function(e) "unknown"
    )
    if (length(git_rev) == 0 || nchar(git_rev) == 0) git_rev <- "unknown"
    hash_str <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), git_rev, sep = "_")
    hash_path <- file.path(FACTOR_DB_DIR, "build_hash.txt")
    writeLines(hash_str, hash_path)
    cat(sprintf("[factor_db_builder] build_hash written: %s -> %s\n", hash_str, hash_path))
  }, error = function(e) {
    cat(sprintf("[factor_db_builder] WARN: could not write build_hash: %s\n",
                conditionMessage(e)))
  })
}

#==============================================================================
# Internal: Load base data (cached within session)
#==============================================================================

.fdb_env <- new.env(parent = emptyenv())

.load_base_data <- function(force = FALSE) {
  if (!force && exists("RAWDATA", envir = .fdb_env)) return(invisible(NULL))

  cat("[factor_db_builder] Loading base data...\n")

  # RAWDATA
  .fdb_env$RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
  cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
              format(nrow(.fdb_env$RAWDATA), big.mark = ","),
              min(.fdb_env$RAWDATA$Date), max(.fdb_env$RAWDATA$Date)))

  # VIX column from macro_fred (for D32_Beta_VIX in compute_defense.R)
  macro_path <- file.path(CACHE_DIR, "macro_fred.parquet")
  if (!("VIX" %in% names(.fdb_env$RAWDATA)) && file.exists(macro_path)) {
    tryCatch({
      macro <- as.data.table(read_parquet(macro_path))
      macro[, Date := as.Date(Date)]
      vix_col <- if ("Series_ID" %in% names(macro) &&
                      "VIXCLS" %in% macro[["Series_ID"]]) {
        macro[Series_ID == "VIXCLS" & !is.na(Value),
              .(Date, VIX = Value)][, .(VIX = last(VIX)), by = Date]
      } else if ("VIX" %in% macro[["Series"]]) {
        macro[Series == "VIX" & !is.na(Value),
              .(Date, VIX = Value)][, .(VIX = last(VIX)), by = Date]
      } else NULL
      if (!is.null(vix_col) && nrow(vix_col) > 0L) {
        setkey(vix_col, Date)
        # ffill VIX over all RAWDATA dates
        all_dates <- data.table(Date = sort(unique(.fdb_env$RAWDATA$Date)))
        vix_filled <- vix_col[all_dates, on = "Date", roll = TRUE]
        .fdb_env$RAWDATA <- merge(.fdb_env$RAWDATA, vix_filled, by = "Date", all.x = TRUE)
        cat(sprintf("  RAWDATA: VIX column added (%d carry-forwarded values)\n",
                    sum(!is.na(vix_filled$VIX))))
      }
    }, error = function(e) {
      cat(sprintf("  RAWDATA: VIX merge failed (%s)\n", conditionMessage(e)))
    })
  }

  # Fundamentals
  fund_path <- file.path(CACHE_DIR, "fundamental_merged.parquet")
  if (file.exists(fund_path)) {
    .fdb_env$FUND <- as.data.table(read_parquet(fund_path))
    cat(sprintf("  Fundamentals: %s rows\n",
                format(nrow(.fdb_env$FUND), big.mark = ",") ))

    # ── Item alias mapping (compute_*.R name compatibility) ──────────────
    # Append rows with canonical names expected by compute modules whose
    # source names differ from fundamental_merged.parquet schema.
    # Audit (2026-05-23):
    #   compute_accrual.R expects CurrentLiabilities/TotalLiabilities
    #   compute_growth.R  expects RnDExpense (PPE/Inventories/SharesOutstanding
    #                              are derived below)
    # Other names (CashAndEquiv, DepAmort, SGAExpense, FinanceCF, AccountsRecv,
    # AccountsPay) match exactly — no alias needed.
    .item_aliases <- list(
      CurrentLiabilities = "CurrentLiab",
      TotalLiabilities   = "TotalLiab",
      RnDExpense         = "RandD",
      AccountsReceivable = "AccountsRecv",
      AccountsPayable    = "AccountsPay"
    )
    .alias_rows <- list()
    for (canonical in names(.item_aliases)) {
      orig <- .item_aliases[[canonical]]
      if (orig %in% .fdb_env$FUND$Item && !(canonical %in% .fdb_env$FUND$Item)) {
        sub <- .fdb_env$FUND[Item == orig]
        if (nrow(sub) > 0L) {
          sub <- copy(sub)[, Item := canonical]
          .alias_rows[[canonical]] <- sub
        }
      }
    }
    if (length(.alias_rows) > 0L) {
      .fdb_env$FUND <- rbindlist(c(list(.fdb_env$FUND), .alias_rows),
                                  use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals alias: +%d Items (%s)\n",
                  length(.alias_rows),
                  paste(names(.alias_rows), collapse = ", ")))
    }

    # Inventories: derive from working capital approximation
    # (CurrentAssets - CashAndEquiv - AccountsRecv) ≈ Inventories + other current assets
    # Best-effort; may be wide. compute_*.R handles NA gracefully.
    if (!("Inventories" %in% .fdb_env$FUND$Item) &&
        all(c("CurrentAssets","CashAndEquiv","AccountsRecv") %in% .fdb_env$FUND$Item)) {
      ca <- .fdb_env$FUND[Item == "CurrentAssets",
                          .(Ticker, Factor_Date, Period, ca = Value)]
      ch <- .fdb_env$FUND[Item == "CashAndEquiv",
                          .(Ticker, Factor_Date, Period, cash = Value)]
      rv <- .fdb_env$FUND[Item == "AccountsRecv",
                          .(Ticker, Factor_Date, Period, recv = Value)]
      inv_est <- merge(merge(ca, ch, by = c("Ticker","Factor_Date","Period"), all = FALSE),
                       rv, by = c("Ticker","Factor_Date","Period"), all = FALSE)
      inv_est[, Inv_proxy := ca - cash - recv]
      inv_est <- inv_est[!is.na(Inv_proxy) & Inv_proxy >= 0]
      if (nrow(inv_est) > 0L) {
        src <- .fdb_env$FUND[Item == "CurrentAssets",
                              .SD[1L], by = .(Ticker, Factor_Date, Period)]
        inv_rows <- merge(inv_est[, .(Ticker, Factor_Date, Period, Value = Inv_proxy)],
                          src[, .(Ticker, Factor_Date, Period, Period_Date, Source)],
                          by = c("Ticker","Factor_Date","Period"), all.x = TRUE)
        inv_rows[, Item := "Inventories"][, Source := paste0(Source %||% "derived", "_proxy")]
        .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND,
                                          inv_rows[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source)]),
                                    use.names = TRUE, fill = TRUE)
        cat(sprintf("  Fundamentals derived: Inventories proxy (+%d rows)\n", nrow(inv_rows)))
      }
    }

    # SharesOutstanding: derive from RAWDATA Size / Close (market cap / price)
    if (!("SharesOutstanding" %in% .fdb_env$FUND$Item) &&
        all(c("Date","Close","Size") %in% names(.fdb_env$RAWDATA))) {
      sh <- .fdb_env$RAWDATA[!is.na(Close) & Close > 1e-6 & !is.na(Size) & Size > 0,
                              .(Ticker, Date, est_shares = Size / Close)]
      # Quarterly snapshot — end of quarter
      sh[, qtr := paste0(year(Date), "Q", quarter(Date))]
      sh_q <- sh[, .SD[.N], by = .(Ticker, qtr)]
      sh_q[, `:=`(Factor_Date = Date,
                  Period_Date = Date,
                  Period = qtr,
                  Item = "SharesOutstanding",
                  Value = est_shares,
                  Source = "derived_from_size")]
      .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND,
                                        sh_q[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source)]),
                                  use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals derived: SharesOutstanding (+%d rows)\n", nrow(sh_q)))
    }

    # PPE: alias from TangibleAssets if available
    if (!("PPE" %in% .fdb_env$FUND$Item) && "TangibleAssets" %in% .fdb_env$FUND$Item) {
      sub <- copy(.fdb_env$FUND[Item == "TangibleAssets"])[, Item := "PPE"]
      .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND, sub), use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals alias: PPE <- TangibleAssets (+%d rows)\n", nrow(sub)))
    }
  } else {
    .fdb_env$FUND <- NULL
    cat("  Fundamentals: NOT FOUND\n")
  }
  if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

  # Valuation (pre-computed fPER/fPBR/fDY/EV_EBITDA/PSR)
  val_path <- file.path(CACHE_DIR, "valuation.parquet")
  if (file.exists(val_path)) {
    .fdb_env$VALUATION <- as.data.table(read_parquet(val_path))
    cat(sprintf("  Valuation: %s rows\n",
                format(nrow(.fdb_env$VALUATION), big.mark = ",")))
  } else {
    .fdb_env$VALUATION <- NULL
    cat("  Valuation: NOT FOUND\n")
  }

  # Consensus — load all available parquets
  cons_dir <- file.path(CACHE_DIR, "consensus")
  .fdb_env$CONSENSUS <- list()
  if (dir.exists(cons_dir)) {
    cons_files <- list.files(cons_dir, pattern = "\\.parquet$", full.names = TRUE)
    for (cf in cons_files) {
      nm <- gsub("\\.parquet$", "", basename(cf))
      .fdb_env$CONSENSUS[[nm]] <- as.data.table(read_parquet(cf))
    }
    cat(sprintf("  Consensus: %d tables (%s)\n",
                length(.fdb_env$CONSENSUS),
                paste(names(.fdb_env$CONSENSUS), collapse = ", ")))
  } else {
    cat("  Consensus: NOT FOUND\n")
  }

  # Investor (거래주체) — wide format parquet
  if (exists("INVESTOR_CACHE")) {
    inv_wide_path <- file.path(INVESTOR_CACHE, "investor_wide.parquet")
  } else {
    inv_wide_path <- file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet")
  }
  if (file.exists(inv_wide_path)) {
    .fdb_env$INVESTOR <- as.data.table(read_parquet(inv_wide_path))
    .fdb_env$INVESTOR[, Date := as.Date(Date)]
    cat(sprintf("  Investor: %s rows | %d tickers\n",
                format(nrow(.fdb_env$INVESTOR), big.mark = ","),
                uniqueN(.fdb_env$INVESTOR$Ticker)))
  } else {
    .fdb_env$INVESTOR <- NULL
    cat("  Investor: NOT FOUND\n")
  }

  # ─── Ensure Date columns are proper Date class (arrow may return IDate) ──────
  # This guarantees compute modules do NOT need copy(RAWDATA)[, Date := as.Date(Date)]
  # to do a conversion — they will still call it but it becomes a near-no-op.
  if (!inherits(.fdb_env$RAWDATA$Date, "Date")) {
    .fdb_env$RAWDATA[, Date := as.Date(Date)]
  }
  if (!is.null(.fdb_env$FUND) && "Factor_Date" %in% names(.fdb_env$FUND)) {
    if (!inherits(.fdb_env$FUND$Factor_Date, "Date")) {
      .fdb_env$FUND[, Factor_Date := as.Date(Factor_Date)]
    }
  }

  # ─── Performance indexes (built once, reused every month) ──────────────────
  setkey(.fdb_env$RAWDATA, Date, Ticker)
  if (!is.null(.fdb_env$FUND) && nrow(.fdb_env$FUND) > 0) {
    setkey(.fdb_env$FUND, Factor_Date, Ticker, Item)
  }
  if (!is.null(.fdb_env$VALUATION) && nrow(.fdb_env$VALUATION) > 0) {
    setkey(.fdb_env$VALUATION, Date, Ticker)
  }
  # Pre-compute sorted unique dates — avoids sort(unique(...)) in every PIT call
  .fdb_env$trading_dates     <- sort(unique(.fdb_env$RAWDATA$Date))
  if (!is.null(.fdb_env$VALUATION)) {
    .fdb_env$valuation_dates <- sort(unique(.fdb_env$VALUATION$Date))
  }

  invisible(NULL)
}


#==============================================================================
# Internal: Module preloader — source each compute_*.R ONCE per session
#==============================================================================

.preload_modules <- function() {
  if (isTRUE(.fdb_env$.modules_loaded)) return(invisible(NULL))

  module_map <- list(
    value            = "compute_value.R",
    momentum         = "compute_momentum.R",
    quality          = "compute_quality.R",
    quality_xf_native = "compute_quality_xf_native.R",
    defense          = "compute_defense.R",
    size             = "compute_size.R",
    consensus        = "compute_consensus.R",
    liquidity        = "compute_liquidity.R",
    accrual          = "compute_accrual.R",
    risk             = "compute_risk.R",
    regime           = "compute_regime.R",
    crowding         = "compute_crowding.R",
    growth           = "compute_growth.R",
    investor         = "compute_investor.R",
    xlsx_fund        = "xlsx_factor_calculator.R"
  )
  func_name_map <- list(
    value            = "compute_value",
    momentum         = "compute_momentum",
    quality          = "compute_quality",
    quality_xf_native = "compute_quality_xf_native",
    defense          = "compute_defense",
    size             = "compute_size",
    consensus        = "compute_consensus",
    liquidity        = "compute_liquidity",
    accrual          = "compute_accrual",
    risk             = "compute_risk",
    regime           = "compute_regime",
    crowding         = "compute_crowding",
    growth           = "compute_growth",
    investor         = "compute_investor",
    xlsx_fund        = "compute_xlsx_fundamentals"
  )

  .fdb_env$module_funcs <- list()
  n_loaded <- 0L

  for (nm in names(module_map)) {
    fpath <- file.path(COMPUTE_MOD_DIR, module_map[[nm]])
    if (!file.exists(fpath)) {
      cat(sprintf("  [PRELOAD SKIP] %s not found\n", module_map[[nm]]))
      next
    }
    tryCatch({
      env <- new.env(parent = globalenv())
      source(fpath, local = env)
      fn_name <- func_name_map[[nm]]
      if (exists(fn_name, envir = env, inherits = FALSE)) {
        .fdb_env$module_funcs[[nm]] <- get(fn_name, envir = env)
        n_loaded <- n_loaded + 1L
      } else {
        cat(sprintf("  [PRELOAD WARN] %s: function '%s' not found\n",
                    module_map[[nm]], fn_name))
      }
    }, error = function(e) {
      cat(sprintf("  [PRELOAD ERROR] %s: %s\n", module_map[[nm]], conditionMessage(e)))
    })
  }

  .fdb_env$.modules_loaded <- TRUE
  cat(sprintf("[factor_db_builder] Preloaded %d/%d compute modules\n",
              n_loaded, length(module_map)))
  invisible(NULL)
}


#==============================================================================
# Internal: PIT-safe data extraction helpers
#==============================================================================

#' Get latest fundamental value per Ticker×Item as of sig_date
#' PIT: Factor_Date <= sig_date, then most recent per Ticker×Item
.pit_fund <- function(sig_date, items = NULL) {
  fund <- .fdb_env$FUND
  if (is.null(fund) || nrow(fund) == 0) return(NULL)

  sig_d <- as.Date(sig_date)
  # Binary-search cutoff via setkey(Factor_Date) index
  dt <- fund[Factor_Date <= sig_d]
  if (!is.null(items)) dt <- dt[Item %in% items]
  if (nrow(dt) == 0) return(NULL)

  # Most recent per Ticker × Item — last row after key-sorted order
  dt[, .SD[.N], by = .(Ticker, Item)]
}

#' Get RAWDATA snapshot on sig_date (or most recent trading day <= sig_date)
.pit_rawdata <- function(sig_date) {
  sig_d <- as.Date(sig_date)

  # findInterval: O(log N) lookup into pre-sorted trading_dates vector
  dates <- .fdb_env$trading_dates
  idx   <- findInterval(sig_d, dates)
  if (idx == 0L) return(NULL)
  actual_date <- dates[idx]

  .fdb_env$RAWDATA[.(actual_date), nomatch = 0L]  # keyed join on Date
}

#' Get price history up to sig_date (for momentum/vol calculations)
.pit_price_history <- function(sig_date, lookback_days = 260L) {
  sig_d   <- as.Date(sig_date)
  start_d <- sig_d - lookback_days

  # setkey(Date, Ticker) → range scan is fast
  .fdb_env$RAWDATA[Date >= start_d & Date <= sig_d]
}

#' Get latest consensus value per Ticker as of sig_date
.pit_consensus <- function(sig_date, table_name) {
  cons <- .fdb_env$CONSENSUS[[table_name]]
  if (is.null(cons) || nrow(cons) == 0) return(NULL)

  sig_d <- as.Date(sig_date)

  # Ensure keyed by Date for fast range scan; key once per table if needed
  if (!isTRUE(.fdb_env$.cons_keyed[[table_name]])) {
    if (is.null(.fdb_env$.cons_keyed)) .fdb_env$.cons_keyed <- list()
    if ("Date" %in% names(cons)) {
      setkeyv(cons, "Date")
      .fdb_env$.cons_keyed[[table_name]] <- TRUE
    }
  }

  dt <- cons[Date <= sig_d]
  if (nrow(dt) == 0) return(NULL)

  # Most recent per Ticker — setorder + .SD[.N] is faster than which.max()
  setorder(dt, Ticker, Date)
  dt[, .SD[.N], by = Ticker]
}

#' Get valuation snapshot on sig_date
.pit_valuation <- function(sig_date) {
  val <- .fdb_env$VALUATION
  if (is.null(val) || nrow(val) == 0) return(NULL)

  sig_d <- as.Date(sig_date)
  # Use pre-computed valuation_dates if available, otherwise fall back
  vdates <- if (!is.null(.fdb_env$valuation_dates)) .fdb_env$valuation_dates
            else sort(unique(val$Date))
  idx <- findInterval(sig_d, vdates)
  if (idx == 0L) return(NULL)
  actual_date <- vdates[idx]

  val[.(actual_date), nomatch = 0L]  # keyed join on Date
}


#==============================================================================
# Internal: Standardization (cross-sectional z-score, sector-neutral, rank)
#==============================================================================

#' Standardize raw factor values cross-sectionally
#' @param dt data.table with Ticker, Factor_Name, Raw_Value
#' @param sector_map data.table with Ticker, Sector (from RAWDATA snapshot)
#' @return dt with Z_Score, Z_Sector, Rank_Pct, Coverage columns added
.standardize_factors <- function(dt, sector_map) {
  if (nrow(dt) == 0) return(dt[, .(Ticker, Factor_Name, Raw_Value,
                                    Z_Score = numeric(0),
                                    Z_Sector = numeric(0),
                                    Rank_Pct = numeric(0),
                                    Coverage = logical(0))])

  # Merge sector info
  dt <- merge(dt, sector_map[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)

  # Coverage: TRUE if Raw_Value is not NA
  dt[, Coverage := !is.na(Raw_Value)]

  # Universe z-score (cross-sectional)
  dt[, Z_Score := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else (vals - mu) / s
  }, by = Factor_Name]

  # Sector-neutral z-score
  dt[, Z_Sector := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else (vals - mu) / s
  }, by = .(Factor_Name, Sector)]

  # Rank percentile (0~1, higher = higher raw value)
  dt[, Rank_Pct := {
    vals <- Raw_Value
    r <- frank(vals, ties.method = "average", na.last = "keep")
    n_valid <- sum(!is.na(vals))
    if (n_valid > 1) (r - 1) / (n_valid - 1) else rep(NA_real_, .N)
  }, by = Factor_Name]

  # Winsorize z-scores at +/- 3
  dt[!is.na(Z_Score), Z_Score := pmin(pmax(Z_Score, -3), 3)]
  dt[!is.na(Z_Sector), Z_Sector := pmin(pmax(Z_Sector, -3), 3)]

  # Option A fix: re-standardize after winsorize to guarantee sd=1
  # Winsorize clips tails → sd < 1 for heavy-tailed factors (M08 +1761%, R16 +529%)
  dt[!is.na(Z_Score), Z_Score := {
    s <- sd(Z_Score, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score / s else Z_Score
  }, by = Factor_Name]
  dt[!is.na(Z_Sector), Z_Sector := {
    s <- sd(Z_Sector, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Sector / s else Z_Sector
  }, by = .(Factor_Name, Sector)]

  # Drop Sector column (not in output schema)
  dt[, Sector := NULL]

  dt
}


#==============================================================================
# 1. build_factor_db(sig_date) — Compute all factors for one signal date
#==============================================================================

#' Build factor DB for a single signal date.
#'
#' Sources each compute_*.R module, combines results, standardizes,
#' and saves to .cache/factor_db/factor_db_YYYYMM.parquet.
#'
#' @param sig_date Character or Date. Signal date (e.g., "2026-02-28")
#' @param save Logical. Save to parquet? (default: TRUE)
#' @param force Logical. Overwrite existing cache? (default: FALSE)
#' @return data.table in long format: Date, Ticker, Factor_Name, Raw_Value,
#'         Z_Score, Z_Sector, Rank_Pct, Coverage
#' @export
build_factor_db <- function(sig_date, save = TRUE, force = FALSE) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  out_path <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  # Check cache

if (!force && file.exists(out_path)) {
    cat(sprintf("[build_factor_db] Cache exists: %s (use force=TRUE to rebuild)\n", out_path))
    return(as.data.table(read_parquet(out_path)))
  }

  cat(sprintf("\n[build_factor_db] === Building factor DB for %s ===\n", sig_d))
  t0 <- Sys.time()

  # Load base data (no-op if already loaded this session)
  .load_base_data()
  # Preload compute modules once per session
  .preload_modules()

  # Get RAWDATA snapshot for sector mapping
  snap <- .pit_rawdata(sig_d)
  if (is.null(snap) || nrow(snap) == 0) {
    warning("[build_factor_db] No RAWDATA on or before ", sig_d)
    return(NULL)
  }
  sector_map <- snap[, .(Ticker, Sector)]
  cat(sprintf("  Universe: %d tickers on %s\n", nrow(sector_map), snap$Date[1]))

  # ─── Pre-slice data once — avoids 14× redundant full-scan inside modules ──
  # M12 Long-Run Reversal needs ~1260 trading days (~1400 calendar days).
  # All other modules need ≤365 calendar days. Use 1400d as conservative bound.
  RAWDATA_sliced <- .fdb_env$RAWDATA[Date <= sig_d & Date >= (sig_d - 1400L)]
  setkey(RAWDATA_sliced, Date, Ticker)

  # Pre-filter fundamentals: modules do copy(FUND)[Factor_Date <= sig_d] N times.
  # Passing the already-filtered subset avoids repeated full-FUND scans.
  FUND_pit <- if (!is.null(.fdb_env$FUND) && nrow(.fdb_env$FUND) > 0L)
                .fdb_env$FUND[Factor_Date <= sig_d]
              else
                NULL

  cat(sprintf("  Pre-sliced RAWDATA: %s rows (full: %s) | FUND_pit: %s rows\n",
              format(nrow(RAWDATA_sliced), big.mark = ","),
              format(nrow(.fdb_env$RAWDATA),  big.mark = ","),
              format(if (!is.null(FUND_pit)) nrow(FUND_pit) else 0L, big.mark = ",")))

  # ─── Execute preloaded compute modules ───────────────────────────────────
  all_factors <- list()

  # Module display names (for logging)
  module_display <- list(
    value = "compute_value.R", momentum = "compute_momentum.R",
    quality = "compute_quality.R",
    quality_xf_native = "compute_quality_xf_native.R",
    defense = "compute_defense.R",
    size = "compute_size.R", consensus = "compute_consensus.R",
    liquidity = "compute_liquidity.R", accrual = "compute_accrual.R",
    risk = "compute_risk.R", regime = "compute_regime.R",
    crowding = "compute_crowding.R", growth = "compute_growth.R",
    investor = "compute_investor.R", xlsx_fund = "xlsx_factor_calculator.R"
  )

  for (nm in names(.fdb_env$module_funcs)) {
    fn <- .fdb_env$module_funcs[[nm]]
    display <- module_display[[nm]]
    tryCatch({
      result <- fn(RAWDATA = RAWDATA_sliced, sig_date = sig_d,
                   FUND = FUND_pit, CONSENSUS = .fdb_env$CONSENSUS)
      if (!is.null(result) && nrow(result) > 0) {
        cat(sprintf("  [OK] %s: %d factor×ticker rows (%d factors)\n",
                    display, nrow(result), uniqueN(result$Factor_Name)))
        all_factors[[nm]] <- result
      } else {
        cat(sprintf("  [EMPTY] %s returned 0 rows\n", display))
      }
    }, error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", display, conditionMessage(e)))
    })
  }

  # Combine all non-NULL results
  all_factors <- all_factors[!sapply(all_factors, is.null)]
  if (length(all_factors) == 0) {
    warning("[build_factor_db] No factors computed for ", sig_d)
    return(NULL)
  }

  combined <- rbindlist(all_factors, use.names = TRUE, fill = TRUE)

  # Remove XF_ factors (xlsx originals already merged into DART names)
  # Inline xlsx-into-dart merge (per Quality factor merge principle):
  #   - 19 mapped pairs (DART <- XF): DART preferred (higher quality),
  #     XF fills gap only when DART has 0 rows for this sig_date
  #   - Unmapped XF_* (DU/EF/GD/LL/PR/RI) preserved as standalone
  # See merge_xlsx_into_dart.R for batch post-process (legacy compatibility)
  .XF_TO_DART <- c(
    XF_Q01_GPA               = "Q01_GPA",
    XF_Q02_ROE               = "Q02_ROE",
    XF_Q03_ROA               = "Q03_ROA",
    XF_A01_Accrual           = "Q05_Accrual",
    XF_Q05_Gross_Margin      = "Q10_Gross_Margin",
    XF_Q07_Net_Margin        = "Q11_Net_Margin",
    XF_Q04_Asset_Turnover    = "Q12_Asset_Turnover",
    XF_Q08_Interest_Coverage = "Q32_Interest_Coverage",
    XF_L01_Debt_to_Equity    = "Q15_Debt_to_Equity",
    XF_L02_Current_Ratio     = "Q14_Current_Ratio",
    XF_P01_Piotroski_F       = "Q04_Piotroski_F",
    XF_V01_BM                = "V01_BM",
    XF_V02_EP                = "V02_EP",
    XF_V03_CFP               = "V03_CFP",
    XF_V04_SP                = "V08_PSR",
    XF_G01_Asset_Growth      = "GR03_Asset_Growth",
    XF_G02_Revenue_Growth    = "GR01_Revenue_Growth",
    XF_G03_Earnings_Growth   = "GR02_Earnings_Growth",
    XF_A02_NOA               = "AC05_NOA"
  )
  # Per-ticker merge: for each (ticker, sig_date) pair, DART value preferred;
  # XF (QuantiWise) used only when DART lacks coverage for that specific ticker.
  # Dohoon mandate (2026-05-23): "DART에서 구할 수 없는 과거데이터를 퀀티와이즈로 보강"
  .n_filled <- 0L; .n_dropped_dup <- 0L
  for (xf_nm in names(.XF_TO_DART)) {
    dart_nm <- .XF_TO_DART[[xf_nm]]
    xf_rows   <- combined[Factor_Name == xf_nm]
    if (nrow(xf_rows) == 0L) next
    dart_tickers <- combined[Factor_Name == dart_nm, unique(Ticker)]
    # XF tickers NOT covered by DART → adopt as fill (renamed to DART)
    xf_fill <- xf_rows[!Ticker %in% dart_tickers]
    xf_drop <- nrow(xf_rows) - nrow(xf_fill)
    if (nrow(xf_fill) > 0L) {
      xf_fill <- copy(xf_fill)[, Factor_Name := dart_nm]
      .n_filled <- .n_filled + nrow(xf_fill)
    }
    # Remove all mapped XF rows + append fill rows under DART name
    combined <- rbindlist(list(combined[Factor_Name != xf_nm], xf_fill),
                          use.names = TRUE, fill = TRUE)
    .n_dropped_dup <- .n_dropped_dup + xf_drop
  }
  if (.n_filled + .n_dropped_dup > 0L) {
    cat(sprintf("  Quality merge: %d XF→DART filled (per-ticker), %d XF dropped (DART covered)\n",
                .n_filled, .n_dropped_dup))
  }
  # Unmapped XF (DU/EF/GD/LL/PR/RI 25개): both compute_quality_xf_native (DART)
  # AND xlsx_factor_calculator (QuantiWise) emit same Factor_Name.
  # Per-(Ticker, Factor_Name) dedup keep first → DART preferred (module called earlier).
  # QuantiWise row remains only for tickers not in DART. Dohoon mandate 2026-05-23.
  .unmapped_xf <- c(
    "XF_DU01_NetMargin","XF_DU02_AssetTurnover","XF_DU03_EquityMultiplier",
    "XF_LL01_DebtToCapital","XF_LL02_NetDebt","XF_LL03_CashRatio",
    "XF_LL04_QuickRatio","XF_LL05_WorkingCapital",
    "XF_PR01_EBITDA_Margin","XF_PR02_RetainedEarnings_Ratio",
    "XF_PR03_TaxRate","XF_PR04_NetInterestMargin","XF_PR05_EBITDA_to_Assets",
    "XF_EF01_InventoryTurnover","XF_EF02_DaysPayable",
    "XF_EF03_DaysReceivable","XF_EF04_CCC",
    "XF_GD01_GrossProfit_Growth","XF_GD02_OpProfit_Growth",
    "XF_GD03_OCF_Growth","XF_GD04_Dividend_Growth",
    "XF_RI01_RnD_to_Revenue","XF_RI02_CapEx_proxy","XF_RI03_SGA_to_Revenue"
  )
  .unmapped_present <- intersect(.unmapped_xf, unique(combined$Factor_Name))
  if (length(.unmapped_present) > 0L) {
    xf_rows <- combined[Factor_Name %in% .unmapped_present]
    before_n <- nrow(xf_rows)
    xf_dedupe <- unique(xf_rows, by = c("Ticker","Factor_Name"), fromLast = FALSE)
    after_n <- nrow(xf_dedupe)
    combined <- rbindlist(list(
      combined[!Factor_Name %in% .unmapped_present],
      xf_dedupe
    ), use.names = TRUE, fill = TRUE)
    cat(sprintf("  Unmapped XF dedup: %d rows kept (DART preferred, was %d)\n",
                after_n, before_n))
  }

  # Ensure required columns
  stopifnot(all(c("Ticker", "Factor_Name", "Raw_Value") %in% names(combined)))

  # ─── Standardize ─────────────────────────────────────────────────────────
  cat("  Standardizing (z-score, sector-neutral, rank)...\n")
  result <- .standardize_factors(combined, sector_map)

  # Add Date column
  result[, Date := sig_d]
  setcolorder(result, c("Date", "Ticker", "Factor_Name", "Raw_Value",
                         "Z_Score", "Z_Sector", "Rank_Pct", "Coverage"))

  # ─── Summary stats ──────────────────────────────────────────────────────
  n_factors <- uniqueN(result$Factor_Name)
  n_tickers <- uniqueN(result$Ticker)
  n_covered <- result[Coverage == TRUE, uniqueN(paste(Ticker, Factor_Name))]
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

  cat(sprintf("  TOTAL: %d factors x %d tickers = %d rows (%d covered) [%.1fs]\n",
              n_factors, n_tickers, nrow(result), n_covered, elapsed))

  # Coverage summary per factor
  cov_summary <- result[, .(
    N_Total = .N,
    N_Covered = sum(Coverage, na.rm = TRUE),
    Pct_Covered = round(100 * mean(Coverage, na.rm = TRUE), 1)
  ), by = Factor_Name][order(Factor_Name)]
  cat("  Coverage by factor:\n")
  print(cov_summary, topn = 5)

  # ─── Save ─────────────────────────────────────────────────────────────────
  if (save) {
    write_parquet(result, out_path)
    cat(sprintf("  Saved: %s (%.1f MB)\n",
                out_path,
                file.size(out_path) / 1e6))
    # v54 Gate 13.1 — update build hash on every save
    .write_build_hash()
  }

  result
}


#==============================================================================
# 2. build_factor_db_monthly(start_date, end_date) — Batch build for range
#==============================================================================

#' Build factor DB for all month-end dates in range.
#'
#' Finds all month-end trading days in RAWDATA between start_date and end_date,
#' then calls build_factor_db() for each.
#'
#' @param start_date Character or Date
#' @param end_date Character or Date
#' @param force Logical. Overwrite existing cache? (default: FALSE)
#' @return Invisibly, the list of signal dates processed
#' @export
build_factor_db_monthly <- function(start_date = format(ANALYSIS_START_DATE, "%Y-%m-%d"),
                                    end_date   = Sys.Date(),
                                    force      = FALSE) {
  .load_base_data()
  .preload_modules()   # source once here; build_factor_db() will skip re-load

  start_d <- as.Date(start_date)
  end_d   <- as.Date(end_date)

  # Use pre-indexed trading dates
  all_dates <- .fdb_env$trading_dates
  all_dates <- all_dates[all_dates >= start_d & all_dates <= end_d]

  # Extract month-end dates: last trading day of each month
  dt_dates <- data.table(Date = all_dates)
  dt_dates[, YM := format(Date, "%Y%m")]
  month_ends <- dt_dates[, .(sig_date = max(Date)), by = YM][order(YM)]$sig_date

  cat(sprintf("[build_factor_db_monthly] %d month-ends from %s to %s\n",
              length(month_ends), start_d, end_d))

  t0 <- Sys.time()
  n_total <- length(month_ends)

  for (i in seq_along(month_ends)) {
    elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta_s     <- if (i > 1) elapsed_s / (i - 1) * (n_total - i + 1) else NA_real_
    eta_str   <- if (is.finite(eta_s)) sprintf(", ETA %.0f min", eta_s / 60) else ""
    cat(sprintf("\n--- [%d/%d] %s (%.0fs elapsed%s) ---\n",
                i, n_total, month_ends[i], elapsed_s, eta_str))
    tryCatch(
      build_factor_db(month_ends[i], save = TRUE, force = force),
      error = function(e) {
        cat(sprintf("  [FATAL] %s: %s\n", month_ends[i], conditionMessage(e)))
      }
    )
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  cat(sprintf("\n[build_factor_db_monthly] Complete: %d months in %.1f minutes\n",
              length(month_ends), elapsed))

  # v54 Gate 13.1 — record build hash after batch completion
  .write_build_hash()

  invisible(month_ends)
}


#==============================================================================
# 2-B. build_factor_db_daily() — Daily Factor DB for ML
#
# 최적화 이력:
#   v1.1 (2026-04-04): parallel::mclapply 날짜 병렬화 + RAWDATA 월별 사전 슬라이싱
#   - workers = min(20, parallel::detectCores()-2) 기본값
#   - 각 worker는 COW fork 공유 메모리로 RAWDATA 중복 없음 (Unix-only)
#   - chunk_size: N 날짜를 workers×4 청크로 나눠 진행률 확인 가능
#   - Windows/WSL 환경: mclapply → lapply 자동 강등 (fork 미지원)
#==============================================================================

#' Build daily-frequency Factor DB. Saves to .cache/factor_db_daily/.
#' Each file: factor_db_daily_YYYYMMDD.parquet
#' Resumable: skips dates with existing files (force=FALSE).
#'
#' @param start_date Start date (default "2005-01-01" — pre-2005 data sparse)
#' @param end_date End date
#' @param force Rebuild existing dates
#' @param workers Integer. Parallel workers. Default: min(20, nCores-2).
#'   Set 1 to disable parallelism.
#' @param chunk_size Integer. Dates per progress-report chunk.
build_factor_db_daily <- function(start_date  = format(ANALYSIS_START_DATE, "%Y-%m-%d"),
                                  end_date    = Sys.Date(),
                                  force       = FALSE,
                                  workers     = NULL,
                                  chunk_size  = NULL) {
  daily_dir <- file.path(CACHE_DIR, "factor_db_daily")
  dir.create(daily_dir, showWarnings = FALSE, recursive = TRUE)

  .load_base_data()
  .preload_modules()

  start_d <- as.Date(start_date)
  end_d   <- as.Date(end_date)
  all_dates <- .fdb_env$trading_dates
  target_dates <- all_dates[all_dates >= start_d & all_dates <= end_d]

  # Skip existing
  if (!force) {
    existing <- gsub("factor_db_daily_(\\d{8})\\.parquet", "\\1",
                     list.files(daily_dir, "^factor_db_daily_\\d{8}\\.parquet$"))
    target_tags <- format(target_dates, "%Y%m%d")
    target_dates <- target_dates[!target_tags %in% existing]
  }

  n_target <- length(target_dates)
  cat(sprintf("[build_factor_db_daily] %d dates to build (%s ~ %s)\n",
              n_target,
              if (n_target > 0) as.character(min(target_dates)) else "none",
              if (n_target > 0) as.character(max(target_dates)) else "none"))

  if (n_target == 0) return(invisible(NULL))

  # ── Worker 수 결정 ───────────────────────────────────────────────────────────
  n_cores <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) 1L)
  if (is.null(workers)) workers <- max(1L, min(20L, n_cores - 2L))

  # fork 가용성 실제 테스트 (WSL2는 OS.type==unix이고 fork 작동)
  use_parallel <- FALSE
  if (workers > 1L && .Platform$OS.type == "unix") {
    fork_ok <- tryCatch({
      r <- parallel::mclapply(1:2, function(x) x^2, mc.cores = 2L)
      !inherits(r[[1]], "try-error")
    }, error = function(e) FALSE)
    use_parallel <- fork_ok
    if (!fork_ok) {
      cat("[build_factor_db_daily] fork 테스트 실패 → workers=1 강등\n")
      workers <- 1L
    }
  } else if (workers > 1L) {
    cat("[build_factor_db_daily] Windows 환경 → workers=1 강등\n")
    workers <- 1L
  }
  cat(sprintf("[build_factor_db_daily] workers=%d | parallel=%s\n",
              workers, use_parallel))

  # ── 청크 사이즈 ─────────────────────────────────────────────────────────────
  if (is.null(chunk_size)) {
    chunk_size <- max(workers * 4L, 50L)
  }

  # ── 월별 사전 슬라이싱 (fork COW 깨짐 방지) ────────────────────────────────
  # 핵심: worker가 .fdb_env$RAWDATA (14M rows)에 직접 접근하면 data.table [
  # 연산이 COW를 깨뜨려 worker당 ~2GB 복사 → OOM.
  # 해결: 부모에서 월별로 RAWDATA를 사전 슬라이싱 → 작은 조각만 worker에 전달.

  cat("[build_factor_db_daily] Pre-slicing RAWDATA by month...\n")
  t_slice <- Sys.time()

  # 날짜를 월별로 그룹화
  dt_target <- data.table(sig_d = target_dates, ym = format(target_dates, "%Y%m"))
  month_groups <- dt_target[, .(dates = list(sig_d)), by = ym][order(ym)]

  # 각 월 그룹에 필요한 RAWDATA 범위 = min(sig_d) - 1400 ~ max(sig_d)
  raw <- .fdb_env$RAWDATA
  fund <- .fdb_env$FUND
  cons <- .fdb_env$CONSENSUS
  module_funcs <- .fdb_env$module_funcs
  trd_dates <- .fdb_env$trading_dates

  cat(sprintf("  %d month-groups, slicing took %.1fs\n",
              nrow(month_groups),
              as.numeric(difftime(Sys.time(), t_slice, units = "secs"))))

  # ── 날짜 1건 처리 (사전 슬라이싱된 데이터 사용) ─────────────────────────────
  .build_one_daily_v2 <- function(sig_d, rd_slice, fund_pit) {
    tag      <- format(sig_d, "%Y%m%d")
    out_path <- file.path(daily_dir, paste0("factor_db_daily_", tag, ".parquet"))
    if (!force && file.exists(out_path)) return(invisible(NULL))

    tryCatch({
      # snapshot: 최근 거래일 <= sig_d
      idx <- findInterval(sig_d, trd_dates)
      if (idx == 0L) return(invisible(NULL))
      actual_d <- trd_dates[idx]
      snap <- rd_slice[Date == actual_d]
      if (nrow(snap) == 0L) return(invisible(NULL))
      sector_map <- snap[, .(Ticker, Sector)]

      daily_modules <- c("value", "momentum", "quality", "defense", "size",
                         "consensus", "liquidity", "growth", "accrual",
                         "investor", "crowding", "risk")

      all_factors <- list()
      for (nm in daily_modules) {
        fn <- module_funcs[[nm]]
        if (is.null(fn)) next
        res <- tryCatch(
          fn(RAWDATA = rd_slice, sig_date = sig_d,
             FUND = fund_pit, CONSENSUS = cons),
          error = function(e) NULL
        )
        if (!is.null(res) && nrow(res) > 0L)
          all_factors[[length(all_factors) + 1L]] <- res
      }

      if (length(all_factors) == 0L) return(invisible(NULL))
      combined <- rbindlist(all_factors, use.names = TRUE, fill = TRUE)
      if (nrow(combined) == 0L) return(invisible(NULL))

      combined <- .standardize_factors(combined, sector_map)
      combined[, Signal_Date := sig_d]
      arrow::write_parquet(combined, out_path)
    }, error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", sig_d, conditionMessage(e)))
    })
    invisible(NULL)
  }

  # ── 월 단위 실행 (월 내 날짜는 병렬) ───────────────────────────────────────
  t0 <- Sys.time()
  done_total <- 0L

  for (mi in seq_len(nrow(month_groups))) {
    ym     <- month_groups$ym[mi]
    m_dates <- month_groups$dates[[mi]]

    # 부모에서 이 월 그룹에 필요한 RAWDATA 슬라이스 생성
    slice_start <- min(m_dates) - 1400L
    slice_end   <- max(m_dates)
    rd_slice <- raw[Date >= slice_start & Date <= slice_end]
    setkey(rd_slice, Date, Ticker)

    # FUND PIT 슬라이스
    fund_pit <- if (!is.null(fund) && nrow(fund) > 0L)
                  fund[Factor_Date <= slice_end]
                else NULL

    # 진행률
    elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
    eta_str <- if (done_total > 0) {
      eta <- elapsed / done_total * (n_target - done_total)
      sprintf(", ETA %.0f min", eta)
    } else ""
    cat(sprintf("\n[Month %d/%d] %s: %d dates (%.1f min%s) | slice: %s rows\n",
                mi, nrow(month_groups), ym, length(m_dates),
                elapsed, eta_str,
                format(nrow(rd_slice), big.mark = ",")))

    if (use_parallel && length(m_dates) > 1L) {
      parallel::mclapply(m_dates, .build_one_daily_v2,
                         rd_slice = rd_slice,
                         fund_pit = fund_pit,
                         mc.cores     = workers,
                         mc.preschedule = TRUE,
                         mc.silent    = FALSE)
    } else {
      lapply(m_dates, .build_one_daily_v2,
             rd_slice = rd_slice,
             fund_pit = fund_pit)
    }

    done_total <- done_total + length(m_dates)

    # 메모리 정리 (슬라이스 해제)
    rm(rd_slice, fund_pit)
    if (mi %% 12 == 0) gc(verbose = FALSE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  n_built <- length(list.files(daily_dir, "^factor_db_daily_\\d{8}\\.parquet$"))
  per_date <- if (n_target > 0) round(elapsed * 60 / n_target, 1) else NA_real_
  cat(sprintf("\n[build_factor_db_daily] Done: %d dates in %.1f min (~%.1fs/date, total cached: %d)\n",
              n_target, elapsed, per_date, n_built))
}

#==============================================================================
# 3. load_factor_db(sig_date, factors) — Load from cache
#==============================================================================

#' Load factor DB from cache. Returns wide-format data.table.
#'
#' @param sig_date Character or Date. Signal date (finds matching YYYYMM)
#' @param factors Character vector of factor names to load. NULL = all.
#' @param format Character. "wide" (default) or "long".
#' @return data.table. Wide: Date, Ticker, V01_BM, M01_Mom12_1, ...
#'         (values are Z_Score by default). Long: full schema.
#' @export
load_factor_db <- function(sig_date, factors = NULL, format = "wide",
                           value_col = "Z_Score") {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  if (!file.exists(fpath)) {
    # Try to find closest available month
    avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
    if (length(avail) == 0) {
      stop("[load_factor_db] No cached factor DB found. Run build_factor_db() first.")
    }
    avail_ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
    cat(sprintf("[load_factor_db] %s not found. Available: %s\n",
                ym_tag, paste(tail(avail_ym, 10), collapse = ", ")))
    stop("[load_factor_db] Requested month not in cache.")
  }

  dt <- as.data.table(read_parquet(fpath))

  # Filter factors if specified
  if (!is.null(factors)) {
    dt <- dt[Factor_Name %in% factors]
    missing <- setdiff(factors, unique(dt$Factor_Name))
    if (length(missing) > 0) {
      warning("[load_factor_db] Requested factors not found: ",
              paste(missing, collapse = ", "))
    }
  }

  if (format == "long") return(dt)

  # Wide format: Date, Ticker, Factor1, Factor2, ...
  stopifnot(value_col %in% names(dt))
  wide <- dcast(dt, Date + Ticker ~ Factor_Name, value.var = value_col)
  wide
}


#==============================================================================
# 4. update_factor_db_daily() — Cron hook: compute current month if missing
#==============================================================================

#' Daily update hook for cron. Builds current month's factor DB if not cached.
#' @export
update_factor_db_daily <- function() {
  today <- Sys.Date()
  ym_tag <- format(today, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  # If today is month-end or cache doesn't exist, rebuild
  next_day <- today + 1L
  is_month_end <- (format(today, "%m") != format(next_day, "%m"))

  if (!file.exists(fpath) || is_month_end) {
    cat(sprintf("[update_factor_db_daily] Building/updating %s...\n", ym_tag))
    build_factor_db(today, save = TRUE, force = is_month_end)
  } else {
    cat(sprintf("[update_factor_db_daily] %s already cached. Skipping.\n", ym_tag))
  }
}


#==============================================================================
# 5. get_factor_ic(factor_name, n_months) — IC/ICIR history
#==============================================================================

#' Compute Information Coefficient (IC) history for a factor.
#'
#' IC = Spearman rank correlation between Factor[t] and Return[t+1].
#' ICIR = mean(IC) / sd(IC).
#'
#' @param factor_name Character. Factor ID (e.g., "V01_BM")
#' @param n_months Integer. Number of months to look back (default: 60)
#' @return List with ic_series (data.table: Date, IC), icir (numeric),
#'         mean_ic (numeric), hit_rate (fraction of positive IC months)
#' @export
get_factor_ic <- function(factor_name, n_months = 60L) {
  # Find available factor DB files
  avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$",
                      full.names = TRUE)
  if (length(avail) == 0) stop("[get_factor_ic] No factor DB files found.")

  avail <- sort(avail)
  # Use last n_months+1 files (need t and t+1 for IC)
  if (length(avail) > n_months + 1) {
    avail <- tail(avail, n_months + 1)
  }

  # Load base data for forward returns
  .load_base_data()
  raw <- .fdb_env$RAWDATA

  # Build IC series
  ic_list <- list()

  for (i in seq_along(avail)[-length(avail)]) {
    tryCatch({
      dt_t  <- as.data.table(read_parquet(avail[i]))
      dt_t1 <- as.data.table(read_parquet(avail[i + 1]))

      # Factor values at t
      fv <- dt_t[Factor_Name == factor_name & Coverage == TRUE,
                 .(Ticker, Raw_Value)]
      if (nrow(fv) < 20) next

      sig_d_t  <- dt_t$Date[1]
      sig_d_t1 <- dt_t1$Date[1]

      # Forward 1-month return: from sig_d_t to sig_d_t1
      # Use RAWDATA cumulative return
      ret_data <- raw[Date > sig_d_t & Date <= sig_d_t1,
                      .(Fwd_Ret = prod(1 + Ret, na.rm = TRUE) - 1),
                      by = Ticker]

      merged <- merge(fv, ret_data, by = "Ticker")
      merged <- merged[is.finite(Raw_Value) & is.finite(Fwd_Ret)]

      if (nrow(merged) < 20) next

      ic <- cor(merged$Raw_Value, merged$Fwd_Ret,
                method = "spearman", use = "complete.obs")

      ic_list[[length(ic_list) + 1]] <- data.table(
        Date = sig_d_t,
        Factor_Name = factor_name,
        IC = ic,
        N_Stocks = nrow(merged)
      )
    }, error = function(e) NULL)
  }

  if (length(ic_list) == 0) {
    cat("[get_factor_ic] No IC data computed for", factor_name, "\n")
    return(list(ic_series = data.table(), icir = NA_real_,
                mean_ic = NA_real_, hit_rate = NA_real_))
  }

  ic_dt <- rbindlist(ic_list)
  mean_ic  <- mean(ic_dt$IC, na.rm = TRUE)
  sd_ic    <- sd(ic_dt$IC, na.rm = TRUE)
  icir     <- if (sd_ic > 1e-8) mean_ic / sd_ic else NA_real_
  hit_rate <- mean(ic_dt$IC > 0, na.rm = TRUE)

  cat(sprintf("[get_factor_ic] %s: IC=%.4f, ICIR=%.3f, Hit=%.1f%% (%d months)\n",
              factor_name, mean_ic, icir, hit_rate * 100, nrow(ic_dt)))

  list(
    ic_series = ic_dt,
    icir      = icir,
    mean_ic   = mean_ic,
    hit_rate  = hit_rate
  )
}


#==============================================================================
# 6. Utility: list_available_months() / factor_db_status()
#==============================================================================

#' List all months with cached factor DB
#' @export
list_factor_db_months <- function() {
  avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
  if (length(avail) == 0) {
    cat("[factor_db] No cached months.\n")
    return(character(0))
  }
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
  ym <- sort(ym)
  cat(sprintf("[factor_db] %d months cached: %s ~ %s\n",
              length(ym), ym[1], tail(ym, 1)))
  ym
}

#' Print factor DB status summary
#' @export
factor_db_status <- function() {
  cat("=== Factor DB Status ===\n")
  months <- list_factor_db_months()
  if (length(months) == 0) return(invisible(NULL))

  # Load most recent
  latest_path <- file.path(FACTOR_DB_DIR,
                           paste0("factor_db_", tail(months, 1), ".parquet"))
  dt <- as.data.table(read_parquet(latest_path))

  cat(sprintf("Latest month: %s\n", tail(months, 1)))
  cat(sprintf("Factors: %d | Tickers: %d | Rows: %s\n",
              uniqueN(dt$Factor_Name), uniqueN(dt$Ticker),
              format(nrow(dt), big.mark = ",")))

  # Coverage summary
  cov <- dt[, .(
    Coverage_Pct = round(100 * mean(Coverage, na.rm = TRUE), 1)
  ), by = Factor_Name][order(Factor_Name)]
  print(cov)

  # Registry check
  if (file.exists(FACTOR_REG_PATH)) {
    reg <- fromJSON(FACTOR_REG_PATH)
    cat(sprintf("\nRegistry: %d factors defined\n", length(reg)))
    registered <- names(reg)
    computed   <- unique(dt$Factor_Name)
    missing    <- setdiff(registered, computed)
    extra      <- setdiff(computed, registered)
    if (length(missing) > 0) cat("  Missing from DB:", paste(missing, collapse = ", "), "\n")
    if (length(extra) > 0)   cat("  Extra (not in registry):", paste(extra, collapse = ", "), "\n")
  }

  invisible(dt)
}


#==============================================================================
# 7. Batch IC computation for all factors
#==============================================================================

#' Compute IC/ICIR for all factors in the most recent DB snapshot
#' @param n_months Integer. Lookback months for IC (default: 60)
#' @return data.table: Factor_Name, Mean_IC, ICIR, Hit_Rate, N_Months
#' @export
get_all_factor_ic <- function(n_months = 60L) {
  # Get factor names from most recent snapshot
  months <- list_factor_db_months()
  if (length(months) == 0) stop("No factor DB cached.")

  latest_path <- file.path(FACTOR_DB_DIR,
                           paste0("factor_db_", tail(months, 1), ".parquet"))
  dt <- as.data.table(read_parquet(latest_path))
  factor_names <- sort(unique(dt$Factor_Name))

  cat(sprintf("[get_all_factor_ic] Computing IC for %d factors...\n",
              length(factor_names)))

  results <- list()
  for (fn in factor_names) {
    res <- tryCatch(get_factor_ic(fn, n_months), error = function(e) NULL)
    if (!is.null(res) && !is.na(res$icir)) {
      results[[length(results) + 1]] <- data.table(
        Factor_Name = fn,
        Mean_IC     = round(res$mean_ic, 4),
        ICIR        = round(res$icir, 3),
        Hit_Rate    = round(res$hit_rate, 3),
        N_Months    = nrow(res$ic_series)
      )
    }
  }

  if (length(results) == 0) return(data.table())

  ic_all <- rbindlist(results)[order(-abs(ICIR))]

  # Save to parquet
  write_parquet(ic_all, FACTOR_IC_PATH)
  cat(sprintf("[get_all_factor_ic] Saved IC history: %s\n", FACTOR_IC_PATH))

  ic_all
}


#==============================================================================
# 7. compute_all_factor_ic_monthly() — Batch IC for allocation engine
#==============================================================================

#' Compute monthly IC for ALL factors across ALL months.
#' IC[t] = Spearman corr(Z_Score[t], Ret[t -> t+1]).
#' Saves to .cache/factor_db/factor_ic_monthly.parquet
#'
#' @return data.table: Date, Factor_Name, IC, N_Stocks
#' @export
compute_all_factor_ic_monthly <- function() {
  .load_base_data()
  raw <- .fdb_env$RAWDATA

  avail <- sort(list.files(FACTOR_DB_DIR,
                           pattern = "^factor_db_\\d{6}\\.parquet$",
                           full.names = TRUE))
  if (length(avail) < 2) stop("[IC_monthly] Need at least 2 months of factor DB.")

  cat(sprintf("[IC_monthly] Computing IC for %d month-pairs...\n", length(avail) - 1))
  t0 <- Sys.time()

  ic_list <- vector("list", length(avail) - 1)

  for (i in seq_along(avail)[-length(avail)]) {
    tryCatch({
      dt_t  <- as.data.table(read_parquet(avail[i]))
      dt_t1 <- as.data.table(read_parquet(avail[i + 1]))

      sig_d_t  <- dt_t$Date[1]
      sig_d_t1 <- dt_t1$Date[1]

      # Forward 1-month return per ticker
      ret_data <- raw[Date > sig_d_t & Date <= sig_d_t1,
                      .(Fwd_Ret = prod(1 + Ret, na.rm = TRUE) - 1),
                      by = Ticker]

      # Get all factors at time t
      fv <- dt_t[Coverage == TRUE, .(Ticker, Factor_Name, Raw_Value)]
      merged <- merge(fv, ret_data, by = "Ticker")
      merged <- merged[is.finite(Raw_Value) & is.finite(Fwd_Ret)]

      if (nrow(merged) < 30) next

      # IC per factor
      ic_per_factor <- merged[, {
        n <- .N
        if (n < 20) list(IC = NA_real_, N_Stocks = n)
        else list(
          IC = cor(Raw_Value, Fwd_Ret, method = "spearman", use = "complete.obs"),
          N_Stocks = n
        )
      }, by = Factor_Name]

      ic_per_factor <- ic_per_factor[!is.na(IC)]
      ic_per_factor[, Date := sig_d_t]
      # Usable_Date: this IC can only be used AFTER the forward return period ends
      # IC[t] uses return[t→t+1], so it's only known at t+1
      ic_per_factor[, Usable_Date := sig_d_t1]

      ic_list[[i]] <- ic_per_factor

      if (i %% 25 == 0) {
        cat(sprintf("  [%d/%d] %s — %d factors\n",
                    i, length(avail) - 1, sig_d_t, nrow(ic_per_factor)))
      }
    }, error = function(e) {
      cat(sprintf("  [WARN] %d: %s\n", i, conditionMessage(e)))
    })
  }

  ic_all <- rbindlist(ic_list[!sapply(ic_list, is.null)])
  setorder(ic_all, Factor_Name, Date)

  out_path <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
  write_parquet(ic_all, out_path)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  cat(sprintf("[IC_monthly] Done: %s rows | %d factors | %d months | %.1f min\n",
              format(nrow(ic_all), big.mark = ","),
              uniqueN(ic_all$Factor_Name),
              uniqueN(ic_all$Date), elapsed))
  cat(sprintf("  Saved: %s\n", out_path))

  invisible(ic_all)
}


cat("[factor_db_builder] Ready. Functions: build_factor_db(), build_factor_db_monthly(),\n")
cat("  load_factor_db(), update_factor_db_daily(), get_factor_ic(),\n")
cat("  compute_all_factor_ic_monthly(), factor_db_status()\n")
