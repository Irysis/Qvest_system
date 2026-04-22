#==============================================================================
# STR_1686 — Factor Engine
# H_1685 v2: Foreign Flow Residualized on Individual Flow (Diversifier)
#
# Mechanism: residual_t(i) = z_F_t(i) - beta_t * z_I_t(i)
#   z_F = cross-section Z of frollsum(Foreign, n=21/63/126) at month-end
#   z_I = cross-section Z of frollsum(Individual, n=21/63/126) at month-end
#   beta_t = expanding pooled OLS, burn-in 60m, shift 1m (C1)
# Reference: Choe-Kho-Stulz 2005 RFS + 고영훈·안일찬 2018
#
# PIT CHECKLIST:
# (1) C1: expanding beta shift=1m, burn-in 60m — cumsum pattern
# (2) C2: month-end signal -> t+1 execution (run_all.R)
# (3) C10: LIQ_THRESHOLD=2e8, frollmean(TradingValue,20) lagged (RAWDATA$LiqPass)
# (4) C11: investor data T+1 lag (QuantiWise daily settlement)
# (5) C13: residual is final signal, no re-Z-score
# (6) OPT-1: investor_wide.parquet loaded once via read_parquet(), no loop
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

cat("[factor_engine H_1685v2] Foreign Resid Individual (INV13)\n")

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

H1685V2_PIT_EVIDENCE <- list(
  factor        = "INV13_Foreign_Resid_Individual (21d/63d/126d)",
  data_source   = "investor_wide.parquet — single read_parquet() call (OPT-1)",
  c1_compliant  = "expanding beta via cumsum, shift=1m, burn-in 60m",
  c2_compliant  = "t+1 execution in run_all.R",
  c10_compliant = "LIQ_THRESHOLD=2e8, frollmean(TradingValue,20) lagged",
  c11_compliant = "investor daily T+1 lag (QuantiWise settlement)",
  c13_compliant = "residual is final signal — no re-Z"
)

# ---- OPT-1: single bulk read_parquet call ----
inv_path <- file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet")
if (!file.exists(inv_path)) stop("[factor_engine] investor_wide.parquet not found")
cat("[factor_engine] Loading investor_wide.parquet (single read)...\n")
INV <- as.data.table(read_parquet(inv_path))
INV[, Date := as.Date(Date)]
# C2/C11: QuantiWise investor data published T+1 (settlement day)
# Apply strict t-1 lag: exclude sig_date itself to avoid same-day circular (C2)
# For each month-end sig_date, only use investor data with Date < sig_date
setkey(INV, Date, Ticker)
cat(sprintf("[factor_engine] INV: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(INV), big.mark=","), uniqueN(INV$Ticker),
            min(INV$Date), max(INV$Date)))

# ---- Month-end signal dates ----
monthend_dates <- RAWDATA[, .(sig_date=max(Date)),
                           by=.(ym=format(Date,"%Y-%m"))]
sig_dates_all <- sort(monthend_dates[sig_date >= as.Date("2004-01-01"), sig_date])
cat(sprintf("[factor_engine] Signal dates: %d (%s ~ %s)\n",
            length(sig_dates_all), min(sig_dates_all), max(sig_dates_all)))

# ---- Rolling sums (OPT-1: by= vectorized, no loop) ----
cat("[factor_engine] Computing frollsum (21/63/126d)...\n")
INV[order(Date), `:=`(
  F_roll21  = frollsum(Foreign,    n=21L,  align="right", na.rm=TRUE),
  F_roll63  = frollsum(Foreign,    n=63L,  align="right", na.rm=TRUE),
  F_roll126 = frollsum(Foreign,    n=126L, align="right", na.rm=TRUE),
  I_roll21  = frollsum(Individual, n=21L,  align="right", na.rm=TRUE),
  I_roll63  = frollsum(Individual, n=63L,  align="right", na.rm=TRUE),
  I_roll126 = frollsum(Individual, n=126L, align="right", na.rm=TRUE)
), by=Ticker]

# ---- Snapshot at month-end dates only (C2/C11: strict t-1 lag) ----
# For each sig_date, find the last trading day strictly BEFORE sig_date.
# QuantiWise investor data is published T+1 — sig_date itself is not yet disclosed.
# Use the most recent Date < sig_date per ticker as the signal snapshot.
snap_list <- lapply(sig_dates_all, function(sd) {
  sub <- INV[Date < sd]
  if (nrow(sub) == 0L) return(NULL)
  last_sub <- sub[, .SD[.N], by=Ticker,
                  .SDcols=c("Date","F_roll21","F_roll63","F_roll126",
                             "I_roll21","I_roll63","I_roll126")]
  last_sub[, sig_date := sd]
  last_sub
})
INV_SNAP <- rbindlist(snap_list[!sapply(snap_list, is.null)], fill=TRUE)
INV_SNAP[, Date := sig_date][, sig_date := NULL]
setnames(INV_SNAP, c("F_roll21","F_roll63","F_roll126","I_roll21","I_roll63","I_roll126"),
                   c("F21","F63","F126","I21","I63","I126"))
setkey(INV_SNAP, Date, Ticker)

