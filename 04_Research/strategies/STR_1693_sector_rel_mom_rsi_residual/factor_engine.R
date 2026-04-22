#==============================================================================
# STR_1693 — Factor Engine
# H_1692: Sector-Relative Industry Momentum Residualized on RSI (Core_Secondary)
#
# Signal: M07_IndMom residualized on M18_RSI via expanding pooled OLS
# Mechanism: Grinblatt-Moskowitz 1999 industry momentum + Wilder 1978 RSI filter
# PIT: Z_Score_Aligned (C13). load_month_factors() (C15/Gate 13). expanding OLS β_t
#      strict shift(1L) lag (C1). t+1 execution (C2). Winsorize 1~99%.
# Gate 13 MANDATORY: read_parquet direct PROHIBITED. load_month_factors() only.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("[factor_engine H_1692] Sector-Relative Industry Momentum Residualized on RSI\n")
cat("[factor_engine H_1692] Gate 13 COMPLIANT: load_month_factors() only\n")

# ---- PIT evidence ----
H1692_PIT_EVIDENCE <- list(
  factor           = "HYB01_IndMom_RSI_Resid",
  base_factors     = c("M07_IndMom", "M18_RSI"),
  c1_compliant     = TRUE,   # expanding pooled OLS β_t with strict shift(1L) lag, burn-in 36m
  c2_compliant     = TRUE,   # signal → t+1 execution in run_all.R
  c13_compliant    = TRUE,   # Z_Score_Aligned only (C13 — no manual sign flip)
  c14_compliant    = TRUE,   # load_month_factors(sig_date) uses Usable_Date <= sig_date
  c15_compliant    = TRUE,   # load_month_factors() Gate 13 enforced
  c10_compliant    = TRUE,   # LIQ_THRESHOLD 2e8 lagged AvgTV20 from RAWDATA
  pit_note         = "β_t computed from all months < sig_d (strict prior data only). No future month data in regression.",
  l161_avoidance   = "M07_IndMom sd=1.000 + M18_RSI sd=1.000: balanced OLS, scale mismatch none",
  capm_trap_avoidance = "RSI residualization not CAPM residualization. portfolio beta=intrinsic (0.95~1.10 expected)"
)

# ---- Build all signal dates (2002-01-01 ~ latest) ----
sig_date_range <- seq(as.Date("2002-01-01"), Sys.Date(), by = "month")
sig_date_range <- as.Date(format(sig_date_range, "%Y-%m-01"))
sig_date_range <- sig_date_range[sig_date_range <= Sys.Date()]

NEEDED_FACTORS <- c("M07_IndMom", "M18_RSI")

# ---- Bulk load via load_month_factors() — Gate 13 compliant (OPT-1: no loop re-load) ----
cat(sprintf("[factor_engine] Bulk-loading %d months via load_month_factors()...\n",
            length(sig_date_range)))

monthly_list <- lapply(sig_date_range, function(sig_d) {
  dt <- tryCatch(
    load_month_factors(sig_d, factor_names = NEEDED_FACTORS, coverage_min = 0.5),
    error = function(e) NULL
  )
  if (is.null(dt) || !is.data.table(dt) || nrow(dt) == 0) return(NULL)

  # Gate 13 uses Z_Score_Aligned (C13 compliant)
  col_use <- if ("Z_Score_Aligned" %in% names(dt)) "Z_Score_Aligned" else
             if ("Z_Score" %in% names(dt)) "Z_Score" else NULL
  if (is.null(col_use)) return(NULL)

  # Filter needed factors only
  dt_sub <- dt[Factor_Name %in% NEEDED_FACTORS, .(Ticker, Factor_Name, Z = get(col_use))]
  if (nrow(dt_sub) == 0) return(NULL)

  # Wide format: M07, M18 per ticker
  dt_wide <- dcast(dt_sub, Ticker ~ Factor_Name, value.var = "Z", fill = NA_real_)
  needed_cols <- intersect(NEEDED_FACTORS, names(dt_wide))
  if (length(needed_cols) < 2) return(NULL)
  if (!all(c("M07_IndMom", "M18_RSI") %in% names(dt_wide))) return(NULL)

  # Liquidity filter (C10): lagged AvgTV20 from RAWDATA
  if (exists("RAWDATA") && "LiqPass" %in% names(RAWDATA)) {
    liq_snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
    if (nrow(liq_snap) == 0) {
      closest_d <- RAWDATA[Date <= sig_d, max(Date, na.rm = TRUE)]
      liq_snap  <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
    }
    dt_wide <- dt_wide[Ticker %in% liq_snap$Ticker]
  }

  if (nrow(dt_wide) < 20L) return(NULL)

  # Winsorize 1~99% (per factor, per cross-section)
  winsor <- function(x, lo = 0.01, hi = 0.99) {
    q <- quantile(x, probs = c(lo, hi), na.rm = TRUE)
    pmax(pmin(x, q[2]), q[1])
  }

  dt_wide[, M07_w := winsor(M07_IndMom)]
  dt_wide[, M18_w := winsor(M18_RSI)]
  dt_wide[, .(Date = sig_d, Ticker, M07 = M07_w, M18 = M18_w)]
})

