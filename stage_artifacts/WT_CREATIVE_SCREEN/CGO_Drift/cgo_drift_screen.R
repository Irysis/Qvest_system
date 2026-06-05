#==============================================================================
# CGO-Drift Capital-Gains-Overhang — cheap IC SCREEN (read-only, SCREEN only)
#
# Grinblatt-Han (2005) capital gains overhang:
#   RP_t = (1/k_t) * sum_{n>=1} [ V_{t-n} * prod_{tau=1..n-1}(1 - V_{t-n+tau}) ] * P_{t-n}
#     where V = turnover (volume/shares), P = price, k = normalization constant
#   CGO_t = (P_t - RP_t) / P_t
#   (+)CGO = unrealized gain -> disposition selling pressure BUT winner underreaction drift.
#
# PIT: ALL features t-1 backward (signal built on daily history strictly before
#      month-end sig_date). Forward label = next-month return only.
#      Lockbox 2023-12-22 strict (regular research). Usable_Date<=sig_date (C14).
#
# Orthogonality control: M01_Mom_12_1, M06_High_52w, M08_Residual_Mom, M17_Low_52w
#   -> monthly cross-sectional residualization (regress CGO_z on controls)
#      -> rank-IC of residual = incremental/partial IC.
#
# Output: SCREEN JSON only. NO backtest / portfolio / admission.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts/WT_CREATIVE_SCREEN/CGO_Drift")
LOCKBOX <- as.Date("2023-12-22")  # regular-research lockbox (strict)

set.seed(42)

#--- 1. Load rawdata (daily) -------------------------------------------------
cat("[1] loading rawdata...\n")
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
rd <- rd[, .(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150,
             AdminStock, TradingHalt)]
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)

# PIT lockbox: regular research -> features must be built on data strictly within lockbox.
# Use data up to LOCKBOX for the final sig_date; signal computed only from backward history.
rd <- rd[Date <= LOCKBOX]
cat("    rows after lockbox:", nrow(rd), " last date:", as.character(max(rd$Date)), "\n")

#--- 2. Daily turnover proxy (PIT, t-1 backward) -----------------------------
# Shares proxy: Size (market cap) / Close = shares*. Turnover_t = Vol_t / shares_t.
# All daily. CGO at month-end uses ONLY daily data strictly <= that day (backward).
rd[, shares := fifelse(Close > 0, Size / Close, NA_real_)]
rd[, turnover := fifelse(shares > 0, Vol / shares, NA_real_)]
# winsorize daily turnover to [0,1] (proxy can exceed 1 on illiquid days)
rd[, turnover := pmin(pmax(turnover, 0), 1)]

#--- 3. Universe + monthly sig_dates ----------------------------------------
rd[, ym := as.integer(format(Date, "%Y%m"))]
# month-end trading day per ticker-month is the sig_date snapshot
month_ends <- rd[, .(me_date = max(Date)), by = ym]
setkey(month_ends, ym)
sig_dates <- sort(unique(month_ends$me_date))
# need >=12 months of history to form CGO; start from 13th month
sig_dates <- sig_dates[sig_dates >= (min(rd$Date) + 400)]
cat("[3] sig_dates:", length(sig_dates), " range:",
    as.character(min(sig_dates)), "to", as.character(max(sig_dates)), "\n")

#--- 4. CGO computation per sig_date (vectorized over lookback window) -------
# Grinblatt-Han with 60-month (~252*5 trading-day) lookback, weekly thinning
# for tractability. Reference price weights = turnover * survival product.
LOOKBACK_DAYS <- 252L * 5L   # 5y horizon (standard GH window)
THIN <- 5L                   # weekly grid to keep O(n) manageable

compute_cgo_one <- function(sub) {
  # sub: ticker daily history sorted by Date, ALL <= sig_date (backward)
  n <- nrow(sub)
  if (n < 60L) return(NA_real_)
  P_t <- sub$Close[n]
  if (is.na(P_t) || P_t <= 0) return(NA_real_)
  # window of past observations strictly before t, thinned
  idx <- seq.int(max(1L, n - LOOKBACK_DAYS), n - 1L, by = THIN)
  if (length(idx) < 12L) return(NA_real_)
  Pn <- sub$Close[idx]
  Vn <- sub$turnover[idx]
  Vn[is.na(Vn)] <- 0
  Pn_ok <- !is.na(Pn) & Pn > 0
  if (sum(Pn_ok) < 12L) return(NA_real_)
  # survival product: weight on obs i = V_i * prod_{j after i}(1 - V_j)
  # iterate from most recent backward (standard GH recursion)
  m <- length(idx)
  w <- numeric(m)
  surv <- 1.0
  for (i in seq.int(m, 1L)) {     # i=m is most recent past obs
    w[i] <- Vn[i] * surv
    surv <- surv * (1 - Vn[i])
  }
  w[!Pn_ok] <- 0
  sw <- sum(w)
  if (sw <= 1e-8) return(NA_real_)
  RP <- sum(w * Pn) / sw          # normalized reference price
  (P_t - RP) / P_t                # CGO
}

cat("[4] computing CGO per sig_date (this is the heavy step)...\n")
cgo_list <- vector("list", length(sig_dates))
for (s in seq_along(sig_dates)) {
  sd <- sig_dates[s]
  # universe at sig_date: K200 or KQ150 == 1, tradable
  uni <- rd[Date == sd & (K200 == 1 | KQ150 == 1) &
              (is.na(AdminStock) | AdminStock == 0) &
              (is.na(TradingHalt) | TradingHalt == 0), unique(Ticker)]
  if (length(uni) < 30L) next
  hist <- rd[Ticker %in% uni & Date <= sd]   # backward only
  setorder(hist, Ticker, Date)
  cg <- hist[, .(CGO = compute_cgo_one(.SD)), by = Ticker,
             .SDcols = c("Close", "turnover")]
  cg <- cg[!is.na(CGO)]
  if (nrow(cg) < 30L) next
  cg[, sig_date := sd]
  cgo_list[[s]] <- cg
  if (s %% 24L == 0L) cat("    ", as.character(sd), " n=", nrow(cg), "\n")
}
cgo <- rbindlist(cgo_list)
cat("    total CGO obs:", nrow(cgo), " over", uniqueN(cgo$sig_date), "months\n")
saveRDS(cgo, file.path(OUT, "cgo_signal.rds"))
