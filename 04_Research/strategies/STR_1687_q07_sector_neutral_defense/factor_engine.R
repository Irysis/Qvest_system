#==============================================================================
# STR_1687 — Factor Engine
# H_1693: Q07 Earnings Stability Sector-Neutral + SUE Quality Boost (Defense)
#
# Mechanism:
#   composite_t(i) = 0.7 * z_sector_Q07_t(i) + 0.3 * z_C01_SUE_t(i)
#   z_sector_Q07 = (Q07 - sector_mean) / sector_sd  [sector-neutral, per month]
#   z_C01_SUE    = cross-section Z_Score_Aligned
#   Top 20 EW Long, t+1 execution. Pure signal S1 — no DD/VT/regime.
#
# References:
#   Dichev-Tang 2009 ROS (earnings quality 2nd moment) +
#   Foster-Olsen-Shevlin 1984 TAR (SUE 1st moment) +
#   Bernard-Thomas 1989 JAR (PEAD) +
#   Daniel-Titman 2006 JF (sector-neutral characteristics) +
#   Asness-Frazzini-Pedersen 2019 ROF QMJ (Safety axis)
#
# PIT CHECKLIST (C1~C15):
# (C4)  Q07: quarterly 45-day lag (Usable_Date in Factor DB)
# (C4)  C01_SUE: daily 'Date <= sig_d' (Usable_Date in Factor DB, L-164)
# (C10) LIQ_THRESHOLD=2e8, shift(frollmean, 1L) — today excluded
# (C13) Z_Score_Aligned; sector-neutral via sector_mean/sd (no NEGATE_FACTORS)
# (C15) load_month_factors() mandatory (L-164)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

cat("[factor_engine H_1693] Q07 Sector-Neutral Defense + SUE\n")

