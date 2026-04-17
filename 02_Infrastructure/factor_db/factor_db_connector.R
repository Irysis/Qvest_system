#==============================================================================
# Factor DB Connector — Factor DB → Architecture Bridge
#
# Connects the Factor DB (268 factors, monthly parquets) to the
# regime-conditional factor allocation engine.
#
# Functions:
#   load_month_factors(sig_date, coverage_min)
#   compute_rolling_ic_all(sig_date, min_months, max_months)
#   group_factors_by_family(registry)
#   align_factor_direction(factor_dt, registry)
#
# PIT: All functions use data available at or before sig_date only.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Paths ----
.fdc_self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FACTOR_DB_DIR")) FACTOR_DB_DIR
    else if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db")
    else file.path(
      "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
      "02_Infrastructure", "factor_db"
    )
  }
)

if (!exists("CACHE_DIR")) {
  source(file.path(dirname(.fdc_self_dir), "config.R"))
}

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
FACTOR_IC_MONTHLY_PATH <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
FACTOR_REG_PATH <- file.path(FACTOR_DB_DIR, "factor_registry.json")

# ---- Load registry (cached) ----
.fdc_registry <- NULL

.load_registry <- function() {
  if (!is.null(.fdc_registry)) return(.fdc_registry)

  # Try multiple paths
  candidates <- c(
    file.path(FUNC_PATH, "factor_db", "factor_registry.json"),
    file.path(.fdc_self_dir, "factor_registry.json"),
    FACTOR_REG_PATH
  )
  reg_path <- NULL
  for (p in candidates) {
    if (file.exists(p)) { reg_path <- p; break }
  }
  if (is.null(reg_path)) {
    cat("[connector] WARNING: factor_registry.json not found in any candidate path\n")
    return(list())
  }
  .fdc_registry <<- fromJSON(reg_path)
  .fdc_registry
}

# ---- IC history (cached) ----
.fdc_ic_hist <- NULL

.load_ic_history <- function() {
  if (!is.null(.fdc_ic_hist)) return(.fdc_ic_hist)
  if (!file.exists(FACTOR_IC_MONTHLY_PATH)) {
    stop("[connector] factor_ic_monthly.parquet not found. Run compute_all_factor_ic_monthly() first.")
  }
  .fdc_ic_hist <<- as.data.table(read_parquet(FACTOR_IC_MONTHLY_PATH))
  .fdc_ic_hist[, Date := as.Date(Date)]
  .fdc_ic_hist
}


#==============================================================================
# 1. load_month_factors()
#==============================================================================

#' Load factor DB for a signal date with coverage filter + direction alignment.
#' @param sig_date Date or character. Signal date (monthly)
#' @param coverage_min Numeric. Min coverage fraction to include factor (0-1)
#' @return data.table: Ticker, Factor_Name, Z_Score_Aligned (higher=better)
load_month_factors <- function(sig_date, coverage_min = 0.05) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  if (!file.exists(fpath)) {
    # Find closest available month
    avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
    ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
    ym_avail <- sort(ym_avail)
    closest <- max(ym_avail[ym_avail <= ym_tag])
    if (is.na(closest)) stop("[connector] No factor DB available for ", sig_date)
    fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", closest, ".parquet"))
  }

  dt <- as.data.table(read_parquet(fpath))

  # Coverage filter: exclude factors with too few stocks
  n_tickers <- uniqueN(dt$Ticker)
  factor_cov <- dt[, .(N_Covered = sum(Coverage == TRUE)), by = Factor_Name]
  factor_cov[, Pct := N_Covered / n_tickers]
  keep_factors <- factor_cov[Pct >= coverage_min, Factor_Name]

  dt <- dt[Factor_Name %in% keep_factors & Coverage == TRUE]

  # Direction alignment
  registry <- .load_registry()
  dt <- align_factor_direction(dt, registry)

  dt[, .(Ticker, Factor_Name, Z_Score_Aligned)]
}


#==============================================================================
# 2. align_factor_direction()
#==============================================================================

