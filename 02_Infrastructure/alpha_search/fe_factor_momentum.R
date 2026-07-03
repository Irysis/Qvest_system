#!/usr/bin/env Rscript
# =============================================================================
# fe_factor_momentum.R — PIT-safe dynamic factor-momentum composite engine
# =============================================================================
# Uses Factor DB's point-in-time connector only. Monthly factor weights are
# derived from compute_rolling_ic_all(sig_date), which filters IC rows by
# Usable_Date <= sig_date.
#
# Env:
#   FACTOR_NAMES       comma-separated candidate factors
#   FM_TOP_K           optional number of factors kept each month (default 6)
#   FM_LOOKBACK_MONTHS optional IC lookback months (default 36)
#   FACTOR_MIN_COUNT   optional min available selected factors per stock
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.FM_FACTOR_STR <- Sys.getenv("FACTOR_NAMES", "")
.FM_FACTORS <- trimws(strsplit(.FM_FACTOR_STR, ",", fixed = TRUE)[[1]])
.FM_FACTORS <- unique(.FM_FACTORS[nzchar(.FM_FACTORS)])
if (!length(.FM_FACTORS)) {
  stop("[fe_factor_momentum] FACTOR_NAMES 환경변수 미설정")
}

.FM_TOP_K <- suppressWarnings(as.integer(Sys.getenv("FM_TOP_K", "")))
if (is.na(.FM_TOP_K) || .FM_TOP_K < 1L) .FM_TOP_K <- min(6L, length(.FM_FACTORS))
.FM_TOP_K <- min(.FM_TOP_K, length(.FM_FACTORS))

.FM_LOOKBACK <- suppressWarnings(as.integer(Sys.getenv("FM_LOOKBACK_MONTHS", "")))
if (is.na(.FM_LOOKBACK) || .FM_LOOKBACK < 12L) .FM_LOOKBACK <- 36L

.FM_MIN_COUNT <- suppressWarnings(as.integer(Sys.getenv("FACTOR_MIN_COUNT", "")))
if (is.na(.FM_MIN_COUNT) || .FM_MIN_COUNT < 1L) .FM_MIN_COUNT <- max(1L, min(3L, .FM_TOP_K))
.FM_MIN_COUNT <- min(.FM_MIN_COUNT, .FM_TOP_K)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function") ||
      !exists("compute_rolling_ic_all", mode = "function")) source(conn)
})

.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd_slim, Ticker, Date)
.rd_slim[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2002-08-01")]

.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- .rd_slim[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                   !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                 .(Date, Ticker)]
setkey(.mem, Date, Ticker)

rm(.rd_slim)
if (exists("RAWDATA", inherits = FALSE)) rm(RAWDATA)
gc(verbose = FALSE)

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  ic <- tryCatch(
    compute_rolling_ic_all(d, min_months = 36L, max_months = .FM_LOOKBACK),
    error = function(e) data.table(Factor_Name = character(), ICIR = numeric())
  )
  ic <- ic[Factor_Name %in% .FM_FACTORS & is.finite(ICIR)]
  if (nrow(ic)) {
    setorder(ic, -ICIR)
    chosen <- head(ic[ICIR > 0, Factor_Name], .FM_TOP_K)
    if (!length(chosen)) chosen <- head(ic$Factor_Name, .FM_TOP_K)
  } else {
    chosen <- head(.FM_FACTORS, .FM_TOP_K)
  }
  if (!length(chosen)) next

  wdt <- ic[Factor_Name %in% chosen, .(Factor_Name, W = pmax(ICIR, 0))]
  if (!nrow(wdt) || !any(is.finite(wdt$W) & wdt$W > 0)) {
    wdt <- data.table(Factor_Name = chosen, W = 1)
  }
  wdt[!is.finite(W) | W <= 0, W := min(W[is.finite(W) & W > 0], na.rm = TRUE)]
  if (any(!is.finite(wdt$W))) wdt[, W := 1]

  fdt <- tryCatch(
    load_month_factors(d, coverage_min = 0.05, factor_names = chosen),
    error = function(e) NULL
  )
  if (is.null(fdt) || nrow(fdt) == 0) {
    if (!is.null(fdt)) rm(fdt)
    next
  }

  fz_long <- fdt[
    Factor_Name %in% chosen & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
    .(Ticker, Factor_Name, Z = Z_Score_Aligned)
  ]
  rm(fdt)
  if (!nrow(fz_long)) next

  fz_long <- merge(fz_long, wdt, by = "Factor_Name", all.x = FALSE)
  fz <- fz_long[
    ,
    .(
      Score = sum(W * Z, na.rm = TRUE) / sum(W, na.rm = TRUE),
      factor_count = .N
    ),
    by = Ticker
  ][factor_count >= .FM_MIN_COUNT & is.finite(Score), .(Ticker, Score)]
  rm(fz_long)

  if (nrow(fz) < 20L) next
  fz[, Date := d]
  .factor_list[[i]] <- fz[, .(Date, Ticker, Score)]
  if (i %% 24L == 0L) gc(verbose = FALSE)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
rm(.factor_list)
gc(verbose = FALSE)

cat(sprintf(
  "[fe_factor_momentum] candidates=%s | top_k=%d | lookback=%d | min_count=%d | rows=%d | signal months=%d | avg N/month=%.0f\n",
  paste(.FM_FACTORS, collapse = ","),
  .FM_TOP_K,
  .FM_LOOKBACK,
  .FM_MIN_COUNT,
  nrow(FACTORS),
  uniqueN(FACTORS$Date),
  if (nrow(FACTORS)) nrow(FACTORS) / max(uniqueN(FACTORS$Date), 1L) else 0
))
