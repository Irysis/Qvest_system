## build_bt_result 계약 산출 — turning-point 최우수 turning-point 변형(dynamic 충실판)
## + NOL4 base 참조. Portfolio_Alpha_t_NW_lag3 확정.
## 주: turning-point 변형은 base 대비 유의 열위(NW-t -3.90)라 "자본후보 최우수"가 아님.
##    계약은 (a) test 대상 dynamic 변형과 (b) NOL4 base 둘 다 산출해 PORT_t(vs BM) 기록.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(lubridate)
})
options(warn = 1)
BASE <- Sys.getenv("CLAUDE_PROJECT_DIR", getwd())
OUT  <- file.path(BASE, "stage_artifacts/pg2_turningpoint")
OFF  <- file.path(BASE, "stage_artifacts/pg2_offense_overlay")
source(file.path(BASE, "02_Infrastructure/contracts/backtest_result_contract.R"))

## series (run_turningpoint_faithful.R 산출)
s <- fread(file.path(OUT, "turningpoint_series.csv"))
s[, anchor_date := as.Date(anchor_date)]; setorder(s, realized_ym)

## 월간 BM 수익 (anchor_date에 정렬 — realized_ym 월수익)
bm <- as.data.table(read_parquet(file.path(OFF, "benchmark_pinned_20260702.parquet")))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
mret <- apply.monthly(xts(bm[[bcol]], order.by=bm$Date), Return.cumulative)
mdt <- data.table(ym=format(index(mret), "%Y-%m"), bm_ret=as.numeric(mret))
## 패널 return_ym = realized_ym - 1 이 실제 수익 월(윈도우). ret_orig는 return_ym 월 수익.
## 벤치도 동일 return_ym 월 수익으로 맞춰 active 산출.
s[, return_ym := format(as.Date(paste0(realized_ym,"-01")) %m-% months(1), "%Y-%m")]
s <- merge(s, mdt[, .(return_ym=ym, bm_ret)], by="return_ym", all.x=TRUE)
setorder(s, realized_ym)
stopifnot(sum(is.na(s$bm_ret))==0)

build_one <- function(ret_vec, sid) {
  strat_xts <- xts(ret_vec, order.by = s$anchor_date)
  nav <- cumprod(1 + ret_vec)
  nav_dt <- data.table(Date = s$anchor_date, NAV = nav, NAV_gross = nav)
  sim <- list(
    strategy_xts = strat_xts,
    DAILY_NAV_DT = nav_dt,
    bm_xts = xts(s$bm_ret, order.by = s$anchor_date),  # 월간 BM (anchor 1obs/월 → apply.monthly idempotent)
    HOLDINGS_LOG = NULL, PORTFOLIO_LOG = NULL
  )
  spec <- list(strategy_id = sid, strategy_name = sid, universe = "KOSPI200_overlay",
               rebalance_freq = "monthly", n_holdings_target = NA_integer_)
  bt <- build_bt_result(
    sim_result = sim, strategy_spec = spec,
    run_id = paste0("TP_", sid, "_", format(Sys.Date(), "%Y%m%d")),
    strategy_id = sid, strategy_version = "v1.0",
    benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "KOSPI200_overlay", code_version = "run_turningpoint_faithful",
    created_by_agent = "Q-Lead"
  )
  ## benchmark_returns 를 pinned KOSPI200 월수익으로 override (계약 기본은 sim 내 BM 없음)
  bt$benchmark_returns <- data.table(
    date = s$anchor_date, benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    benchmark_ret = s$bm_ret, frequency = "monthly"
  )
  ## benchmark_compare 재계산 (override된 BM으로)
  bt$benchmark_compare <- build_benchmark_compare(
    bt$period_returns, bt$benchmark_returns,
    run_id = bt$manifest$run_id[1], strategy_id = sid, annualization_factor = 12
  )
  bt
}

bt_dyn  <- build_one(s$ret_tp_dynamic,  "NOL4_x_tp_dynamic")
bt_base <- build_one(s$ret_NOL4_base,   "NOL4_base")

get_pa <- function(bt) {
  bc <- bt$benchmark_compare
  list(
    PORT_t = bc[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value],
    IR     = bc[metric_name=="Information_Ratio", active_value],
    TE     = bc[metric_name=="Tracking_Error", active_value],
    Alpha  = bc[metric_name=="Alpha_Annualized", active_value],
    Beta   = bc[metric_name=="Beta_to_Benchmark", strategy_value]
  )
}
pa_dyn <- get_pa(bt_dyn); pa_base <- get_pa(bt_base)
cat("\n===== Portfolio_Alpha_t_NW_lag3 (vs KOSPI200) =====\n")
cat(sprintf("  NOL4_base         : PORT_t=%.3f  IR=%.3f  Alpha=%.4f  Beta=%.3f\n",
    pa_base$PORT_t, pa_base$IR, pa_base$Alpha, pa_base$Beta))
cat(sprintf("  NOL4_x_tp_dynamic : PORT_t=%.3f  IR=%.3f  Alpha=%.4f  Beta=%.3f\n",
    pa_dyn$PORT_t, pa_dyn$IR, pa_dyn$Alpha, pa_dyn$Beta))
cat(sprintf("  ΔIR (dynamic - base) = %.4f  (book-marginal crit3: 필요 >= 0.05)\n",
    pa_dyn$IR - pa_base$IR))

## 최우수 turning-point 변형 = dynamic 충실판 (test 대상) 을 rds로 저장
saveRDS(bt_dyn, file.path(OUT, "bt_result_tp_dynamic.rds"))
saveRDS(bt_base, file.path(OUT, "bt_result_nol4_base.rds"))
val <- validate_bt_result(bt_dyn)
cat(sprintf("\n[validate] bt_dyn valid=%s %s\n", val$valid,
    if (length(val$errors)) paste(val$errors, collapse="; ") else ""))
cat("[DONE] rds:", file.path(OUT, "bt_result_tp_dynamic.rds"), "\n")

## meta append
mj <- jsonlite::fromJSON(file.path(OUT, "turningpoint_meta.json"))
mj$contract <- list(
  benchmark="KOSPI200 (pinned, monthly return_ym-aligned)",
  NOL4_base=list(PORT_t=round(pa_base$PORT_t,3), IR=round(pa_base$IR,3), Alpha=round(pa_base$Alpha,4), Beta=round(pa_base$Beta,3)),
  NOL4_x_tp_dynamic=list(PORT_t=round(pa_dyn$PORT_t,3), IR=round(pa_dyn$IR,3), Alpha=round(pa_dyn$Alpha,4), Beta=round(pa_dyn$Beta,3)),
  dIR_dynamic_minus_base=round(pa_dyn$IR - pa_base$IR,4)
)
jsonlite::write_json(mj, file.path(OUT, "turningpoint_meta.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
