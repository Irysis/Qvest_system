#==============================================================================
# A3_us_sector_flow_builder.R — US sector ETF flow → KR bearish predictor
#
# Plan v1.0 alt data based bearish forecast — Sprint 3
#
# 학술 anchor:
#   Asness-Moskowitz-Pedersen 2013 JoF — "Value-Momentum Everywhere"
#   Global factor structure: US sector ETF flow → KR equity transmission
#
# Features (8 sector × 21d return):
#   us_sector_avg_z       : 8 sector 21d return 평균 z (US 시장 risk-off direction)
#   us_sector_dispersion_z: 8 sector cross-sectional volatility z (시장 변동성 ↑ = bear)
#
# Source: quantmod::getSymbols (yahoo finance)
#   8 sectors: XLF / XLK / XLE / XLY / XLI / XLV / XLP / XLU
#
# Output: outputs/01_data/A3_us_sector_flow.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(quantmod)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
OUT_DIR <- file.path(WS_DIR, "outputs/01_data")
SECTOR_CACHE <- file.path(CACHE_DIR, "us_sector_etf")
dir.create(SECTOR_CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(WS_DIR, "scripts/00_pit_manifest_loader.R"))

rolling_zscore_expanding <- function(x, min_obs = 252) {
  n <- length(x); z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    vals <- x[1:i]; vals <- vals[!is.na(vals)]
    if (length(vals) < min_obs) next
    mu <- mean(vals); sg <- sd(vals)
    if (is.na(sg) || sg < 1e-10) next
    z[i] <- (x[i] - mu) / sg
  }
  z
}
lag1 <- function(x) c(NA, head(x, -1))

SECTORS <- c("XLF", "XLK", "XLE", "XLY", "XLI", "XLV", "XLP", "XLU")

build_a3_us_sector_flow <- function() {
  cat("[A3] Building US sector flow from 8 ETFs...\n")

  sector_data <- list()
  for (sym in SECTORS) {
    cache_path <- file.path(SECTOR_CACHE, paste0(sym, "_daily.parquet"))
    if (file.exists(cache_path)) {
      cat(sprintf("  %s: cache hit\n", sym))
      sector_data[[sym]] <- as.data.table(read_parquet(cache_path))
    } else {
      cat(sprintf("  %s: fetching from yahoo...\n", sym))
      x <- tryCatch(
        getSymbols(sym, src = "yahoo", from = "2000-01-01", auto.assign = FALSE),
        error = function(e) NULL
      )
      if (is.null(x)) {
        cat(sprintf("  %s: FAIL\n", sym)); next
      }
      df <- data.table(Date = as.Date(index(x)),
                       Close = as.numeric(x[, paste0(sym, ".Adjusted")]))
      df <- df[!is.na(Close) & Close > 0]
      df[, sym := sym]
      write_parquet(df, cache_path)
      sector_data[[sym]] <- df
      Sys.sleep(0.5)  # rate limit safety
    }
  }

  if (length(sector_data) == 0) stop("[A3] all sectors FAIL")

  # Compute 21d return per sector
  for (sym in names(sector_data)) {
    d <- sector_data[[sym]]
    setorder(d, Date)
    d[, ret_21d := Close / shift(Close, 21) - 1]
    sector_data[[sym]] <- d
  }

  # Merge by Date (wide)
  wide <- Reduce(function(a, b) merge(a, b, by = "Date", all = TRUE),
                 lapply(names(sector_data), function(sym) {
                   d <- sector_data[[sym]][, .(Date, ret_21d)]
                   setnames(d, "ret_21d", paste0("ret_", sym))
                   d
                 }))
  setorder(wide, Date)

  ret_cols <- paste0("ret_", names(sector_data))
  wide[, us_sector_avg := rowMeans(wide[, ret_cols, with = FALSE], na.rm = TRUE)]
  wide[, us_sector_avg := ifelse(is.nan(us_sector_avg), NA_real_, us_sector_avg)]
  wide[, us_sector_dispersion := apply(wide[, ret_cols, with = FALSE], 1, function(r) sd(r, na.rm = TRUE))]

  # Expanding z-score + lag1
  wide[, us_sector_avg_z_raw := rolling_zscore_expanding(us_sector_avg)]
  wide[, us_sector_dispersion_z_raw := rolling_zscore_expanding(us_sector_dispersion)]
  wide[, us_sector_avg_z := lag1(us_sector_avg_z_raw)]
  wide[, us_sector_dispersion_z := lag1(us_sector_dispersion_z_raw)]

  result <- wide[, .(Date, us_sector_avg_z, us_sector_dispersion_z)]

  out_path <- file.path(OUT_DIR, "A3_us_sector_flow.parquet")
  write_parquet(result, out_path)

  cat(sprintf("[A3] DONE: %d rows / %s ~ %s\n",
              nrow(result), as.character(min(result$Date)), as.character(max(result$Date))))
  cat(sprintf("  us_sector_avg_z non-NA: %d\n", sum(!is.na(result$us_sector_avg_z))))
  cat(sprintf("  us_sector_dispersion_z non-NA: %d\n", sum(!is.na(result$us_sector_dispersion_z))))
  cat(sprintf("  Output: %s\n", out_path))

  invisible(result)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  build_a3_us_sector_flow()
}