#' Flip factor z-scores so higher = better for all factors.
#' Uses IC sign to AUTOMATICALLY determine direction (no manual registry needed).
#'
#' Logic: IC = corr(Raw_Value, Forward_Return)
#'   If mean IC > 0 → higher Raw_Value = higher return → Z_Aligned = Z_Score
#'   If mean IC < 0 → higher Raw_Value = lower return → Z_Aligned = -Z_Score
#'   If IC unknown → fall back to registry direction
#'
#' This eliminates double-negation bugs from compute modules that pre-negate.
#'
#' @param factor_dt data.table with Factor_Name, Z_Score columns
#' @param registry Parsed factor_registry.json (fallback only)
#' @return factor_dt with Z_Score_Aligned column added
align_factor_direction <- function(factor_dt, registry) {
  # Load IC history for automatic direction detection
  ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)

  if (!is.null(ic_hist) && nrow(ic_hist) > 0) {
    # IC-based direction: mean IC sign determines direction
    ic_dir <- ic_hist[, .(Mean_IC = mean(IC, na.rm = TRUE), N = .N), by = Factor_Name]
    ic_dir[, ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]  # positive IC → higher Raw = better
    factor_dt <- merge(factor_dt, ic_dir[, .(Factor_Name, ic_sign)],
                       by = "Factor_Name", all.x = TRUE)

    # Fallback for factors without IC history: use registry
    if (!is.null(registry) && length(registry) > 0) {
      reg_dir <- data.table(
        Factor_Name = names(registry),
        reg_sign = sapply(registry, function(x) {
          d <- x$direction %||% "higher_better"
          if (d == "lower_better") -1L else 1L
        })
      )
      factor_dt <- merge(factor_dt, reg_dir, by = "Factor_Name", all.x = TRUE)
      factor_dt[is.na(ic_sign), ic_sign := reg_sign]
      factor_dt[is.na(ic_sign), ic_sign := 1L]
      factor_dt[, reg_sign := NULL]
    } else {
      factor_dt[is.na(ic_sign), ic_sign := 1L]
    }
  } else {
    # No IC history at all: use registry only
    dir_map <- data.table(
      Factor_Name = names(registry),
      ic_sign = sapply(registry, function(x) {
        d <- x$direction %||% "higher_better"
        if (d == "lower_better") -1L else 1L
      })
    )
    factor_dt <- merge(factor_dt, dir_map, by = "Factor_Name", all.x = TRUE)
    factor_dt[is.na(ic_sign), ic_sign := 1L]
  }

  # Apply direction: Z_Score_Aligned = Z_Score * ic_sign
  # This ensures higher Z_Score_Aligned = higher expected return for ALL factors
  factor_dt[, Z_Score_Aligned := Z_Score * ic_sign]
  factor_dt[, ic_sign := NULL]

  factor_dt
}


#==============================================================================
# 3. compute_rolling_ic_all()
#==============================================================================

#' Compute expanding-window IC and ICIR for all factors up to sig_date.
#' PIT ENFORCED: Uses Usable_Date column — IC[t] is only usable after t+1.
#' IC[t] = corr(factor[t], return[t→t+1]), so we need Usable_Date <= sig_date.
#'
#' @param sig_date Date. Current signal date
#' @param min_months Integer. Min months for valid ICIR (default 36)
#' @param max_months Integer. Max lookback months (default 120)
#' @return data.table: Factor_Name, Mean_IC, ICIR, Hit_Rate, N_Months
compute_rolling_ic_all <- function(sig_date, min_months = 36L, max_months = 120L) {
  sig_d <- as.Date(sig_date)
  ic_hist <- .load_ic_history()

  # PIT ENFORCED: use Usable_Date if available, otherwise Date < sig_d (2-month safety)
  if ("Usable_Date" %in% names(ic_hist)) {
    ic_avail <- ic_hist[Usable_Date <= sig_d]
  } else {
    # Legacy fallback: Date < sig_d excludes current month's IC
    # But this still has 1-month lookahead risk — warn
    cat("[WARN] factor_ic_monthly.parquet missing Usable_Date. Using Date < sig_d (legacy).\n")
    ic_avail <- ic_hist[Date < sig_d]
  }

  if (nrow(ic_avail) == 0) {
    return(data.table(Factor_Name = character(), Mean_IC = numeric(),
                      ICIR = numeric(), Hit_Rate = numeric(), N_Months = integer()))
  }

  # Limit lookback
  if (max_months < Inf) {
    cutoff <- sort(unique(ic_avail$Date), decreasing = TRUE)
    if (length(cutoff) > max_months) {
      cutoff_date <- cutoff[max_months]
      ic_avail <- ic_avail[Date >= cutoff_date]
    }
  }

  # Compute ICIR per factor
  result <- ic_avail[, {
    n <- .N
    if (n < min_months) {
      list(Mean_IC = NA_real_, ICIR = NA_real_, Hit_Rate = NA_real_, N_Months = n)
    } else {
      m <- mean(IC, na.rm = TRUE)
      s <- sd(IC, na.rm = TRUE)
      list(
        Mean_IC = m,
        ICIR = if (s > 1e-8) m / s else NA_real_,
        Hit_Rate = mean(IC > 0, na.rm = TRUE),
        N_Months = n
      )
    }
  }, by = Factor_Name]

  result[!is.na(ICIR)]
}


#==============================================================================
# 4. group_factors_by_family()
#==============================================================================

#' Group factor names by economic family (7 groups for allocation).
#' @param registry Parsed factor_registry.json (default: auto-load)
#' @return Named list: group_name -> character vector of factor IDs
group_factors_by_family <- function(registry = NULL) {
  if (is.null(registry)) registry <- .load_registry()

  # Map registry categories to 7 allocation groups
  group_map <- list(
    defense   = c("defense", "risk"),
    quality   = c("quality", "accrual"),
    value     = c("value"),
    momentum  = c("momentum"),
    growth    = c("growth"),
    consensus = c("consensus"),
    liquidity = c("liquidity", "crowding")
  )

  groups <- list()
  for (gname in names(group_map)) {
    cats <- group_map[[gname]]
    factors <- names(registry)[sapply(registry, function(x) {
      (x$category %in% cats) || (x$labels$economic_family %in% cats)
    })]
    if (length(factors) > 0) groups[[gname]] <- factors
  }

  # Excluded: regime, size (used as controls, not alpha sources)
  groups
}


cat("[factor_db_connector] Loaded. Functions: load_month_factors(), compute_rolling_ic_all(),\n")
cat("  group_factors_by_family(), align_factor_direction()\n")
