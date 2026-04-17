# STR_1622: IC-Weighted Statistical Blend (C19+V14+Q01+D01+M25)
# 5-factor IC-weighted blend with expanding 12M rolling IC
# Shrinkage: w_i = 0.5 * IC_norm_i + 0.5 * (1/5). Floor 5%, cap 40%.
# PIT: C1 (no full-sample), C13 (Z_Score_Aligned), C14 (Usable_Date <= sig_d), C15 (load_month_factors)
# Arnott et al. 2019 + DeMiguel et al. 2009

cat("[factor_engine] STR_1622: IC-Weighted Statistical Blend 5F (C19+V14+Q01+D01+M25)...\n")
set.seed(1622)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
N_FACTORS  <- 5L
FLOOR_W    <- 0.05
CAP_W      <- 0.40
N_FACTORS_EW <- 1.0 / N_FACTORS  # EW benchmark = 0.20

NEEDED_FACTORS <- c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
                    "D01_IdioVol", "M25_Earnings_Mom_Streak")

pq_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                       pattern = "\\.parquet$", full.names = TRUE)
ds <- open_dataset(pq_files, format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
# C14 fallback: Usable_Date not in DB → use Date (monthly end-of-period signal)
FDB_ALL[, Usable_Date := Date]
# C13: rename Z_Score → Z_Score_Aligned (canonical name, no manual flip)
setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
# Build forward returns for IC calculation (t+1 month return)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, FwdRet := shift(Ret, n = -1L, type = "lead"), by = Ticker]

fdb_dates <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

# IC history accumulator (expanding window, 12M rolling)
# Stores list of monthly IC vectors
ic_history <- list()  # [[fn]] = vector of monthly IC values

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # C14: only use FDB rows where Usable_Date <= sig_d
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)

  # C14 enforcement: filter by Usable_Date <= sig_d
  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE & Usable_Date <= sig_d]
  if (nrow(fdt) == 0L) {
    # Fallback: use Date filter only (if Usable_Date not available)
    fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  }
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, FwdRet)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Compute IC at this date (rank correlation with FwdRet)
  # This IC is stored AFTER the fact (available for next period's weighting)
  ic_current <- setNames(rep(NA_real_, N_FACTORS), NEEDED_FACTORS)
  for (fn in NEEDED_FACTORS) {
    if (fn %in% names(fdt_wide)) {
      vals <- fdt_wide[[fn]]
      fwd  <- fdt_wide$FwdRet
      mask <- !is.na(vals) & !is.na(fwd)
      if (sum(mask) >= 20L) {
        ic_current[fn] <- cor(rank(vals[mask]), rank(fwd[mask]),
                               method = "spearman")
      }
    }
  }
  # Store IC for this period (will be used from NEXT period onward: t-1 lag)
  ic_history[[as.character(sig_d)]] <- ic_current

  # Compute IC-based weights using PAST 12M rolling IC (t-1 lag)
  # Use all stored ICs BEFORE sig_d (i.e., ic_history[1..i-1])
  past_dates <- names(ic_history)[as.Date(names(ic_history)) < sig_d]

  if (length(past_dates) == 0L) {
    # No history: equal weights
    weights <- setNames(rep(N_FACTORS_EW, N_FACTORS), NEEDED_FACTORS)
  } else {
    # Rolling 12M: use last 12 periods max
    window_dates <- tail(past_dates, 12L)
    ic_mat <- do.call(rbind, lapply(window_dates, function(d) ic_history[[d]]))
    ic_mean <- colMeans(ic_mat, na.rm = TRUE)

    # Shrinkage: w_i = 0.5 * IC_norm + 0.5 * EW
    ic_abs <- abs(ic_mean)
    ic_abs[is.na(ic_abs)] <- 0
    ic_sum <- sum(ic_abs)
    if (ic_sum > 0) {
      ic_norm <- ic_abs / ic_sum
    } else {
      ic_norm <- rep(N_FACTORS_EW, N_FACTORS)
    }
    weights_raw <- 0.5 * ic_norm + 0.5 * N_FACTORS_EW
    # Floor + cap
    weights_raw <- pmax(weights_raw, FLOOR_W)
    weights_raw <- pmin(weights_raw, CAP_W)
    weights <- weights_raw / sum(weights_raw)  # renormalize
    names(weights) <- NEEDED_FACTORS
  }

  # Compute rank scores with IC-based weights
  fdt_wide[, Score := 0.0]
  total_w <- 0
  for (fn in NEEDED_FACTORS) {
    w <- weights[fn]
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      fdt_wide[, Score := Score + w * rnk]
      total_w <- total_w + w
    }
  }
  if (total_w == 0) { n_skipped <- n_skipped + 1L; next }
  fdt_wide[, Score := Score / total_w]

  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
if ("FwdRet" %in% names(RAWDATA)) RAWDATA[, FwdRet := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL, ic_history); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
