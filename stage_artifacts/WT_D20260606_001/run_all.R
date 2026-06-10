# =============================================================================
# WT-D20260606_001 FORGE — Pure Function 3-package integration + authoritative backtest
# Method = STATIC_MULTISLEEVE_EW_a0.15  (book = 0.85*R05[frozen] + 0.15*residual-mom-sleeve)
#
# HARD boundaries (v6.1 Pure Function):
#   - weights.csv as-is for sleeve holdings (Schedule Fidelity Mandate). NO alpha_scores top-N re-selection.
#   - R05 incumbent leg = frozen monthly ret_net (WT-D20260430_001), NOT re-weighted.
#   - target_weights / covariance / alpha NEVER modified.
#   - Portfolio return construction = R Return.portfolio (PerformanceAnalytics). NO hand-synth prod/cumprod/sum.
#   - 10-component bt_result via build_bt_result() -> audit_bt_result() -> save_bt_result().
#
# Measurement basis: MONTHLY (R05 leg available only monthly). Sleeve leg reconstructed
#   share-based (daily-within-month compound via Return.portfolio) then aggregated monthly,
#   so the 2-leg book is combined on a consistent monthly grid.
# =============================================================================

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
options(warn = 1)
root <- "G:/Quant_Module_Moltbot"; setwd(root)
set.seed(606)

