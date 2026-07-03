# weighted_screen_bt.R — 임의 가중 contract-grade 백테 (canonical_screen_bt 일반화, 도훈 mandate 2026-06-18)
#
# 목적: 가중 A/B(EW vs score-tilt vs Σ-가중 vs 논문 방법)를 위해, *임의 weights*(Date,Ticker,w)를 받아
#       canonical_screen_bt와 *동일 contract 경로*(build_benchmark_compare, NW lag-3)로 실측.
#       QEPM 후보(optimizer/risk) 자동 A/B 하니스(H1)의 keystone primitive.
#
# 비용 규약: canonical_screen_bt와 동일 — traded_t=sum(|w_t - w_{t-1}|), cost=traded*bps/1e4 (double-count 금지).
# PIT: weights_dt는 sig_date 기준(t에 알 수 있는 값), returns_dt Ret_1m은 forward 실현수익. 호출자가 PIT-align 보장.
suppressMessages(library(data.table))

# contract(build_benchmark_compare) 견고 소싱 — 호출 컨텍스트 무관(sys.frame→QM_ROOT→cwd fallback, idempotent).
local({
  if (exists("build_benchmark_compare")) return(invisible())
  wsb_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA_character_)
  cands <- c(
    if (!is.na(wsb_dir)) file.path(wsb_dir, "backtest_result_contract.R") else NULL,
    file.path(Sys.getenv("QM_ROOT", "."), "02_Infrastructure", "contracts", "backtest_result_contract.R"),
    file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "."), "02_Infrastructure", "contracts", "backtest_result_contract.R"),
    "02_Infrastructure/contracts/backtest_result_contract.R"
  )
  for (f in cands) if (!is.null(f) && file.exists(f)) { suppressMessages(source(f)); break }
})

#' 임의 가중 long-only 백테 — contract-grade.
#' @param weights_dt data.table(Date, Ticker, w) — Date별 가중(합 1로 자동정규화, w>=0 권장)
#' @param returns_dt data.table(Date, Ticker, Ret_1m) forward 1M 실현수익(PIT-aligned)
#' @param bench_dt   data.table(Date, BM_Ret)
#' @return canonical_screen_bt와 동일 키(metric_type="weighted_screen")
weighted_screen_bt <- function(weights_dt, returns_dt, bench_dt, cost_bps_oneway = 15,
                               run_id = "weighted_screen", strategy_id = "weighted_screen",
                               exposure_dt = NULL) {
  # exposure_dt: data.table(Date, exposure) — 오버레이 노출 스칼라(현 book 실현 β_combined=m4×AR×R05).
  #   cash@0 가정에서 오버레이는 곱셈 노출이라 net 수익 비례 축소(ret_net <- ret_net*exposure). NULL이면 1(bare).
  #   오버레이 리밸 비용은 β-schedule이 모든 가중법에 동일 적용돼 cross-method 비교서 상쇄 → 생략(라벨).
  stopifnot(all(c("Date", "Ticker", "w") %in% names(weights_dt)))
  stopifnot(all(c("Date", "Ticker", "Ret_1m") %in% names(returns_dt)))
  stopifnot(all(c("Date", "BM_Ret") %in% names(bench_dt)))

  W <- as.data.table(weights_dt)[!is.na(w) & w != 0, .(Date, Ticker, w)]
  R <- as.data.table(returns_dt)[!is.na(Ret_1m)]
  W[, w := w / sum(w), by = Date]   # Date별 합 1 정규화 (안전)

  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]

  # turnover: traded_t = sum(|w_t - w_{t-1}|) (ticker union) — canonical과 동일
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur", "_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * cost_bps_oneway / 1e4]
  port[, ret_net := port_gross - cost]
  if (!is.null(exposure_dt)) {
    ed <- as.data.table(exposure_dt)[, .(Date, exposure)]
    port <- merge(port, ed, by = "Date", all.x = TRUE)
    port[is.na(exposure), exposure := 1]
    port[, ret_net := ret_net * exposure]   # 오버레이 노출 적용(현 book 실현 β_combined)
  }

  pr <- merge(port[, .(date = Date, ret_net)], bench_dt[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  if (nrow(pr) == 0) {
    return(list(metric_type = "weighted_screen", n_months = 0L,
                portfolio_alpha_t_nw_lag3 = NA_real_, note = "no overlap"))
  }
  period_returns_tbl <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret,
                                       benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                run_id = run_id, strategy_id = strategy_id, annualization_factor = 12)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  net_sr <- mean(active) / stats::sd(active) * sqrt(12)
  # 절대(active 아님) 포트 성과 — 검증앵커/표시용 (벤치-중첩 구간 ret_net 기준)
  .mdd <- function(r) { cum <- cumprod(1 + r); min(cum / cummax(cum) - 1, na.rm = TRUE) }
  abs_net_sr <- mean(pr$ret_net) / stats::sd(pr$ret_net) * sqrt(12)
  abs_cagr   <- (prod(1 + pr$ret_net)^(12 / nrow(pr)) - 1)
  abs_mdd    <- .mdd(pr$ret_net)

  list(
    metric_type = "weighted_screen",
    n_months = nrow(pr),
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized  = getbc("Alpha_Annualized"),
    net_sr = net_sr,
    abs_net_sr = abs_net_sr,
    abs_cagr = abs_cagr,
    abs_mdd = abs_mdd,
    mean_active_net = mean(active),
    turnover_annual = mean(port$traded, na.rm = TRUE) * 12,
    period_returns = data.table(date = pr$date, ret_net = pr$ret_net, benchmark_ret = pr$benchmark_ret),  # [2026-06-19] oos_retention 등 후처리용
    benchmark_compare = bc
  )
}
cat("[weighted_screen_bt.R] Loaded — weighted_screen_bt() (임의 가중 contract-grade A/B primitive)\n")
