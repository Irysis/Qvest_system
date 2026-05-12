#==============================================================================
# RF-A7 + Codex C1 fix: Multi-sig-date alpha_scores.parquet (Date x Ticker x score)
# RF-A4 + Codex C5 fix: post-neutralization IC 정량 측정
# 60+ sig_dates 보장 (Codex rebuttal 1)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

cat("[RF-A7 fix] Building multi-sig-date alpha_scores.parquet\n")

rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setkey(rd, Date, Ticker)
rd[, in_univ := (K200 == 1 | KQ150 == 1)]
rd[is.na(in_univ), in_univ := FALSE]
rd[, ym := format(Date, "%Y-%m")]
month_ends <- rd[, .(month_end = max(Date)), by = ym]
rd_me <- merge(rd, month_ends, by = "ym")
rd_me <- rd_me[Date == month_end & in_univ == TRUE & !is.na(Sector),
               .(Date, Ticker, Close, Sector, Size, K200, KQ150)]
rd_me[, Size := as.numeric(Size)]
setkey(rd_me, Date, Ticker)

# Monthly stock returns
rd_me[, ret_1m := Close / shift(Close, 1) - 1, by = Ticker]
rd_me[, w_size_lag := shift(Size, 1), by = Ticker]
rd_me <- rd_me[!is.na(ret_1m) & !is.na(w_size_lag) & w_size_lag > 0]

# Sector value-weighted returns
sector_ret <- rd_me[, .(
  ret_sector_vw = sum(ret_1m * w_size_lag, na.rm=TRUE) / sum(w_size_lag, na.rm=TRUE),
  n_stocks = .N
), by = .(Date, Sector)]
sector_ret <- sector_ret[n_stocks >= 3]
setkey(sector_ret, Sector, Date)

# 12-1 momentum
compute_mom <- function(returns, lookback=12, skip=1) {
  n <- length(returns); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    win_start <- i - lookback + 1; win_end <- i - skip
    if (win_start < 1 || win_end < win_start) next
    r <- returns[win_start:win_end]
    if (any(is.na(r))) next
    out[i] <- prod(1 + r) - 1
  }
  out
}
sector_ret[, mom_12_1 := compute_mom(ret_sector_vw), by = Sector]

# Date list (60+ sig_dates required, use 2020-01 to 2026-05 = 77 months for clean Date column)
all_dates <- sort(unique(sector_ret$Date[!is.na(sector_ret$mom_12_1)]))
# Use last 84 months for diversity
sig_dates <- tail(all_dates, 84)
cat("Multi-sig-date:", length(sig_dates), "dates from", as.character(min(sig_dates)),
    "to", as.character(max(sig_dates)), "\n")

# Build per-date alpha
build_alpha_at <- function(sig_d) {
  # sector mom at sig_d
  sm <- sector_ret[Date == sig_d, .(Sector, mom_12_1)]
  if (nrow(sm) == 0 || all(is.na(sm$mom_12_1))) return(NULL)
  # stock universe at sig_d
  ss <- rd_me[Date == sig_d, .(Ticker, Sector)]
  joined <- merge(ss, sm, by = "Sector")
  joined <- joined[!is.na(mom_12_1)]
  if (nrow(joined) == 0) return(NULL)
  # cross-section z
  mu <- mean(joined$mom_12_1); sg <- sd(joined$mom_12_1)
  if (is.na(sg) || sg == 0) return(NULL)
  joined[, alpha_z := (mom_12_1 - mu) / sg]
  joined[, sig_date := sig_d]
  joined[, .(sig_date, Ticker, Sector, mom_12_1, alpha_z)]
}

alpha_panel <- rbindlist(lapply(sig_dates, build_alpha_at), use.names = TRUE, fill = TRUE)
setnames(alpha_panel, "sig_date", "Date")
setkey(alpha_panel, Date, Ticker)
cat("Alpha panel rows:", nrow(alpha_panel), " unique dates:", uniqueN(alpha_panel$Date),
    " unique tickers:", uniqueN(alpha_panel$Ticker), "\n")

# Scale alpha_hat with universe std return × full-sample IC
xs_std <- sd(rd_me$ret_1m, na.rm=TRUE)
ic_full <- 0.0243  # full sample
alpha_panel[, alpha_hat := alpha_z * ic_full * xs_std]

# Write multi-sig-date parquet (Date x Ticker x score)
write_parquet(alpha_panel, "stage_artifacts/WT_D20260508_008/alpha_scores.parquet")
cat("✅ Multi-sig-date alpha_scores.parquet:", nrow(alpha_panel), "rows × 5 cols\n")

#==============================================================================
# RF-A4 + Codex C5 fix: post-neutralization IC (sector-neutral + size-neutral)
#==============================================================================
cat("\n[RF-A4 fix] Computing post-neutralization IC ...\n")

# Add forward 1m return at sig_date for IC
rd_me[, ret_fwd := shift(ret_1m, -1), by = Ticker]
rd_me_fwd <- rd_me[, .(Date, Ticker, ret_fwd)]
ap <- merge(alpha_panel, rd_me_fwd, by = c("Date", "Ticker"))
ap <- ap[!is.na(ret_fwd) & !is.na(alpha_z)]

