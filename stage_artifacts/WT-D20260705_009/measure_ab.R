# measure_ab.R — WT-D20260705_009 Alpha Research: the core A/B test.
# Arm A (raw)      : top-25 by mu_hat
# Arm B (risk-adj) : top-25 by (mu_hat / sigma_hat)   [forecast information ratio]
# Both measured via canonical_screen_bt (contract-grade forge-authoritative PORT_t NW lag-3).
# Full period (2005~) AND post-2017 subperiod. Paired NW-t on monthly active-return SR difference.

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

STAGE <- file.path(ROOT, "stage_artifacts/WT-D20260705_009")
PANEL <- file.path(STAGE, "panel")
TOPN  <- 25L
COST  <- 15
LIQ_MIN <- 5e7   # WT universe_definition

norm_date <- function(dt) { dt[, Date := as.Date(cut(as.Date(Date), "month"))]; dt }

fc   <- norm_date(as.data.table(read_parquet(file.path(STAGE, "forecast_dist.parquet"))))
ret  <- norm_date(as.data.table(read_parquet(file.path(PANEL, "returns_monthly.parquet"))))
bench<- norm_date(as.data.table(read_parquet(file.path(PANEL, "benchmark_monthly.parquet"))))
uf   <- norm_date(as.data.table(read_parquet(file.path(PANEL, "universe_flags.parquet"))))

# liquidity filter table (Date,Ticker,adv) at signal month t (t-1 ADV proxy = trailing 20d ending month-end)
liq <- uf[, .(Date, Ticker, adv = adv20)]

# Arm scores
fc[, score_A := mu_hat]
fc[, score_B := mu_hat / sigma_hat]

run_arm <- function(score_col, date_filter = NULL, tag = "") {
  s <- fc[, .(Date, Ticker, score = get(score_col))][!is.na(score)]
  if (!is.null(date_filter)) s <- s[date_filter(Date)]
  r <- ret
  b <- bench
  if (!is.null(date_filter)) { r <- ret[date_filter(Date)]; b <- bench[date_filter(Date)] }
  res <- canonical_screen_bt(
    scores_dt = s, returns_dt = r[, .(Date, Ticker, Ret_1m)], bench_dt = b[, .(Date, BM_Ret)],
    top_n = TOPN, cost_bps_oneway = COST,
    liq_dt = liq, liq_min = LIQ_MIN,
    run_id = tag, strategy_id = tag, periods_per_year = 12L)
  res
}

post2017 <- function(d) d >= as.Date("2017-01-01")

# ---- run all four cells ----
A_full  <- run_arm("score_A", NULL,      "ArmA_full")
B_full  <- run_arm("score_B", NULL,      "ArmB_full")
A_p2017 <- run_arm("score_A", post2017,  "ArmA_post2017")
B_p2017 <- run_arm("score_B", post2017,  "ArmB_post2017")

# ---- paired NW-t on SR difference (bootstrap-free analytic via active-return series) ----
# We compare monthly ACTIVE net returns of Arm B vs Arm A on the OVERLAPPING months.
# SR diff significance: regress (activeB - activeA) on 1, NW lag-3 t on intercept? No -- that tests mean diff.
# For SR diff we use Ledoit-Wolf style: but simplest robust: paired mean-active diff NW-t (mean is the driver of
# long-only SR here since vol similar). We report BOTH mean-active-diff NW-t and delta SR.
nw_t_mean <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 5) return(NA_real_)
  mu <- mean(x); e <- x - mu; g0 <- sum(e^2)/n
  v <- g0
  for (l in 1:min(lag, n-1)) { w <- 1 - l/(lag+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*w*gl }
  se <- sqrt(v/n); if (se <= 0) return(NA_real_); mu/se
}

paired_diff <- function(resA, resB) {
  pa <- resA$period_returns; pb <- resB$period_returns
  if (is.null(pa) || is.null(pb)) return(list())
  pa <- as.data.table(pa)[, .(date, activeA = ret_net - benchmark_ret)]
  pb <- as.data.table(pb)[, .(date, activeB = ret_net - benchmark_ret)]
  m <- merge(pa, pb, by = "date")
  m[, diff := activeB - activeA]
  srA <- mean(m$activeA)/sd(m$activeA)*sqrt(12)
  srB <- mean(m$activeB)/sd(m$activeB)*sqrt(12)
  list(n = nrow(m), sr_A = srA, sr_B = srB, delta_sr = srB - srA,
       mean_diff_ann = mean(m$diff)*12, nw_t_mean_diff = nw_t_mean(m$diff, 3L))
}

pd_full  <- paired_diff(A_full,  B_full)
pd_p2017 <- paired_diff(A_p2017, B_p2017)

# ---- compact table ----
cell <- function(res) list(
  n_months = res$n_months,
  port_t_nw = res$portfolio_alpha_t_nw_lag3,
  port_t_pval = res$portfolio_alpha_t_pvalue,
  IR = res$information_ratio,
  net_sr = res$net_sr,
  alpha_ann = res$alpha_annualized,
  mean_active_net = res$mean_active_net,
  turnover_annual = res$turnover_annual
)

result <- list(
  wt = "WT-D20260705_009",
  metric_type = "canonical_screen",
  top_n = TOPN, cost_bps_oneway = COST, liq_min = LIQ_MIN,
  full = list(ArmA = cell(A_full), ArmB = cell(B_full), paired = pd_full),
  post2017 = list(ArmA = cell(A_p2017), ArmB = cell(B_p2017), paired = pd_p2017)
)

write_json(result, file.path(STAGE, "ab_result.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

# save benchmark_compare tables + period returns for audit
fwrite(A_full$benchmark_compare, file.path(STAGE, "bc_ArmA_full.csv"))
fwrite(B_full$benchmark_compare, file.path(STAGE, "bc_ArmB_full.csv"))
saveRDS(list(A_full=A_full$period_returns, B_full=B_full$period_returns,
             A_p2017=A_p2017$period_returns, B_p2017=B_p2017$period_returns),
        file.path(STAGE, "period_returns_ab.rds"))

fmt <- function(x) ifelse(is.null(x)||is.na(x), "NA", sprintf("%.3f", x))
cat("\n================ A/B RESULT (canonical_screen, forge-authoritative PORT_t) ================\n")
cat(sprintf("%-16s %8s %8s %8s %8s %8s %8s\n","cell","n_mo","PORT_t","IR","net_SR","alpha_a","TO"))
for (nm in c("full","post2017")) {
  for (arm in c("ArmA","ArmB")) {
    c1 <- result[[nm]][[arm]]
    cat(sprintf("%-16s %8s %8s %8s %8s %8s %8s\n",
      paste0(arm,"_",nm), c1$n_months, fmt(c1$port_t_nw), fmt(c1$IR),
      fmt(c1$net_sr), fmt(c1$alpha_ann), fmt(c1$turnover_annual)))
  }
}
cat("\n-- paired (B - A) --\n")
for (nm in c("full","post2017")) {
  p <- result[[nm]]$paired
  cat(sprintf("%-10s n=%s  SR_A=%s  SR_B=%s  dSR=%s  mean_diff_ann=%s  NW_t_diff=%s\n",
    nm, p$n, fmt(p$sr_A), fmt(p$sr_B), fmt(p$delta_sr), fmt(p$mean_diff_ann), fmt(p$nw_t_mean_diff)))
}
cat("\n[measure_ab] saved -> ab_result.json\n")
