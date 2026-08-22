## frame_lib.R — WT-D20260821_002 소비-형태 프레임 백테 (canonical_screen_bt 자구 승계 fork)
##
## ★유일한 변경 = 가중 규칙(canonical_screen_bt.R L318~323 블록).
##   비용·회전율·수익집계·contract routing(build_benchmark_compare)은 원본 자구 그대로.
##   자체합성 없음 — 원본 계약이 쓰는 동일 라인만 사용한다.
##
## gate 단계에서는 metrics=FALSE 로 호출해 period return 계열만 얻는다
## (arm 별 성과량조차 관문 단계에서 산출하지 않기 위함 — PREREG §3 mean-blind).

suppressPackageStartupMessages({library(data.table)})

## 프레임별 월내 가중 벡터. S 는 그 달의 (Ticker, score) — 스코어 내림차순 정렬 전제.
## rank_i = 1 이 최고 스코어. 반환 = data.table(Ticker, w)
.frame_weights <- function(tk, frame) {
  M <- length(tk)
  if (frame == "F0") {                       # top-25 동일가중 (기존 프레임)
    n <- min(25L, M); return(data.table(Ticker = tk[seq_len(n)], w = rep(1/n, n)))
  }
  if (frame %in% c("F1", "F2", "F3L")) {     # long-only 랭크-선형, 경계 가중 정확히 0
    N <- switch(frame, F1 = min(50L, M), F2 = min(100L, M), F3L = M)
    r <- seq_len(N)
    raw <- N - r                             # rank=N -> 0 (경계 연속 수렴)
    s <- sum(raw)
    if (!is.finite(s) || s <= 0) return(data.table(Ticker = character(0), w = numeric(0)))
    return(data.table(Ticker = tk[r], w = raw / s))
  }
  if (frame == "F3") {                       # 설계 원안 — 센터드랭크 Σ|w|=1 (롱숏, 진단 전용)
    r <- seq_len(M)
    raw <- (M + 1)/2 - r                     # rank 1 = 최대 양수
    s <- sum(abs(raw))
    if (!is.finite(s) || s <= 0) return(data.table(Ticker = character(0), w = numeric(0)))
    return(data.table(Ticker = tk[r], w = raw / s))
  }
  stop("unknown frame: ", frame)
}

#' frame_screen_bt — 프레임별 소비 형태 백테.
#' @param metrics FALSE 면 period return 계열만 반환(관문 단계). TRUE 면 contract 지표 부착.
frame_screen_bt <- function(scores_dt, returns_dt, bench_dt, frame,
                            cost_bps_oneway = 15, metrics = FALSE,
                            run_id = "wt002", strategy_id = "wt002",
                            periods_per_year = 12L) {
  stopifnot(all(c("Date","Ticker","score") %in% names(scores_dt)))
  S <- as.data.table(scores_dt)[!is.na(score)]
  R <- as.data.table(returns_dt)[!is.na(Ret_1m)]

  ## --- canonical_screen_bt L266~275 자구 승계: Ret_1m sanity 방화벽 ---
  bad_1m <- is.finite(R$Ret_1m) & (R$Ret_1m > 5.0 | R$Ret_1m < -1.0)
  if (any(bad_1m)) { warning(sprintf("[frame_screen_bt] Ret_1m sanity 격리 %d행", sum(bad_1m))); R <- R[!bad_1m] }

  ## --- 가중 (유일한 변경점) ---
  setorder(S, Date, -score)
  W <- S[, .frame_weights(Ticker, frame), by = Date]

  ## --- canonical_screen_bt L326~355 자구 승계: 수익집계 · 회전율 · 비용 ---
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  sel_cov <- WR[, mean(!is.na(Ret_1m))]
  if (is.finite(sel_cov) && sel_cov < 0.95)
    warning(sprintf("[frame_screen_bt/%s] 선택분 Ret_1m 커버리지 %.1f%% < 95%%", frame, 100*sel_cov))
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]

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

  pr <- merge(port[, .(date = Date, ret_net, port_gross, traded)],
              bench_dt[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  out <- list(frame = frame, n_months = nrow(pr), period_returns = pr,
              turnover_annual = mean(port$traded, na.rm = TRUE) * periods_per_year,
              selected_ret_coverage = sel_cov,
              avg_n_names = W[, .N, by = Date][, mean(N)],
              avg_eff_n_names = W[, .(enn = sum(w)^2/sum(w^2)), by = Date][, mean(enn)])
  if (!isTRUE(metrics)) return(out)

  ## --- canonical_screen_bt L363~390 자구 승계: contract routing ---
  period_returns_tbl <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret,
                                      benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                run_id = run_id, strategy_id = strategy_id,
                                annualization_factor = periods_per_year)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]
                          if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  out$metric_type <- "canonical_screen_frame"
  out$metric_type_note <- paste0("canonical_screen_bt fork — 가중 규칙만 교체(", frame,
    "). admission binding 아님. 브레드스 확대 프레임은 검출 장치이지 운용 후보 아님(Production Constraints max 25 고정 축).")
  out$portfolio_alpha_t_nw_lag3 <- getbc("Portfolio_Alpha_t_NW_lag3")
  out$portfolio_alpha_t_pvalue  <- getbc("Portfolio_Alpha_t_pvalue")
  out$information_ratio <- getbc("Information_Ratio")
  out$alpha_annualized  <- getbc("Alpha_Annualized")
  out$net_sr <- mean(active) / stats::sd(active) * sqrt(periods_per_year)
  out$mean_active_net <- mean(active)
  out$benchmark_compare <- bc
  out
}

## armC_measure.R::nw_t 자구 승계
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }

## r33_profile_stage2.R::skew 자구 승계 (모집단 왜도)
skew <- function(x) { x <- x[is.finite(x)]; n <- length(x); if (n < 3) return(NA_real_)
  m <- mean(x); s <- sqrt(sum((x-m)^2)/n); if (s == 0) return(NA_real_); sum((x-m)^3)/(n*s^3) }