# Raw IC per Date
ic_raw_panel <- ap[, .(ic_raw = cor(alpha_z, ret_fwd, method="spearman")), by=Date]
cat("Raw IC mean:", round(mean(ic_raw_panel$ic_raw, na.rm=TRUE), 4),
    "  ICIR:", round(mean(ic_raw_panel$ic_raw, na.rm=TRUE)/sd(ic_raw_panel$ic_raw, na.rm=TRUE), 4), "\n")

# Sector-neutral: demean within sector at each Date
ap[, alpha_sn := alpha_z - mean(alpha_z, na.rm=TRUE), by=.(Date, Sector)]
# When sector has only 1 stock, alpha_sn = 0; remove
ap[, n_in_sec := .N, by=.(Date, Sector)]
ap_sn <- ap[n_in_sec >= 2]
ic_sn_panel <- ap_sn[, .(ic_sn = cor(alpha_sn, ret_fwd, method="spearman")), by=Date]
ic_sn_mean <- mean(ic_sn_panel$ic_sn, na.rm=TRUE)
ic_sn_icir <- mean(ic_sn_panel$ic_sn, na.rm=TRUE)/sd(ic_sn_panel$ic_sn, na.rm=TRUE)
cat("Post-sector-neutral IC mean:", round(ic_sn_mean, 4),
    "  ICIR:", round(ic_sn_icir, 4), "\n")

# Sector + size neutral: regress alpha_z on log(size) within each (Date, Sector), residual
sz <- rd_me[, .(Date, Ticker, log_size = log(pmax(Size, 1)))]
ap2 <- merge(ap, sz, by = c("Date", "Ticker"))
# For each Date, regress alpha_z ~ log_size + Sector dummies
do_resid <- function(x) {
  # x: subset of ap2 at Date
  if (nrow(x) < 30) return(rep(NA_real_, nrow(x)))
  fit <- tryCatch(lm(alpha_z ~ log_size + factor(Sector), data = x), error = function(e) NULL)
  if (is.null(fit)) return(rep(NA_real_, nrow(x)))
  residuals(fit)
}
ap2[, alpha_neut := do_resid(.SD), by = Date]
ic_neut_panel <- ap2[!is.na(alpha_neut), .(ic_neut = cor(alpha_neut, ret_fwd, method="spearman")), by=Date]
ic_neut_mean <- mean(ic_neut_panel$ic_neut, na.rm=TRUE)
ic_neut_icir <- mean(ic_neut_panel$ic_neut, na.rm=TRUE)/sd(ic_neut_panel$ic_neut, na.rm=TRUE)
cat("Post-sector+size-neutral IC mean:", round(ic_neut_mean, 4),
    "  ICIR:", round(ic_neut_icir, 4), "\n")

# RF-A4: post-neut IC < 0.3 * raw_IC
raw_ic_local <- mean(ic_raw_panel$ic_raw, na.rm=TRUE)
rf_a4_threshold <- 0.3 * raw_ic_local
cat("\nRF-A4 audit:\n")
cat(" raw IC:", round(raw_ic_local, 4), "\n")
cat(" 0.3 * raw IC threshold:", round(rf_a4_threshold, 4), "\n")
cat(" post-neutralization IC (sector-neutral):", round(ic_sn_mean, 4), "\n")
cat(" post-neutralization IC (sector+size):", round(ic_neut_mean, 4), "\n")
cat(" RF-A4 sector-neut FAIL:", abs(ic_sn_mean) < abs(rf_a4_threshold), "\n")
cat(" RF-A4 sector+size FAIL:", abs(ic_neut_mean) < abs(rf_a4_threshold), "\n")

# Save extended diagnostics
ext_diag <- list(
  multi_sig_date = list(
    n_dates = uniqueN(alpha_panel$Date),
    date_min = as.character(min(alpha_panel$Date)),
    date_max = as.character(max(alpha_panel$Date)),
    n_total_rows = nrow(alpha_panel),
    schema = "Date | Ticker | Sector | mom_12_1 | alpha_z | alpha_hat",
    rf_a7_pass = uniqueN(alpha_panel$Date) >= 60
  ),
  post_neutralization_ic = list(
    raw_ic = round(raw_ic_local, 5),
    sector_neutral_ic = round(ic_sn_mean, 5),
    sector_neutral_icir = round(ic_sn_icir, 4),
    sector_size_neutral_ic = round(ic_neut_mean, 5),
    sector_size_neutral_icir = round(ic_neut_icir, 4),
    rf_a4_threshold_30pct_raw = round(rf_a4_threshold, 5),
    rf_a4_sector_neutral_fail = abs(ic_sn_mean) < abs(rf_a4_threshold),
    rf_a4_sector_size_neutral_fail = abs(ic_neut_mean) < abs(rf_a4_threshold),
    interpretation = "Sector-neutral residualization 후 IC가 0.3*raw 이하면 alpha의 대부분이 sector-bet에 있음"
  )
)
write_json(ext_diag, "stage_artifacts/WT_D20260508_008/extended_diagnostics.json",
           pretty=TRUE, auto_unbox=TRUE)
cat("\nextended_diagnostics.json saved\n")

# Save IC panels for audit
fwrite(ic_raw_panel, "stage_artifacts/WT_D20260508_008/ic_raw_panel.csv")
fwrite(ic_sn_panel, "stage_artifacts/WT_D20260508_008/ic_sector_neutral_panel.csv")
fwrite(ic_neut_panel, "stage_artifacts/WT_D20260508_008/ic_sector_size_neutral_panel.csv")
