## STR_1422: S5 M2_COMBO_D01 — D01 IdioVol 0.7 + Flow Reversal 0.3 Blend
## D01 = verified primary alpha (Factor DB). FlowRev = independent signal (investor data).
## S5: 강한 alpha(D01)에 독립 flow reversal 신호(0.3 weight) 추가.
## C13: Z_Score_Aligned for D01. FlowRev = custom signal (contrarian Z-score).
## PIT: investor data t+1, rolling window only, no lookahead.

cat("[factor_engine] STR_1422 S5: D01*0.7 + FlowRev*0.3 blend...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

W_D01 <- 0.7; W_FLOW <- 0.3

# ── Step 1: Load D01 from Factor DB ──
NEEDED_FACTORS <- c("D01_IdioVol")
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
library(arrow)
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::collect() |>
  as.data.table()
cat(sprintf("  D01 loaded: %s rows\n", format(nrow(FDB_RAW), big.mark = ",")))

registry <- .load_registry()
FDB_D01 <- align_factor_direction(FDB_RAW, registry)
FDB_D01[, Date := as.Date(Date)]
setkey(FDB_D01, Date, Ticker)
rm(FDB_RAW, ds); gc(verbose = FALSE)

# ── Step 2: Load investor data + compute Flow Reversal signal ──
cat("  Loading investor_wide.parquet for flow reversal...\n")
inv <- as.data.table(read_parquet(
  file.path(PROJECT_ROOT, ".cache", "investor_stock", "investor_wide.parquet")
))
setkey(inv, Ticker, Date)

# 20-day rolling cumulative foreign net buying (PIT: rolling window only)
inv[, Foreign_Cum20 := frollsum(Foreign, n = 20L, algo = "exact", align = "right"),
    by = Ticker]
inv <- inv[!is.na(Foreign_Cum20)]

# Extract end-of-month signals
inv[, YearMonth := format(Date, "%Y-%m")]
eom_flow <- inv[, .SD[which.max(Date)], by = .(Ticker, YearMonth)]

# Contrarian Z-score: higher score = more foreign selling = expected reversal
eom_flow[, FlowSellZ := {
  x <- -Foreign_Cum20  # contrarian
  valid <- !is.na(x)
  z <- rep(NA_real_, length(x))
  if (sum(valid) >= 20) {
    mu <- mean(x[valid]); sd_val <- sd(x[valid])
    if (sd_val > 1e-10) z[valid] <- (x[valid] - mu) / sd_val
  }
  pmin(pmax(z, -3), 3)  # winsorize
}, by = YearMonth]

# Create lookup: Date, Ticker, FlowZ
flow_signal <- eom_flow[!is.na(FlowSellZ), .(Date, Ticker, FlowZ = FlowSellZ)]
setkey(flow_signal, Date, Ticker)
cat(sprintf("  Flow signal: %s rows, %d months\n",
            format(nrow(flow_signal), big.mark = ","), uniqueN(flow_signal$Date)))
rm(inv, eom_flow); gc(verbose = FALSE)

# ── Step 3: Build blended score per month ──
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"),
                            1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])

  # Universe
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30) { n_skip <- n_skip + 1L; next }

  # D01 factor score
  d01_dt <- FDB_D01[Date == sig_d & Factor_Name == "D01_IdioVol",
                    .(Ticker, D01_Z = Z_Score_Aligned)]

  # Flow reversal score (use closest available date <= sig_d)
  flow_dt <- flow_signal[Date == sig_d, .(Ticker, FlowZ)]
  if (nrow(flow_dt) == 0) {
    # Try nearest earlier date within same month
    flow_candidates <- flow_signal[Date <= sig_d & Date >= sig_d - 5]
    if (nrow(flow_candidates) > 0) {
      flow_dt <- flow_candidates[Date == max(Date), .(Ticker, FlowZ)]
    }
  }

  if (nrow(d01_dt) == 0) { n_skip <- n_skip + 1L; next }

  # Merge all
  dt <- merge(snap, d01_dt, by = "Ticker")
  dt <- merge(dt, flow_dt, by = "Ticker", all.x = TRUE)  # FlowZ may be NA for some

  # Blend: D01*0.7 + FlowRev*0.3 (NA flow → D01 only)
  dt[, Score := fifelse(is.na(FlowZ),
                        D01_Z,
                        W_D01 * D01_Z + W_FLOW * FlowZ)]
  dt <- dt[!is.na(Score)]
  if (nrow(dt) < 30) { n_skip <- n_skip + 1L; next }

  # Sector neutral
  dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  dt[, Date := sig_d]
  factor_list[[i]] <- dt[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# Cleanup
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_D01, flow_signal); gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d signal dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
