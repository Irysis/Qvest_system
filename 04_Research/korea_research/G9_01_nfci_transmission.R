cat("=== TEST-KR-G9-01: NFCI → Korea Factor IC Transmission ===\n")
cat("=== 근거: KR-015 (한국은행 SSRN:3016974, 미국→한국 전이) ===\n")
cat("=== 가설: NFCI 긴축 시 한국 Defense IC 상승, Momentum IC 하락 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db_builder.R")
})
library(data.table)

# ── 1. NFCI 데이터 로드 (FRED) ───────────────────────────────────
cat("[G9-01] Step 1: Loading NFCI from cache/FRED...\n")

nfci_path <- file.path(CACHE_DIR, "fred_nfci.csv")
if (file.exists(nfci_path)) {
  nfci <- fread(nfci_path)
  nfci[, Date := as.Date(Date)]
  cat(sprintf("  NFCI cached: %d rows (%s ~ %s)\n",
              nrow(nfci), min(nfci$Date), max(nfci$Date)))
} else {
  cat("  [INFO] NFCI cache not found. Attempting FRED API...\n")
  # FRED API fallback
  tryCatch({
    fred_url <- sprintf(
      "https://api.stlouisfed.org/fred/series/observations?series_id=NFCI&api_key=%s&file_type=json&observation_start=2000-01-01",
      Sys.getenv("FRED_API_KEY")
    )
    resp <- jsonlite::fromJSON(fred_url)
    nfci <- data.table(
      Date = as.Date(resp$observations$date),
      NFCI = as.numeric(resp$observations$value)
    )
    nfci <- nfci[!is.na(NFCI)]
    fwrite(nfci, nfci_path)
    cat(sprintf("  NFCI fetched: %d rows\n", nrow(nfci)))
  }, error = function(e) {
    cat(sprintf("  [ERROR] FRED API failed: %s\n", e$message))
    cat("  Generating synthetic NFCI from VIX proxy...\n")
    # VIX proxy from regime engine
    nfci <<- data.table(Date = seq(as.Date("2005-01-01"),
                                    as.Date("2026-03-01"), by = "month"),
                         NFCI = 0)
    cat("  [WARN] Using dummy NFCI=0. Results will show no transmission.\n")
  })
}

# C1: expanding window Z-score (full-sample Z 금지)
setorder(nfci, Date)
nfci[, NFCI_z := {
  z <- rep(NA_real_, .N)
  for (j in 36:.N) {
    window <- NFCI[1:j]
    z[j] <- (NFCI[j] - mean(window, na.rm = TRUE)) /
      (sd(window, na.rm = TRUE) + 1e-8)
  }
  z
}]

# C5: t-1 lag
nfci[, NFCI_z_lag := shift(NFCI_z, n = 1L, type = "lag")]

# Regime: Tightening (>0.5), Neutral, Easing (<-0.5)
nfci[, NFCI_regime := fifelse(
  NFCI_z_lag > 0.5, "TIGHTENING",
  fifelse(NFCI_z_lag < -0.5, "EASING", "NEUTRAL")
)]

# Monthly aggregation (weekly → monthly: use last observation)
nfci[, YM := format(Date, "%Y%m")]
nfci_monthly <- nfci[, .SD[.N], by = YM]
setorder(nfci_monthly, Date)

cat(sprintf("  NFCI monthly: %d rows\n", nrow(nfci_monthly)))
cat("  Regime distribution:\n")
print(table(nfci_monthly$NFCI_regime, useNA = "ifany"))

# ── 2. Factor IC × NFCI Regime ───────────────────────────────────
cat("\n[G9-01] Step 2: Computing factor IC conditional on NFCI regime...\n")
.load_base_data()
RAWDATA <- .fdb_env$RAWDATA

all_dates <- sort(unique(RAWDATA$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date
month_ends <- month_ends[month_ends >= as.Date("2005-01-01")]

# Key factors to test
TEST_FACTORS <- c(
  "C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
  "D01_IdioVol", "M05_Trended_Mom", "M04_Mom_1",
  "R01_VaR_95", "D44_Kurtosis", "MK01_CAPM_Beta"
)

results <- list()
processed <- 0L

for (sig_date in as.character(month_ends)) {
  sig_d <- as.Date(sig_date)
  fdb <- tryCatch(load_factor_db(sig_d, format = "wide"), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) < 50) next

  next_idx <- which(as.character(month_ends) == sig_date) + 1L
  if (next_idx > length(month_ends)) next
  next_month <- month_ends[next_idx]

  fwd <- RAWDATA[Date > sig_d & Date <= next_month,
                 .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]
  merged <- merge(fdb, fwd, by = "Ticker")
  if (nrow(merged) < 30) next

  # NFCI regime for this month (t-1 lagged)
  sig_ym <- format(sig_d, "%Y%m")
  nfci_row <- nfci_monthly[YM == sig_ym]
  if (nrow(nfci_row) == 0L) {
    nfci_regime <- "UNKNOWN"
  } else {
    nfci_regime <- as.character(nfci_row$NFCI_regime[1])
    if (is.na(nfci_regime)) nfci_regime <- "UNKNOWN"
  }

  for (fc in TEST_FACTORS) {
    if (!(fc %in% names(merged))) next
    vals <- merged[[fc]]
    if (sum(!is.na(vals)) < 20) next
    ic_val <- cor(vals, merged$Fwd_Ret, use = "pairwise.complete.obs",
                  method = "spearman")
    if (!is.finite(ic_val)) next

    results[[length(results) + 1L]] <- data.table(
      sig_date = sig_d, factor_id = fc, ic = ic_val,
      nfci_regime = nfci_regime
    )
  }
  processed <- processed + 1L
  if (processed %% 50 == 0) cat(sprintf("  Processed %d months\n", processed))
}

cat(sprintf("  Total: %d months processed\n", processed))

# ── 3. 집계: NFCI 국면별 IC ──────────────────────────────────────
cat("\n[G9-01] Step 3: Aggregating by NFCI regime...\n")
ic_dt <- rbindlist(results)

regime_ic <- ic_dt[nfci_regime != "UNKNOWN", .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  n_months = .N
), by = .(factor_id, nfci_regime)]

regime_wide <- dcast(regime_ic, factor_id ~ nfci_regime,
                     value.var = c("mean_ic", "icir", "n_months"))

# Transmission effect: TIGHTENING IC - EASING IC
if ("mean_ic_TIGHTENING" %in% names(regime_wide) &&
    "mean_ic_EASING" %in% names(regime_wide)) {
  regime_wide[, transmission := mean_ic_TIGHTENING - mean_ic_EASING]
  setorder(regime_wide, -transmission)
}

# ── 4. 저장 + 출력 ──────────────────────────────────────────────
cat("\n=== NFCI Regime Conditional IC ===\n")
print_cols <- intersect(
  c("factor_id", "mean_ic_EASING", "mean_ic_NEUTRAL",
    "mean_ic_TIGHTENING", "transmission"),
  names(regime_wide)
)
print(regime_wide[, ..print_cols])

cat("\n=== NFCI Regime Distribution in Sample ===\n")
print(ic_dt[, .N, by = nfci_regime])

out_dir <- "04_Research/korea_research/G9_01_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(regime_wide, file.path(out_dir, "nfci_conditional_ic.csv"))
fwrite(nfci_monthly[!is.na(NFCI_regime)],
       file.path(out_dir, "nfci_monthly.csv"))

cat("\n[G9-01] Complete.\n")
