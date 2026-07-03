#==============================================================================
# Factor DB Connector — Factor DB → Architecture Bridge
#
# Connects the Factor DB (monthly long parquets, .cache/factor_db/) to the
# regime-conditional factor allocation engine.
# Factor counts vary by month — 고정 "N factors" 표기 금지 (2026-06-10 실측:
#   registry 373 등록 / 월간 parquet distinct 342 (최신월 202605 = 315) /
#   IC history 327 / 일간 DB 304).
# Registry 제안(미백필, open item): entry별 "storage" 필드(monthly/daily/both)
#   — 신규 등재 2건(AC14_Discretionary_Accruals, XF_Q06_Op_Margin)에만 시범 도입.
#
# Functions:
#   load_month_factors(sig_date, coverage_min, factor_names)
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
  library(dplyr)
  library(jsonlite)
})

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                              (length(a) == 1L && is.na(a))) b else a
}

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
.fdc_ic_dir_cache <- new.env(parent = emptyenv())

.load_ic_history <- function() {
  if (!is.null(.fdc_ic_hist)) return(.fdc_ic_hist)
  if (!file.exists(FACTOR_IC_MONTHLY_PATH)) {
    stop("[connector] factor_ic_monthly.parquet not found. Run compute_all_factor_ic_monthly() first.")
  }
  # v2.1: col_select — N_Stocks 미사용. any_of()로 Usable_Date 부재 legacy 파일 호환 유지.
  .fdc_ic_hist <<- as.data.table(read_parquet(
    FACTOR_IC_MONTHLY_PATH,
    col_select = tidyselect::any_of(c("Factor_Name", "IC", "Date", "Usable_Date"))
  ))
  .fdc_ic_hist[, Date := as.Date(Date)]
  # v2.0 (L-168): ensure Usable_Date is also Date type for consistent filtering
  if ("Usable_Date" %in% names(.fdc_ic_hist)) {
    .fdc_ic_hist[, Usable_Date := as.Date(Usable_Date)]
  }
  .fdc_ic_hist
}

.ic_direction_cache_path <- function(sig_d, min_ic_months) {
  info <- tryCatch(file.info(FACTOR_IC_MONTHLY_PATH), error = function(e) NULL)
  stamp <- "noic"
  size_tag <- "0"
  if (!is.null(info) && nrow(info) > 0 && !is.na(info$mtime[1])) {
    stamp <- format(as.POSIXct(info$mtime[1]), "%Y%m%d%H%M%S")
    size_tag <- as.character(info$size[1] %||% 0)
  }
  cache_dir <- file.path(FACTOR_DB_DIR, "ic_direction_cache_v1")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  file.path(
    cache_dir,
    sprintf("ic_dir_%s_m%d_%s_%s.rds",
            format(as.Date(sig_d), "%Y%m%d"), as.integer(min_ic_months),
            stamp, size_tag)
  )
}

.load_ic_direction_cached <- function(sig_d, min_ic_months = 36L) {
  sig_d <- as.Date(sig_d)
  cache_key <- sprintf("%s_m%d", format(sig_d, "%Y%m%d"), as.integer(min_ic_months))
  if (exists(cache_key, envir = .fdc_ic_dir_cache, inherits = FALSE)) {
    return(get(cache_key, envir = .fdc_ic_dir_cache, inherits = FALSE))
  }

  cache_path <- .ic_direction_cache_path(sig_d, min_ic_months)
  if (file.exists(cache_path)) {
    cached <- tryCatch(readRDS(cache_path), error = function(e) NULL)
    if (is.data.table(cached) && all(c("Factor_Name", "ic_sign") %in% names(cached))) {
      assign(cache_key, cached, envir = .fdc_ic_dir_cache)
      return(cached)
    }
  }

  ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)
  if (is.null(ic_hist) || nrow(ic_hist) == 0) return(NULL)

  if ("Usable_Date" %in% names(ic_hist)) {
    ic_avail <- ic_hist[Usable_Date <= sig_d]
  } else {
    cat("[WARN] align_factor_direction: factor_ic_monthly.parquet missing Usable_Date. Using Date < sig_d (legacy).\n")
    ic_avail <- ic_hist[Date < sig_d]
  }
  if (nrow(ic_avail) == 0) return(NULL)

  ic_dir <- ic_avail[, {
    n <- .N
    if (n >= min_ic_months) {
      m <- mean(IC, na.rm = TRUE)
      list(Mean_IC = m, ic_sign = fifelse(m >= 0, 1L, -1L), N_IC = n)
    } else {
      list(Mean_IC = NA_real_, ic_sign = NA_integer_, N_IC = n)
    }
  }, by = Factor_Name]

  tmp <- sprintf("%s.%s.tmp", cache_path, Sys.getpid())
  tryCatch({
    saveRDS(ic_dir, tmp)
    if (!file.rename(tmp, cache_path) && !file.exists(cache_path)) {
      file.copy(tmp, cache_path, overwrite = FALSE)
    }
    if (file.exists(tmp)) unlink(tmp)
  }, error = function(e) {
    if (file.exists(tmp)) unlink(tmp)
    NULL
  })

  assign(cache_key, ic_dir, envir = .fdc_ic_dir_cache)
  ic_dir
}


#==============================================================================
# 1. load_month_factors()
#==============================================================================

