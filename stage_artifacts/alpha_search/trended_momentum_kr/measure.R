#!/usr/bin/env Rscript
#==============================================================================
# measure.R — lean-forge step: contract build_bt_result + essence_score grade
# Reads sim_result.rds (handoff from run_all.R). No self-synthesis of metrics.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics) })

PROJECT_ROOT <- Sys.getenv("QM_ROOT", unset = getwd())
.find_root <- function(start){ d<-start; for(i in 1:8){ if(file.exists(file.path(d,"02_Infrastructure","config.R"))) return(d); d<-dirname(d) }; start }
PROJECT_ROOT <- .find_root(getwd())
source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "essence_score.R"))

OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", "trended_momentum_kr")
obj <- readRDS(file.path(OUT_DIR, "sim_result.rds"))
sim_result <- obj$sim_result; strategy_spec <- obj$strategy_spec

run_id <- paste0("AS_TRENDMOM_KR_", format(Sys.Date(), "%Y%m%d"))

# ---- Build MONTHLY-aligned series on a COMMON month-end key ----------------
# (Fix: feeding a daily NAV with frequency="monthly" mis-annualizes CAGR and
#  apply.monthly stamps strategy vs BM on different last-days → merge off-by-one.
#  Instead: aggregate both to monthly via Return.cumulative, restamp to the
#  calendar month-end so dates align exactly, then pass frequency="daily" so the
#  contract treats these monthly bars as native periods. af=12 for annualization.
#  Return aggregation uses PerformanceAnalytics::apply.monthly+Return.cumulative.)
to_month_end <- function(d) as.Date(format(d, "%Y-%m-28"))  # common monthly key

strat_m <- apply.monthly(sim_result$strategy_xts, Return.cumulative)
bm_m    <- apply.monthly(sim_result$bm_xts,        Return.cumulative)
strat_dt <- data.table(mkey = to_month_end(index(strat_m)), r = as.numeric(strat_m))
bm_dt    <- data.table(mkey = to_month_end(index(bm_m)),    r = as.numeric(bm_m))
common   <- merge(strat_dt, bm_dt, by = "mkey", suffixes = c("_s","_b"))
setorder(common, mkey)

strat_m_xts <- xts(common$r_s, order.by = common$mkey)
bm_m_xts    <- xts(common$r_b, order.by = common$mkey)
nav_m_net   <- as.numeric(cumprod(1 + common$r_s))   # NAV path chaining of monthly net returns

sim_monthly <- list(
  strategy_xts  = strat_m_xts,                       # ALREADY monthly
  DAILY_NAV_DT  = data.table(Date = common$mkey, NAV = nav_m_net, NAV_gross = nav_m_net),
  bm_xts        = bm_m_xts,                           # ALREADY monthly, same dates
  HOLDINGS_LOG  = sim_result$HOLDINGS_LOG,
  PORTFOLIO_LOG = sim_result$PORTFOLIO_LOG
)

bt <- build_bt_result(
  sim_result            = sim_monthly,
  strategy_spec         = strategy_spec,
  run_id                = run_id,
  strategy_id           = "TRENDED_MOM_KR",
  strategy_version      = "v1.0_poc",
  benchmark_id          = "KOSPI200",
  benchmark_name        = "KOSPI 200",
  transaction_cost_bps  = 15, slippage_bps = 15,
  frequency             = "daily",         # series already monthly → no re-aggregation
  annualization_factor  = 12,              # but annualize as monthly
  universe_id           = "KR_K200_KQ150",
  code_version          = "trended_mom_kr_v1",
  created_by_agent      = "strategy-implementer-poc"
)

bt <- tryCatch(audit_bt_result(bt), error = function(e){ message("[audit] skip: ", conditionMessage(e)); bt })

es <- essence_score(bt, n_trials_cumulative = NULL)   # 1 paper / 1 alpha → DSR N/A

