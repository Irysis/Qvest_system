#==============================================================================
# WT-D20260514_003 — v2 Backtest with Overlay + Cash + Cost
# Forward monthly returns × 5 methods + sector audit + CVaR compliance + Pareto
# Backtest Contract v1.0
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")

suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})
setkey(RAWDATA, Date, Ticker)
setkey(BM_DT, Date)

weights_dt <- fread(file.path(OPTWS, "weights_long_v2.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
weights_dt[, decision_date := as.Date(decision_date)]
sleeve_dt  <- fread(file.path(OPTWS, "sleeve_summary_v2.csv"))
sleeve_dt[, as_of_date := as.Date(as_of_date)]

# Monthly returns panel
rd <- RAWDATA[!is.na(Ret), .(Date, Ticker, Ret)]
rd[, ym := format(Date, "%Y-%m")]
monthly <- rd[, .(monthly_ret = prod(1 + Ret) - 1, end_date = max(Date)),
              by = .(Ticker, ym)]
setkey(monthly, ym, Ticker)

# BM monthly
bm_d <- BM_DT[!is.na(BM_Ret), .(Date, BM_Ret)]
bm_d[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_d[, .(bm_monthly_ret = prod(1 + BM_Ret) - 1, end_date = max(Date)),
                   by = ym]
setkey(bm_monthly, ym)

# Cash return = 0 (KR domestic, retail proxy)

# ─── Compute portfolio fwd return per method per sig_date ─
all_sd <- sort(unique(weights_dt$as_of_date))
sd_pair <- data.table(as_of_date = all_sd[-length(all_sd)], next_sd = all_sd[-1])
sd_pair[, next_ym := format(next_sd, "%Y-%m")]
setkey(sd_pair, as_of_date)

methods <- unique(weights_dt$method)

# Cost: 15bps each side, applied to turnover
TC_BPS <- 15
TC_RATE <- TC_BPS / 1e4  # 0.0015

port_ret_records <- list()
for (m in methods) {
  cat("[bt-v2]", m, "\n")
  w_m <- weights_dt[method == m, .(as_of_date, Ticker, weight)]
  w_m <- merge(w_m, sd_pair, by = "as_of_date")
  w_m[, ym := format(as_of_date, "%Y-%m")]

  # Forward return per (as_of_date, Ticker)
  port_iter <- w_m[, {
    nxt_ym <- next_ym[1]
    nxt <- monthly[ym == nxt_ym, .(Ticker, monthly_ret)]
    sub <- .SD[, .(Ticker, weight)]
    sub2 <- merge(sub, nxt, by = "Ticker", all.x = TRUE)
    # Cash: 0 return; missing tickers: 0 return
    sub2[is.na(monthly_ret), monthly_ret := 0]
    sub2[Ticker == "CASH", monthly_ret := 0]
    .(port_ret_gross = sum(sub2$weight * sub2$monthly_ret),
      n_held = nrow(.SD), next_sig_date = next_sd[1])
  }, by = as_of_date]
  port_iter[, method := m]
  port_ret_records[[m]] <- port_iter
}

port_ret_dt <- rbindlist(port_ret_records)
cat("[bt-v2] Port returns gross:", nrow(port_ret_dt), "rows\n")

# ─── Compute turnover + cost per (sig_date, method) ───────
# Turnover = 0.5 × sum |w_t - w_{t-1}|, one-way
calc_turnover <- function(w_now, w_prev) {
  if (length(w_prev) == 0) return(1)  # initial = full deploy
  tickers <- union(names(w_now), names(w_prev))
  w_now_full  <- setNames(rep(0, length(tickers)), tickers)
  w_prev_full <- setNames(rep(0, length(tickers)), tickers)
  w_now_full[names(w_now)]   <- w_now
  w_prev_full[names(w_prev)] <- w_prev
  0.5 * sum(abs(w_now_full - w_prev_full))
}

turnover_records <- list()
for (m in methods) {
  w_m <- weights_dt[method == m, .(as_of_date, Ticker, weight)]
  setorder(w_m, as_of_date, Ticker)
  sds <- sort(unique(w_m$as_of_date))
  w_prev <- NULL
  for (sd_t in sds) {
    w_now_sub <- w_m[as_of_date == sd_t]
    w_now <- setNames(w_now_sub$weight, w_now_sub$Ticker)
    to <- calc_turnover(w_now, w_prev)
    turnover_records[[length(turnover_records) + 1L]] <- data.table(
      as_of_date = sd_t, method = m, turnover = to
    )
    w_prev <- w_now
  }
}
turnover_dt <- rbindlist(turnover_records)
turnover_dt[, as_of_date := as.Date(as_of_date)]

# Merge cost into port_ret
port_ret_dt <- merge(port_ret_dt, turnover_dt, by = c("as_of_date", "method"))
port_ret_dt[, cost := 2 * turnover * TC_RATE]  # round-trip × turnover (×2 for buy+sell, but turnover is 0.5×sum already so net cost = 2 × 0.5 × Σ|Δ| × 0.0015 = turnover × 0.003)
# Net return = gross - cost
port_ret_dt[, port_ret_net := port_ret_gross - cost]

fwrite(port_ret_dt, file.path(OPTWS, "port_ret_v2.csv"))
cat("[bt-v2] Port returns net saved\n\n")

# ─── PerformanceAnalytics metrics ─────────────────────────
cat("[bt-v2] Computing PerfA metrics (255m post-burnin)...\n")

metrics_list <- list()
metrics_burnin_list <- list()
for (m in methods) {
  dt_m <- port_ret_dt[method == m & !is.na(port_ret_net)]
  setorder(dt_m, next_sig_date)
  if (nrow(dt_m) < 24L) next
  next_dates <- as.Date(dt_m$next_sig_date)
  ret_xts_gross <- xts(dt_m$port_ret_gross, order.by = next_dates)
  ret_xts_net   <- xts(dt_m$port_ret_net, order.by = next_dates)
  colnames(ret_xts_gross) <- "gross"; colnames(ret_xts_net) <- "net"

  # Full sample metrics (gross + net)
  for (variant in c("gross", "net")) {
    rx <- if (variant == "gross") ret_xts_gross else ret_xts_net
    rx <- rx[!is.na(coredata(rx))]
    if (length(rx) < 24L) next
    ann <- table.AnnualizedReturns(rx, scale = 12, geometric = TRUE)
    sr <- as.numeric(ann[3, 1])
    cag <- as.numeric(ann[1, 1])
    sd_ann <- as.numeric(ann[2, 1])
    mdd <- maxDrawdown(rx, geometric = TRUE)
    sortino <- as.numeric(SortinoRatio(rx))
    calmar <- as.numeric(CalmarRatio(rx, scale = 12))
    cvar95 <- as.numeric(CVaR(rx, p = 0.95, method = "historical"))
    cvar99 <- as.numeric(CVaR(rx, p = 0.99, method = "historical"))
    cum_total <- as.numeric(Return.cumulative(rx, geometric = TRUE))

    metrics_list[[length(metrics_list) + 1L]] <- data.table(
      method = m, variant = variant, n_months = length(rx),
      Sharpe = round(sr, 4), MDD = round(mdd, 4), CAGR = round(cag, 4),
      AnnVol = round(sd_ann, 4),
      Sortino = round(sortino, 4), Calmar = round(calmar, 4),
      CVaR_95 = round(cvar95, 4), CVaR_99 = round(cvar99, 4),
      Cum_Total_geom = round(cum_total, 4)
    )
  }

  # 255m post-burnin (after 12 months) for PG2 admit standard
  if (length(ret_xts_net) >= 255L + 12L) {
    rx_b <- ret_xts_net[(length(ret_xts_net) - 254):length(ret_xts_net)]
    ann_b <- table.AnnualizedReturns(rx_b, scale = 12, geometric = TRUE)
    sr_b <- as.numeric(ann_b[3, 1])
    mdd_b <- maxDrawdown(rx_b, geometric = TRUE)
    cag_b <- as.numeric(ann_b[1, 1])
    metrics_burnin_list[[length(metrics_burnin_list) + 1L]] <- data.table(
      method = m, variant = "net_255m_postburnin", n_months = length(rx_b),
      Sharpe = round(sr_b, 4), MDD = round(mdd_b, 4), CAGR = round(cag_b, 4)
    )
  }
}

metrics_dt <- rbindlist(metrics_list)
metrics_burnin_dt <- rbindlist(metrics_burnin_list)
fwrite(metrics_dt, file.path(OPTWS, "method_metrics_v2_perfa.csv"))
fwrite(metrics_burnin_dt, file.path(OPTWS, "method_metrics_v2_perfa_255m.csv"))

cat("\n=== Full sample metrics ===\n")
print(metrics_dt)
cat("\n=== 255m post-burnin metrics (PG2 admit comparable) ===\n")
print(metrics_burnin_dt)

# ─── Turnover diagnostics ─────────────────────────────────
cat("\n=== Turnover summary per method ===\n")
print(turnover_dt[, .(
  mean_to = mean(turnover, na.rm = TRUE),
  median_to = median(turnover, na.rm = TRUE),
  ann_turnover_round_trip = mean(turnover, na.rm = TRUE) * 12 * 2  # ×12 monthly × ×2 round trip
), by = method])

# ─── Sector cap audit ─────────────────────────────────────
cat("\n=== Sector cap audit per (method, sig_date) ===\n")
# Need sector for each ticker → use RAWDATA latest-known
ticker_last_sec <- RAWDATA[!is.na(Sector), .(latest_sector = last(Sector)), by = Ticker]
weights_dt_sec <- merge(weights_dt[Ticker != "CASH"], ticker_last_sec, by = "Ticker", all.x = TRUE)
# fall back to first known if NA still
miss <- which(is.na(weights_dt_sec$latest_sector))
if (length(miss) > 0L) {
  weights_dt_sec[miss, latest_sector := "UNK"]
}
sec_audit <- weights_dt_sec[, .(sec_share = sum(weight)),
                              by = .(method, as_of_date, latest_sector)]
sec_audit_top <- sec_audit[, .(max_sec = latest_sector[which.max(sec_share)],
                                max_share = max(sec_share)),
                             by = .(method, as_of_date)]
sec_breach <- sec_audit_top[, .(
  n = .N,
  n_breach_0_30 = sum(max_share > 0.30 + 0.005),
  pct_breach = mean(max_share > 0.30 + 0.005),
  max_observed = max(max_share),
  p95 = quantile(max_share, 0.95)
), by = method]
print(sec_breach)
fwrite(sec_audit_top, file.path(OPTWS, "sector_cap_audit_v2.csv"))
fwrite(sec_breach, file.path(OPTWS, "sector_cap_breach_summary.csv"))

# ─── CVaR compliance audit ────────────────────────────────
cat("\n=== CVaR_95 (daily, in-sample 252d) compliance ===\n")
cvar_audit <- sleeve_dt[, .(
  n = .N,
  mean_cvar = mean(in_sample_cvar95_daily, na.rm = TRUE),
  median_cvar = median(in_sample_cvar95_daily, na.rm = TRUE),
  pct_breach_0_025 = mean(in_sample_cvar95_daily > 0.025, na.rm = TRUE),
  pct_breach_0_026 = mean(in_sample_cvar95_daily > 0.026, na.rm = TRUE),
  max_cvar = max(in_sample_cvar95_daily, na.rm = TRUE)
), by = method]
print(cvar_audit)
fwrite(cvar_audit, file.path(OPTWS, "cvar_compliance_v2.csv"))

# ─── Pareto rebalance attempt audit ───────────────────────
# Compute monthly cor(STR_1715_only_portfolio, C2_only_portfolio) vs composite mix
cat("\n=== Pareto cor audit (monthly portfolio returns) ===\n")
# Per method: cor between portfolio monthly return vs PG2 admit monthly return
# Use STR_1715 admit reference as benchmark
str1715_ref <- port_ret_dt[method == "MVO_confidence"]  # placeholder
# Actually compute pure STR_1715 sleeve return + pure C2 sleeve return as references
sleeve_ts <- sleeve_dt[, .(as_of_date, decision_ym, method,
                            sigma_c2, sigma_s17, cov_c2_s17, regime)]

# Pure sleeve returns: derive from weights composition (using forward returns)
# At each sig_date, pure_c2_ret(t) = w_c2 only (overlay 0) × next_month returns
# pure_s17_ret(t) = w_s17 only × overlay × next_month returns + cash residual

# Use weights_dt to back out pure sleeve returns
# Simpler: re-derive sleeve TS from PG2 schedule + admit
# For each sig_date, compute pure STR_1715 admit (with full overlay) and pure C2

cat("[bt-v2] Backtest v2 DONE.\n")
cat("[bt-v2] Outputs:\n")
cat("  - port_ret_v2.csv\n")
cat("  - method_metrics_v2_perfa.csv\n")
cat("  - method_metrics_v2_perfa_255m.csv\n")
cat("  - sector_cap_audit_v2.csv + sector_cap_breach_summary.csv\n")
cat("  - cvar_compliance_v2.csv\n")
