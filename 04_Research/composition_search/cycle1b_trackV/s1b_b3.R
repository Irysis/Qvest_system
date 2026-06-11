# =============================================================================
# s1b_b3.R — resume interrupted s1_build_inputs.R: B3 valmom (AMP2013) scores
#
# fe_valmom.R logic VERBATIM, with ONE implementation substitution:
#   value leg V01_BM Z_Score_Aligned is read from
#   stage_artifacts/alpha_search/lo_screen/_factor_cache.rds instead of calling
#   load_month_factors(d) per month. The cache is the *verbatim slim copy* of
#   load_month_factors output (build_lo_factor_cache.R: Z_Score_Aligned preserved
#   unchanged, universe = same K200uKQ150 + AvgTV20>=2e8 month-end membership) —
#   numerically identical input, ~25x faster I/O. Equality is SPOT-VERIFIED below
#   against 3 live load_month_factors calls (assert max|diff| == 0) before use.
# Momentum leg + universe + z-combo + decile N: fe_valmom.R lines 40-106 verbatim.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                  # load_rawdata
source(file.path(INFRA, "factor_db", "factor_db_connector.R")) # load_month_factors (spot-check)
OUT <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV/inputs")
t0 <- Sys.time()

# ---- value leg from verified cache ----
FC <- readRDS(file.path(PROJ, "stage_artifacts/alpha_search/lo_screen/_factor_cache.rds"))
VAL <- FC[Factor_Name == "V01_BM", .(Date, Ticker, Val = Z_Score_Aligned)]
rm(FC); gc(FALSE)
setkey(VAL, Date, Ticker)
cat(sprintf("[s1b_b3] V01_BM cache: %d rows, %d months (%s ~ %s)\n",
            nrow(VAL), uniqueN(VAL$Date), min(VAL$Date), max(VAL$Date)))

# ---- RAWDATA: universe + momentum (fe_valmom.R verbatim) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)
rm(RAWDATA); gc(FALSE)

# ---- SPOT-CHECK: cache V01_BM == live load_month_factors on 3 dates ----
chk_dates <- as.Date(c("2005-06-30", "2015-06-30", "2024-12-30"))
chk_dates <- vapply(chk_dates, function(d) as.character(max(.month_ends[.month_ends <= d])), character(1))
chk_dates <- as.Date(chk_dates)
for (d in as.list(chk_dates)) {
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  fdt <- load_month_factors(d, coverage_min = 0.05)
  live <- fdt[Factor_Name == "V01_BM" & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
              .(Ticker, Val_live = Z_Score_Aligned)]
  rm(fdt)
  cc <- merge(VAL[.(d)][, .(Ticker, Val)], live, by = "Ticker", all = TRUE)
  n_miss <- cc[, sum(is.na(Val) | is.na(Val_live))]
  mx <- cc[!is.na(Val) & !is.na(Val_live), max(abs(Val - Val_live))]
  cat(sprintf("[s1b_b3] spot-check %s: n_cache=%d n_live=%d unmatched=%d max|diff|=%.3e\n",
              as.character(d), VAL[.(d), .N], nrow(live), n_miss, mx))
  stopifnot(n_miss == 0, mx == 0)
}
cat("[s1b_b3] SPOT-CHECK PASS: cache == load_month_factors (V01_BM, 3 dates exact)\n")

# ---- monthly combo loop (fe_valmom.R verbatim, value from cache) ----
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  val <- VAL[.(d), .(Ticker, Val), nomatch = 0L]
  val <- val[Ticker %in% uni_tk & is.finite(Val)]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L]
  mom <- mom[Ticker %in% uni_tk]
  cmb <- merge(val, mom, by = "Ticker")
  if (nrow(cmb) < 10L) next
  cmb[, Zv := .zsc(Val)]
  cmb[, Zm := .zsc(Mom)]
  cmb <- cmb[is.finite(Zv) & is.finite(Zm)]
  if (nrow(cmb) < 10L) next
  cmb[, Score := Zv + Zm]
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]
cat(sprintf("[s1b_b3] FACTORS rows=%d | months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N)))
write_parquet(FACTORS, file.path(OUT, "b3_scores.parquet"))
cat(sprintf("[s1b_b3] b3_scores saved | %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("[s1b_b3] DONE\n")