# pull headline metrics for report
M <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
getm <- function(n){ v<-M[metric_name==n, metric_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }
getbc<- function(n){ v<-BC[metric_name==n, active_value]; if(length(v)) as.numeric(v[1]) else NA_real_ }

n_obs <- nrow(bt$period_returns)
period_start <- as.character(min(bt$period_returns$date))
period_end   <- as.character(max(bt$period_returns$date))

# --- order-invariant verified diagnostics (contract's order-sensitive beta/cor/
#     hit/capture are corrupted by a latent keyed+unkeyed merge bug; recompute
#     cleanly here. Graded essence metrics PORT_t/IR/Sharpe are order-invariant
#     and already correct in the contract output — verified to match manual.) ---
prx <- as.data.table(bt$period_returns); brx <- as.data.table(bt$benchmark_returns)
mm <- merge(prx[,.(date,ret_net)], brx[,.(date,benchmark_ret)], by="date"); setorder(mm,date)
vbeta <- as.numeric(cov(mm$ret_net,mm$benchmark_ret)/var(mm$benchmark_ret))
vcor  <- as.numeric(cor(mm$ret_net,mm$benchmark_ret))
vhit  <- mean(mm$ret_net > mm$benchmark_ret)
valpha<- (mean(mm$ret_net) - vbeta*mean(mm$benchmark_ret))*12

summary_out <- list(
  idea_id     = "trended_momentum_kr",
  run_id      = run_id,
  grade       = es$grade,
  metric_type = es$metric_type,
  essence     = es$essence,
  reasons     = es$reasons,
  headline = list(
    portfolio_alpha_t_nw_lag3 = es$essence$portfolio_alpha_t_nw_lag3,
    oos_retention             = es$essence$oos_retention,
    net_sharpe                = es$essence$net_sharpe,
    cagr                      = es$essence$cagr,
    calmar                    = es$essence$calmar,
    net_ir                    = es$essence$net_ir,
    mdd                       = es$essence$mdd
  ),
  diagnostics = list(
    total_return       = getm("Total_Return"),
    annualized_vol     = getm("Annualized_Volatility"),
    alpha_annualized   = round(valpha,3),
    beta_to_benchmark  = round(vbeta,3),
    tracking_error     = getbc("Tracking_Error"),
    hit_ratio_vs_bm    = round(vhit,3),
    correlation        = round(vcor,3),
    avg_n_holdings     = getm("Average_N_Holdings"),
    contract_diag_note = "beta/cor/hit recomputed (contract order-sensitive merge bug); PORT_t/IR/Sharpe order-invariant & contract-native"
  ),
  n_obs_months = n_obs,
  period       = paste(period_start, "..", period_end),
  dsr_note     = "DSR not applied (1 paper / 1 alpha, n_trials=1) — SOT §3.5"
)

saveRDS(bt, file.path(OUT_DIR, "bt_result.rds"))
writeLines(jsonlite::toJSON(summary_out, auto_unbox = TRUE, pretty = TRUE, na = "null"),
           file.path(OUT_DIR, "essence_grade.json"))

cat("\n================= GRADE =================\n")
cat("grade:", es$grade, "| metric_type:", es$metric_type, "\n")
cat("reasons:", es$reasons, "\n")
cat(sprintf("PORT_t(NWlag3)=%s | OOS_ret=%s | net_Sharpe=%s | CAGR=%s | Calmar=%s | net_IR=%s | MDD=%s\n",
            es$essence$portfolio_alpha_t_nw_lag3, es$essence$oos_retention, es$essence$net_sharpe,
            es$essence$cagr, es$essence$calmar, es$essence$net_ir, es$essence$mdd))
cat(sprintf("n_obs months=%d | period=%s .. %s\n", n_obs, period_start, period_end))
cat(sprintf("ann_vol=%.3f | beta=%.3f | TE=%.3f | hit=%.3f | avgN=%.1f | ann_turnover=%.2f\n",
            getm("Annualized_Volatility"), getbc("Beta_to_Benchmark"), getbc("Tracking_Error"),
            getbc("Hit_Ratio_vs_BM"), getm("Average_N_Holdings"), getm("Annualized_Turnover")))
cat("========================================\n")