#' Load factor DB for a signal date with coverage filter + direction alignment.
#' @param sig_date Date or character. Signal date (monthly)
#' @param coverage_min Numeric. Min coverage fraction to include factor (0-1)
#' @param factor_names Optional character vector. If supplied, only these factor
#'   names are direction-aligned and returned. This preserves C15 because the
#'   caller still uses the PIT-safe connector rather than reading parquet
#'   directly.
#' @return data.table: Ticker, Factor_Name, Z_Score_Aligned (higher=better)
load_month_factors <- function(sig_date, coverage_min = 0.05, factor_names = NULL) {
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

  if (!is.null(factor_names)) {
    factor_names <- unique(as.character(factor_names))
    factor_names <- factor_names[nzchar(factor_names)]
  }

  # v2.2: when caller requests specific factors, push the Factor_Name filter
  # through Arrow before collect(). This keeps the PIT-safe connector boundary
  # while avoiding full monthly factor DB materialization for combo runners.
  dt <- if (!is.null(factor_names) && length(factor_names)) {
    as.data.table(
      open_dataset(fpath, format = "parquet") %>%
        select(Ticker, Factor_Name, Z_Score, Coverage) %>%
        filter(Factor_Name %in% factor_names) %>%
        collect()
    )
  } else {
    # v2.1: col_select — only columns needed downstream (Coverage filter + direction
    # alignment). Date/Raw_Value/Z_Sector/Rank_Pct unused here → IO/메모리 절감.
    as.data.table(read_parquet(
      fpath,
      col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")
    ))
  }

  # Coverage filter: exclude factors with too few stocks.
  # v2.1: N_Covered = Coverage & !is.na(Z_Score) — 시장레벨 dead 팩터(RE*/MA05-07/
  # M31_Breadth_Mom/CR03 등)는 Z 전부 NA인데 Coverage=TRUE 전행이라 구 sum(Coverage)
  # 집계가 필터를 무력화했음. 빌더 Coverage 재정의와 이중 방어 (구 parquet에도 즉효).
  n_tickers <- uniqueN(dt$Ticker)
  factor_cov <- dt[, .(N_Covered = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name]
  factor_cov[, Pct := N_Covered / n_tickers]
  keep_factors <- factor_cov[Pct >= coverage_min, Factor_Name]

  dt <- dt[Factor_Name %in% keep_factors & Coverage == TRUE & !is.na(Z_Score)]

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
    ic_dir <- .load_ic_direction_cached(sig_d, min_ic_months)
    if (!is.null(ic_dir) && nrow(ic_dir) > 0) {
      # v2.1: 구 로그(IC-history 전체 기준 카운트) 제거 — 로드된 팩터 기준
      # 집계로 대체 (merge 이후 하단). IC-history에 아예 없는 팩터(구 73건)가
      # 로그에 비가시화되던 문제 해소.
      cat(sprintf("[align_factor_direction] PIT-safe: sig_date=%s | min_months=%d\n",
                  sig_d, min_ic_months))
    }
  } else {
    # No sig_date: registry-only mode (backward compatible, PIT-safe by construction)
    cat("[align_factor_direction] No sig_date provided — registry-only direction (PIT-safe default).\n")
  }

  # ---- Merge direction into factor_dt (v2.1: per-factor source tracking) ----
  if (!is.null(ic_dir) && nrow(ic_dir[!is.na(ic_sign)]) > 0) {
    # Primary: IC-based direction (PIT-filtered)
    factor_dt <- merge(factor_dt, ic_dir[, .(Factor_Name, ic_sign)],
                       by = "Factor_Name", all.x = TRUE)
    factor_dt[, dir_source := fifelse(is.na(ic_sign), NA_character_, "ic")]

    # Secondary fallback: registry direction for factors without sufficient IC
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir, by = "Factor_Name", all.x = TRUE)
      factor_dt[is.na(ic_sign) & !is.na(reg_sign), dir_source := "registry"]
      factor_dt[is.na(ic_sign), ic_sign := reg_sign]
      factor_dt[, reg_sign := NULL]
    }

    # Tertiary fallback: default higher_better — WARN emitted below (v2.1)
    factor_dt[is.na(ic_sign), `:=`(ic_sign = 1L, dir_source = "default")]
  } else {
    # Registry-only path (no IC available or no sig_date)
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir[, .(Factor_Name, ic_sign = reg_sign)],
                         by = "Factor_Name", all.x = TRUE)
      factor_dt[, dir_source := fifelse(is.na(ic_sign), NA_character_, "registry")]
      factor_dt[is.na(ic_sign), `:=`(ic_sign = 1L, dir_source = "default")]
    } else {
      factor_dt[, `:=`(ic_sign = 1L, dir_source = "default")]
    }
  }

  # ---- v2.1 direction-source log: LOADED-factor 기준 (IC-history 전체 아님) ----
  .src_per_factor <- factor_dt[, .(src = dir_source[1L]), by = Factor_Name]
  n_dir_ic  <- .src_per_factor[src == "ic", .N]
  n_dir_reg <- .src_per_factor[src == "registry", .N]
  n_dir_def <- .src_per_factor[src == "default", .N]
  cat(sprintf("[align_factor_direction] loaded-factor direction: IC-inferred=%d / registry-fallback=%d / default-fallback=%d (n_factors=%d)\n",
              n_dir_ic, n_dir_reg, n_dir_def, n_dir_ic + n_dir_reg + n_dir_def))
  if (n_dir_def > 0) {
    .def_names <- sort(.src_per_factor[src == "default", Factor_Name])
    cat(sprintf("[align_factor_direction] WARN: %d factor(s) in neither IC history nor registry — defaulted ic_sign=1 (higher_better 가정): %s%s\n",
                n_dir_def,
                paste(head(.def_names, 10L), collapse = ", "),
                if (length(.def_names) > 10L) sprintf(" ... (+%d more)", length(.def_names) - 10L) else ""))
  }
  factor_dt[, dir_source := NULL]

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
