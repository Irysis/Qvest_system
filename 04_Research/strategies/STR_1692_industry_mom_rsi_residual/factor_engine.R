#==============================================================================
# STR_1692 — Factor Engine
# H_1692 v2: Sector-Relative Industry Momentum Residualized on RSI (Core_Secondary)
#
# Mechanism: residual_t(i) = z_M07_t(i) - beta_t * z_M18_t(i)
#   z_M07 = cross-section winsorize+z of M07_IndMom at month-end t
#   z_M18 = cross-section winsorize+z of M18_RSI at month-end t
#   beta_t = expanding pooled no-intercept OLS, shift=1m (C1), burn-in 36m
#   z_residual = cross-section z of residual (signal for Top 20 EW Long)
#
# References:
#   Grinblatt-Moskowitz 1999 JF (industry momentum) +
#   Wilder 1978 RSI + Lee-Swaminathan 2000 JF +
#   Barberis-Shleifer 2003 JFE + Hanauer-Huber 2019 EMR
#
# PIT CHECKLIST (C1~C15):
# (C1)  expanding beta shift=1m, burn-in 36m — cumsum pooled OLS
# (C2)  month-end signal → t+1 execution (run_all.R)
# (C10) LIQ_THRESHOLD=2e8, shift(frollmean,1L) via RAWDATA$LiqPass
# (C13) Z_Score_Aligned via load_month_factors; residual final signal, no re-negate
# (C15) load_month_factors() mandatory (L-164)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

cat("[factor_engine H_1692v2] Industry Mom RSI Residual (Core_Secondary)\n")

