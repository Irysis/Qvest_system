## aif_factor_perf.R — 팩터 성과 측정기(독립 스크립트). aif_common.R 을 먼저 source 한다.
##   팩터 = 월말 종목 점수(클수록 좋음). 유니버스 멤버를 점수순 5분위로 나누고(종목 수 제한 없음),
##   상위 분위 롱온리와 상위−하위 롱숏의 일별 수익을 PerformanceAnalytics::Return.portfolio 로 만든다.
##   지표 계산도 PerformanceAnalytics(2.0.8)로 하고 인자를 모두 명시한다.

## 계산 대상 구간의 일별 수익 xts(완결된 마지막 보유월 끝까지)
aif_rx <- function(M) {
  e <- match(M$last_hold_end, M$dates)
  xts(M$R0[seq_len(e), , drop = FALSE], order.by = M$dates[seq_len(e)])
}

## 월별 순위 IC(스피어먼) — 유니버스 멤버 · 점수와 수익이 모두 있는 종목 · min_n 미만인 달은 뺀다
aif_ic <- function(S, M, h = 1L, min_n = 30L) {
  Fm <- M$FWD[[as.character(h)]]; ns <- nrow(S)
  ic <- rep(NA_real_, ns); n <- integer(ns)
  for (s in seq_len(ns)) {
    ok <- M$MEM[s, ] & is.finite(S[s, ]) & is.finite(Fm[s, ])
    n[s] <- sum(ok)
    if (n[s] >= min_n) ic[s] <- suppressWarnings(cor(rank(S[s, ok]), rank(Fm[s, ok])))
  }
  list(ic = ic, n = n)
}

## 분위 배정 — 0 = 점수 없음 · 1 = 하위 … nq = 상위. 멤버 가운데 점수가 있는 종목만, 같은 수로 나눈다.
aif_quantiles <- function(S, M, nq = 5L, min_n = 30L) {
  Q <- matrix(0L, nrow(S), ncol(S))
  for (s in seq_len(nrow(S))) {
    ok <- which(M$MEM[s, ] & is.finite(S[s, ]))
    if (length(ok) < min_n) next
    Q[s, ok] <- as.integer(ceiling(rank(S[s, ok], ties.method = "first") * nq / length(ok)))
  }
  Q
}

## 보유 표(신호 × 종목 · 논리) → 동일가중 포트폴리오의 일별 수익(M$dates 에 맞춘 벡터 · 시작 전 = NA)
##   월말 신호일의 비중이 다음 거래일부터 적용된다 = 신호일 종가에 매매했다고 보는 규약(월말 특성 → 다음 달 수익).
##   달 안에서는 비중이 수익을 따라 흘러간다(Return.portfolio).
##   lag_days = 1 이면 매매를 하루 늦춘다(다음 달 첫 거래일 종가에 매매 → 둘째 거래일 수익부터 새 비중) — 같은 종가 매매 가정에 기대는 정도를 보는 판.
aif_port_daily <- function(mask, M, Rx, lag_days = 0L) {
  e <- nrow(Rx); out <- rep(NA_real_, length(M$dates))
  rows <- which(rowSums(mask) > 0 & M$hold_ok)
  if (!length(rows)) return(out)
  W <- mask[rows, , drop = FALSE] / rowSums(mask[rows, , drop = FALSE])
  wx <- xts(W, order.by = M$dates[M$sig_idx[rows] + lag_days]); colnames(wx) <- M$tickers
  r <- suppressWarnings(Return.portfolio(Rx, weights = wx, geometric = TRUE, verbose = FALSE))
  out[match(as.Date(index(r)), M$dates)] <- as.numeric(r)
  out[seq_along(out) > e] <- NA_real_
  out
}

## 같은 것을 직접 계산(달 초 동일가중 · 달 안 보유) — Return.portfolio 와 같은 값인지 대조하는 용도
aif_port_daily_direct <- function(mask, M) {
  out <- rep(NA_real_, length(M$dates))
  rows <- which(rowSums(mask) > 0 & M$hold_ok)
  e <- match(M$last_hold_end, M$dates)
  for (k in seq_along(rows)) {
    s <- rows[k]; a <- M$sig_idx[s] + 1L
    b <- if (k < length(rows)) M$sig_idx[rows[k + 1L]] else e
    if (a > b) next
    held <- which(mask[s, ]); rr <- a:b
    G <- 1 + M$R0[rr, held, drop = FALSE]
    V <- rowMeans(apply(G, 2L, cumprod, simplify = TRUE) |> matrix(nrow = length(rr)))
    out[rr] <- V / c(1, V[-length(V)]) - 1
  }
  out
}

