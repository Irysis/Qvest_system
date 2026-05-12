#==============================================================================
# WT-D20260511_001 PD30 — 297m full backtest + 3 weighting comparison
#
# Inherit:
#   - alpha_scores_pd27_burn0m.parquet (1715 H1 alpha 2001-07~2026-04, 298 sig_dates)
#   - alpha_scores_pd24.parquet (NEW Vol/Skew alpha)
#   - pd28/synthetic_etf_returns_2001_2026.parquet (8-ETF synthesis)
#
# Method A canonical (PD26 verdict):
#   - sig_date label t -> forward 1m held period (t+1 month)
#   - Ret_1m = prod(1 + RAWDATA$Ret) per (Ticker, t+1 YearMonth)
#   - NO first-trading-day anchor (PD26 PIT_FAIL_HARD)
#
# 3 Weighting variants (sleeve internal, then × 0.55 portfolio share):
#   A. EW                  : w_i = 1/n
#   B. Alpha-tilt linear   : w_i = max(z_i, 0) / sum(max(z_j, 0))
#   C. Softmax z-tilted    : w_i = exp(z_i / tau) / sum(exp(z_j / tau))
#
# Common: single asset cap [0, 0.20] strict + iterative redistribute (B/C only)
# 4-sleeve: 55% KR equity + 22.5% TSMOM + 18% KR_10y + 4.5% Cash
# Cost: 15bps one-way × turnover (sleeve rebal + inner churn)
#
# Pure Function: 3-package md5 start/end identical (HARD audit)
# Backtest Contract v1.0: PerformanceAnalytics standard functions only
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(dplyr)
  library(PerformanceAnalytics); library(xts); library(zoo)
  library(jsonlite); library(lubridate)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_DIR    <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR    <- "stage_artifacts/WT_D20260511_001"
PD28_DIR  <- file.path(SA_DIR, "pd28")
OUT_DIR   <- file.path(WT_DIR, "backtest_result_pd30")
JUDGE_DIR <- file.path(WT_DIR, "judge_ready", "pd30")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(JUDGE_DIR, showWarnings = FALSE, recursive = TRUE)
for (sub in c("A_EW", "B_alpha_linear", "C_softmax")) {
  dir.create(file.path(OUT_DIR, sub), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(OUT_DIR, sub, "output"), showWarnings = FALSE, recursive = TRUE)
}

cat("================ PD30 — 297m full backtest + 3 weighting comparison ================\n")

START_DATE  <- as.Date("2001-07-01")
END_DATE    <- as.Date("2026-04-01")
COST_BPS    <- 0.0015  # 15bps one-way
SLEEVE_W    <- c(KR_EQUITY = 0.55, TSMOM = 0.225, KR_10Y = 0.18, CASH = 0.045)
SINGLE_CAP  <- 0.20
N_HOLD      <- 20L
LIQ_THRESH  <- 2e8
W_1715      <- 0.45 / (0.45 + 0.10)   # 0.8182
W_NEW       <- 0.10 / (0.45 + 0.10)   # 0.1818

#==============================================================================
# Pure Function audit — start hashes
#==============================================================================
ALPHA_PD27 <- "stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet"
ALPHA_PD24 <- "stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"
ETF_PD28   <- "stage_artifacts/WT_D20260511_001/pd28/synthetic_etf_returns_2001_2026.parquet"
PKG_PD27   <- file.path(WT_DIR, "alpha_package_pd27.json")

md5_start <- list(
  alpha_pd27 = tools::md5sum(ALPHA_PD27),
  alpha_pd24 = tools::md5sum(ALPHA_PD24),
  etf_pd28   = tools::md5sum(ETF_PD28),
  alpha_package_pd27_json = tools::md5sum(PKG_PD27)
)
cat("[Pure Function] Start hashes recorded.\n")
for (k in names(md5_start)) cat(sprintf("  %s: %s\n", k, md5_start[[k]]))

#==============================================================================
# Step 1: Load alphas + build z_composite per sig_date
#==============================================================================
cat("\n[Step 1] Load alphas + build z_composite ...\n")

pd27 <- as.data.table(read_parquet(ALPHA_PD27))
setnames(pd27, "Date", "sig_date")
pd27 <- pd27[sig_date >= START_DATE & sig_date <= END_DATE]
pd27[, z_1715 := scale(score_eff)[, 1], by = sig_date]
cat(sprintf("  PD27: %d rows, %d sig_dates (%s ~ %s)\n",
            nrow(pd27), uniqueN(pd27$sig_date),
            as.character(min(pd27$sig_date)), as.character(max(pd27$sig_date))))

pd24 <- as.data.table(read_parquet(ALPHA_PD24))
pd24 <- pd24[sig_date >= START_DATE & sig_date <= END_DATE]
pd24[, z_NEW := scale(alpha)[, 1], by = sig_date]
cat(sprintf("  PD24: %d rows, %d sig_dates\n",
            nrow(pd24), uniqueN(pd24$sig_date)))

# Outer join: tickers present in either alpha; missing -> 0 z
merged <- merge(pd27[, .(sig_date, Ticker, z_1715)],
                pd24[, .(sig_date, Ticker, z_NEW)],
                by = c("sig_date", "Ticker"), all = TRUE)
merged[is.na(z_1715), z_1715 := 0]
merged[is.na(z_NEW),  z_NEW  := 0]
merged[, composite_z := W_1715 * z_1715 + W_NEW * z_NEW]
setkey(merged, sig_date, Ticker)
cat(sprintf("  Merged composite_z: %d rows, %d sig_dates\n",
            nrow(merged), uniqueN(merged$sig_date)))

#==============================================================================
# Step 2: Load RAWDATA, compute Ret_1m per (Ticker, held YearMonth), liquidity
#==============================================================================
cat("\n[Step 2] RAWDATA load + Ret_1m + ADV_20d ...\n")

rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
       col_select = c("Date", "Ticker", "Ret", "Close", "Vol", "K200", "KQ150")))