WT_ID    <- "WT-D20260606_001"
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
STAGE    <- "stage_artifacts/WT_D20260606_001"
OUT      <- file.path(STAGE, "output"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
BT_OUT   <- file.path(WT_DIR, "backtest_result"); dir.create(BT_OUT, showWarnings = FALSE, recursive = TRUE)
COST_BPS <- 15 / 1e4
A_BOOK   <- 0.15  # selected book allocation to sleeve (overlay OFF deliverable)

source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(root, "02_Infrastructure/contracts/save_bt_result.R"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

cat("=== [0] HASH AUDIT (start) — 3-package md5 ===\n")
md5 <- function(p) tools::md5sum(p)[[1]]
alpha_p <- file.path(WT_DIR, "alpha_package.json")
risk_p  <- file.path(WT_DIR, "risk_package.json")
opt_p   <- file.path(WT_DIR, "optimization_package.json")
hash_start <- list(alpha = md5(alpha_p), risk = md5(risk_p), opt = md5(opt_p))
print(unlist(hash_start))

# ---------------------------------------------------------------------------
# [1] Load packages + weights.csv (as-is) + R05 frozen leg + RAWDATA
# ---------------------------------------------------------------------------
cat("\n=== [1] Load inputs ===\n")
alpha_pkg <- fromJSON(alpha_p, simplifyVector = FALSE)
opt_pkg   <- fromJSON(opt_p,   simplifyVector = FALSE)

W <- fread(file.path(STAGE, "weights.csv"))
W[, Date := as.Date(Date)]; W[, as_of_date := as.Date(as_of_date)]
stopifnot(all(c("Date","Ticker","sleeve_weight","overlay_exposure") %in% names(W)))
sig_dates <- sort(unique(W$Date))
cat(sprintf("  weights.csv: %d dates x 20 names | overlay 0.3 in %d months\n",
            length(sig_dates), length(unique(W[overlay_exposure < 1]$Date))))

# R05 frozen incumbent leg (monthly net, M4 overlay) — DO NOT modify
r05dt <- as.data.table(read_parquet(
  "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
r05dt <- r05dt[!is.na(ret_net), .(Date, ym = format(Date, "%Y-%m"), r05_net = ret_net)]
setorder(r05dt, Date)
cat(sprintf("  R05 frozen leg: %d months %s..%s\n", nrow(r05dt),
            as.character(min(r05dt$Date)), as.character(max(r05dt$Date))))

RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                  col_select = c("Date","Ticker","Close","BM_Ret")))
RAW[, Date := as.Date(Date)]
setkey(RAW, Ticker, Date)

# ---------------------------------------------------------------------------
# [2] Hard-constraint re-verification (per sig_date)
# ---------------------------------------------------------------------------
cat("\n=== [2] Hard constraints (per Date) ===\n")
chk <- W[, .(n = .N, sumw = sum(sleeve_weight), maxw = max(sleeve_weight)), by = Date]
stopifnot(max(chk$n) <= 25)                  # max_names cap 25
stopifnot(all(W$sleeve_weight >= -1e-9))     # long-only
stopifnot(max(abs(chk$sumw - 1)) < 1e-6)     # Sw = 1 (sleeve)
stopifnot(max(chk$maxw) <= 0.20 + 1e-9)      # weight bound
cat(sprintf("  PASS: n<=%d, long-only, Sw=1, maxw=%.3f<=0.20\n", max(chk$n), max(chk$maxw)))

# ---------------------------------------------------------------------------
# [3] Sleeve share-based monthly net return reconstruction
#     For each sig_date t: hold 20 names at sleeve_weight, buy-and-hold to next sig_date.
#     Daily portfolio return via Return.portfolio (share drift), aggregate to monthly,
#     deduct 15bps one-way on turnover at each rebalance.
# ---------------------------------------------------------------------------
cat("\n=== [3] Sleeve share-based NAV reconstruction (Return.portfolio daily) ===\n")

held_tk <- unique(W$Ticker)
px <- RAW[Ticker %in% held_tk & !is.na(Close), .(Date, Ticker, Close)]
setkey(px, Ticker, Date)
# daily simple returns per ticker
setorder(px, Ticker, Date)
px[, ret := Close / shift(Close, 1L) - 1, by = Ticker]

all_trading <- sort(unique(RAW$Date))
# build a daily weights matrix: at each sig_date, set target sleeve weights; carry forward
# We use PerformanceAnalytics Return.portfolio with a monthly-rebalanced weight xts.

# Wide daily returns for held tickers
retw <- dcast(px[!is.na(ret)], Date ~ Ticker, value.var = "ret")
ret_dates <- retw$Date
ret_mat <- as.matrix(retw[, -1]); rownames(ret_mat) <- as.character(ret_dates)
ret_mat[is.na(ret_mat)] <- 0
ret_xts_assets <- xts(ret_mat, order.by = ret_dates)

# weight xts on rebalance (sig) dates: align each sig_date to the nearest trading day <= sig_date
align_to_trading <- function(d, trd) {
  idx <- findInterval(d, trd); trd[pmax(idx, 1)]
}
trd <- ret_dates
Wd <- copy(W)
Wd[, rebal_day := align_to_trading(Date, trd)]
# build weight matrix rows = rebal days, cols = all held tickers
wcast <- dcast(Wd, rebal_day ~ Ticker, value.var = "sleeve_weight", fill = 0)
wdays <- wcast$rebal_day
wmat <- as.matrix(wcast[, -1])
# ensure same column order/space as asset returns
allcols <- colnames(ret_xts_assets)
wfull <- matrix(0, nrow = nrow(wmat), ncol = length(allcols), dimnames = list(NULL, allcols))
common <- intersect(colnames(wmat), allcols)
wfull[, common] <- wmat[, common]
weights_xts <- xts(wfull, order.by = wdays)

# Return.portfolio: daily contributions, monthly rebalance to sleeve weights -> GROSS daily sleeve returns
rp <- Return.portfolio(R = ret_xts_assets, weights = weights_xts,
                       rebalance_on = NA, verbose = TRUE)
sleeve_daily_gross <- rp$returns
colnames(sleeve_daily_gross) <- "sleeve_gross"

# Aggregate to monthly gross (Return.cumulative within month)
sleeve_m_gross <- apply.monthly(sleeve_daily_gross, Return.cumulative)
sleeve_m_gross_dt <- data.table(Date = as.Date(index(sleeve_m_gross)),
                                ym = format(as.Date(index(sleeve_m_gross)), "%Y-%m"),
                                gross = as.numeric(sleeve_m_gross))

# turnover at each rebalance (one-way), cost = turnover * 15bps, charged in the month of rebalance
wlong <- Wd[, .(rebal_day, Ticker, w = sleeve_weight)]
wc <- dcast(wlong, rebal_day ~ Ticker, value.var = "w", fill = 0)
wm <- as.matrix(wc[, -1])
to_oneway <- c(NA, sapply(2:nrow(wm), function(i) sum(abs(wm[i, ] - wm[i - 1, ])) / 2))
to_dt <- data.table(rebal_day = wc$rebal_day, ym = format(wc$rebal_day, "%Y-%m"),
                    turnover_oneway = to_oneway)
to_dt[, cost := fifelse(is.na(turnover_oneway), 0, turnover_oneway * 2 * COST_BPS)]  # round-trip at rebalance

sleeve_m <- merge(sleeve_m_gross_dt, to_dt[, .(ym, turnover_oneway, cost)], by = "ym", all.x = TRUE)
sleeve_m[is.na(cost), cost := 0]
sleeve_m[, sleeve_net := gross - cost]
setorder(sleeve_m, ym)
cat(sprintf("  sleeve months: %d | mean turnover one-way/mo %.3f -> ann round-trip %.2f\n",
            nrow(sleeve_m), mean(sleeve_m$turnover_oneway, na.rm = TRUE),
            mean(sleeve_m$turnover_oneway, na.rm = TRUE) * 12 * 2))

# ---------------------------------------------------------------------------
# [4] Forward-month alignment to R05 (Jegadeesh-Titman, optimizer-consistent)
#     Sleeve weight as_of t earns FORWARD month return. R05 ret_net is already
#     the realized forward-month series keyed by ym. Join sleeve to R05 by realized ym.
# ---------------------------------------------------------------------------
cat("\n=== [4] Forward-month alignment sleeve <-> R05 ===\n")
# Sleeve monthly return realized in month ym corresponds to weights set at end of (ym-1).
# R05 r05_net at ym is realized return of month ym. Join by realized ym directly.
J <- merge(sleeve_m[, .(ym, sleeve_net)], r05dt[, .(ym, r05_net, Date)], by = "ym")
setorder(J, ym)
J <- J[is.finite(sleeve_net) & is.finite(r05_net)]
cat(sprintf("  overlap months sleeve<->R05: %d (%s..%s)\n", nrow(J),
            min(J$ym), max(J$ym)))

# Benchmark: KOSPI200 TR realized monthly (BM_Ret compounded within ym), aligned to realized ym
bm <- unique(RAW[!is.na(BM_Ret), .(Date, ym = format(Date, "%Y-%m"), BM_Ret)])
bm_m <- bm[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
J <- merge(J, bm_m, by = "ym", all.x = TRUE)
J <- J[is.finite(bm_ret)]
setorder(J, ym)
cat(sprintf("  panel with BM: %d months\n", nrow(J)))
J[, mdate := as.Date(paste0(ym, "-01"))]

# ---------------------------------------------------------------------------
# [5] BOOK construction = Return.portfolio 2-asset monthly rebalance [0.85 R05, 0.15 sleeve]
#     (overlay OFF — authoritative deliverable)
# ---------------------------------------------------------------------------
cat("\n=== [5] Book = Return.portfolio(0.85 R05 + 0.15 sleeve), monthly rebal ===\n")
twoasset <- xts(as.matrix(J[, .(R05 = r05_net, SLEEVE = sleeve_net)]), order.by = J$mdate)
book_rp <- Return.portfolio(twoasset, weights = c(1 - A_BOOK, A_BOOK),
                            rebalance_on = "months", verbose = FALSE)
book_ret <- as.numeric(book_rp); names(book_ret) <- as.character(J$mdate)
J[, book_net := book_ret]

# Incumbent R05-only book on same panel (baseline for book-marginal dIR)
r05_only <- xts(J$r05_net, order.by = J$mdate)
bm_xts   <- xts(J$bm_ret,  order.by = J$mdate)
book_xts <- xts(J$book_net, order.by = J$mdate)

# ---------------------------------------------------------------------------
# [6] sim_result for build_bt_result (10-component contract, monthly)
# ---------------------------------------------------------------------------
cat("\n=== [6] build_bt_result (10-component, metric_type=backtested) ===\n")
# Daily NAV grid: use monthly NAV points (book is monthly). build_nav computes DD on these.
book_nav <- cumprod(1 + J$book_net)
DAILY_NAV_DT <- data.table(Date = J$mdate, NAV = book_nav, NAV_gross = book_nav)  # net=gross (cost already in sleeve_net/r05_net)

# holdings log: effective book weights per name per month (R05 leg is a return series, sleeve names explicit)
hold_log <- Wd[Date %in% (function(){
  # map realized ym back to sig as_of: sleeve weights at as_of end-of-(ym-1)
  sig_dates
})()]
HOLDINGS_LOG <- W[, .(date = as_of_date, ticker = Ticker,
                      actual_weight = sleeve_weight * A_BOOK)]  # sleeve-leg book contribution

sim_result <- list(
  DAILY_NAV_DT  = DAILY_NAV_DT,
  strategy_xts  = book_xts,
  bm_xts        = bm_xts,
  HOLDINGS_LOG  = HOLDINGS_LOG,
  PORTFOLIO_LOG = NULL
)

strategy_spec <- list(
  strategy_name      = "WT-D20260606_001_R05_plus_residmom_a0.15",
  rebalance_frequency = "monthly",
  execution_date_rule = "month_end_signal_t_plus_1",
  universe           = "KOSPI200 U KOSDAQ150",
  n_holdings_target  = 20L,
  weighting          = "multi_sleeve_0.85R05_0.15EW",
  cost_model_version = "v2.3_kr_retail_15bps",
  lookahead_prevention = "PIT C1-C15: forward-month alignment (Jegadeesh-Titman, score t-1 close -> realized t..t+1); R05 leg frozen ret_net (no re-fit); sleeve prices t-1 close; weights.csv as-is (no alpha_scores re-selection). NOTE: alpha C15 caveat inherited (alpha read factor_db parquet directly, not load_month_factors) — forge measures via contract path, byte-identical Z_Score cache.",
  survivorship_bias_control = "RAWDATA full KR universe incl. delisted (no survivor filter); weights.csv holdings PIT from alpha_scores cutoff"
)

run_id <- sprintf("%s_a015_%s", WT_ID, format(Sys.time(), "%Y%m%d%H%M%S"))
bt <- build_bt_result(
  sim_result = sim_result, strategy_spec = strategy_spec,
  run_id = run_id, strategy_id = "WT-D20260606_001_a0.15",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "KR_K200_KQ150",
  code_version = "forge_v6.1_pure_function_WTD20260606_001",
  created_by_agent = "forge"
)

cat("\n=== [7] audit_bt_result ===\n")
bt <- audit_bt_result(bt)
cat(sprintf("  integrity_status = %s\n", bt$manifest$integrity_status))

cat("\n=== [8] save_bt_result (10-component CSV/JSON/RDS/XLSX) ===\n")
save_dir <- file.path(BT_OUT, "output_a015")
save_bt_result(bt, save_dir)

# ---------------------------------------------------------------------------
# [9] Gates (authoritative) — net SR / CAGR / MDD / Calmar / PORT_t / oos_retention / DSR / dIR
# ---------------------------------------------------------------------------
cat("\n=== [9] Authoritative gates ===\n")
nw_t_mean <- function(x, L = 3) {
  x <- x[is.finite(x)]; n <- length(x); mu <- mean(x); e <- x - mu
  g0 <- sum(e^2)/n; v <- g0
  if (L > 0) for (l in 1:L) { wt <- 1 - l/(L+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*wt*gl }
  mu / sqrt(v/n)
}
ann_metrics <- function(x) {
  xx <- xts(x, order.by = J$mdate)
  ar <- as.numeric(Return.annualized(xx, scale = 12))
  sd <- as.numeric(StdDev.annualized(xx, scale = 12))
  list(CAGR = ar, Vol = sd, SR = ar/sd, MDD = as.numeric(maxDrawdown(xx)))
}
m_book <- ann_metrics(J$book_net)
m_r05  <- ann_metrics(J$r05_net)

# active vs BM
act_book <- J$book_net - J$bm_ret
act_r05  <- J$r05_net  - J$bm_ret
ir_book  <- mean(act_book)/sd(act_book)*sqrt(12)
ir_r05   <- mean(act_r05)/sd(act_r05)*sqrt(12)
port_t_book <- nw_t_mean(act_book, 3)
port_t_r05  <- nw_t_mean(act_r05, 3)
dIR <- ir_book - ir_r05

calmar_book <- m_book$CAGR / m_book$MDD

# oos_retention: active Sharpe OOS/IS. Split panel 70/30 by time.
n <- nrow(J); cut <- floor(n * 0.7)
sr_active <- function(a) mean(a)/sd(a)*sqrt(12)
is_sr  <- sr_active(act_book[1:cut])
oos_sr <- sr_active(act_book[(cut+1):n])
oos_retention <- oos_sr / is_sr

# DSR (Deflated Sharpe). n_trials: book is the selected design among optimizer's 9 candidates
# + alpha 8-candidate sweep -> multiple-testing style. Use n_trials per measurement-graduation.
# Compute observed SR (book net, monthly, annualized->per-period), skew/kurt of book_net.
deflated_sr <- function(rets, n_trials) {
  rets <- rets[is.finite(rets)]; Tn <- length(rets)
  sr <- mean(rets)/sd(rets)               # per-period SR
  g3 <- PerformanceAnalytics::skewness(rets); g4 <- PerformanceAnalytics::kurtosis(rets) + 3
  # SR0 = expected max SR under N null trials (Bailey-Lopez de Prado 2014)
  emc <- 0.5772156649
  z1 <- qnorm(1 - 1/n_trials); z2 <- qnorm(1 - 1/n_trials * exp(-1))
  sr0_var <- 1  # var of trial SR ~ 1 under null (per-period, T-normalized handled below)
  sr_star <- sqrt((1 - g3*sr + (g4-1)/4*sr^2)/(Tn-1))  # SR estimation SE
  expmax <- (1 - emc)*z1 + emc*z2
  sr0 <- expmax * sqrt(1/Tn)  # benchmark threshold SR (per-period scale approx)
  psr_arg <- ((sr - sr0) * sqrt(Tn - 1)) / sqrt(1 - g3*sr + (g4-1)/4*sr^2)
  list(dsr = pnorm(psr_arg), sr_pp = sr, sr0_pp = sr0)
}
n_trials_book <- 9L   # optimizer candidates_tried (book selection sweep)
dsr_res <- deflated_sr(J$book_net, n_trials_book)

cat(sprintf("  BOOK net : SR %.4f CAGR %.4f Vol %.4f MDD %.4f Calmar %.4f\n",
            m_book$SR, m_book$CAGR, m_book$Vol, m_book$MDD, calmar_book))
cat(sprintf("  R05 net  : SR %.4f CAGR %.4f MDD %.4f IR %.4f PORT_t %.3f\n",
            m_r05$SR, m_r05$CAGR, m_r05$MDD, ir_r05, port_t_r05))
cat(sprintf("  BOOK     : IR %.4f PORT_t(NW3) %.3f | dIR vs R05 %+.4f (thr 0.05)\n",
            ir_book, port_t_book, dIR))
cat(sprintf("  oos_retention %.3f (IS %.3f / OOS %.3f) | DSR(n=%d) %.4f (sr_pp %.4f vs sr0 %.4f)\n",
            oos_retention, is_sr, oos_sr, n_trials_book, dsr_res$dsr, dsr_res$sr_pp, dsr_res$sr0_pp))

# benchmark_compare PORT_t from contract (cross-check)
bc <- bt$benchmark_compare
port_t_contract <- bc[metric_name == "Portfolio_Alpha_t_NW_lag3"]$active_value
ir_contract     <- bc[metric_name == "Information_Ratio"]$active_value
cat(sprintf("  [contract xcheck] PORT_t %.3f  IR %.3f\n", port_t_contract, ir_contract))

# ---------------------------------------------------------------------------
# [10] Overlay ON reference (regime de-risk: crisis months exposure 0.3)
# ---------------------------------------------------------------------------
cat("\n=== [10] Overlay ON reference ===\n")
ov <- W[, .(ym_sig = format(as_of_date, "%Y-%m"), exposure = overlay_exposure)][!duplicated(ym_sig)]
# exposure set at as_of (end of prior month) applies to forward (realized) month -> shift to realized ym
ov[, ym := format(as.Date(paste0(ym_sig, "-01")) + 32, "%Y-%m")]  # next month realized
Jov <- merge(J, ov[, .(ym, exposure)], by = "ym", all.x = TRUE)
Jov[is.na(exposure), exposure := 1.0]
setorder(Jov, ym)
# de-risked book: exposure fraction invested, (1-exposure) in cash (0 return)
book_ov <- Jov$exposure * Jov$book_net
m_ov <- {
  xx <- xts(book_ov, order.by = Jov$mdate)
  list(SR = as.numeric(Return.annualized(xx,12)/StdDev.annualized(xx,12)),
       CAGR = as.numeric(Return.annualized(xx,12)),
       MDD = as.numeric(maxDrawdown(xx)))
}
act_ov <- book_ov - Jov$bm_ret
ir_ov <- mean(act_ov)/sd(act_ov)*sqrt(12)
cat(sprintf("  Overlay ON: SR %.4f CAGR %.4f MDD %.4f IR %.4f (dIR %+.4f) | crisis months %d\n",
            m_ov$SR, m_ov$CAGR, m_ov$MDD, ir_ov, ir_ov - ir_r05, sum(Jov$exposure < 1)))

# ---------------------------------------------------------------------------
# [11] vs optimizer design-stage reconciliation
# ---------------------------------------------------------------------------
opt_design_book_sr <- as.numeric(opt_pkg$expected_book_sr %||% NA)        # 1.701
opt_design_dIR     <- as.numeric(opt_pkg$book_marginal_dIR$delta_ir_EW_a0.15 %||% NA) # 0.049
opt_design_r05_ir  <- as.numeric(opt_pkg$book_marginal_dIR$incumbent_ir %||% NA)      # 0.661
cat(sprintf("\n=== [11] vs optimizer design-stage ===\n"))
cat(sprintf("  opt design book SR %.3f vs forge %.4f (div %+.4f)\n",
            opt_design_book_sr, m_book$SR, m_book$SR - opt_design_book_sr))
cat(sprintf("  opt design dIR %.3f vs forge %.4f | opt R05 IR %.3f vs forge %.4f\n",
            opt_design_dIR, dIR, opt_design_r05_ir, ir_r05))

# ---------------------------------------------------------------------------
# [12] HASH AUDIT (end)
# ---------------------------------------------------------------------------
hash_end <- list(alpha = md5(alpha_p), risk = md5(risk_p), opt = md5(opt_p))
hash_pass <- identical(hash_start, hash_end)
cat(sprintf("\n=== [12] HASH AUDIT end: pass=%s ===\n", hash_pass))

# ---------------------------------------------------------------------------
# [13] OOS Chart Mandate (v6.1): equity_curve / annual_returns / oos_zoom / regime_decomposition
# ---------------------------------------------------------------------------
cat("\n=== [13] OOS charts ===\n")
book_cum <- cumprod(1 + J$book_net)
r05_cum  <- cumprod(1 + J$r05_net)
bm_cum   <- cumprod(1 + J$bm_ret)
dts <- J$mdate
# Lockbox/OOS marker: R05 train-cutoff ~ 2023-12 (alpha lockbox); OOS = beyond
oos_start <- as.Date("2024-01-01")

png(file.path(OUT, "equity_curve.png"), width = 1100, height = 620)
plot(dts, book_cum, type = "l", log = "y", col = "blue", lwd = 2,
     main = "WT-D20260606_001 Book (0.85 R05 + 0.15 ResidMom) — Equity Curve (net, log)",
     xlab = "", ylab = "Growth of 1 (net)")
lines(dts, r05_cum, col = "darkgreen", lwd = 1.6, lty = 2)
lines(dts, bm_cum, col = "grey50", lwd = 1.2)
abline(v = oos_start, col = "red", lty = 3)
legend("topleft", c("Book a0.15", "R05 incumbent", "KOSPI200 TR", "OOS marker 2024-01"),
       col = c("blue","darkgreen","grey50","red"), lwd = c(2,1.6,1.2,1), lty = c(1,2,1,3), bty = "n")
dev.off()

# annual returns
yr <- data.table(year = as.integer(format(dts, "%Y")), book = J$book_net, r05 = J$r05_net, bm = J$bm_ret)
yra <- yr[, .(book = prod(1+book)-1, r05 = prod(1+r05)-1, bm = prod(1+bm)-1), by = year]
png(file.path(OUT, "annual_returns.png"), width = 1100, height = 560)
bp <- barplot(t(as.matrix(yra[, .(book, r05, bm)])), beside = TRUE,
              names.arg = yra$year, col = c("blue","darkgreen","grey60"),
              main = "Annual Returns: Book vs R05 vs KOSPI200 TR (net)", las = 2, cex.names = 0.7)
legend("topright", c("Book","R05","KOSPI200"), fill = c("blue","darkgreen","grey60"), bty = "n")
abline(h = 0)
dev.off()

# OOS zoom: recent 5Y (2021-06..) + lockbox-beyond
zoom_from <- as.Date("2021-06-01")
zi <- dts >= zoom_from
png(file.path(OUT, "oos_zoom_chart.png"), width = 1100, height = 560)
plot(dts[zi], cumprod(1+J$book_net[zi]), type = "l", col = "blue", lwd = 2,
     main = "OOS Zoom (recent 5Y, rebased): Book vs R05 vs KOSPI200",
     xlab = "", ylab = "Growth of 1 (rebased)")
lines(dts[zi], cumprod(1+J$r05_net[zi]), col = "darkgreen", lwd = 1.6, lty = 2)
lines(dts[zi], cumprod(1+J$bm_ret[zi]), col = "grey50", lwd = 1.2)
abline(v = oos_start, col = "red", lty = 3)
legend("topleft", c("Book","R05","KOSPI200","OOS 2024-01"),
       col = c("blue","darkgreen","grey50","red"), lwd = c(2,1.6,1.2,1), lty = c(1,2,1,3), bty = "n")
dev.off()

# regime decomposition: overlay crisis (exposure<1) vs normal months — SR/CAGR per regime
Jr <- merge(J, Jov[, .(ym, exposure)], by = "ym", all.x = TRUE); Jr[is.na(exposure), exposure := 1]
reg_stats <- Jr[, .(n = .N,
                    book_sr = mean(book_net)/sd(book_net)*sqrt(12),
                    book_cagr = prod(1+book_net)^(12/.N)-1),
                by = .(regime = ifelse(exposure < 1, "Crisis(overlay)", "Normal"))]
png(file.path(OUT, "regime_decomposition.png"), width = 900, height = 520)
par(mfrow = c(1,2))
barplot(reg_stats$book_sr, names.arg = reg_stats$regime, col = c("firebrick","steelblue"),
        main = "Book SR by regime", ylab = "Annualized SR"); abline(h=0)
barplot(reg_stats$book_cagr, names.arg = reg_stats$regime, col = c("firebrick","steelblue"),
        main = "Book CAGR by regime", ylab = "CAGR"); abline(h=0)
dev.off()
cat("  charts written to", OUT, "\n")
print(reg_stats)

# ---------------------------------------------------------------------------
# Persist computed metrics for forge_package assembly
# ---------------------------------------------------------------------------
metrics_out <- list(
  n_months = nrow(J), period = c(min(J$ym), max(J$ym)),
  book = c(SR = m_book$SR, CAGR = m_book$CAGR, Vol = m_book$Vol, MDD = m_book$MDD,
           Calmar = calmar_book, IR = ir_book, PORT_t = port_t_book,
           oos_retention = oos_retention, oos_is_sr = is_sr, oos_oos_sr = oos_sr,
           DSR = dsr_res$dsr, dIR_vs_R05 = dIR),
  r05 = c(SR = m_r05$SR, CAGR = m_r05$CAGR, MDD = m_r05$MDD, IR = ir_r05, PORT_t = port_t_r05),
  overlay_on = c(SR = m_ov$SR, CAGR = m_ov$CAGR, MDD = m_ov$MDD, IR = ir_ov),
  contract = c(PORT_t = port_t_contract, IR = ir_contract),
  opt_design = c(book_sr = opt_design_book_sr, dIR = opt_design_dIR, r05_ir = opt_design_r05_ir),
  hash_start = hash_start, hash_end = hash_end, hash_pass = hash_pass,
  run_id = run_id, save_dir = save_dir,
  turnover_sleeve_oneway_mo = mean(sleeve_m$turnover_oneway, na.rm = TRUE),
  book_turnover_rt = mean(sleeve_m$turnover_oneway, na.rm = TRUE) * 12 * 2 * A_BOOK,
  integrity_status = bt$manifest$integrity_status,
  n_trials_book = n_trials_book,
  dsr_sr_pp = dsr_res$sr_pp, dsr_sr0_pp = dsr_res$sr0_pp
)
saveRDS(list(J = J, Jov = Jov, bt = bt, metrics = metrics_out, sleeve_m = sleeve_m),
        file.path(STAGE, "forge_intermediate.rds"))
cat("\n[saved forge_intermediate.rds]\n")
cat("=== FORGE run_all.R complete ===\n")
