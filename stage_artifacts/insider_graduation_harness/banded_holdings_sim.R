# banded_holdings_sim.R — 임원 순매수 신호 보유밴드(holding-band) 시뮬레이터.
# =============================================================================
# 목적: raw canonical screen 은 매월 top-N 을 재선정 → episodic 임원거래에서 회전 폭발(~1,580%/yr).
#   임원 순매수 신호는 1~6개월 지속(Cohen-Malloy-Pomorski) → 보유밴드(entry/exit 이원 임계 =
#   hysteresis)로 회전 3~10배 절감. 지속신호만 유지·노이즈 교체 억제.
#
# ★ anti-look-ahead PIT (raw 하네스와 동일 규율):
#   - 신호 score 는 이미 usable_month(=sig+lag) 기준 = 홀딩월 시작 전 정보(PIT-safe).
#   - 밴드 유지/교체 판단은 **월 t 에 알 수 있는 score 만** 사용(과거+현재 filing).
#     미래 신호 참조 없음. 'Date < 홀딩월 시작' 규율 그대로.
#   - held 포지션의 carried 신호도 과거 filing → 절대 forward 없음.
#   - lag 스트레스(PIT_LAG 1↔2)로 누출 재점검(raw 와 동일).
#
# 밴드 규칙 (사전등록, 과최적화 금지 — 폭 2종만):
#   각 홀딩월 t:
#     eligible_t = 지금까지(<=t) 관측된 각 종목의 '가장 최근 filing 의 net-officer-flow'.
#                  staleness > max_hold 개월이면 신호 만료(carry 중단).
#     - fresh negative flow(이번달 임원 순매도) → 즉시 exit(내부자 매도 = 청산 신호).
#     - rank = eligible 중 flow 내림차순 순위.
#     - 보유중 종목: rank <= n_exit(=exit buffer band) 이고 신호 미만료면 유지.
#     - 신규 편입: 미보유 종목 중 rank <= n_entry 이고 flow>0 이고 fresh(이번달 관측)면 편입.
#     - 최종 보유수 <= top_n(25) hard. 초과 시 flow 상위 top_n 만(EW).
#   → EW long-only. |Δw| 기반 15bps 비용. 지속 종목은 그대로 두어 회전 절감.
#
# 사전등록 밴드폭:
#   band_A: entry=20, exit=30, max_hold=6   (넓은 버퍼 = 강한 회전억제)
#   band_B: entry=25, exit=35, max_hold=3   (좁은 버퍼·짧은 보유 = raw 근접)
#
# 산출: contract build_benchmark_compare 경유 PORT_t (raw canonical 과 동일 계약경로) +
#       turnover(|Δw|×12) + calmar + period_returns. metric_type=canonical_screen(밴드변형).
# =============================================================================
suppressMessages({ library(data.table) })

.BS_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "02_Infrastructure/contracts")
local({
  f <- file.path(.BS_DIR, "backtest_result_contract.R")
  if (file.exists(f)) suppressMessages(source(f))
})