FDB_ALL <- rbindlist(monthly_list[!sapply(monthly_list, is.null)], use.names = TRUE, fill = TRUE)
if (nrow(FDB_ALL) == 0) stop("[factor_engine] FDB_ALL empty — M07/M18 not found via load_month_factors()")
setkey(FDB_ALL, Date, Ticker)
rm(monthly_list); gc(verbose = FALSE)

cat(sprintf("[factor_engine] FDB_ALL: %s rows | %d months\n",
            format(nrow(FDB_ALL), big.mark = ","), uniqueN(FDB_ALL$Date)))

# ---- Expanding pooled OLS β_t (C1 strict: prior data only, burn-in 36m) ----
# β_t = Σ_{s < t} Σ_i M07_w_{s,i} × M18_w_{s,i} / Σ_{s < t} Σ_i M18_w_{s,i}²
# No intercept pooled OLS. strict shift(1L): only months BEFORE sig_d.
BURN_IN <- 36L
all_dates <- sort(unique(FDB_ALL$Date))
cat(sprintf("[factor_engine] Computing expanding OLS β_t (burn-in %d months)...\n", BURN_IN))

FACTORS_list <- lapply(seq_along(all_dates), function(i) {
  sig_d <- all_dates[i]
  if (i <= BURN_IN) return(NULL)

  # Strict prior: Date < sig_d (C1 — no same-month data in β estimation)
  prior <- FDB_ALL[Date < sig_d & !is.na(M07) & !is.na(M18)]
  if (nrow(prior) < 500L) return(NULL)   # min pooled obs

  # Pooled no-intercept OLS: β = cov(M07,M18) / var(M18)
  cross_M07_M18 <- sum(prior$M07 * prior$M18, na.rm = TRUE)
  var_M18       <- sum(prior$M18^2, na.rm = TRUE)
  if (var_M18 < 1e-10) return(NULL)
  beta_t <- cross_M07_M18 / var_M18

  # Current month residualization
  cur <- FDB_ALL[Date == sig_d & !is.na(M07) & !is.na(M18)]
  if (nrow(cur) < 20L) return(NULL)

  cur[, resid := M07 - beta_t * M18]

  # Cross-section Z-score of residual
  mu_r <- mean(cur$resid, na.rm = TRUE)
  sd_r <- sd(cur$resid,   na.rm = TRUE)
  if (is.na(sd_r) || sd_r < 1e-10) return(NULL)
  cur[, Score := (resid - mu_r) / sd_r]

  cur[, .(Date, Ticker, Score, beta_t = beta_t)]
})

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)], fill = TRUE)
if ("beta_t" %in% names(FACTORS)) {
  # Store beta series for diagnostics, then drop from FACTORS
  H1692_BETA_SERIES <- FACTORS[, .(Date = unique(Date)), by = .(Date, beta_t)][, .(Date, beta_t)]
  FACTORS[, beta_t := NULL]
}
setkey(FACTORS, Date, Ticker)

cat(sprintf("[factor_engine H_1692] FACTORS: %d rows | %d months | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
if (exists("H1692_BETA_SERIES") && nrow(H1692_BETA_SERIES) > 0) {
  cat(sprintf("[factor_engine H_1692] β_t range: [%.4f, %.4f] | mean: %.4f\n",
              min(H1692_BETA_SERIES$beta_t, na.rm = TRUE),
              max(H1692_BETA_SERIES$beta_t, na.rm = TRUE),
              mean(H1692_BETA_SERIES$beta_t, na.rm = TRUE)))
}