H1692V2_PIT_EVIDENCE <- list(
  factor       = "HYB01_IndMom_RSI_Resid_v2",
  data_source  = "load_month_factors() C15+L-164 mandatory",
  c1_compliant = "expanding beta via cumsum pooled OLS, shift=1m, burn-in 36m",
  c2_compliant = "t+1 execution in run_all.R",
  c10_compliant = "LIQ_THRESHOLD=2e8, shift(frollmean,1L) via RAWDATA$LiqPass",
  c13_compliant = "Z_Score_Aligned from Factor DB; residual is final signal, no manual negate",
  c15_compliant = "load_month_factors() only"
)

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- Signal dates: month-end from RAWDATA ----
monthend_dates <- RAWDATA[, .(sig_date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
sig_dates_all  <- sort(monthend_dates[sig_date >= as.Date("2004-01-01"), sig_date])

# ---- Factor DB load (C15 + L-164): bulk rbindlist over monthly parquets ----
cat("[factor_engine] Loading M07_IndMom + M18_RSI via load_month_factors()...\n")
required_factors <- c("M07_IndMom", "M18_RSI")

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
  stop("[factor_engine] FDB empty — M07/M18 not found in Factor DB")

setkey(FDB, Date, Ticker)
cat(sprintf("[factor_engine] FDB: %s rows | %d dates\n",
            format(nrow(FDB), big.mark=","), uniqueN(FDB$Date)))

# ---- Wide format ----
FDB_WIDE <- dcast(FDB, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                  fill = NA_real_)
setkey(FDB_WIDE, Date, Ticker)
rm(FDB); gc(verbose = FALSE)

m07_col <- grep("M07", names(FDB_WIDE), value = TRUE)[1L]
m18_col <- grep("M18", names(FDB_WIDE), value = TRUE)[1L]
if (is.na(m07_col) || is.na(m18_col))
  stop(sprintf("[factor_engine] Missing columns: M07=%s M18=%s", m07_col, m18_col))
cat(sprintf("[factor_engine] M07 col: '%s' | M18 col: '%s'\n", m07_col, m18_col))

# ---- Liquidity filter (C10) ----
LIQ_SNAP <- RAWDATA[Date %in% sig_dates_all & LiqPass == TRUE, .(Date, Ticker)]

FDB_SNAP <- FDB_WIDE[, .(Date, Ticker, z_M07 = get(m07_col), z_M18 = get(m18_col))]
FDB_SNAP <- FDB_SNAP[LIQ_SNAP, on = c("Date", "Ticker"), nomatch = NULL]
FDB_SNAP <- FDB_SNAP[!is.na(z_M07) & !is.na(z_M18)]
rm(FDB_WIDE); gc(verbose = FALSE)

cat(sprintf("[factor_engine] After LIQ filter: %s rows | %d dates\n",
            format(nrow(FDB_SNAP), big.mark=","), uniqueN(FDB_SNAP$Date)))

# ---- Cross-section winsorize (applied on top of Z_Score_Aligned) ----
winsor_cs <- function(x) {
  q  <- quantile(x, probs = c(0.01, 0.99), na.rm = TRUE)
  pmax(pmin(x, q[2L]), q[1L])
}
FDB_SNAP[, z_M07 := winsor_cs(z_M07), by = Date]
FDB_SNAP[, z_M18 := winsor_cs(z_M18), by = Date]

# ---- Expanding pooled OLS beta (C1: cumsum, shift=1, burn-in 36m) ----
monthly_agg <- FDB_SNAP[, .(
  num = sum(z_M07 * z_M18, na.rm = TRUE),
  den = sum(z_M18^2,       na.rm = TRUE)
), by = Date][order(Date)]

monthly_agg[, `:=`(cum_num = cumsum(num), cum_den = cumsum(den))]
monthly_agg[, beta_raw := ifelse(cum_den > 1e-10, cum_num / cum_den, NA_real_)]

BURN_IN <- 36L
monthly_agg[, beta := ifelse(.I > BURN_IN, shift(beta_raw, 1L), NA_real_)]

BETA_DT <- monthly_agg[, .(Date, beta)]
setkey(BETA_DT, Date)
cat(sprintf("[factor_engine] Beta series: first valid=%s | latest=%.4f\n",
            as.character(BETA_DT[!is.na(beta), min(Date)]),
            BETA_DT[!is.na(beta), tail(beta, 1)]))

# ---- Structural break audit (S1-C3 action_3) ----
monthly_agg[, period := fcase(
  Date <  as.Date("2008-01-01"), "pre_2008",
  Date <  as.Date("2020-01-01"), "mid_2008_2019",
  default = "post_2020"
)]
beta_by_period <- monthly_agg[!is.na(beta_raw), .(
  mean_beta = mean(beta_raw, na.rm = TRUE),
  sd_beta   = sd(beta_raw,   na.rm = TRUE),
  n         = .N
), by = period]
H1692V2_BETA_BY_PERIOD <- beta_by_period
cat("[factor_engine] Beta by period:\n"); print(beta_by_period)

# ---- Merge beta + compute residuals ----
FDB_SNAP <- merge(FDB_SNAP, BETA_DT, by = "Date", all.x = TRUE)
FDB_SNAP[, residual := ifelse(!is.na(beta), z_M07 - beta * z_M18, NA_real_)]

# ---- z_residual cross-section (final signal) ----
zscore_cs <- function(x) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - m) / s
}
FDB_SNAP[!is.na(residual), z_residual := zscore_cs(residual), by = Date]

n_valid <- sum(!is.na(FDB_SNAP$z_residual))
cat(sprintf("[factor_engine] z_residual valid: %d rows | %d dates\n",
            n_valid, uniqueN(FDB_SNAP[!is.na(z_residual), Date])))

# ---- FACTORS: V1 primary (residual), V2 M07-only, V3 M18-aligned ----
# C13: Z_Score_Aligned 직접 사용. Score = -z_M18 FLIP_SIGN 금지.
# M18_RSI Z_Score_Aligned 방향: load_month_factors()가 이미 PIT-aligned 반환.
FACTORS    <- FDB_SNAP[!is.na(z_residual), .(Date, Ticker, Score = z_residual)]
FACTORS_V2 <- FDB_SNAP[!is.na(z_M07),     .(Date, Ticker, Score = z_M07)]
FACTORS_V3 <- FDB_SNAP[!is.na(z_M18),     .(Date, Ticker, Score = z_M18)]

setkey(FACTORS,    Date, Ticker)
setkey(FACTORS_V2, Date, Ticker)
setkey(FACTORS_V3, Date, Ticker)

cat(sprintf("[factor_engine] V1(residual)=%d | V2(M07-only)=%d | V3(M18-neg)=%d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3)))

H1692V2_FDB_SNAP <- FDB_SNAP
H1692V2_BETA_DT  <- BETA_DT