#' Banded holdings backtest — hysteresis entry/exit, contract-grade PORT_t.
#' @param scores_dt data.table(Date, Ticker, score)  Date=홀딩월 begin(usable), score=net-officer-flow(부호有)
#' @param returns_dt data.table(Date, Ticker, Ret_1m)  홀딩월 실현수익(PIT-aligned)
#' @param bench_dt data.table(Date, BM_Ret)
#' @param n_entry,n_exit integer  진입/청산 이원 임계(exit>=entry). exit buffer band.
#' @param max_hold integer  신호 만료 개월(staleness). 이후 carry 중단.
#' @param top_n integer  최종 보유 상한(25 hard).
#' @param cost_bps_oneway numeric  15bps.
#' @param liq_dt optional data.table(Date, Ticker, adv) — t-1 20d ADV.
#' @param liq_min numeric 2e8.
banded_holdings_bt <- function(scores_dt, returns_dt, bench_dt,
                               n_entry = 20L, n_exit = 30L, max_hold = 6L,
                               top_n = 25L, cost_bps_oneway = 15,
                               liq_dt = NULL, liq_min = 2e8,
                               run_id = "insider_band", strategy_id = "insider_band",
                               periods_per_year = 12L) {
  stopifnot(n_exit >= n_entry)
  S <- as.data.table(scores_dt)[is.finite(score)]
  R <- as.data.table(returns_dt)[is.finite(Ret_1m)]
  if (!is.null(liq_dt)) {
    L <- as.data.table(liq_dt)
    S <- merge(S, L[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
    S <- S[is.na(adv) | adv >= liq_min]; S[, adv := NULL]
  }
  setorder(S, Date)
  months <- sort(unique(S$Date))
  # month index for staleness (ordinal, contiguity-safe within observed months only)
  # staleness in *observed signal months* — episodic gap(수집갭) 은 carry 종료로 보수 처리.
  # 여기선 달력월 기준 staleness: 실제 경과 개월.
  cal_idx <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))

  held <- character(0)                 # 현재 보유 티커
  last_flow <- setNames(numeric(0), character(0))   # 종목별 최근 flow
  last_seen <- setNames(integer(0), character(0))   # 종목별 최근 관측 cal idx

  W_list <- list()
  for (t in months) {
    cur <- S[Date == t]
    ci <- cal_idx(t)
    # update last-seen state with this month's fresh filings
    for (i in seq_len(nrow(cur))) {
      tk <- cur$Ticker[i]; fl <- cur$score[i]
      last_flow[tk] <- fl; last_seen[tk] <- ci
    }
    fresh_tk <- cur$Ticker
    fresh_neg <- cur[score < 0, Ticker]     # 이번달 임원 순매도 = exit 신호

    # eligible: 신호 미만료(staleness<=max_hold) 종목의 carried flow
    if (length(last_seen)) {
      stale_ok <- names(last_seen)[(ci - last_seen) <= max_hold]
    } else stale_ok <- character(0)
    elig_tk <- stale_ok
    elig_flow <- last_flow[elig_tk]
    # rank by carried flow desc (only positive flow rankable for entry; exit uses full rank)
    ord <- order(-elig_flow)
    ranked <- elig_tk[ord]
    rank_of <- setNames(seq_along(ranked), ranked)

    # 1) exit: held 종목 중 (a)fresh negative, (b)만료, (c)rank>n_exit → 제거
    keep <- character(0)
    for (tk in held) {
      if (tk %in% fresh_neg) next                       # 내부자 매도 청산
      if (!(tk %in% elig_tk)) next                      # 만료
      rk <- rank_of[[tk]]
      if (is.null(rk) || is.na(rk) || rk > n_exit) next # 밴드 이탈
      keep <- c(keep, tk)
    }

    # 2) entry: 미보유 중 fresh & flow>0 & rank<=n_entry
    entry_cand <- setdiff(ranked, keep)
    entry_cand <- entry_cand[entry_cand %in% fresh_tk]
    entry_cand <- entry_cand[last_flow[entry_cand] > 0]
    entry_cand <- entry_cand[!is.na(rank_of[entry_cand]) & rank_of[entry_cand] <= n_entry]
    new_held <- c(keep, entry_cand)

    # 3) top_n hard: 초과 시 carried flow 상위 top_n
    if (length(new_held) > top_n) {
      fl <- last_flow[new_held]
      new_held <- new_held[order(-fl)][seq_len(top_n)]
    }
    held <- new_held
    if (length(held)) {
      W_list[[as.character(t)]] <- data.table(Date = t, Ticker = held, w = 1 / length(held))
    } else {
      W_list[[as.character(t)]] <- data.table(Date = t, Ticker = character(0), w = numeric(0))
    }
  }
  W <- rbindlist(W_list)
  if (nrow(W) == 0) return(list(metric_type = "canonical_screen", n_months = 0L,
                                portfolio_alpha_t_nw_lag3 = NA_real_, note = "no holdings"))

  # gross monthly port return
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]

  # turnover: traded_t = sum(|w_t - w_{t-1}|) over ticker union
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

  pr <- merge(port[, .(date = Date, ret_net)], bench_dt[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  if (nrow(pr) == 0) return(list(metric_type = "canonical_screen", n_months = 0L,
                                 portfolio_alpha_t_nw_lag3 = NA_real_, note = "no overlap"))
  period_returns_tbl <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret,
                                       benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                run_id = run_id, strategy_id = strategy_id,
                                annualization_factor = periods_per_year)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  net_sr <- mean(active) / stats::sd(active) * sqrt(periods_per_year)
  turnover_annual <- mean(port$traded, na.rm = TRUE) * periods_per_year
  avg_names <- mean(W[, .N, by = Date]$N)

  list(
    metric_type = "canonical_screen",
    metric_type_note = "보유밴드 hysteresis EW long-only 실측(contract build_benchmark_compare 경유). screening-tier.",
    n_months = nrow(pr), top_n = top_n, n_entry = n_entry, n_exit = n_exit, max_hold = max_hold,
    avg_holdings = avg_names,
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized  = getbc("Alpha_Annualized"),
    net_sr = net_sr, mean_active_net = mean(active),
    turnover_annual = turnover_annual,
    benchmark_compare = bc, period_returns = pr
  )
}

cat("[banded_holdings_sim.R] Loaded — banded_holdings_bt() (hysteresis holding-band, contract-grade)\n")