rd <- rd[Date >= as.Date("2001-01-01") & Date <= as.Date("2026-06-15")]
setkey(rd, Ticker, Date)
cat(sprintf("  RAWDATA: %d rows, %d tickers, Date %s ~ %s\n",
            nrow(rd), uniqueN(rd$Ticker),
            as.character(min(rd$Date)), as.character(max(rd$Date))))

# ADV_20d (PIT-safe rolling, align right)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

# Per (Ticker, YearMonth) Ret_1m via prod(1+Ret) — Method A canonical
rd_mo <- rd[!is.na(Ret),
            .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
            by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
rd_mo[, held_period := as.Date(paste0(YearMonth, "-01"))]
setkey(rd_mo, held_period, Ticker)
cat(sprintf("  rd_mo (Ticker × YearMonth Ret_1m): %d rows\n", nrow(rd_mo)))

#==============================================================================
# Step 3: Per-sig_date Top20 holdings + weighting (3 variants)
#==============================================================================
cat("\n[Step 3] Top20 per sig_date + weighting A/B/C ...\n")

sig_dates <- sort(unique(merged$sig_date))
cat(sprintf("  N sig_dates total: %d\n", length(sig_dates)))

# Helper: redistribute excess weight when single asset > cap
redistribute_cap <- function(w, cap = SINGLE_CAP) {
  # iterative: cap, then proportionally redistribute excess to uncapped
  n <- length(w)
  if (sum(w) <= 1e-9) return(rep(1/n, n))
  w <- w / sum(w)
  for (iter in 1:50) {
    over <- w > cap
    if (!any(over)) break
    excess <- sum(w[over] - cap)
    w[over] <- cap
    uncapped <- !over & w > 0
    if (!any(uncapped)) {
      # all capped — distribute excess equally to all
      w <- w + excess / n
    } else {
      w[uncapped] <- w[uncapped] + excess * (w[uncapped] / sum(w[uncapped]))
    }
  }
  w / sum(w)
}

# Storage for 3 variants
all_records <- list(A_EW = list(), B_alpha_linear = list(), C_softmax = list())
holdings_A <- list(); holdings_B <- list(); holdings_C <- list()
cap_audit_records <- list()

for (i in seq_along(sig_dates)) {
  sd_now <- sig_dates[i]
  d_lag  <- sd_now - 1L
  hp_now <- as.Date(sd_now %m+% months(1))

  # Liquidity universe (t-1 strict)
  uni_dt <- rd[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESH]
  if (nrow(uni_dt) == 0) next

  # Composite z within universe
  cs_now <- merged[sig_date == sd_now & Ticker %in% uni_dt$Ticker]
  if (nrow(cs_now) < N_HOLD) {
    cat(sprintf("  [%3d/%3d] %s: SKIP (universe too small: %d)\n",
                i, length(sig_dates), as.character(sd_now), nrow(cs_now)))
    next
  }

  setorder(cs_now, -composite_z)
  top20 <- head(cs_now, N_HOLD)

  # Forward 1m returns at held_period hp_now (Method A canonical)
  rets_held <- rd_mo[held_period == hp_now & Ticker %in% top20$Ticker,
                     .(Ticker, Ret_1m)]

  merged_top <- merge(top20[, .(Ticker, composite_z)], rets_held,
                      by = "Ticker", all.x = TRUE)
  merged_top[is.na(Ret_1m), Ret_1m := 0]  # missing return = 0

  # === Weighting A: EW ===
  w_A <- rep(1 / N_HOLD, N_HOLD)
  ret_A <- sum(w_A * merged_top$Ret_1m)
  all_records$A_EW[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, held_period = hp_now,
    monthly_ret = ret_A, n_holdings = N_HOLD,
    n_present = sum(!is.na(rets_held$Ret_1m))
  )
  holdings_A[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, Ticker = merged_top$Ticker,
    composite_z = merged_top$composite_z, weight = w_A
  )

  # === Weighting B: alpha-tilt linear ===
  z_pos <- pmax(merged_top$composite_z, 0)
  if (sum(z_pos) < 1e-9) {
    w_B <- rep(1 / N_HOLD, N_HOLD)  # fallback to EW
    fallback_B <- TRUE
  } else {
    w_B <- z_pos / sum(z_pos)
    fallback_B <- FALSE
  }
  w_B_pre_cap <- w_B
  w_B <- redistribute_cap(w_B, SINGLE_CAP)
  ret_B <- sum(w_B * merged_top$Ret_1m)

  max_pre_B <- max(w_B_pre_cap); max_post_B <- max(w_B)
  cap_audit_records[[paste0(as.character(sd_now), "_B")]] <- data.table(
    sig_date = sd_now, variant = "B_alpha_linear",
    fallback_EW = fallback_B, max_pre_cap = max_pre_B,
    max_post_cap = max_post_B, n_capped = sum(w_B_pre_cap > SINGLE_CAP)
  )

  all_records$B_alpha_linear[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, held_period = hp_now,
    monthly_ret = ret_B, n_holdings = N_HOLD,
    n_present = sum(!is.na(rets_held$Ret_1m))
  )
  holdings_B[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, Ticker = merged_top$Ticker,
    composite_z = merged_top$composite_z, weight = w_B
  )

  # === Weighting C: softmax z-tilted ===
  # tau = median(|z|) of top20 (adaptive Boltzmann temperature)
  tau <- median(abs(merged_top$composite_z))
  if (tau < 0.1) tau <- 0.1  # floor to avoid extreme concentration
  shifted_z <- merged_top$composite_z - max(merged_top$composite_z)  # numerical stability
  w_C_raw <- exp(shifted_z / tau)
  w_C <- w_C_raw / sum(w_C_raw)
  w_C_pre_cap <- w_C
  w_C <- redistribute_cap(w_C, SINGLE_CAP)
  ret_C <- sum(w_C * merged_top$Ret_1m)

  max_pre_C <- max(w_C_pre_cap); max_post_C <- max(w_C)
  cap_audit_records[[paste0(as.character(sd_now), "_C")]] <- data.table(
    sig_date = sd_now, variant = "C_softmax",
    fallback_EW = FALSE, max_pre_cap = max_pre_C,
    max_post_cap = max_post_C, n_capped = sum(w_C_pre_cap > SINGLE_CAP),
    tau = tau
  )

  all_records$C_softmax[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, held_period = hp_now,
    monthly_ret = ret_C, n_holdings = N_HOLD,
    n_present = sum(!is.na(rets_held$Ret_1m))
  )
  holdings_C[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, Ticker = merged_top$Ticker,
    composite_z = merged_top$composite_z, weight = w_C
  )

  if (i %% 30 == 0 || i == 1 || i == length(sig_dates)) {
    cat(sprintf("  [%3d/%3d] %s: A=%.4f B=%.4f C=%.4f (tau=%.2f, n_cap_C=%d)\n",
                i, length(sig_dates), as.character(sd_now),
                ret_A, ret_B, ret_C, tau, sum(w_C_pre_cap > SINGLE_CAP)))
  }
}

sleeve_A_dt <- rbindlist(all_records$A_EW)
sleeve_B_dt <- rbindlist(all_records$B_alpha_linear)
sleeve_C_dt <- rbindlist(all_records$C_softmax)
cap_audit_dt <- rbindlist(cap_audit_records, fill = TRUE)
holdings_A_dt <- rbindlist(holdings_A)
holdings_B_dt <- rbindlist(holdings_B)
holdings_C_dt <- rbindlist(holdings_C)

fwrite(sleeve_A_dt, file.path(OUT_DIR, "A_EW", "sleeve_kr_equity_returns.csv"))
fwrite(sleeve_B_dt, file.path(OUT_DIR, "B_alpha_linear", "sleeve_kr_equity_returns.csv"))
fwrite(sleeve_C_dt, file.path(OUT_DIR, "C_softmax", "sleeve_kr_equity_returns.csv"))
fwrite(holdings_A_dt, file.path(OUT_DIR, "A_EW", "holdings.csv"))
fwrite(holdings_B_dt, file.path(OUT_DIR, "B_alpha_linear", "holdings.csv"))
fwrite(holdings_C_dt, file.path(OUT_DIR, "C_softmax", "holdings.csv"))
fwrite(cap_audit_dt, file.path(OUT_DIR, "single_asset_cap_audit.csv"))

cat(sprintf("  Sleeve A_EW: %d months | B_linear: %d months | C_softmax: %d months\n",
            nrow(sleeve_A_dt), nrow(sleeve_B_dt), nrow(sleeve_C_dt)))

#==============================================================================
# Step 4: ETF synthesis inherit + TSMOM build
#==============================================================================
cat("\n[Step 4] ETF inherit + TSMOM ...\n")

etf <- as.data.table(read_parquet(ETF_PD28))
setkey(etf, sig_date)

# TSMOM 8-ETF
tsmom_8 <- c("KOSPI200", "KR_10Y", "KR_SHORT", "US_10Y_H",
             "KOSDAQ150", "GOLD_H_PROXY", "SP500_H_PROXY", "REIT_PROXY")

etf_tsmom <- etf[, c("sig_date", tsmom_8), with = FALSE]
n_tsmom <- nrow(etf_tsmom)
tsmom_signals <- matrix(NA_real_, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  for (col in tsmom_8) {
    start <- i - 12 + 1; end <- i - 1
    if (start >= 1 && end >= start) {
      vals <- etf_tsmom[[col]][start:end]
      if (sum(!is.na(vals)) > 0) {
        tsmom_signals[i, col] <- prod(1 + vals, na.rm = TRUE) - 1
      }
    }
  }
}

tsmom_weights <- matrix(0, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  pos <- which(tsmom_signals[i, ] > 0)
  if (length(pos) > 0) tsmom_weights[i, pos] <- 1 / length(pos)
}

# TSMOM return at sig_date i = weights(i-1) × rets(i)
tsmom_ret <- numeric(n_tsmom)
for (i in 2:n_tsmom) {
  r_i <- as.numeric(etf_tsmom[i, -1, with = FALSE])
  r_i[is.na(r_i)] <- 0
  tsmom_ret[i] <- sum(tsmom_weights[i-1, ] * r_i)
}
tsmom_dt <- data.table(held_period = etf_tsmom$sig_date, TSMOM = tsmom_ret)
cat(sprintf("  TSMOM sleeve: %d months\n", nrow(tsmom_dt)))

#==============================================================================
# Step 5: 4-sleeve portfolio backtest per weighting variant
#==============================================================================
cat("\n[Step 5] 4-sleeve portfolio backtest (3 variants) ...\n")

# Build sleeve panel: held_period × {KR_EQUITY, TSMOM, KR_10Y, CASH}
backtest_variant <- function(sleeve_dt, variant_name) {
  # sleeve_dt has columns: sig_date, held_period, monthly_ret (this is forward 1m ret)
  # For PerformanceAnalytics, we use held_period as the time index (when return realized)
  # held_period = sig_date + 1m
  port_dt <- merge(
    data.table(held_period = etf$sig_date),
    sleeve_dt[, .(held_period, KR_EQUITY = monthly_ret)],
    by = "held_period", all.x = TRUE
  )
  port_dt <- merge(port_dt, tsmom_dt[, .(held_period, TSMOM)],
                   by = "held_period", all.x = TRUE)
  port_dt <- merge(port_dt, etf[, .(held_period = sig_date, KR_10Y, CASH)],
                   by = "held_period", all.x = TRUE)
  # Filter to months where all 4 sleeves have data
  port_dt <- port_dt[!is.na(KR_EQUITY) & !is.na(TSMOM) & !is.na(KR_10Y) & !is.na(CASH)]
  cat(sprintf("  [%s] Portfolio: %d months (%s ~ %s)\n", variant_name,
              nrow(port_dt), min(port_dt$held_period), max(port_dt$held_period)))

  returns_xts <- xts(port_dt[, .(KR_EQUITY, TSMOM, KR_10Y, CASH)],
                     order.by = port_dt$held_period)
  port_ret <- Return.portfolio(R = returns_xts, weights = SLEEVE_W,
                                geometric = TRUE, rebalance_on = "months",
                                verbose = TRUE)
  port_returns_xts <- port_ret$returns
  port_weights_xts <- port_ret$BOP.Weight

  # Turnover: sleeve turnover + inner sleeve churn
  turnover_vec <- numeric(nrow(port_weights_xts))
  for (i in 2:nrow(port_weights_xts)) {
    prev_w <- as.numeric(port_weights_xts[i-1, ])
    curr_w <- as.numeric(port_weights_xts[i, ])
    turnover_vec[i] <- sum(abs(curr_w - prev_w))
  }
  # Inner sleeve churn assumption: KR equity ~ 30% monthly (top20 rotation),
  # TSMOM ~ 50% monthly. Held into 0.55 and 0.225 portfolio shares.
  total_turnover <- turnover_vec + 0.30 * 0.55 + 0.50 * 0.225
  monthly_cost <- total_turnover * COST_BPS
  port_ret_net <- as.numeric(port_returns_xts) - monthly_cost
  port_ret_net_xts <- xts(port_ret_net, order.by = index(port_returns_xts))

  list(
    port_dt = port_dt,
    returns_xts = returns_xts,
    port_ret = port_ret,
    port_returns_xts = port_returns_xts,
    port_ret_net_xts = port_ret_net_xts,
    turnover = total_turnover,
    monthly_cost = monthly_cost
  )
}

bt_A <- backtest_variant(sleeve_A_dt, "A_EW")
bt_B <- backtest_variant(sleeve_B_dt, "B_alpha_linear")
bt_C <- backtest_variant(sleeve_C_dt, "C_softmax")

#==============================================================================
# Step 6: Metrics per variant
#==============================================================================
cat("\n[Step 6] Metrics per variant ...\n")

compute_metrics <- function(bt, variant_name, sub_dir) {
  net_xts <- bt$port_ret_net_xts
  ar_table <- table.AnnualizedReturns(net_xts, scale = 12, geometric = TRUE)
  cagr <- as.numeric(ar_table[1, 1])
  ann_sd <- as.numeric(ar_table[2, 1])
  sr <- as.numeric(ar_table[3, 1])
  mdd <- maxDrawdown(net_xts)
  cvar95 <- as.numeric(CVaR(net_xts, p = 0.95, method = "historical"))
  sortino <- as.numeric(SortinoRatio(net_xts))
  calmar <- as.numeric(CalmarRatio(net_xts, scale = 12))
  ann_to <- mean(bt$turnover[-1], na.rm = TRUE) * 12
  n_mo <- length(net_xts)

  metrics <- data.table(
    metric = c("annualized_return", "annualized_stdev", "sharpe_ratio",
               "max_drawdown", "cvar_95", "sortino_ratio", "calmar_ratio",
               "annualized_turnover", "n_months",
               "period_start", "period_end"),
    value = c(cagr, ann_sd, sr, mdd, cvar95, sortino, calmar,
              ann_to, n_mo,
              as.character(min(index(net_xts))),
              as.character(max(index(net_xts))))
  )
  fwrite(metrics, file.path(OUT_DIR, sub_dir, "metrics.csv"))

  # NAV + drawdowns + period_returns
  nav_xts <- cumprod(1 + net_xts)
  nav_dt <- data.table(date = index(nav_xts), NAV = as.numeric(nav_xts))
  fwrite(nav_dt, file.path(OUT_DIR, sub_dir, "nav.csv"))
  dd_xts <- Drawdowns(net_xts)
  dd_dt <- data.table(date = index(dd_xts), drawdown = as.numeric(dd_xts))
  fwrite(dd_dt, file.path(OUT_DIR, sub_dir, "drawdowns.csv"))

  pr_dt <- data.table(
    date = index(bt$port_returns_xts),
    gross_return = as.numeric(bt$port_returns_xts),
    turnover = bt$turnover,
    cost = bt$monthly_cost,
    net_return = as.numeric(net_xts)
  )
  fwrite(pr_dt, file.path(OUT_DIR, sub_dir, "period_returns.csv"))

  cat(sprintf("  [%s] SR=%.4f  CAGR=%.4f  MDD=%.4f  CVaR=%.4f  Sortino=%.4f  Calmar=%.4f  TO=%.2f  N=%d\n",
              variant_name, sr, cagr, mdd, cvar95, sortino, calmar, ann_to, n_mo))

  list(metrics = metrics, nav = nav_dt, dd = dd_dt, period_returns = pr_dt,
       cagr = cagr, ann_sd = ann_sd, sr = sr, mdd = mdd, cvar95 = cvar95,
       sortino = sortino, calmar = calmar, ann_to = ann_to, n_mo = n_mo,
       net_xts = net_xts)
}

m_A <- compute_metrics(bt_A, "A_EW",            "A_EW")
m_B <- compute_metrics(bt_B, "B_alpha_linear",  "B_alpha_linear")
m_C <- compute_metrics(bt_C, "C_softmax",       "C_softmax")

#==============================================================================
# Step 7: Comparison + vs S4 v2 4-axis strict + Hurdle v2.2
#==============================================================================
cat("\n[Step 7] Comparison vs S4 v2 baseline + Hurdle v2.2 ...\n")

S4_V2 <- list(SR = 1.81, CAGR = 0.1999, MDD = -0.1263, CVaR_95 = -0.0501, TO = 0.30)

eval_variant <- function(m, label) {
  improve <- list(
    SR = m$sr > S4_V2$SR,
    CAGR = m$cagr > S4_V2$CAGR,
    MDD = (-m$mdd) > S4_V2$MDD,  # MDD: less negative = better; S4_V2 stored as -0.1263 (i.e., 12.63% loss)
    CVaR_95 = m$cvar95 > S4_V2$CVaR_95
  )
  n_imp <- sum(unlist(improve))

  # Hurdle v2.2: hard fail if MDD > 45% OR TO > 600% (=6.0)
  hard_fail <- (-m$mdd > 0.45) || (m$ann_to > 6.0)
  score <- 0
  if (m$sr >= 0.8)          score <- score + 20
  if (m$cagr >= 0.16)       score <- score + 20
  if (-m$mdd <= 0.25)       score <- score + 20
  if (-m$mdd <= 0.45)       score <- score + 5
  if (n_imp >= 3)           score <- score + 10
  grade <- if (hard_fail) "HARD_FAIL"
            else if (score >= 50 && m$cagr >= 0.16 && m$sr >= 0.8) "A"
            else if (score >= 30) "B"
            else "C"

  list(variant = label,
       sr = m$sr, cagr = m$cagr, mdd = -m$mdd, cvar95 = m$cvar95, ann_to = m$ann_to,
       SR_imp = improve$SR, CAGR_imp = improve$CAGR,
       MDD_imp = improve$MDD, CVaR_imp = improve$CVaR_95,
       n_improve = n_imp, strict_4axis_pass = (n_imp == 4),
       hard_fail = hard_fail, score = score, grade = grade,
       hurdle_to_600_pass = (m$ann_to <= 6.0))
}

ev_A <- eval_variant(m_A, "A_EW")
ev_B <- eval_variant(m_B, "B_alpha_linear")
ev_C <- eval_variant(m_C, "C_softmax")

comparison_dt <- data.table(
  variant = c(ev_A$variant, ev_B$variant, ev_C$variant),
  SR = c(ev_A$sr, ev_B$sr, ev_C$sr),
  CAGR = c(ev_A$cagr, ev_B$cagr, ev_C$cagr),
  MDD = c(ev_A$mdd, ev_B$mdd, ev_C$mdd),
  CVaR_95 = c(ev_A$cvar95, ev_B$cvar95, ev_C$cvar95),
  Annualized_TO = c(ev_A$ann_to, ev_B$ann_to, ev_C$ann_to),
  vs_S4_SR = c(ev_A$SR_imp, ev_B$SR_imp, ev_C$SR_imp),
  vs_S4_CAGR = c(ev_A$CAGR_imp, ev_B$CAGR_imp, ev_C$CAGR_imp),
  vs_S4_MDD = c(ev_A$MDD_imp, ev_B$MDD_imp, ev_C$MDD_imp),
  vs_S4_CVaR = c(ev_A$CVaR_imp, ev_B$CVaR_imp, ev_C$CVaR_imp),
  n_improve = c(ev_A$n_improve, ev_B$n_improve, ev_C$n_improve),
  strict_4axis_pass = c(ev_A$strict_4axis_pass, ev_B$strict_4axis_pass, ev_C$strict_4axis_pass),
  hurdle_TO_600_pass = c(ev_A$hurdle_to_600_pass, ev_B$hurdle_to_600_pass, ev_C$hurdle_to_600_pass),
  hard_fail = c(ev_A$hard_fail, ev_B$hard_fail, ev_C$hard_fail),
  score = c(ev_A$score, ev_B$score, ev_C$score),
  grade = c(ev_A$grade, ev_B$grade, ev_C$grade)
)
fwrite(comparison_dt, file.path(OUT_DIR, "comparison_3_weighting.csv"))
print(comparison_dt)

# Also per-variant hurdle CSV
for (m in list(list(m_A, "A_EW", ev_A), list(m_B, "B_alpha_linear", ev_B),
               list(m_C, "C_softmax", ev_C))) {
  ev <- m[[3]]
  hurdle_dt <- data.table(
    hard_fail = ev$hard_fail, score = ev$score, grade = ev$grade,
    sharpe = ev$sr, cagr = ev$cagr, mdd = ev$mdd, cvar_95 = ev$cvar95,
    to_annualized = ev$ann_to, s4_v2_4axis_improve = ev$n_improve,
    s4_v2_strict_pass = ev$strict_4axis_pass,
    hurdle_v2_2_to_600_pass = ev$hurdle_to_600_pass
  )
  fwrite(hurdle_dt, file.path(OUT_DIR, m[[2]], "hurdle_result.csv"))
  imp_dt <- data.table(
    axis = c("SR", "CAGR", "MDD", "CVaR_95"),
    pd30_value = c(ev$sr, ev$cagr, ev$mdd, ev$cvar95),
    s4_v2_baseline = c(S4_V2$SR, S4_V2$CAGR, S4_V2$MDD, S4_V2$CVaR_95),
    improved = c(ev$SR_imp, ev$CAGR_imp, ev$MDD_imp, ev$CVaR_imp)
  )
  fwrite(imp_dt, file.path(OUT_DIR, m[[2]], "4axis_strict_vs_s4_v2.csv"))
}

#==============================================================================
# Step 8: Sub-period decomposition (PRE-2011 / POST-2011)
#==============================================================================
cat("\n[Step 8] Sub-period analysis ...\n")

sub_period <- function(m, label) {
  net_xts <- m$net_xts
  pre_idx  <- index(net_xts) < as.Date("2011-01-01")
  post_idx <- index(net_xts) >= as.Date("2011-01-01")
  ret_pre  <- net_xts[pre_idx]
  ret_post <- net_xts[post_idx]
  ar_pre   <- table.AnnualizedReturns(ret_pre,  scale = 12, geometric = TRUE)
  ar_post  <- table.AnnualizedReturns(ret_post, scale = 12, geometric = TRUE)
  list(
    label = label,
    pre_n = length(ret_pre),
    pre_sr = as.numeric(ar_pre[3, 1]),
    pre_cagr = as.numeric(ar_pre[1, 1]),
    pre_mdd = maxDrawdown(ret_pre),
    post_n = length(ret_post),
    post_sr = as.numeric(ar_post[3, 1]),
    post_cagr = as.numeric(ar_post[1, 1]),
    post_mdd = maxDrawdown(ret_post)
  )
}

sp_A <- sub_period(m_A, "A_EW")
sp_B <- sub_period(m_B, "B_alpha_linear")
sp_C <- sub_period(m_C, "C_softmax")

sub_dt <- rbindlist(list(
  data.table(variant = "A_EW",
             pre_n = sp_A$pre_n, pre_SR = sp_A$pre_sr, pre_CAGR = sp_A$pre_cagr, pre_MDD = sp_A$pre_mdd,
             post_n = sp_A$post_n, post_SR = sp_A$post_sr, post_CAGR = sp_A$post_cagr, post_MDD = sp_A$post_mdd),
  data.table(variant = "B_alpha_linear",
             pre_n = sp_B$pre_n, pre_SR = sp_B$pre_sr, pre_CAGR = sp_B$pre_cagr, pre_MDD = sp_B$pre_mdd,
             post_n = sp_B$post_n, post_SR = sp_B$post_sr, post_CAGR = sp_B$post_cagr, post_MDD = sp_B$post_mdd),
  data.table(variant = "C_softmax",
             pre_n = sp_C$pre_n, pre_SR = sp_C$pre_sr, pre_CAGR = sp_C$pre_cagr, pre_MDD = sp_C$pre_mdd,
             post_n = sp_C$post_n, post_SR = sp_C$post_sr, post_CAGR = sp_C$post_cagr, post_MDD = sp_C$post_mdd)
))
fwrite(sub_dt, file.path(OUT_DIR, "sub_period_pre_post_2011.csv"))
print(sub_dt)

#==============================================================================
# Step 9: DM test (pairwise A vs B vs C, Newey-West HAC lag 6)
#==============================================================================
cat("\n[Step 9] Diebold-Mariano pairwise (NW HAC lag 6) ...\n")

dm_test <- function(r1, r2, label1, label2, lag = 6) {
  # Common index
  dt1 <- data.table(date = index(r1), r = as.numeric(r1))
  dt2 <- data.table(date = index(r2), r = as.numeric(r2))
  m <- merge(dt1, dt2, by = "date", suffixes = c("_1", "_2"))
  if (nrow(m) < 24) return(data.table(pair = paste(label1, label2), n = nrow(m),
                                       dm_stat = NA, p_value = NA, decision = "INSUFFICIENT_N"))
  d <- m$r_1 - m$r_2
  d_mean <- mean(d)

  # NW HAC variance
  n <- length(d)
  s0 <- var(d) * (n - 1) / n
  s_total <- s0
  for (k in 1:lag) {
    w <- 1 - k / (lag + 1)
    cov_k <- sum((d[1:(n-k)] - d_mean) * (d[(k+1):n] - d_mean)) / n
    s_total <- s_total + 2 * w * cov_k
  }
  s_total <- max(s_total, 1e-12)
  dm_stat <- d_mean / sqrt(s_total / n)
  p_value <- 2 * (1 - pnorm(abs(dm_stat)))

  data.table(pair = paste(label1, "vs", label2),
             n = nrow(m), mean_diff = d_mean,
             dm_stat = dm_stat, p_value = p_value,
             decision = ifelse(p_value < 0.05,
                               ifelse(d_mean > 0, paste(label1, ">>", label2),
                                                  paste(label2, ">>", label1)),
                               "INDIFFERENT"))
}

dm_AB <- dm_test(m_A$net_xts, m_B$net_xts, "A_EW", "B_linear")
dm_AC <- dm_test(m_A$net_xts, m_C$net_xts, "A_EW", "C_softmax")
dm_BC <- dm_test(m_B$net_xts, m_C$net_xts, "B_linear", "C_softmax")
dm_dt <- rbindlist(list(dm_AB, dm_AC, dm_BC))
fwrite(dm_dt, file.path(OUT_DIR, "dm_test_pairwise.csv"))
print(dm_dt)

#==============================================================================
# Step 10: Regime decomposition (drawdown-based)
#==============================================================================
cat("\n[Step 10] Regime decomposition ...\n")

regime_decomp <- function(m, sub_dir) {
  net_xts <- m$net_xts
  dd_dt <- m$dd
  regimes <- ifelse(dd_dt$drawdown < -0.15, "Bear",
                    ifelse(dd_dt$drawdown < -0.05, "Recovery",
                           ifelse(dd_dt$drawdown > -0.02, "Bull", "Stable")))
  rd_df <- data.table(date = dd_dt$date, regime = regimes, ret = as.numeric(net_xts))
  rs <- rd_df[, .(SR = ifelse(sd(ret, na.rm = TRUE) > 0,
                              mean(ret, na.rm = TRUE) * 12 / (sd(ret, na.rm = TRUE) * sqrt(12)),
                              NA_real_),
                   mean_ret_annual = mean(ret, na.rm = TRUE) * 12,
                   n = .N), by = regime]
  fwrite(rs, file.path(OUT_DIR, sub_dir, "regime_sr.csv"))
  rs
}

rs_A <- regime_decomp(m_A, "A_EW")
rs_B <- regime_decomp(m_B, "B_alpha_linear")
rs_C <- regime_decomp(m_C, "C_softmax")

#==============================================================================
# Step 11: Charts per variant
#==============================================================================
cat("\n[Step 11] Charts per variant ...\n")

draw_charts <- function(m, sub_dir, variant_label) {
  nav_dt <- m$nav
  dd_dt <- m$dd
  net_xts <- m$net_xts

  # Equity curve
  png(file.path(OUT_DIR, sub_dir, "output", "equity_curve.png"),
      width = 1200, height = 700)
  plot(nav_dt$date, nav_dt$NAV, type = "l",
       main = sprintf("PD30 %s — 297m Equity Curve\nSR=%.3f CAGR=%.2f%% MDD=%.2f%% N=%d",
                      variant_label, m$sr, m$cagr * 100, m$mdd * 100, m$n_mo),
       xlab = "Date", ylab = "NAV (cum from start)", col = "darkblue", lwd = 2)
  abline(h = 1, lty = 2, col = "gray")
  abline(v = as.Date("2008-09-01"), col = "red", lty = 3)
  abline(v = as.Date("2020-03-01"), col = "red", lty = 3)
  text(as.Date("2008-09-01"), 0.9 * max(nav_dt$NAV), "2008 GFC", pos = 4, cex = 0.7, col = "darkred")
  text(as.Date("2020-03-01"), 0.7 * max(nav_dt$NAV), "2020 COVID", pos = 4, cex = 0.7, col = "darkred")
  dev.off()

  # Annual returns
  ret_dt <- data.table(date = index(net_xts), ret = as.numeric(net_xts))
  ret_dt[, year := format(date, "%Y")]
  ar_yr <- ret_dt[, .(annual_ret = prod(1 + ret, na.rm = TRUE) - 1), by = year]
  png(file.path(OUT_DIR, sub_dir, "output", "annual_returns.png"),
      width = 1200, height = 700)
  barplot(ar_yr$annual_ret, names.arg = ar_yr$year,
          main = sprintf("PD30 %s Annual Returns\nMean=%.2f%% Max=%.2f%% Min=%.2f%%",
                         variant_label,
                         mean(ar_yr$annual_ret) * 100,
                         max(ar_yr$annual_ret) * 100,
                         min(ar_yr$annual_ret) * 100),
          col = ifelse(ar_yr$annual_ret >= 0, "darkgreen", "darkred"),
          las = 2, cex.names = 0.7)
  abline(h = 0)
  dev.off()

  # OOS zoom (last 5Y)
  oos_start <- max(index(net_xts)) - 365 * 5
  nav_xts <- xts(nav_dt$NAV, order.by = nav_dt$date)
  oos_nav <- nav_xts[index(nav_xts) >= oos_start]
  png(file.path(OUT_DIR, sub_dir, "output", "oos_zoom_chart.png"),
      width = 1200, height = 700)
  plot(index(oos_nav), as.numeric(oos_nav), type = "l",
       main = sprintf("PD30 %s OOS Zoom (last 5Y)", variant_label),
       xlab = "Date", ylab = "NAV", col = "darkred", lwd = 2)
  dev.off()

  # Regime decomposition
  regimes <- ifelse(dd_dt$drawdown < -0.15, "Bear",
                    ifelse(dd_dt$drawdown < -0.05, "Recovery",
                           ifelse(dd_dt$drawdown > -0.02, "Bull", "Stable")))
  rd_df <- data.table(date = dd_dt$date, regime = regimes, ret = as.numeric(net_xts))
  rs <- rd_df[, .(SR = ifelse(sd(ret, na.rm = TRUE) > 0,
                              mean(ret, na.rm = TRUE) * 12 / (sd(ret, na.rm = TRUE) * sqrt(12)),
                              NA_real_),
                  n = .N), by = regime]
  png(file.path(OUT_DIR, sub_dir, "output", "regime_decomposition.png"),
      width = 1200, height = 700)
  barplot(rs$SR, names.arg = rs$regime,
          main = sprintf("PD30 %s Regime SR Decomposition", variant_label),
          col = c("darkred", "orange", "darkgreen", "gray")[1:nrow(rs)],
          ylab = "Annualized SR")
  abline(h = 0)
  dev.off()
}

draw_charts(m_A, "A_EW", "A_EW")
draw_charts(m_B, "B_alpha_linear", "B_alpha_linear")
draw_charts(m_C, "C_softmax", "C_softmax")

#==============================================================================
# Step 12: Pure Function audit (md5 end)
#==============================================================================
cat("\n[Audit] Pure Function md5 end ...\n")
md5_end <- list(
  alpha_pd27 = tools::md5sum(ALPHA_PD27),
  alpha_pd24 = tools::md5sum(ALPHA_PD24),
  etf_pd28   = tools::md5sum(ETF_PD28),
  alpha_package_pd27_json = tools::md5sum(PKG_PD27)
)
all_match <- all(unlist(md5_start) == unlist(md5_end))
cat(sprintf("  All match: %s\n", all_match))
audit_dt <- data.table(
  package = names(md5_start),
  md5_start = unname(unlist(md5_start)),
  md5_end = unname(unlist(md5_end)),
  match = unlist(md5_start) == unlist(md5_end)
)
fwrite(audit_dt, file.path(OUT_DIR, "pure_function_audit.csv"))

#==============================================================================
# Step 13: Single asset cap audit summary
#==============================================================================
cat("\n[Audit] Single asset cap audit ...\n")
cap_summary <- cap_audit_dt[, .(
  n_sig_dates = .N,
  n_capped_total = sum(n_capped),
  max_pre_cap_observed = max(max_pre_cap),
  max_post_cap_observed = max(max_post_cap),
  violations_post_cap = sum(max_post_cap > SINGLE_CAP + 1e-9)
), by = variant]
print(cap_summary)
fwrite(cap_summary, file.path(OUT_DIR, "single_asset_cap_audit_summary.csv"))

#==============================================================================
# Step 14: Summary JSON
#==============================================================================
cat("\n[Step 14] Summary JSON ...\n")

summary_json <- list(
  wt_id = "WT-D20260511_001",
  phase = "PD30",
  generated_at = as.character(Sys.time()),
  window = list(start = as.character(START_DATE), end = as.character(END_DATE),
                n_sig_dates_alpha = length(sig_dates),
                n_months_backtest = m_A$n_mo),
  z_composite_construction = list(
    w_1715 = W_1715, w_NEW = W_NEW,
    z_scaling = "per-sig_date scale() on score_eff (PD27) and alpha (PD24)",
    outer_join = "tickers present in either alpha; missing z set to 0",
    universe_filter = "K200|KQ150 + ADV_20d (t-1) >= 2e8"
  ),
  sleeve_weights = SLEEVE_W,
  variants = list(
    A_EW = list(
      metrics = list(sr = m_A$sr, cagr = m_A$cagr, ann_sd = m_A$ann_sd,
                     mdd = m_A$mdd, cvar95 = m_A$cvar95, sortino = m_A$sortino,
                     calmar = m_A$calmar, ann_to = m_A$ann_to, n_months = m_A$n_mo),
      vs_s4_v2 = list(SR = ev_A$SR_imp, CAGR = ev_A$CAGR_imp,
                      MDD = ev_A$MDD_imp, CVaR = ev_A$CVaR_imp,
                      n_improve = ev_A$n_improve, strict_pass = ev_A$strict_4axis_pass),
      hurdle = list(hard_fail = ev_A$hard_fail, score = ev_A$score,
                    grade = ev_A$grade, hurdle_to_600_pass = ev_A$hurdle_to_600_pass),
      sub_period = list(
        pre_2011 = list(n = sp_A$pre_n, SR = sp_A$pre_sr,
                        CAGR = sp_A$pre_cagr, MDD = sp_A$pre_mdd),
        post_2011 = list(n = sp_A$post_n, SR = sp_A$post_sr,
                         CAGR = sp_A$post_cagr, MDD = sp_A$post_mdd)
      )
    ),
    B_alpha_linear = list(
      metrics = list(sr = m_B$sr, cagr = m_B$cagr, ann_sd = m_B$ann_sd,
                     mdd = m_B$mdd, cvar95 = m_B$cvar95, sortino = m_B$sortino,
                     calmar = m_B$calmar, ann_to = m_B$ann_to, n_months = m_B$n_mo),
      vs_s4_v2 = list(SR = ev_B$SR_imp, CAGR = ev_B$CAGR_imp,
                      MDD = ev_B$MDD_imp, CVaR = ev_B$CVaR_imp,
                      n_improve = ev_B$n_improve, strict_pass = ev_B$strict_4axis_pass),
      hurdle = list(hard_fail = ev_B$hard_fail, score = ev_B$score,
                    grade = ev_B$grade, hurdle_to_600_pass = ev_B$hurdle_to_600_pass),
      sub_period = list(
        pre_2011 = list(n = sp_B$pre_n, SR = sp_B$pre_sr,
                        CAGR = sp_B$pre_cagr, MDD = sp_B$pre_mdd),
        post_2011 = list(n = sp_B$post_n, SR = sp_B$post_sr,
                         CAGR = sp_B$post_cagr, MDD = sp_B$post_mdd)
      )
    ),
    C_softmax = list(
      metrics = list(sr = m_C$sr, cagr = m_C$cagr, ann_sd = m_C$ann_sd,
                     mdd = m_C$mdd, cvar95 = m_C$cvar95, sortino = m_C$sortino,
                     calmar = m_C$calmar, ann_to = m_C$ann_to, n_months = m_C$n_mo),
      vs_s4_v2 = list(SR = ev_C$SR_imp, CAGR = ev_C$CAGR_imp,
                      MDD = ev_C$MDD_imp, CVaR = ev_C$CVaR_imp,
                      n_improve = ev_C$n_improve, strict_pass = ev_C$strict_4axis_pass),
      hurdle = list(hard_fail = ev_C$hard_fail, score = ev_C$score,
                    grade = ev_C$grade, hurdle_to_600_pass = ev_C$hurdle_to_600_pass),
      sub_period = list(
        pre_2011 = list(n = sp_C$pre_n, SR = sp_C$pre_sr,
                        CAGR = sp_C$pre_cagr, MDD = sp_C$pre_mdd),
        post_2011 = list(n = sp_C$post_n, SR = sp_C$post_sr,
                         CAGR = sp_C$post_cagr, MDD = sp_C$post_mdd)
      )
    )
  ),
  dm_test_pairwise = dm_dt,
  s4_v2_baseline = S4_V2,
  cap_audit = cap_summary,
  pure_function_audit = list(all_match = all_match, detail = audit_dt),
  method_a_canonical = list(
    trade_timing = "sig_date label t = forward 1m held period (t+1 month)",
    first_trading_day_anchor = "FORBIDDEN (PD26 PIT_FAIL_HARD)",
    performance_analytics_chain = "Return.portfolio + table.AnnualizedReturns + maxDrawdown + CVaR + SortinoRatio + CalmarRatio standard chain"
  ),
  charts = list(
    A_EW = list(equity = "A_EW/output/equity_curve.png",
                annual = "A_EW/output/annual_returns.png",
                oos = "A_EW/output/oos_zoom_chart.png",
                regime = "A_EW/output/regime_decomposition.png"),
    B_alpha_linear = list(equity = "B_alpha_linear/output/equity_curve.png",
                          annual = "B_alpha_linear/output/annual_returns.png",
                          oos = "B_alpha_linear/output/oos_zoom_chart.png",
                          regime = "B_alpha_linear/output/regime_decomposition.png"),
    C_softmax = list(equity = "C_softmax/output/equity_curve.png",
                     annual = "C_softmax/output/annual_returns.png",
                     oos = "C_softmax/output/oos_zoom_chart.png",
                     regime = "C_softmax/output/regime_decomposition.png")
  )
)
write_json(summary_json, file.path(OUT_DIR, "metrics_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(summary_json, file.path(JUDGE_DIR, "backtest_summary_pd30.json"),
           pretty = TRUE, auto_unbox = TRUE)

#==============================================================================
# DONE
#==============================================================================
cat("\n================ PD30 — DONE ================\n")
cat(sprintf("  A_EW              : SR=%.3f  CAGR=%.2f%%  MDD=%.2f%%  TO=%.2f  Grade=%s\n",
            m_A$sr, m_A$cagr * 100, m_A$mdd * 100, m_A$ann_to, ev_A$grade))
cat(sprintf("  B_alpha_linear    : SR=%.3f  CAGR=%.2f%%  MDD=%.2f%%  TO=%.2f  Grade=%s\n",
            m_B$sr, m_B$cagr * 100, m_B$mdd * 100, m_B$ann_to, ev_B$grade))
cat(sprintf("  C_softmax         : SR=%.3f  CAGR=%.2f%%  MDD=%.2f%%  TO=%.2f  Grade=%s\n",
            m_C$sr, m_C$cagr * 100, m_C$mdd * 100, m_C$ann_to, ev_C$grade))
cat(sprintf("  S4 v2 baseline    : SR=%.2f  CAGR=%.2f%%  MDD=%.2f%%\n",
            S4_V2$SR, S4_V2$CAGR * 100, S4_V2$MDD * 100))
cat(sprintf("  Pure Function     : all_match=%s\n", all_match))
cat("Output directory: ", OUT_DIR, "\n")
