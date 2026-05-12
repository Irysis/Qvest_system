#==============================================================================
# WT-D20260511_001 PD25 XV — Cross-validation using RAWDATA Close-to-Close
#
# Motivation: PD20-B Path 2 reported SR=2.16 using rawdata Close-to-Close, while
# PD25 primary using Iter5 Ret_1m reports SR=1.10. The ~1pp SR divergence
# requires cross-validation.
#
# Method: Re-build composite top20 monthly returns using:
#   - RAWDATA Close at sig_date (first trading day at or after) → entry_price
#   - RAWDATA Close at next sig_date (first trading day) → exit_price
#   - ret = exit_price / entry_price - 1 (PD20-B methodology)
# Then apply 3 within-sleeve weighting paths.
#
# Question: Under PD20-B methodology, do Paths B/C improve over Path A (EW)?
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR   <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR   <- "stage_artifacts/WT_D20260511_001"
ITER5    <- "stage_artifacts/WT_D20260425_010"
OUT_DIR  <- file.path(WT_DIR, "backtest_result_pd25")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== PD25 XV — RAWDATA Close-to-Close cross-validation ===\n")
cat(sprintf("Started: %s\n\n", format(Sys.time())))

# Load source
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd <- rd[!is.na(Date) & !is.na(Ticker) & !is.na(Close) & Close > 0]
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)
cat(sprintf("RAWDATA: %d rows, %d tickers\n", nrow(rd), uniqueN(rd$Ticker)))

# Iter5 alpha for sig_dates + scores
a1715 <- as.data.table(read_parquet(file.path(ITER5, "alpha_scores.parquet")))
a1715 <- a1715[, .(sig_date = Date, Ticker, score_eff)]
a1715[, z_1715 := (score_eff - mean(score_eff, na.rm = TRUE)) /
        sd(score_eff, na.rm = TRUE), by = sig_date]
a1715[is.na(z_1715) | is.infinite(z_1715), z_1715 := 0]

aNEW <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
setnames(aNEW, "alpha", "alpha_NEW")
aNEW[, z_NEW := (alpha_NEW - mean(alpha_NEW, na.rm = TRUE)) /
       sd(alpha_NEW, na.rm = TRUE), by = sig_date]
aNEW[is.na(z_NEW) | is.infinite(z_NEW), z_NEW := 0]

z_kr <- merge(a1715, aNEW[, .(sig_date, Ticker, z_NEW)],
              by = c("sig_date", "Ticker"), all.x = TRUE)
z_kr[is.na(z_NEW), z_NEW := 0]
W_1715 <- 0.818; W_NEW <- 0.182
z_kr[, composite_z := W_1715 * z_1715 + W_NEW * z_NEW]

# Active composite sig_dates (where z_NEW present)
sig_dates_active <- sort(unique(aNEW$sig_date))
cat(sprintf("Active composite sig_dates: %d (%s ~ %s)\n",
            length(sig_dates_active),
            as.character(min(sig_dates_active)),
            as.character(max(sig_dates_active))))

# Build top20 + RAWDATA close-to-close returns
cat("\nBuilding composite top20 monthly returns (RAWDATA Close-to-Close) ...\n")

