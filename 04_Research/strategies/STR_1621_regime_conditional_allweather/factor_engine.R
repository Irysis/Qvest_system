# STR_1621: Regime-Conditional All-Weather (C19+V14 core / D01+D44 defense)
# 2-sleeve dynamic allocation using Regime_Score (t-1 lag, expanding window)
# core_w = max(0.2, 1 - Regime_Score/100); def_w = 1 - core_w
# Regime is alpha source → Regime overlay ALLOWED at S1 (exception rule)
# Ang & Timmermann 2012: regime-switching in factor returns

cat("[factor_engine] STR_1621: Regime-Conditional AllWeather (C19+V14 / D01+D44)...\n")
set.seed(1621)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
CORE_FACTORS    <- c("C19_Composite_Earnings", "V14_EBIT_EV")
DEFENSE_FACTORS <- c("D01_IdioVol", "D44_Kurtosis")
NEEDED_FACTORS  <- c(CORE_FACTORS, DEFENSE_FACTORS)

# C15: load_month_factors() 경유 (직접 parquet 로드 금지)
# Z_Score_Aligned는 parquet에 없고 load_month_factors()가 동적으로 생성
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# Factor DB 날짜 목록 (어느 월이 가용한지 확인용)
fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$", full.names = FALSE)
fdb_dates_ym <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
cat(sprintf("  Factor DB: %d monthly files available (latest: %s)\n",
            length(fdb_dates_ym), if (length(fdb_dates_ym) > 0) tail(fdb_dates_ym, 1) else "NONE"))

# Load regime signal (t-1 lag enforced below via shift)
cat("  Loading regime signal...\n")
source(file.path(REGIME_DIR, "regime_signal.R"))
tryCatch({
  regime_dt <- load_regime_signal()
  if (is.null(regime_dt) || nrow(regime_dt) == 0L) {
    regime_dt <- build_regime_signal_table()
  }
  regime_dt[, Date := as.Date(Date)]
  setorder(regime_dt, Date)
  # t-1 lag: use previous month's regime score
  regime_dt[, Regime_Score_Lag := shift(Regime_Score, n = 1L, type = "lag")]
  setkey(regime_dt, Date)
  cat(sprintf("  Regime signal: %d months\n", nrow(regime_dt)))
}, error = function(e) {
  cat("[WARN] Regime signal failed, defaulting to NEUTRAL (score=0):", e$message, "\n")
  regime_dt <<- data.table(Date = as.Date(character(0)), Regime_Score_Lag = numeric(0))
})

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # C15: load_month_factors() 경유 — Z_Score_Aligned 자동 방향 정렬 포함
  fdt <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) { cat(sprintf("  [SKIP %s] %s\n", sig_d, e$message)); NULL }
  )
  if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Regime weights (t-1 lag: use lagged score)
  # Find nearest regime date <= sig_d
  valid_regime_dates <- regime_dt$Date[regime_dt$Date <= sig_d & !is.na(regime_dt$Regime_Score_Lag)]
  if (length(valid_regime_dates) > 0L) {
    rd <- max(valid_regime_dates)
    rsc <- regime_dt[Date == rd, Regime_Score_Lag]
    if (is.na(rsc) || length(rsc) == 0L) rsc <- 0
  } else {
    rsc <- 0  # NEUTRAL default
  }
  core_w <- max(0.2, 1 - rsc / 100)
  def_w  <- 1 - core_w

  # Core sleeve rank score
  core_score <- rep(0.0, nrow(fdt_wide))
  n_core_valid <- 0L
  for (fn in CORE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      core_score <- core_score + ifelse(is.na(rnk), 0, rnk)
      n_core_valid <- n_core_valid + 1L
    }
  }
  if (n_core_valid > 0L) core_score <- core_score / n_core_valid

  # Defense sleeve rank score
  def_score <- rep(0.0, nrow(fdt_wide))
  n_def_valid <- 0L
  for (fn in DEFENSE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      def_score <- def_score + ifelse(is.na(rnk), 0, rnk)
      n_def_valid <- n_def_valid + 1L
    }
  }
  if (n_def_valid > 0L) def_score <- def_score / n_def_valid

  # Combined score
  fdt_wide[, Score := core_w * core_score + def_w * def_score]

  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