# ---- Liquidity filter (C10) ----
LIQ_SNAP <- RAWDATA[Date %in% sig_dates_all & LiqPass==TRUE, .(Date, Ticker)]
INV_SNAP <- INV_SNAP[LIQ_SNAP, on=c("Date","Ticker"), nomatch=NULL]
cat(sprintf("[factor_engine] After LIQ filter: %s rows | %d dates\n",
            format(nrow(INV_SNAP), big.mark=","), uniqueN(INV_SNAP$Date)))

# ---- Cross-section winsorize + Z-score (by=Date vectorized) ----
winsor_std <- function(x) {
  q <- quantile(x, probs=c(0.01,0.99), na.rm=TRUE)
  xw <- pmax(pmin(x, q[2L]), q[1L])
  m <- mean(xw, na.rm=TRUE); s <- sd(xw, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (xw - m) / s
}

INV_SNAP[, `:=`(
  zF21  = winsor_std(F21),  zI21  = winsor_std(I21),
  zF63  = winsor_std(F63),  zI63  = winsor_std(I63),
  zF126 = winsor_std(F126), zI126 = winsor_std(I126)
), by=Date]

# ---- Expanding pooled OLS beta: cumsum approach (no loop, C1) ----
# Sort by Date; compute cumulative numerator/denominator across all tickers
# beta_t = shift(cumsum_num / cumsum_den, 1) — vectorized via cumsum on monthly aggregates
monthly_agg <- INV_SNAP[, .(
  num21  = sum(zF21  * zI21,  na.rm=TRUE),
  den21  = sum(zI21^2,        na.rm=TRUE),
  num63  = sum(zF63  * zI63,  na.rm=TRUE),
  den63  = sum(zI63^2,        na.rm=TRUE),
  num126 = sum(zF126 * zI126, na.rm=TRUE),
  den126 = sum(zI126^2,       na.rm=TRUE)
), by=Date][order(Date)]

monthly_agg[, `:=`(
  cum_num21  = cumsum(num21),  cum_den21  = cumsum(den21),
  cum_num63  = cumsum(num63),  cum_den63  = cumsum(den63),
  cum_num126 = cumsum(num126), cum_den126 = cumsum(den126)
)]

# Raw beta (using all data up to and including t)
monthly_agg[, `:=`(
  beta21_raw  = ifelse(cum_den21  > 1e-10, cum_num21  / cum_den21,  NA_real_),
  beta63_raw  = ifelse(cum_den63  > 1e-10, cum_num63  / cum_den63,  NA_real_),
  beta126_raw = ifelse(cum_den126 > 1e-10, cum_num126 / cum_den126, NA_real_)
)]

# C1 shift=1: use previous month's beta at current month (strict lag)
# burn-in 60m: beta NA until row > 60
BURN_IN <- 60L
monthly_agg[, `:=`(
  beta21  = ifelse(.I > BURN_IN, shift(beta21_raw,  1L), NA_real_),
  beta63  = ifelse(.I > BURN_IN, shift(beta63_raw,  1L), NA_real_),
  beta126 = ifelse(.I > BURN_IN, shift(beta126_raw, 1L), NA_real_)
)]

BETA_DT <- monthly_agg[, .(Date, beta21, beta63, beta126)]
setkey(BETA_DT, Date)
cat(sprintf("[factor_engine] Beta series: %d months | first valid 21d=%s\n",
            nrow(BETA_DT),
            as.character(BETA_DT[!is.na(beta21), min(Date)])))

# ---- Merge beta and compute residuals ----
INV_SNAP <- merge(INV_SNAP, BETA_DT, by="Date", all.x=TRUE)

INV_SNAP[, `:=`(
  resid21  = ifelse(!is.na(beta21),  zF21  - beta21  * zI21,  NA_real_),
  resid63  = ifelse(!is.na(beta63),  zF63  - beta63  * zI63,  NA_real_),
  resid126 = ifelse(!is.na(beta126), zF126 - beta126 * zI126, NA_real_)
)]

n21  <- sum(!is.na(INV_SNAP$resid21))
n63  <- sum(!is.na(INV_SNAP$resid63))
n126 <- sum(!is.na(INV_SNAP$resid126))
cat(sprintf("[factor_engine] Residuals: 21d=%d | 63d=%d | 126d=%d\n", n21, n63, n126))

# ---- FACTORS tables (V1=21d primary, V2=63d, V3=126d) ----
FACTORS    <- INV_SNAP[!is.na(resid21),  .(Date, Ticker, Score=resid21)]
FACTORS_V2 <- INV_SNAP[!is.na(resid63),  .(Date, Ticker, Score=resid63)]
FACTORS_V3 <- INV_SNAP[!is.na(resid126), .(Date, Ticker, Score=resid126)]
setkey(FACTORS,    Date, Ticker)
setkey(FACTORS_V2, Date, Ticker)
setkey(FACTORS_V3, Date, Ticker)

cat(sprintf("[factor_engine] V1(21d)=%d rows | V2(63d)=%d | V3(126d)=%d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3)))

H1685V2_BETA_DT  <- BETA_DT
H1685V2_INV_SNAP <- INV_SNAP