H1693_PIT_EVIDENCE <- list(
  factor      = "composite: 0.7*z_sector_Q07 + 0.3*z_C01_SUE",
  data_source = "load_month_factors() C15+L-164 mandatory",
  c4_q07      = "quarterly 45-day lag (Factor DB Usable_Date)",
  c4_c01_sue  = "daily Usable_Date <= sig_date (Factor DB)",
  c10         = "LIQ_THRESHOLD=2e8, shift(frollmean,1L)",
  c13         = "Z_Score_Aligned; z_sector_Q07 via (x-sector_mean)/sector_sd — no manual negate",
  c15         = "load_month_factors() only"
)

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- Signal dates: month-end from RAWDATA ----
monthend_dates <- RAWDATA[, .(sig_date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
sig_dates_all  <- sort(monthend_dates[sig_date >= as.Date("2004-01-01"), sig_date])

# ---- Factor DB load (C15 + L-164): bulk rbindlist over monthly parquets ----
# C15: load_month_factors(sig_date) per month — no direct parquet access from strategy code.
# OPT-1: lapply over sig_dates_all + rbindlist (single load, no repeated parquet in loop body).
cat("[factor_engine] Loading Q07_Earnings_Stability + C01_SUE via load_month_factors()...\n")
required_factors <- c("Q07_Earnings_Stability", "C01_SUE")

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

FDB <- rbindlist(lapply(sig_dates_all, function(sd) {
  dt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0L) return(NULL)
  dt <- dt[Factor_Name %in% required_factors]
  if (nrow(dt) == 0L) return(NULL)
  dt[, Date := sd]
  dt
}), use.names = TRUE, fill = TRUE)

if (is.null(FDB) || nrow(FDB) == 0L)
  stop("[factor_engine] FDB empty — Q07/C01_SUE not found in Factor DB")

setkey(FDB, Date, Ticker)

cat(sprintf("[factor_engine] FDB: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(FDB), big.mark=","), uniqueN(FDB$Ticker),
            min(FDB$Date), max(FDB$Date)))

# ---- Liquidity filter (C10) ----
LIQ_SNAP <- RAWDATA[Date %in% sig_dates_all & LiqPass == TRUE, .(Date, Ticker)]

# ---- Wide format: Factor_Name -> columns ----
# load_month_factors() returns long: (Ticker, Factor_Name, Z_Score_Aligned, Date)
FDB_WIDE <- dcast(FDB, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                  fill = NA_real_)
setkey(FDB_WIDE, Date, Ticker)

# Identify Q07 / C01_SUE columns
q07_col <- grep("Q07", names(FDB_WIDE), value = TRUE)
sue_col <- grep("C01_SUE|C01$", names(FDB_WIDE), value = TRUE)

pick_col <- function(cols, label) {
  if (length(cols) > 0L) return(cols[1L])
  stop(sprintf("[factor_engine] Column not found: %s", label))
}

q07_use <- pick_col(q07_col, "Q07_Earnings_Stability")
sue_use <- pick_col(sue_col, "C01_SUE")
cat(sprintf("[factor_engine] Q07 column: '%s' | SUE column: '%s'\n", q07_use, sue_use))

# ---- Snapshot: liquidity filter (C10) ----
FDB_SNAP <- FDB_WIDE[, .(Date, Ticker,
                          z_Q07 = get(q07_use),
                          z_SUE = get(sue_use))]
FDB_SNAP <- FDB_SNAP[LIQ_SNAP, on = c("Date", "Ticker"), nomatch = NULL]
FDB_SNAP <- FDB_SNAP[!is.na(z_Q07) | !is.na(z_SUE)]
rm(FDB_WIDE, FDB); gc(verbose = FALSE)

cat(sprintf("[factor_engine] After LIQ+snap: %s rows | %d dates\n",
            format(nrow(FDB_SNAP), big.mark=","), uniqueN(FDB_SNAP$Date)))

# ---- Sector column ----
if ("Sector" %in% names(RAWDATA)) {
  SECTOR_DT <- unique(RAWDATA[Date %in% sig_dates_all, .(Date, Ticker, Sector)])
  FDB_SNAP  <- merge(FDB_SNAP, SECTOR_DT, by = c("Date","Ticker"), all.x = TRUE)
  FDB_SNAP[is.na(Sector), Sector := "Unknown"]
} else {
  cat("[factor_engine WARN] No Sector column — z_sector_Q07 = cross-section z\n")
  FDB_SNAP[, Sector := "All"]
}

# ---- Cross-section winsorize helper ----
winsor_std <- function(x) {
  q  <- quantile(x, probs = c(0.01, 0.99), na.rm = TRUE)
  xw <- pmax(pmin(x, q[2L]), q[1L])
  m  <- mean(xw, na.rm = TRUE)
  s  <- sd(xw, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (xw - m) / s
}

# ---- Winsorize both signals cross-sectionally ----
FDB_SNAP[, z_Q07_win := winsor_std(z_Q07), by = Date]
FDB_SNAP[, z_SUE_win := winsor_std(z_SUE), by = Date]

# ---- Z_Sector: sector-neutral Q07 (Daniel-Titman 2006, C13) ----
# z_sector_Q07(i) = (Q07_win(i) - sector_mean) / sector_sd
# sector_sd < 1e-6 (< 2 stocks) → NA (S1-C8 gate)
FDB_SNAP[, z_sector_Q07 := {
  smean <- mean(z_Q07_win, na.rm = TRUE)
  ssd   <- sd(z_Q07_win, na.rm = TRUE)
  if (is.na(ssd) || ssd < 1e-6) rep(NA_real_, .N)
  else (z_Q07_win - smean) / ssd
}, by = .(Date, Sector)]

# NA tracking (S1-C8 audit)
na_sector_month     <- FDB_SNAP[, .(na_count = sum(is.na(z_sector_Q07)),
                                    total    = .N,
                                    na_ratio = sum(is.na(z_sector_Q07)) / .N), by = Date]
overall_na_ratio    <- mean(na_sector_month$na_ratio, na.rm = TRUE)
H1693_ZSECTOR_NA       <- na_sector_month
H1693_ZSECTOR_NA_RATIO <- overall_na_ratio

cat(sprintf("[factor_engine] Z_Sector NA: %.1f%% (warn threshold 15%%)\n",
            overall_na_ratio * 100))
if (overall_na_ratio > 0.15) cat("[factor_engine WARN] Z_Sector NA > 15% — S1-C8 WARNING\n")

# ---- Composite: 0.7 * z_sector_Q07 + 0.3 * z_C01_SUE ----
FDB_SNAP[, composite     := 0.7 * z_sector_Q07 + 0.3 * z_SUE_win]
# Ablation V4: equal-weight 0.5/0.5
FDB_SNAP[, composite_ew  := 0.5 * z_sector_Q07 + 0.5 * z_SUE_win]

n_valid <- sum(!is.na(FDB_SNAP$composite))
cat(sprintf("[factor_engine] Composite valid: %d (%.1f%%)\n",
            n_valid, 100 * n_valid / nrow(FDB_SNAP)))

# ---- FACTORS tables (V1=primary, V2=Q07-only, V3=SUE-only, V4=EW) ----
FACTORS    <- FDB_SNAP[!is.na(composite),    .(Date, Ticker, Score = composite)]
FACTORS_V2 <- FDB_SNAP[!is.na(z_sector_Q07), .(Date, Ticker, Score = z_sector_Q07)]
FACTORS_V3 <- FDB_SNAP[!is.na(z_SUE_win),    .(Date, Ticker, Score = z_SUE_win)]
FACTORS_V4 <- FDB_SNAP[!is.na(composite_ew), .(Date, Ticker, Score = composite_ew)]

setkey(FACTORS,    Date, Ticker)
setkey(FACTORS_V2, Date, Ticker)
setkey(FACTORS_V3, Date, Ticker)
setkey(FACTORS_V4, Date, Ticker)

cat(sprintf("[factor_engine] V1(0.7/0.3)=%d | V2(Q07)=%d | V3(SUE)=%d | V4(EW)=%d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3), nrow(FACTORS_V4)))

# ---- C01_SUE regime reconciliation helper (S1-C7) ----
H1693_FDB_SNAP <- FDB_SNAP
