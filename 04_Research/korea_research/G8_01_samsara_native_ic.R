cat("=== TEST-KR-G8-01b: Samsara Native Factor IC (from RAWDATA) ===\n")
cat("=== Psi, STP, Gravity, Aleph, LHI — 05_Production 로직 이식 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table); library(TTR)

# ── 1. RAWDATA 로드 ─────────────────────────────────────────────
cat("[G8-01b] Step 1: Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)
cat(sprintf("  RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# ── 2. Samsara 팩터 계산 (Samsara_Protocol.R Step 5 이식) ────────
cat("[G8-01b] Step 2: Computing Samsara factors on RAWDATA...\n")

window_beta    <- 60L
window_physics <- 20L
LIQ_THRESHOLD  <- 2e8

setorder(RAWDATA, Ticker, Date)

# [Phase 1] Beta
cat("  Phase 1: Beta (60d rolling)...\n")
RAWDATA[, Beta := {
  if (.N >= window_beta) {
    runCov(Ret, BM_Ret, n = window_beta) /
      (runVar(BM_Ret, n = window_beta) + 1e-8)
  } else rep(NA_real_, .N)
}, by = Ticker]

# Bollinger components (STP)
RAWDATA[, Mean_Close := {
  if (.N >= window_physics) runMean(Close, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]
RAWDATA[, SD_Close := {
  if (.N >= window_physics) runSD(Close, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

# Momentum (20d)
RAWDATA[, Momentum := {
  if (.N >= window_physics) (Close / shift(Close, n = window_physics)) - 1
  else rep(NA_real_, .N)
}, by = Ticker]

# [Phase 2] Residual + derived
cat("  Phase 2: Residual, Aleph, Volatility...\n")
RAWDATA[, Residual := Ret - (Beta * BM_Ret)]

RAWDATA[, Aleph := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics) {
    abs(runSum(Residual, n = window_physics)) /
      (runSum(abs(Residual), n = window_physics) + 1e-6)
  } else rep(NA_real_, .N)
}, by = Ticker]

RAWDATA[, Volatility := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics) {
    runSD(Residual, n = window_physics)
  } else rep(NA_real_, .N)
}, by = Ticker]

RAWDATA[, Mean_Res := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics) {
    runMean(Residual, n = window_physics)
  } else rep(NA_real_, .N)
}, by = Ticker]

# [Phase 3] Final factors
cat("  Phase 3: Psi, STP, Gravity, LHI...\n")
RAWDATA[, Psi := (Residual - Mean_Res) / (Volatility + 1e-6)]
RAWDATA[, STP := (Close - (Mean_Close + 2 * SD_Close)) / Close]
RAWDATA[, Gravity := abs(Momentum) * Aleph]

RAWDATA[, LHI := {
  if (sum(!is.na(Volatility)) >= window_physics && .N >= window_physics) {
    runSD(Volatility, n = window_physics)
  } else rep(NA_real_, .N)
}, by = Ticker]

# Cleanup temp cols
for (col in c("Mean_Res", "Mean_Close", "SD_Close", "Beta",
              "Residual", "Volatility", "Momentum")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)

samsara_factors <- c("Psi", "STP", "Gravity", "Aleph", "LHI")
cat(sprintf("  Samsara factors computed. Non-NA check:\n"))
for (f in samsara_factors) {
  cat(sprintf("    %s: %s non-NA rows\n", f,
              format(sum(!is.na(RAWDATA[[f]])), big.mark = ",")))
}

# ── 3. 월말 Cross-Sectional IC 계산 ──────────────────────────────
cat("\n[G8-01b] Step 3: Computing monthly cross-sectional IC...\n")

RAWDATA[, YM := format(Date, "%Y%m")]
all_dates <- sort(unique(RAWDATA$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date
month_ends <- month_ends[month_ends >= as.Date("2005-01-01") &
                          month_ends <= as.Date("2026-03-01")]

# Liquidity filter prep (t-1 lag)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

results <- list()
processed <- 0L

for (idx in seq_along(month_ends)) {
  sig_d <- month_ends[idx]
  if (idx >= length(month_ends)) next
  next_month <- month_ends[idx + 1L]

  # Signal date snapshot
  snap <- RAWDATA[Date == sig_d & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 50) next

  # Forward return (t+1 month)
  fwd <- RAWDATA[Date > sig_d & Date <= next_month,
                 .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]
  merged <- merge(snap, fwd, by = "Ticker")
  if (nrow(merged) < 30) next

  for (fc in samsara_factors) {
    vals <- merged[[fc]]
    if (sum(!is.na(vals)) < 20) next
    ic_val <- cor(rank(vals[!is.na(vals) & !is.na(merged$Fwd_Ret[!is.na(vals)])]),
                  rank(merged$Fwd_Ret[!is.na(vals) & !is.na(merged$Fwd_Ret[!is.na(vals)])]),
                  method = "spearman",
                  use = "pairwise.complete.obs")
    # Simpler approach
    mask <- !is.na(vals) & !is.na(merged$Fwd_Ret)
    if (sum(mask) < 20) next
    ic_val <- cor(vals[mask], merged$Fwd_Ret[mask], method = "spearman")
    if (!is.finite(ic_val)) next

    results[[length(results) + 1L]] <- data.table(
      sig_date = sig_d, factor_id = fc, ic = ic_val,
      n_stocks = sum(mask)
    )
  }

  processed <- processed + 1L
  if (processed %% 50 == 0) cat(sprintf("  Processed %d/%d months\n",
                                         processed, length(month_ends) - 1))
}

cat(sprintf("  Total: %d months processed\n", processed))

# ── 4. 집계 ──────────────────────────────────────────────────────
cat("\n[G8-01b] Step 4: Aggregating IC/ICIR...\n")
ic_dt <- rbindlist(results)

summary_dt <- ic_dt[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  pos_rate = mean(ic > 0, na.rm = TRUE),
  n_months = .N
), by = factor_id]
setorder(summary_dt, -icir)

cat("\n=== Samsara Native Factor IC/ICIR ===\n")
print(summary_dt)

# ── 5. Factor DB proxy 비교 ──────────────────────────────────────
cat("\n[G8-01b] Step 5: Comparison with Factor DB proxy...\n")
fdb_path <- "04_Research/korea_research/G8_01_output/factor_ic_summary.csv"
if (file.exists(fdb_path)) {
  fdb_ic <- fread(fdb_path)
  cat("\n=== Factor DB Physics-Proxy IC (from G8-01) ===\n")
  print(fdb_ic[factor_id %in% c("D01_IdioVol", "D03_RealVol",
                                  "D44_Kurtosis", "D46_Sortino",
                                  "D22_Tracking_Error", "MK01_CAPM_Beta")])

  cat("\n=== Side-by-Side: Samsara Native vs Factor DB Proxy ===\n")
  mapping <- data.table(
    samsara = c("LHI", "Aleph", "Psi", "STP", "Gravity"),
    concept = c("Vol-of-Vol (chaos)", "Order/Negentropy",
                "Residual Z-score", "Bollinger Breakout",
                "Momentum x Order"),
    closest_fdb = c("D22_Tracking_Error", "D01_IdioVol",
                     "D44_Kurtosis", "M05_Trended_Mom", "M09_Composite_Mom")
  )
  comparison <- merge(summary_dt, mapping, by.x = "factor_id", by.y = "samsara",
                      all.x = TRUE)
  # Add FDB ICIR
  comparison <- merge(comparison,
                      fdb_ic[, .(closest_fdb = factor_id, fdb_icir = icir)],
                      by = "closest_fdb", all.x = TRUE)
  print(comparison[, .(factor_id, concept, icir, fdb_icir = round(fdb_icir, 3),
                        icir_advantage = round(icir - fdb_icir, 3))])
}

# ── 6. Cross-correlation (Samsara 간) ─────────────────────────────
cat("\n[G8-01b] Step 6: Samsara inter-factor correlation...\n")
ic_wide <- dcast(ic_dt, sig_date ~ factor_id, value.var = "ic")
corr_cols <- intersect(samsara_factors, names(ic_wide))
if (length(corr_cols) >= 2) {
  corr_mat <- cor(ic_wide[, ..corr_cols], use = "pairwise.complete.obs")
  cat("  IC Time-Series Correlation:\n")
  print(round(corr_mat, 3))
}

# ── 7. 저장 ──────────────────────────────────────────────────────
out_dir <- "04_Research/korea_research/G8_01_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(summary_dt, file.path(out_dir, "samsara_native_ic.csv"))
fwrite(ic_dt, file.path(out_dir, "samsara_native_ic_monthly.csv"))

cat(sprintf("\n[G8-01b] Complete. Saved to %s/samsara_native_ic.csv\n", out_dir))
