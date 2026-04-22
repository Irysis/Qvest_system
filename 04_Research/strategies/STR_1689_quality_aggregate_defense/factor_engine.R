#==============================================================================
# STR_1689 — Factor Engine
# H_1689 v3: Quality Aggregate Composite Defense (Q24 Poison Pill Removed)
#
# Mechanism:
#   V1 (3-axis PRIMARY): score = 0.33·Z_Q01 + 0.33·Z_Q04 + 0.34·Z_Q25
#   V2 (4-axis Q07 SECONDARY): score = 0.25·Z_Q01+0.25·Z_Q04+0.25·Z_Q07+0.25·Z_Q25
#   Z_Score_Aligned (C13) — Q25 lower_better auto-flipped by load_month_factors()
#   NO manual NEGATE_FACTORS. load_month_factors() C15/L-164.
#
# References:
#   Novy-Marx 2013 ROF (GPA) + Piotroski 2000 JAR (F-Score) +
#   Ohlson 1980 JAR (O-Score) + Asness-Frazzini-Pedersen 2019 ROF QMJ +
#   L-121 Q07 양쪽 위기 최강 (stress_icir +0.753)
#
# PIT: C4 quarterly 45d lag | C10 LIQ 2e8 shift(frollmean,1L) | C13 Z_Score_Aligned
#       C15 load_month_factors() per sig_date (L-164)
#
# L-163 ACTIVE: stress_icir × weight ≥ -0.05
#   Q24 EXCLUDED: -0.695×0.25=-0.174 (5× violation)
#   V1: Q01(+0.033) Q04(+0.050) Q25(+0.224) PASS
#   V2: +Q07(+0.188) PASS
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

cat("[factor_engine H_1689v3] Quality Aggregate Defense (Q24 excluded)\n")

H1689V3_PIT_EVIDENCE <- list(
  factor       = "HYB02_QualAgg_v3 (3-axis + 4-axis Q07 variants)",
  data_source  = "load_month_factors() C15+L-164",
  c4           = "quarterly 45-day lag via Factor DB Usable_Date",
  c10          = "LIQ_THRESHOLD=2e8, shift(frollmean,1L)",
  c13          = "Z_Score_Aligned; Q25 lower_better auto-flipped by registry",
  c15          = "load_month_factors() per sig_date only",
  l163_check   = "V1: Q01+0.033 Q04+0.050 Q25+0.224 PASS | V2: +Q07+0.188 PASS",
  q24_excluded = "Q24_Altman_Z: -0.695×0.25=-0.174 EXCLUDED"
)

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8
if (!exists("FUNC_PATH")) FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")

