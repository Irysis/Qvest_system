# =============================================================================
# s1_build_inputs.R — Track V (Composition Search Cycle 1b) measurement inputs
#
# Builds, ONCE, all signal/return/liquidity inputs for the preregistered grid
# (prereg_variations.json FROZEN 2026-06-11). No measurement here.
#
# Outputs (04_Research/composition_search/cycle1b_trackV/inputs/):
#   adv_panel.parquet  - Date(me), Ticker, adv(=AvgTV20), K200, KQ150
#   me_panel.parquet   - Date(me), Ticker, Close, ret_fwd(fwd 1M), ret_date
#   bm_monthly.csv     - Date(=realization me), BM_Ret_m (daily BM_Ret compounded
#                        over (prev_me, me] - identical to driver logic)
#   b2_scores.parquet  - fe_str1715v2.R FACTORS (Date,Ticker,Score,N) N_CAP=25
#   b3_scores.parquet  - fe_valmom.R FACTORS (Date,Ticker,Score,N=decile)
#   b4_scores.parquet  - C19_Composite_Earnings Z_Score_Aligned within
#                        K200uKQ150+ADV>=2e8 universe (driver_lo_screen legacy path)
#
# PIT: identical to original engines (fe_* sourced verbatim; C13/C14/C15 via
#      load_month_factors; AvgTV20 = trailing 20d window; ret_fwd = forward 1M).
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(arrow)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))   # load_rawdata
OUT <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV/inputs")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
t0 <- Sys.time()

# ---- 1. RAWDATA + BM ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date"))  BM_DT[,  Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
cat(sprintf("[s1] RAWDATA %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ---- 2. month-end (trading) grid + adv panel ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
adv <- RAWDATA[Date %in% me_dates, .(Date, Ticker, adv = .AvgTV20, K200, KQ150)]
write_parquet(adv, file.path(OUT, "adv_panel.parquet"))
cat(sprintf("[s1] adv_panel saved: %d rows, %d month-ends\n", nrow(adv), uniqueN(adv$Date)))
RAWDATA[, c(".TV", ".AvgTV20") := NULL]

# ---- 3. me_panel: month-end Close -> forward 1M (identical to driver logic) ----
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]
write_parquet(me_panel, file.path(OUT, "me_panel.parquet"))
cat(sprintf("[s1] me_panel saved: %d rows\n", nrow(me_panel)))

# ---- 4. bm monthly ((prev_me, me] daily compounding - driver-identical) ----
setorder(BM_DT, Date)
bm_d <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret)]
me_idx <- data.table(d = me_dates, nd = shift(me_dates, 1L, type = "lead"))[!is.na(nd)]
bm_list <- vector("list", nrow(me_idx))
for (i in seq_len(nrow(me_idx))) {
  d <- me_idx$d[i]; nd <- me_idx$nd[i]
  seg <- bm_d[Date > d & Date <= nd, BM_Ret]
  if (length(seg) < 1L) next
  bm_list[[i]] <- data.table(Date = nd, BM_Ret_m = prod(1 + seg) - 1)  # interval compounding (Return.cumulative-equivalent, driver-identical)
}
bm_m <- rbindlist(Filter(Negate(is.null), bm_list))
fwrite(bm_m, file.path(OUT, "bm_monthly.csv"))
cat(sprintf("[s1] bm_monthly saved: %d months\n", nrow(bm_m)))
rm(BM_DT, bm_d); gc(FALSE)

# ---- 5. B2 signals: fe_str1715v2.R verbatim (original measurement signal path) ----
Sys.setenv(W_C = "0.45", W_D = "0.25", W_V = "0.30", N_CAP = "25")
cat("[s1] sourcing fe_str1715v2.R (bulk factor pre-load)...\n")
source(file.path(INFRA, "alpha_search", "fe_str1715v2.R"))
stopifnot(exists("FACTORS"), all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
write_parquet(FACTORS, file.path(OUT, "b2_scores.parquet"))
cat(sprintf("[s1] b2_scores saved: %d rows, %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(FACTORS); if (exists("fdb_all")) rm(fdb_all); gc(FALSE)

# ---- 6. B3 signals: fe_valmom.R verbatim ----
cat("[s1] sourcing fe_valmom.R (monthly V01_BM loop + momentum)...\n")
source(file.path(INFRA, "alpha_search", "fe_valmom.R"))
stopifnot(exists("FACTORS"), all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
write_parquet(FACTORS, file.path(OUT, "b3_scores.parquet"))
cat(sprintf("[s1] b3_scores saved: %d rows, %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(FACTORS); gc(FALSE)

# ---- 7. B4 signals: C19_Composite_Earnings (driver_lo_screen legacy-loop logic) ----
.fdb_min <- as.Date("2002-08-01")
mem <- adv[Date >= .fdb_min & (K200 == TRUE | KQ150 == TRUE) & !is.na(adv) & adv >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(RAWDATA); gc(FALSE)
b4_dates <- me_dates[me_dates >= .fdb_min]
fac_list <- vector("list", length(b4_dates))
cat(sprintf("[s1] C19 monthly loop: %d months...\n", length(b4_dates)))
for (i in seq_along(b4_dates)) {
  d <- b4_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  ff <- fdt[Factor_Name == "C19_Composite_Earnings" & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
            .(Ticker, Score = Z_Score_Aligned)]
  rm(fdt)
  if (nrow(ff) >= 10L) { ff[, Date := d]; fac_list[[i]] <- ff[, .(Date, Ticker, Score)] }
  if (i %% 24L == 0L) gc(FALSE)
}
b4 <- rbindlist(Filter(Negate(is.null), fac_list), use.names = TRUE)
stopifnot(nrow(b4) > 0)
write_parquet(b4, file.path(OUT, "b4_scores.parquet"))
cat(sprintf("[s1] b4_scores saved: %d rows, %d months\n", nrow(b4), uniqueN(b4$Date)))

cat(sprintf("[s1] DONE in %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
