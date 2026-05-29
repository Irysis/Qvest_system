# canonical_screen_bt.R — Qvest v8.x WS1 (Real-Computation, 하이브리드 C)
#
# 목적: alpha/risk 단계가 portfolio-alpha t / SR 등 성능수치를 **proxy 손계산**
#       (top-quintile EW + turnover×15bps 인라인 근사)으로 보고하던 것을 폐기하고,
#       표준 canonical 포트폴리오를 **contract 경유 실측**으로 산출하게 하는 공용 helper.
#
# 설계:
#   - 표준 top-N EW **long-only** + 유동성필터(2e8) + 실 15bps 비용.
#   - period 수익률을 contract `build_benchmark_compare()`로 routing → portfolio_alpha_t_nw_lag3
#     (NW lag-3) + IR + alpha를 **contract-grade**로 산출 (forge와 동일 함수, 일관성).
#   - metric_type = "canonical_screen" — forge build_bt_result(="backtested", 최적화 weights)도,
#     proxy도 아님. **admission binding 수치 아님**(그건 forge). screening/직교 측정용 실측.
#
# 비용 규약 (FLOW/optimizer 정합, double-count 금지):
#   traded_t = sum(|w_t - w_{t-1}|)            # 월별 매매 notional(매수+매도)
#   cost_t   = traded_t * cost_bps/1e4         # one-way 15bps를 traded 단위마다 1회
#   turnover_annual(보고) = mean(traded_t) * 12
#
# PIT: scores_dt는 sig_date 기준(t에 알 수 있는 값), returns_dt의 Ret_1m은 forward 실현수익.
#      유동성필터는 t-1 ADV(C10). 호출자가 PIT-aligned 입력 보장 의무.

suppressMessages({
  library(data.table)
})

# contract 재사용 (build_benchmark_compare + .nw_t_mean)
.CANON_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "02_Infrastructure/contracts")
local({
  f <- file.path(.CANON_DIR, "backtest_result_contract.R")
  if (file.exists(f)) suppressMessages(source(f))
})

#' Canonical screening backtest — top-N EW long-only, contract-grade.
#' @param scores_dt  data.table(Date, Ticker, score)  higher score = 선호
#' @param returns_dt data.table(Date, Ticker, Ret_1m) forward 1M 실현수익(PIT-aligned)
#' @param bench_dt   data.table(Date, BM_Ret)
#' @param top_n      integer (default 20; max 25 mandate 내)
#' @param cost_bps_oneway numeric one-way bps (default 15)
#' @param liq_dt     optional data.table(Date, Ticker, adv) — 20d 평균 거래대금(t-1)
#' @param liq_min    numeric (default 2e8)
#' @return list(metric_type, n_months, portfolio_alpha_t_nw_lag3, portfolio_alpha_t_pvalue,
#'              information_ratio, alpha_annualized, net_sr, mean_active_net, turnover_annual,
#'              benchmark_compare, note)
canonical_screen_bt <- function(scores_dt, returns_dt, bench_dt,
                                 top_n = 20L, cost_bps_oneway = 15,
                                 liq_dt = NULL, liq_min = 2e8,
                                 run_id = "canonical_screen", strategy_id = "canonical_screen") {
  stopifnot(all(c("Date","Ticker","score") %in% names(scores_dt)))
  stopifnot(all(c("Date","Ticker","Ret_1m") %in% names(returns_dt)))
  stopifnot(all(c("Date","BM_Ret") %in% names(bench_dt)))

  S <- as.data.table(scores_dt)[!is.na(score)]
  R <- as.data.table(returns_dt)[!is.na(Ret_1m)]
  if (!is.null(liq_dt)) {
    L <- as.data.table(liq_dt)
    S <- merge(S, L[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
    S <- S[is.na(adv) | adv >= liq_min]   # 유동성필터(adv 없으면 통과 — 호출자 책임)
    S[, adv := NULL]
  }

  # per-Date: top_n EW long-only weights
  setorder(S, Date, -score)
  W <- S[, {
    n <- min(top_n, .N)
    .(Ticker = Ticker[seq_len(n)], w = rep(1 / n, n))
  }, by = Date]

  # gross monthly port return = sum(w_t * Ret_1m_t)
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]

  # turnover: traded_t = sum(|w_t - w_{t-1}|)  (ticker union)
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * cost_bps_oneway / 1e4]
  port[, ret_net := port_gross - cost]

  # benchmark merge → period_returns_tbl + benchmark_returns_tbl (contract 형식)
  pr <- merge(port[, .(date = Date, ret_net)], bench_dt[, .(date = Date, benchmark_ret = BM_Ret)],
              by = "date")
  if (nrow(pr) == 0) {
    return(list(metric_type = "canonical_screen", n_months = 0L,
                portfolio_alpha_t_nw_lag3 = NA_real_, note = "no overlap"))
  }
  period_returns_tbl <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret,
                                       benchmark_id = "KOSPI200_total_return")

  # contract-grade: build_benchmark_compare (= forge와 동일 함수, NW t 포함)
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                 run_id = run_id, strategy_id = strategy_id,
                                 annualization_factor = 12)
  getbc <- function(nm) {
    v <- bc[metric_name == nm, active_value]
    if (length(v) == 0) NA_real_ else as.numeric(v[1])
  }
  active <- pr$ret_net - pr$benchmark_ret
  net_sr <- mean(active) / stats::sd(active) * sqrt(12)
  turnover_annual <- mean(port$traded, na.rm = TRUE) * 12

  list(
    metric_type = "canonical_screen",
    metric_type_note = "표준 top-N EW long-only 실측(contract build_benchmark_compare 경유). admission binding 아님 — forge build_bt_result가 authoritative.",
    n_months = nrow(pr),
    top_n = top_n,
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized  = getbc("Alpha_Annualized"),
    net_sr = net_sr,
    mean_active_net = mean(active),
    turnover_annual = turnover_annual,
    benchmark_compare = bc
  )
}

cat("[canonical_screen_bt.R] Loaded — canonical_screen_bt() (v8.x WS1 real-computation helper)\n")