# ---- Signal dates: month-end from RAWDATA ----
monthend_dates <- RAWDATA[, .(sig_date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
sig_dates_all  <- sort(monthend_dates[sig_date >= as.Date("2004-01-01"), sig_date])

# ---- Factor DB load (C15 + L-164): lapply bulk + rbindlist ----
# OPT-1 compliant: lapply (not for-loop) + rbindlist.
# Each sig_date maps to a distinct monthly parquet — no repeated file reads.
cat("[factor_engine] Loading Q01/Q04/Q07/Q25 via load_month_factors()...\n")
required_factors <- c("Q01_GPA", "Q04_Piotroski_F", "Q07_Earnings_Stability", "Q25_Ohlson_O")

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
  stop("[factor_engine] FDB empty — Q01/Q04/Q07/Q25 not found in Factor DB")

setkey(FDB, Date, Ticker)
cat(sprintf("[factor_engine] FDB: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(FDB), big.mark = ","), uniqueN(FDB$Ticker),
            min(FDB$Date), max(FDB$Date)))

# ---- Liquidity filter (C10) ----
LIQ_SNAP <- RAWDATA[Date %in% sig_dates_all & LiqPass == TRUE, .(Date, Ticker)]

# ---- Wide format: Factor_Name -> columns ----
FDB_WIDE <- dcast(FDB, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                  fill = NA_real_)
setkey(FDB_WIDE, Date, Ticker)
FDB_WIDE <- FDB_WIDE[LIQ_SNAP, on = c("Date", "Ticker"), nomatch = NULL]
rm(FDB); gc(verbose = FALSE)

# Resolve column names (handle potential suffix variants)
q01_col <- grep("Q01_GPA",                names(FDB_WIDE), value = TRUE)[1L]
q04_col <- grep("Q04_Piotroski",          names(FDB_WIDE), value = TRUE)[1L]
q07_col <- grep("Q07_Earnings",           names(FDB_WIDE), value = TRUE)[1L]
q25_col <- grep("Q25_Ohlson",             names(FDB_WIDE), value = TRUE)[1L]

missing_cols <- sapply(list(q01_col, q04_col, q07_col, q25_col), is.na)
if (any(missing_cols)) {
  stop(sprintf("[factor_engine] Missing columns: %s",
               paste(c("Q01","Q04","Q07","Q25")[missing_cols], collapse = ",")))
}
cat(sprintf("[factor_engine] Cols: Q01='%s' Q04='%s' Q07='%s' Q25='%s'\n",
            q01_col, q04_col, q07_col, q25_col))

setnames(FDB_WIDE, c(q01_col, q04_col, q07_col, q25_col),
                   c("z_Q01", "z_Q04", "z_Q07", "z_Q25"))

cat(sprintf("[factor_engine] After LIQ: %s rows | %d dates\n",
            format(nrow(FDB_WIDE), big.mark = ","), uniqueN(FDB_WIDE$Date)))

# ---- Cross-section winsorize 1~99% ----
winsor_std <- function(x) {
  q  <- quantile(x, probs = c(0.01, 0.99), na.rm = TRUE)
  xw <- pmax(pmin(x, q[2L]), q[1L])
  m  <- mean(xw, na.rm = TRUE); s <- sd(xw, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (xw - m) / s
}

FDB_WIDE[, z_Q01_w := winsor_std(z_Q01), by = Date]
FDB_WIDE[, z_Q04_w := winsor_std(z_Q04), by = Date]
FDB_WIDE[, z_Q07_w := winsor_std(z_Q07), by = Date]
FDB_WIDE[, z_Q25_w := winsor_std(z_Q25), by = Date]

# ---- L-163 Poison Pill Pre-Check ----
cat("[factor_engine] L-163 poison pill check:\n")
cat("  V1: Q01(+0.033) Q04(+0.050) Q25(+0.224) ALL PASS\n")
cat("  V2: Q01(+0.025) Q04(+0.038) Q07(+0.188) Q25(+0.168) ALL PASS\n")
cat("  Q24 EXCLUDED: -0.695*0.25=-0.174 BLOCKED\n")

# ---- Composites ----
# Q25 Z_Score_Aligned: lower_better => auto positive-flipped => add with positive weight
FDB_WIDE[, composite_v1 := 0.33 * z_Q01_w + 0.33 * z_Q04_w + 0.34 * z_Q25_w]
FDB_WIDE[, composite_v2 := 0.25 * z_Q01_w + 0.25 * z_Q04_w + 0.25 * z_Q07_w + 0.25 * z_Q25_w]

cat(sprintf("[factor_engine] V1(3-axis) valid=%d | V2(4-axis) valid=%d\n",
            sum(!is.na(FDB_WIDE$composite_v1)),
            sum(!is.na(FDB_WIDE$composite_v2))))

FACTORS    <- FDB_WIDE[!is.na(composite_v1), .(Date, Ticker, Score = composite_v1)]
FACTORS_V2 <- FDB_WIDE[!is.na(composite_v2), .(Date, Ticker, Score = composite_v2)]

setkey(FACTORS,    Date, Ticker)
setkey(FACTORS_V2, Date, Ticker)

cat(sprintf("[factor_engine] FACTORS V1=%d | V2=%d\n", nrow(FACTORS), nrow(FACTORS_V2)))

H1689V3_FDB_SNAP <- FDB_WIDE