## 리밸런싱 때 사고판 비중의 합(Σ|Δw|) — 지난 달 수익으로 흘러간 비중과 새 비중의 차이. 신호 × 1 벡터.
aif_traded <- function(mask, M) {
  ns <- nrow(mask); tr <- rep(NA_real_, ns); prev <- NULL; ps <- NA_integer_
  f1 <- M$FWD[["1"]]
  for (s in which(rowSums(mask) > 0 & M$hold_ok)) {
    w <- mask[s, ] / sum(mask[s, ])
    if (is.null(prev)) tr[s] <- sum(w) else {
      g <- 1 + ifelse(is.finite(f1[ps, ]), f1[ps, ], 0)
      wo <- prev * g; wo <- wo / sum(wo)
      tr[s] <- sum(abs(w - wo))
    }
    prev <- w; ps <- s
  }
  tr
}

## 거래비용 차감 — 리밸런싱 뒤 첫 거래일 수익에서 (편도 비용 × 사고판 비중 합)을 뺀다
aif_net <- function(r, traded, M, cost_bps) {
  rn <- r
  for (s in which(is.finite(traded))) {
    d <- M$sig_idx[s] + 1L
    if (d <= length(rn) && is.finite(rn[d])) rn[d] <- (1 + rn[d]) * (1 - traded[s] * cost_bps / 1e4) - 1
  }
  rn
}

## 일별 수익 → 성과 · 리스크 지표(연환산 252일). ls = TRUE 면 자기자본 없는 롱숏이라 무위험 수익을 빼지 않는다.
aif_stats <- function(r, dates, bm, rf, cfg, ls = FALSE) {
  ok <- is.finite(r); if (sum(ok) < 60L) return(NULL)
  r <- r[ok]; d <- dates[ok]; bm <- bm[ok]; rf <- rf[ok]
  sc <- cfg$measure$days_per_year
  x <- xts(r, order.by = d)
  cagr <- as.numeric(Return.annualized(x, scale = sc, geometric = TRUE))
  sdv <- as.numeric(StdDev.annualized(x, scale = sc))
  rfx <- xts(if (ls) rep(0, length(r)) else rf, order.by = d)
  sr <- as.numeric(SharpeRatio.annualized(x, Rf = rfx, scale = sc, geometric = TRUE))
  mdd <- -as.numeric(maxDrawdown(x, geometric = TRUE, invert = TRUE))
  mon <- as.numeric(xts::apply.monthly(x, PerformanceAnalytics::Return.cumulative, geometric = TRUE))   # 달별 누적 수익
  o <- list(start = as.character(d[1]), end = as.character(d[length(d)]), n_days = length(r),
            CAGR = cagr, SD = sdv, SR = sr, MDD = mdd, Calmar = if (mdd < 0) cagr / abs(mdd) else NA_real_,
            win_month = mean(mon > 0), worst_month = min(mon))
  if (!ls) {
    bx <- xts(bm, order.by = d)
    bcagr <- as.numeric(Return.annualized(bx, scale = sc, geometric = TRUE))
    fit <- stats::lm.fit(cbind(1, bm - rf), r - rf)
    o <- c(o, list(excess_CAGR = cagr - bcagr, TE = as.numeric(TrackingError(x, bx, scale = sc)),
                   IR = as.numeric(InformationRatio(x, bx, scale = sc)),
                   beta = unname(fit$coefficients[2]), alpha_ann = unname(fit$coefficients[1]) * sc))
  }
  o
}

aif_periods <- function(cfg) {
  ie <- as.Date(cfg$measure$is_end)
  list(ALL = c(as.Date("1900-01-01"), as.Date("2999-12-31")), IS = c(as.Date("1900-01-01"), ie), OOS = c(ie + 1L, as.Date("2999-12-31")))
}

## IC 요약(기간별) — 평균 · 표준편차 · ICIR(연환산) · t · 양수 비율 · 달 수
aif_ic_summary <- function(ic, sig_dates, cfg) {
  rbindlist(lapply(names(aif_periods(cfg)), function(p) {
    pr <- aif_periods(cfg)[[p]]; v <- ic[sig_dates >= pr[1] & sig_dates <= pr[2]]; v <- v[is.finite(v)]
    if (length(v) < 6L) return(data.table(period = p, n_months = length(v), IC = NA_real_, IC_sd = NA_real_, ICIR = NA_real_, IC_t = NA_real_, IC_pos = NA_real_))
    data.table(period = p, n_months = length(v), IC = mean(v), IC_sd = sd(v), ICIR = mean(v) / sd(v) * sqrt(cfg$measure$months_per_year),
               IC_t = mean(v) / (sd(v) / sqrt(length(v))), IC_pos = mean(v > 0))
  }))
}

