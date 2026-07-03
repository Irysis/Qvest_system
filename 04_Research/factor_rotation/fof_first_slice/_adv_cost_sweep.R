suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

DIR <- "04_Research/factor_rotation/fof_first_slice"
rp <- function(f) as.data.table(read_parquet(file.path(DIR, f)))

bench <- rp("kns_master_bench.parquet")
bench <- bench[is.finite(BM_Ret)]

run_universe <- function(univ) {
  sc  <- rp(sprintf("kns_scores_L2_%s.parquet", univ))
  ret <- rp(sprintf("kns_ret_%s.parquet", univ))
  liq <- rp(sprintf("kns_liq_%s.parquet", univ))
  ret <- ret[is.finite(Ret_1m)]
  # align: scores Date <= max(ret Date) (drop holdings-only last month)
  maxret <- max(ret$Date)
  sc  <- sc[Date <= maxret]

  # calmar helper from period_returns (PerformanceAnalytics-style via canonical outputs)
  # We compute CAGR and MDD on ret_net (net active-book NAV is ret_net series itself)
  costs <- c(15, 30, 50, 75, 100)
  out <- list()
  turn_report <- NA_real_
  for (cb in costs) {
    cs <- canonical_screen_bt(scores_dt = sc, returns_dt = ret, bench_dt = bench,
                              top_n = 25L, cost_bps_oneway = cb,
                              liq_dt = liq, liq_min = 2e8,
                              run_id = sprintf("%s_c%d", univ, cb),
                              strategy_id = sprintf("KNS_L2_%s", univ))
    pr <- as.data.table(cs$period_returns)
    setorder(pr, date)
    # net book NAV (ret_net is net-of-cost portfolio return, long-only book)
    n <- nrow(pr)
    nav <- cumprod(1 + pr$ret_net)
    yrs <- n / 12
    cagr <- nav[n]^(1/yrs) - 1
    # MDD on nav
    peak <- cummax(nav)
    dd <- nav/peak - 1
    mdd <- -min(dd)
    calmar <- if (mdd > 0) cagr / mdd else NA_real_
    turn_report <- cs$turnover_annual
    out[[as.character(cb)]] <- data.table(
      universe = univ, cost_bps = cb, n_months = cs$n_months,
      port_t = round(cs$portfolio_alpha_t_nw_lag3, 3),
      net_SR = round(cs$net_sr, 3),
      IR = round(cs$information_ratio, 3),
      CAGR = round(cagr, 4), MDD = round(mdd, 4),
      calmar = round(calmar, 3),
      turnover_annual = round(cs$turnover_annual, 3)
    )
  }
  rbindlist(out)
}

res <- rbindlist(list(run_universe("allliq"), run_universe("allclean")))
print(res)
saveRDS(res, file.path(DIR, "_adv_cost_sweep.rds"))
cat("TURNOVER_note: turnover_annual = mean(traded_t)*12, traded_t=sum(|w_t-w_{t-1}|) sum(buy+sell)\n")
cat("COST_SWEEP_DONE\n")
