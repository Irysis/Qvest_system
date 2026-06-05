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
# v2.0 (L-168 fix): align_factor_direction() uses Usable_Date <= sig_date
#   for IC-based direction inference (expanding window, 36-month burn-in).
#   Backward compatible: sig_date=NULL triggers registry-only safe default.
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
      Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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
  # v2.0 (L-168): ensure Usable_Date is also Date type for consistent filtering
  if ("Usable_Date" %in% names(.fdc_ic_hist)) {
    .fdc_ic_hist[, Usable_Date := as.Date(Usable_Date)]
  }
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

  # Direction alignment (v2.0 PIT-safe: pass sig_date for expanding IC window)
  registry <- .load_registry()
  dt <- align_factor_direction(dt, registry, sig_date = sig_d)

  result <- dt[, .(Ticker, Factor_Name, Z_Score_Aligned)]

  # v54 Gate 13.1 — attach build hash for traceability
  build_hash_path <- file.path(FACTOR_DB_DIR, "build_hash.txt")
  build_hash <- if (file.exists(build_hash_path)) {
    tryCatch(readLines(build_hash_path, n = 1L), error = function(e) "unknown")
  } else {
    "unknown"
  }
  attr(result, "factor_db_build_hash") <- build_hash

  result
}


#==============================================================================
# 2. align_factor_direction()
#==============================================================================

#' Flip factor z-scores so higher = better for all factors.
#'
#' v2.0 PIT-SAFE (L-168 fix): When sig_date is provided, uses ONLY IC history
#' with Usable_Date <= sig_date (expanding window). This ensures no future IC
#' information leaks into direction inference. Matches compute_rolling_ic_all()
#' PIT treatment (line 220-230 of this file).
#'
#' Logic: IC = corr(Raw_Value, Forward_Return)
#'   If expanding mean IC > 0 → higher Raw_Value = higher return → Z_Aligned = Z_Score
#'   If expanding mean IC < 0 → higher Raw_Value = lower return → Z_Aligned = -Z_Score
#'   If IC unknown or insufficient → fall back to registry direction
#'
#' Backward compatibility: sig_date=NULL triggers registry-only mode (safe default).
#'
#' @param factor_dt data.table with Factor_Name, Z_Score columns
#' @param registry Parsed factor_registry.json (fallback / primary when no sig_date)
#' @param sig_date Date or character. Signal date for PIT-safe IC filtering (default: NULL)
#' @param min_ic_months Integer. Minimum IC observations for direction inference (default: 36)
#' @return factor_dt with Z_Score_Aligned column added
align_factor_direction <- function(factor_dt, registry, sig_date = NULL, min_ic_months = 36L) {

  # ---- Registry-based direction map (always computed as fallback) ----
  reg_dir <- NULL
  if (!is.null(registry) && length(registry) > 0) {
    reg_dir <- data.table(
      Factor_Name = names(registry),
      reg_sign = sapply(registry, function(x) {
        d <- x$direction %||% "higher_better"
        if (d == "lower_better") -1L else 1L
      })
    )
  }

  # ---- IC-based direction: PIT-safe expanding window ----
  ic_dir <- NULL

  if (!is.null(sig_date)) {
    sig_d <- as.Date(sig_date)
    ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)

    if (!is.null(ic_hist) && nrow(ic_hist) > 0) {
      # PIT ENFORCED: Usable_Date <= sig_date (identical to compute_rolling_ic_all line 222-224)
      if ("Usable_Date" %in% names(ic_hist)) {
        ic_avail <- ic_hist[Usable_Date <= sig_d]
      } else {
        # Legacy fallback: Date < sig_d (excludes current month, 1-month safety)
        cat("[WARN] align_factor_direction: factor_ic_monthly.parquet missing Usable_Date. Using Date < sig_d (legacy).\n")
        ic_avail <- ic_hist[Date < sig_d]
      }

      if (nrow(ic_avail) > 0) {
        # Expanding window mean IC per factor, with min_ic_months burn-in
        ic_dir <- ic_avail[, {
          n <- .N
          if (n >= min_ic_months) {
            m <- mean(IC, na.rm = TRUE)
            list(Mean_IC = m, ic_sign = fifelse(m >= 0, 1L, -1L), N_IC = n)
          } else {
            # Insufficient IC history: mark for registry fallback
            list(Mean_IC = NA_real_, ic_sign = NA_integer_, N_IC = n)
          }
        }, by = Factor_Name]

        # Log direction inference summary
        n_ic_inferred <- sum(!is.na(ic_dir$ic_sign))
        n_ic_fallback <- sum(is.na(ic_dir$ic_sign))
        cat(sprintf("[align_factor_direction] PIT-safe: sig_date=%s | IC-inferred=%d | fallback=%d | min_months=%d\n",
                    sig_d, n_ic_inferred, n_ic_fallback, min_ic_months))
      }
    }
  } else {
    # No sig_date: registry-only mode (backward compatible, PIT-safe by construction)
    cat("[align_factor_direction] No sig_date provided — registry-only direction (PIT-safe default).\n")
  }

  # ---- Merge direction into factor_dt ----
  if (!is.null(ic_dir) && nrow(ic_dir[!is.na(ic_sign)]) > 0) {
    # Primary: IC-based direction (PIT-filtered)
    factor_dt <- merge(factor_dt, ic_dir[, .(Factor_Name, ic_sign)],
                       by = "Factor_Name", all.x = TRUE)

    # Secondary fallback: registry direction for factors without sufficient IC
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir, by = "Factor_Name", all.x = TRUE)
      factor_dt[is.na(ic_sign), ic_sign := reg_sign]
      factor_dt[, reg_sign := NULL]
    }

    # Tertiary fallback: default higher_better
    factor_dt[is.na(ic_sign), ic_sign := 1L]
  } else {
    # Registry-only path (no IC available or no sig_date)
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir[, .(Factor_Name, ic_sign = reg_sign)],
                         by = "Factor_Name", all.x = TRUE)
      factor_dt[is.na(ic_sign), ic_sign := 1L]
    } else {
      factor_dt[, ic_sign := 1L]
    }
  }

  # Apply direction: Z_Score_Aligned = Z_Score * ic_sign
  # This ensures higher Z_Score_Aligned = higher expected return for ALL factors
  factor_dt[, Z_Score_Aligned := Z_Score * ic_sign]
  factor_dt[, ic_sign := NULL]

  # RC1 fix: re-standardize to sd=1 after direction flip (winsorize in builder may leave sd!=1)
  # Prevents M08 +1761% / R12=D01 +1316% / R16 +529% distortion (Scout 9/12 CRITICAL finding)
  factor_dt[!is.na(Z_Score_Aligned), Z_Score_Aligned := {
    s <- sd(Z_Score_Aligned, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score_Aligned / s else Z_Score_Aligned
  }, by = Factor_Name]

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