## ── 팩터 하나 측정 ───────────────────────────────────────────────────────────
##   all_quantiles = TRUE 면 5분위 전부의 일별 수익도 만든다(신규 팩터용 · 기존 팩터는 상위와 하위만).
## 보유 표(상위 · 하위 분위)에서 일별 수익과 지표를 만든다. mid = 가운데 분위들의 보유 표(이름 = q2 …) — 주면 그 일별 수익도 낸다.
##   delay = TRUE 면 매매를 하루 늦춘 판(cost = "gross_d1")의 지표도 낸다(신규 팩터용).
aif_measure_masks <- function(id, top, bot, M, Rx, cfg, mid = NULL, delay = FALSE) {
  nq <- cfg$measure$n_quantiles; cb <- cfg$measure$cost_bps_one_way
  r_top <- aif_port_daily(top, M, Rx); r_bot <- aif_port_daily(bot, M, Rx)
  tr_top <- aif_traded(top, M); tr_bot <- aif_traded(bot, M)
  r_top_net <- aif_net(r_top, tr_top, M, cb)
  r_ls <- r_top - r_bot
  r_ls_net <- r_top_net - aif_net(r_bot, -tr_bot, M, cb)       # 매도 다리의 비용도 롱숏 수익에서 빠진다
  daily <- data.table(Date = M$dates, top = r_top, bottom = r_bot, ls = r_ls, top_net = r_top_net, ls_net = r_ls_net)
  if (delay) { td <- aif_port_daily(top, M, Rx, 1L); set(daily, j = "top_d1", value = td); set(daily, j = "ls_d1", value = td - aif_port_daily(bot, M, Rx, 1L)) }
  if (!is.null(mid)) {
    set(daily, j = "q1", value = r_bot)
    for (nm in names(mid)) set(daily, j = nm, value = aif_port_daily(mid[[nm]], M, Rx))
    set(daily, j = paste0("q", nq), value = r_top)
  }
  daily <- daily[is.finite(top)]
  per <- aif_periods(cfg)
  st <- rbindlist(lapply(names(per), function(p) {
    sel <- daily$Date >= per[[p]][1] & daily$Date <= per[[p]][2]
    if (sum(sel) < 60L) return(NULL)
    d <- daily$Date[sel]; i <- match(d, M$dates)
    mk <- function(r, port, cst, ls) {
      z <- aif_stats(r[sel], d, M$bm[i], M$rf[i], cfg, ls = ls)
      if (is.null(z)) NULL else cbind(data.table(factor = id, portfolio = port, cost = cst, period = p), as.data.table(z))
    }
    rbindlist(list(mk(daily$top, "top", "gross", FALSE), mk(daily$top_net, "top", "net", FALSE),
                   mk(daily$ls, "ls", "gross", TRUE), mk(daily$ls_net, "ls", "net", TRUE),
                   if (delay) mk(daily$top_d1, "top", "gross_d1", FALSE), if (delay) mk(daily$ls_d1, "ls", "gross_d1", TRUE)), fill = TRUE)
  }), fill = TRUE)
  list(daily = daily, stats = st, tr_top = tr_top, tr_bot = tr_bot)
}