all_holdings <- list()
for (i in seq_along(sig_dates_active)) {
  sd_now <- sig_dates_active[i]
  sd_next <- if (i < length(sig_dates_active)) sig_dates_active[i + 1] else sd_now + 32  # rough
  if (i < length(sig_dates_active)) sd_next <- as.Date(sd_next, origin = "1970-01-01")

  # Top20 by composite_z
  cand <- z_kr[sig_date == sd_now]
  setorder(cand, -composite_z)
  top20 <- head(cand, 20)

  # Entry price: first trading day at/after sd_now
  rd_entry <- rd[Ticker %in% top20$Ticker & Date >= sd_now & Date <= (sd_now + 5)]
  rd_entry <- rd_entry[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(rd_entry, c("Ticker", "entry_date", "entry_price"))

  # Exit price: first trading day at/after sd_next
  rd_exit <- rd[Ticker %in% top20$Ticker & Date >= sd_next & Date <= (sd_next + 5)]
  rd_exit <- rd_exit[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(rd_exit, c("Ticker", "exit_date", "exit_price"))

  rets <- merge(rd_entry, rd_exit, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := (exit_price / entry_price) - 1]

  # Merge ret_pct back into top20
  top20 <- merge(top20, rets[, .(Ticker, ret_pct)], by = "Ticker", all.x = TRUE)
  top20[, rank := 1:.N]
  all_holdings[[length(all_holdings) + 1]] <- top20
}

holdings_xv <- rbindlist(all_holdings, fill = TRUE)

# Compare overall mean return
cat(sprintf("\nRet_pct (rawdata) stats: mean=%.4f, sd=%.4f, n_NA=%d\n",
            mean(holdings_xv$ret_pct, na.rm = TRUE), sd(holdings_xv$ret_pct, na.rm = TRUE),
            sum(is.na(holdings_xv$ret_pct))))
cat(sprintf("Iter5 Ret_1m would be: mean=0.0167 (from primary run)\n"))

# Now compute 3 paths
N_STOCKS <- 20
SLEEVE_W <- 0.55
W_CAP <- 0.20

# Path A — EW
holdings_xv[, w_sleeve_A := 1 / N_STOCKS]

# Path B — Z-linear
compute_path_B <- function(z) {
  z_pos <- pmax(z, 0)
  s <- sum(z_pos, na.rm = TRUE)
  if (s <= 1e-9) return(rep(1 / length(z), length(z)))
  z_pos / s
}
holdings_xv[, w_sleeve_B := compute_path_B(composite_z), by = sig_date]

# Path C — Z-softmax
compute_path_C <- function(z) {
  tau <- median(abs(z), na.rm = TRUE)
  if (is.na(tau) || tau <= 1e-9) tau <- 1.0
  z_scaled <- z / tau
  z_max <- max(z_scaled, na.rm = TRUE)
  e <- exp(z_scaled - z_max)
  e / sum(e, na.rm = TRUE)
}
holdings_xv[, w_sleeve_C := compute_path_C(composite_z), by = sig_date]

# Sleeve-level returns
holdings_xv[, ret_contrib_A := w_sleeve_A * ret_pct]
holdings_xv[, ret_contrib_B := w_sleeve_B * ret_pct]
holdings_xv[, ret_contrib_C := w_sleeve_C * ret_pct]

period_ret <- holdings_xv[, .(
  Composite_A = sum(ret_contrib_A, na.rm = TRUE),
  Composite_B = sum(ret_contrib_B, na.rm = TRUE),
  Composite_C = sum(ret_contrib_C, na.rm = TRUE),
  n_holdings = .N, n_with_ret = sum(!is.na(ret_pct))
), by = sig_date]
setorder(period_ret, sig_date)

cat(sprintf("\nSleeve-level returns (gross, RAWDATA method):\n"))
cat(sprintf("  Path A (EW)       : mean=%.4f, sd=%.4f\n",
            mean(period_ret$Composite_A), sd(period_ret$Composite_A)))
cat(sprintf("  Path B (Z-linear) : mean=%.4f, sd=%.4f\n",
            mean(period_ret$Composite_B), sd(period_ret$Composite_B)))
cat(sprintf("  Path C (Z-softmax): mean=%.4f, sd=%.4f\n",
            mean(period_ret$Composite_C), sd(period_ret$Composite_C)))

# Compute turnover (sleeve-level)
compute_turnover <- function(holdings, weight_col) {
  ud <- sort(unique(holdings$sig_date))
  to <- numeric(length(ud))
  to[1] <- 1.0
  for (i in 2:length(ud)) {
    curr <- holdings[sig_date == ud[i], .(Ticker, w = get(weight_col))]
    prev <- holdings[sig_date == ud[i - 1], .(Ticker, w_prev = get(weight_col))]
    m <- merge(curr, prev, by = "Ticker", all = TRUE)
    m[is.na(w), w := 0]
    m[is.na(w_prev), w_prev := 0]
    to[i] <- sum(abs(m$w - m$w_prev)) / 2
  }
  to
}
to_A <- compute_turnover(holdings_xv, "w_sleeve_A")
to_B <- compute_turnover(holdings_xv, "w_sleeve_B")
to_C <- compute_turnover(holdings_xv, "w_sleeve_C")

# Cost embed
COST_BPS <- 0.0015
period_ret[, sig_date := as.Date(sig_date)]
period_ret[, to_A := to_A]; period_ret[, to_B := to_B]; period_ret[, to_C := to_C]
period_ret[, cost_A := 2 * to_A * COST_BPS]
period_ret[, cost_B := 2 * to_B * COST_BPS]
period_ret[, cost_C := 2 * to_C * COST_BPS]
period_ret[, Composite_A_net := Composite_A - cost_A]
period_ret[, Composite_B_net := Composite_B - cost_B]
period_ret[, Composite_C_net := Composite_C - cost_C]

# Portfolio (4-sleeve: 0.55 KR + 0.225 TSMOM + 0.18 KR_10y + 0.045 Cash)
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
sm[, ym := format(Date, "%Y-%m")]
period_ret[, ym := format(sig_date, "%Y-%m")]

portfolio <- merge(sm, period_ret[, .(ym, Composite_A, Composite_B, Composite_C,
                                       Composite_A_net, Composite_B_net, Composite_C_net,
                                       cost_A, cost_B, cost_C)],
                   by = "ym", all.x = TRUE)
setorder(portfolio, Date)
portfolio[, has_composite := !is.na(Composite_A)]

# Pre-2011 S4 baseline (50/25/20/5)
portfolio[, ret_path_A := ifelse(has_composite,
  0.55 * Composite_A + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4 + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]
portfolio[, ret_path_B := ifelse(has_composite,
  0.55 * Composite_B + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4 + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]
portfolio[, ret_path_C := ifelse(has_composite,
  0.55 * Composite_C + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4 + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]

COST_BASELINE_OTHER <- 0.10 * 0.0015 * 2 * 0.45
portfolio[, drag_A := ifelse(has_composite, 0.55 * cost_A + COST_BASELINE_OTHER, 0.50 * 0.10 * 0.0015 * 2)]
portfolio[, drag_B := ifelse(has_composite, 0.55 * cost_B + COST_BASELINE_OTHER, 0.50 * 0.10 * 0.0015 * 2)]
portfolio[, drag_C := ifelse(has_composite, 0.55 * cost_C + COST_BASELINE_OTHER, 0.50 * 0.10 * 0.0015 * 2)]

portfolio[, ret_path_A_net := ret_path_A - drag_A]
portfolio[, ret_path_B_net := ret_path_B - drag_B]
portfolio[, ret_path_C_net := ret_path_C - drag_C]

# S4 v2 baseline
portfolio[, ret_S4 := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]
portfolio[, drag_S4 := 0.05 * 0.0015 * 2]
portfolio[, ret_S4_net := ret_S4 - drag_S4]

# Metrics
compute_m <- function(rets, dates, label) {
  rc <- rets[!is.na(rets)]
  dc <- dates[!is.na(rets)]
  if (length(rc) < 12) return(NULL)
  xt <- xts(rc, order.by = dc)
  list(label = label, N = length(rc),
       SR = as.numeric(SharpeRatio.annualized(xt, scale = 12, geometric = TRUE)),
       CAGR = as.numeric(Return.annualized(xt, scale = 12, geometric = TRUE)),
       MDD = as.numeric(maxDrawdown(xt, geometric = TRUE)),
       CVaR_95 = as.numeric(ES(xt, p = 0.95, method = "historical")))
}

m_A_full <- compute_m(portfolio$ret_path_A_net, portfolio$Date, "Path_A_EW_XV_full")
m_B_full <- compute_m(portfolio$ret_path_B_net, portfolio$Date, "Path_B_Zlinear_XV_full")
m_C_full <- compute_m(portfolio$ret_path_C_net, portfolio$Date, "Path_C_Zsoftmax_XV_full")
m_S4_full <- compute_m(portfolio$ret_S4_net, portfolio$Date, "S4_v2_XV_full")

cat(sprintf("\n[Full 255m XV (RAWDATA Close-to-Close basis)]\n"))
for (m in list(m_A_full, m_B_full, m_C_full, m_S4_full)) {
  cat(sprintf("  [%s] SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f, N=%d\n",
              m$label, m$SR, m$CAGR, m$MDD, m$CVaR_95, m$N))
}

# Active 184m
portfolio_active <- portfolio[has_composite == TRUE]
m_A_act <- compute_m(portfolio_active$ret_path_A_net, portfolio_active$Date, "Path_A_EW_XV_act")
m_B_act <- compute_m(portfolio_active$ret_path_B_net, portfolio_active$Date, "Path_B_Zlinear_XV_act")
m_C_act <- compute_m(portfolio_active$ret_path_C_net, portfolio_active$Date, "Path_C_Zsoftmax_XV_act")
m_S4_act <- compute_m(portfolio_active$ret_S4_net, portfolio_active$Date, "S4_v2_XV_act")

cat(sprintf("\n[Active 184m XV]\n"))
for (m in list(m_A_act, m_B_act, m_C_act, m_S4_act)) {
  cat(sprintf("  [%s] SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f, N=%d\n",
              m$label, m$SR, m$CAGR, m$MDD, m$CVaR_95, m$N))
}

# Save period_ret for DM
fwrite(portfolio[, .(Date, ret_path_A_net, ret_path_B_net, ret_path_C_net, ret_S4_net,
                     has_composite, ret_path_A, ret_path_B, ret_path_C, ret_S4,
                     Composite_A, Composite_B, Composite_C)],
       file.path(OUT_DIR, "period_returns_xv_rawdata.csv"))

# Compute Diebold-Mariano vs S4 baseline (XV methodology, full 255m)
compute_dm <- function(rs, rb, label) {
  d <- (rs - rb)[!is.na(rs) & !is.na(rb)]
  N <- length(d); m <- mean(d); v <- var(d); lag <- 6
  for (l in 1:lag) {
    w <- 1 - l/(lag+1)
    ac <- mean((d[(l+1):N] - m) * (d[1:(N-l)] - m))
    v <- v + 2 * w * ac
  }
  se <- sqrt(v / N); t <- m / se; p <- 2 * pnorm(-abs(t))
  list(label = label, N = N, mean_diff = m, NW_lag6_SE = se,
       t_NW = t, p_value = p, hlz_pass = abs(t) > 3.0)
}

dm_A_xv <- compute_dm(portfolio$ret_path_A_net, portfolio$ret_S4_net, "Path_A_XV_vs_S4")
dm_B_xv <- compute_dm(portfolio$ret_path_B_net, portfolio$ret_S4_net, "Path_B_XV_vs_S4")
dm_C_xv <- compute_dm(portfolio$ret_path_C_net, portfolio$ret_S4_net, "Path_C_XV_vs_S4")

cat(sprintf("\n[Diebold-Mariano XV vs S4 baseline (full 255m, RAWDATA basis)]\n"))
for (d in list(dm_A_xv, dm_B_xv, dm_C_xv)) {
  cat(sprintf("  [%s] N=%d, mean_diff=%.6f, t_NW=%.4f, p=%.4f, Harvey3.0=%s\n",
              d$label, d$N, d$mean_diff, d$t_NW, d$p_value,
              ifelse(d$hlz_pass, "PASS", "FAIL")))
}

dm_xv_csv <- data.table(
  path = c("Path_A_EW", "Path_B_Zlinear", "Path_C_Zsoftmax"),
  N = c(dm_A_xv$N, dm_B_xv$N, dm_C_xv$N),
  mean_diff = c(dm_A_xv$mean_diff, dm_B_xv$mean_diff, dm_C_xv$mean_diff),
  NW_lag6_SE = c(dm_A_xv$NW_lag6_SE, dm_B_xv$NW_lag6_SE, dm_C_xv$NW_lag6_SE),
  t_NW = c(dm_A_xv$t_NW, dm_B_xv$t_NW, dm_C_xv$t_NW),
  p_value = c(dm_A_xv$p_value, dm_B_xv$p_value, dm_C_xv$p_value),
  Harvey_3_pass = c(dm_A_xv$hlz_pass, dm_B_xv$hlz_pass, dm_C_xv$hlz_pass)
)
fwrite(dm_xv_csv, file.path(OUT_DIR, "diebold_mariano_xv_rawdata.csv"))

# Save
xv_csv <- data.table(
  window = c(rep("full_255m", 4), rep("active_184m", 4)),
  path = rep(c("Path_A_EW", "Path_B_Zlinear", "Path_C_Zsoftmax", "S4_v2"), 2),
  SR = c(m_A_full$SR, m_B_full$SR, m_C_full$SR, m_S4_full$SR,
         m_A_act$SR, m_B_act$SR, m_C_act$SR, m_S4_act$SR),
  CAGR = c(m_A_full$CAGR, m_B_full$CAGR, m_C_full$CAGR, m_S4_full$CAGR,
           m_A_act$CAGR, m_B_act$CAGR, m_C_act$CAGR, m_S4_act$CAGR),
  MDD = c(m_A_full$MDD, m_B_full$MDD, m_C_full$MDD, m_S4_full$MDD,
          m_A_act$MDD, m_B_act$MDD, m_C_act$MDD, m_S4_act$MDD),
  CVaR_95 = c(m_A_full$CVaR_95, m_B_full$CVaR_95, m_C_full$CVaR_95, m_S4_full$CVaR_95,
              m_A_act$CVaR_95, m_B_act$CVaR_95, m_C_act$CVaR_95, m_S4_act$CVaR_95)
)
fwrite(xv_csv, file.path(OUT_DIR, "metrics_xv_rawdata.csv"))

saveRDS(list(
  m_full = list(A = m_A_full, B = m_B_full, C = m_C_full, S4 = m_S4_full),
  m_act = list(A = m_A_act, B = m_B_act, C = m_C_act, S4 = m_S4_act),
  turnover = list(A = mean(to_A), B = mean(to_B), C = mean(to_C))
), file.path(OUT_DIR, "metrics_xv_rawdata.rds"))

cat(sprintf("\n=== PD25 XV DONE ===\n"))
cat(sprintf("Finished: %s\n", format(Sys.time())))