AIF_MEASURER_VERSION <- 2L   # 2 = 매매를 하루 늦춘 판(gross_d1) 추가. 바뀌면 신규 팩터를 다시 잰다(체크포인트의 판 번호와 대조).
aif_measure_factor <- function(id, S, M, Rx, cfg, all_quantiles = TRUE) {
  nq <- cfg$measure$n_quantiles; mn <- cfg$measure$min_names
  Q <- aif_quantiles(S, M, nq, mn)
  scored <- rowSums(Q > 0L)
  if (!any(scored > 0L & M$hold_ok)) stop("[aif] 분위를 만들 수 있는 달이 없다: ", id)
  mid <- if (all_quantiles && nq > 2L) setNames(lapply(2:(nq - 1L), function(q) Q == q), paste0("q", 2:(nq - 1L))) else NULL
  mm <- aif_measure_masks(id, Q == nq, Q == 1L, M, Rx, cfg, mid = mid, delay = TRUE)
  daily <- mm$daily; st <- mm$stats; tr_top <- mm$tr_top; tr_bot <- mm$tr_bot

  ## 예측력
  icl <- lapply(unlist(cfg$measure$ic_horizons_m), function(h) aif_ic(S, M, h, mn))
  names(icl) <- as.character(unlist(cfg$measure$ic_horizons_m))
  ic_tab <- rbindlist(lapply(names(icl), function(h) cbind(data.table(factor = id, horizon_m = as.integer(h)), aif_ic_summary(icl[[h]]$ic, M$sig_dates, cfg))))
  ic_monthly <- data.table(Date = M$sig_dates, IC = icl[["1"]]$ic, n = icl[["1"]]$n)[is.finite(IC)]

  ## 분위 구조(달별 분위 평균 수익) · 거래 · 커버리지
  f1 <- M$FWD[["1"]]; rows <- which(scored > 0L & M$hold_ok)
  qm <- t(vapply(rows, function(s) vapply(seq_len(nq), function(q) mean(f1[s, Q[s, ] == q], na.rm = TRUE), 0), numeric(nq)))
  q_mean <- colMeans(qm, na.rm = TRUE)
  ac <- vapply(rows[-1L], function(s) {
    ok <- M$MEM[s, ] & is.finite(S[s, ]) & is.finite(S[s - 1L, ])
    if (sum(ok) < mn) NA_real_ else suppressWarnings(cor(rank(S[s, ok]), rank(S[s - 1L, ok])))
  }, 0)
  misc <- data.table(factor = id, first_signal = as.character(M$sig_dates[min(rows)]), last_signal = as.character(M$sig_dates[max(rows)]),
                     n_months = length(rows), names_avg = mean(scored[rows]), coverage = mean(scored[rows] / rowSums(M$MEM)[rows]),
                     turnover_top = mean(tr_top[rows][-1L], na.rm = TRUE) / 2, turnover_bottom = mean(tr_bot[rows][-1L], na.rm = TRUE) / 2,
                     rank_autocorr = mean(ac, na.rm = TRUE),
                     monotonic = suppressWarnings(cor(seq_len(nq), q_mean, method = "spearman")))
  for (q in seq_len(nq)) set(misc, j = paste0("q", q, "_month_mean"), value = q_mean[q])
  list(id = id, stats = st, ic = ic_tab, ic_monthly = ic_monthly, misc = misc, daily = daily)
}

## 측정 결과 저장(팩터 하나 = 폴더 하나 · 확정 저장) / 이미 끝난 팩터인지
aif_perf_dir <- function(set, id, root = aif_root(), cfg = aif_cfg(root)) aif_out("perf", set, id, root = root, cfg = cfg)
aif_perf_done <- function(set, id, ...) file.exists(file.path(aif_perf_dir(set, id, ...), "done.json"))
aif_perf_save <- function(set, res, meta = list(), ...) {
  d <- aif_perf_dir(set, res$id, ...); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  aif_write_atomic(file.path(d, "daily.parquet"), function(p) write_parquet(res$daily, p))
  aif_write_atomic(file.path(d, "stats.csv"), function(p) fwrite(res$stats, p))
  aif_write_atomic(file.path(d, "ic.csv"), function(p) fwrite(res$ic, p))
  aif_write_atomic(file.path(d, "ic_monthly.csv"), function(p) fwrite(res$ic_monthly, p))
  aif_write_atomic(file.path(d, "misc.csv"), function(p) fwrite(res$misc, p))
  aif_write_json(c(list(id = res$id, set = set, saved_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")), meta), file.path(d, "done.json"))
  invisible(d)
}
aif_perf_load <- function(set, id, ...) {
  d <- aif_perf_dir(set, id, ...)
  list(id = id, stats = fread(file.path(d, "stats.csv")), ic = fread(file.path(d, "ic.csv")), ic_monthly = fread(file.path(d, "ic_monthly.csv")),
       misc = fread(file.path(d, "misc.csv")), daily = as.data.table(read_parquet(file.path(d, "daily.parquet"))))
}

## 벤치마크와 유니버스 동일가중의 같은 지표(비교 기준 줄)
aif_reference <- function(M, Rx, cfg) {
  e <- nrow(Rx); d <- M$dates[seq_len(e)]
  ew <- aif_port_daily(M$MEM, M, Rx)[seq_len(e)]
  per <- aif_periods(cfg)
  st <- rbindlist(lapply(names(per), function(p) {
    sel <- d >= per[[p]][1] & d <= per[[p]][2] & is.finite(ew)
    if (sum(sel) < 60L) return(NULL)
    a <- aif_stats(M$bm[seq_len(e)][sel], d[sel], M$bm[seq_len(e)][sel], M$rf[seq_len(e)][sel], cfg)
    b <- aif_stats(ew[sel], d[sel], M$bm[seq_len(e)][sel], M$rf[seq_len(e)][sel], cfg)
    rbindlist(list(cbind(data.table(factor = cfg$measure$benchmark_label, portfolio = "benchmark", cost = "gross", period = p), as.data.table(a)),
                   cbind(data.table(factor = "유니버스 동일가중", portfolio = "universe_ew", cost = "gross", period = p), as.data.table(b))), fill = TRUE)
  }), fill = TRUE)
  list(stats = st, daily = data.table(Date = d, bm = M$bm[seq_len(e)], universe_ew = ew, rf = M$rf[seq_len(e)]))
}
