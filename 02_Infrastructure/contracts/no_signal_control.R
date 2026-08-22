## no_signal_control.R — 무신호 대조군 계약 (2026-08-22 신설)
## ─────────────────────────────────────────────────────────────────────────────
## 왜 필요한가 (실측 근거, DFA 아크 R41):
##   게이트 0(종목 <=25 · 비중 <=0.20)을 지키며 살아남은 유일한 팔(T3)이
##   **팩터 신호를 전혀 쓰지 않는 시총 상위 25종 포트폴리오와 구별되지 않았다** —
##   clean 창 초과수익 차이 +0.06%/yr · NW-t 0.028 · 두 계열 상관 0.960 이고,
##   오히려 무신호 대조의 IR(+0.437)과 PORT_t(+1.418)가 더 높았다.
##   즉 '제약을 지키며 벤치를 이겼다' 는 것만으로는 신호의 기여를 증명하지 못한다.
##   롱온리 top-N cap-w 는 그 자체로 대형주 노출을 담고, 그것이 벤치(전체 유니버스 cap-w)를 이길 수 있다.
##
## 두 번째 실측 근거: PORT_t = mean(r - r_bm) 는 alpha 와 (beta-1)*E[r_bm] 을 **섞는다**.
##   T3 의 clean PORT_t +1.065 중 beta 기여가 활성수익의 52% 였다(beta 1.097).
##   ⇒ 알파 존재 판정에는 beta 통제가 필요하다.
##
## 사용법:
##   src <- source("02_Infrastructure/contracts/no_signal_control.R")
##   ctl <- build_no_signal_control(months = ym_vector, n_stocks = 25)
##   res <- no_signal_gate(strategy_monthly, ctl$ret, benchmark_monthly)
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({library(data.table)})

.nsc_cap_weights <- function(w, cap = 0.20, iters = 200L) {
  w <- w / sum(w)
  for (i in seq_len(iters)) {
    ov <- w > cap + 1e-12
    if (!any(ov)) break
    ex <- sum(w[ov] - cap); w[ov] <- cap; fr <- !ov
    if (!any(fr) || sum(w[fr]) <= 0) break
    w[fr] <- w[fr] + ex * w[fr] / sum(w[fr])
  }
  w / sum(w)
}

#' 무신호 대조군 월수익 구축
#'
#' 팩터/신호를 **전혀 사용하지 않고** 유니버스 시총 상위 n_stocks 종목을 cap-weight 로
#' 보유하는 포트폴리오. 제약(종목수·비중 상한)은 전략과 동일하게 적용한다.
#' PIT: 리밸 시점 m 의 구성은 m-1 월말 시총으로 결정한다.
#'
#' @param months  chr vector "YYYY-MM" — 전략과 동일한 월 그리드 (정렬 가정)
#' @param n_stocks 보유 종목 수 (제약과 일치시킬 것)
#' @param cap     단일종목 비중 상한
#' @param freq    리밸 주기(개월)
#' @param bps     편도 거래비용 (delta-based, sum|dw| 에 부과)
#' @param rawdata_path .cache/rawdata.parquet 경로
#' @return list(ret = 월수익 벡터(months 정렬), n_rebal, holdings_n, max_w)
build_no_signal_control <- function(months, n_stocks = 25L, cap = 0.20,
                                    freq = 3L, bps = 15,
                                    rawdata_path = ".cache/rawdata.parquet") {
  stopifnot(is.character(months), length(months) >= 24L, n_stocks >= 1L)
  suppressPackageStartupMessages(library(arrow))
  rd <- as.data.table(arrow::read_parquet(rawdata_path,
          col_select = c("Date","Ticker","Ret","Size","K200","KQ150")))
  rd[, Date := as.Date(Date)]
  rd <- rd[is.finite(Ret)]
  rd[, inuniv := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  rd <- rd[inuniv == TRUE]
  rd[, ym := format(Date, "%Y-%m")]
  MR  <- rd[, .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym)]
  UNI <- rd[is.finite(Size) & Size > 0, .SD[which.max(Date)], by = .(Ticker, ym), .SDcols = "Size"]

  NM <- length(months); out <- rep(NA_real_, NM)
  hn <- integer(0); mw <- numeric(0); prev <- NULL
  starts <- seq(2L, NM, by = freq)      # m=1 은 결정시점(m-1) 부재
  for (i in seq_along(starts)) {
    m0 <- starts[i]; mend <- if (i < length(starts)) starts[i+1] - 1L else NM
    u <- UNI[ym == months[m0 - 1L]][order(-Size)]
    if (nrow(u) < max(10L, n_stocks %/% 2L)) next
    u <- u[seq_len(min(n_stocks, nrow(u)))]
    cur <- setNames(.nsc_cap_weights(u$Size, cap), u$Ticker)
    hn <- c(hn, length(cur)); mw <- c(mw, max(cur))
    tov <- if (is.null(prev)) 1 else {
      al <- union(names(cur), names(prev))
      sum(abs(ifelse(is.na(cur[al]), 0, cur[al]) - ifelse(is.na(prev[al]), 0, prev[al])), na.rm = TRUE) }
    for (mm in m0:mend) {
      rr <- MR[ym == months[mm]][match(names(cur), Ticker), mret]; rr[!is.finite(rr)] <- 0
      out[mm] <- sum(cur * rr) - (if (mm == m0) (bps/1e4) * tov else 0)
      dd <- cur * (1 + rr); cur <- dd / sum(dd)
    }
    prev <- cur
  }
  list(ret = out, n_rebal = length(hn),
       holdings_n = if (length(hn)) as.integer(median(hn)) else NA_integer_,
       max_w = if (length(mw)) max(mw) else NA_real_,
       spec = list(n_stocks = n_stocks, cap = cap, freq = freq, bps = bps,
                   universe = "K200 U KQ150", selection = "market cap top-N (신호 미사용)"))
}

#' 무신호 대조 게이트 + beta-통제 alpha
#'
#' @param strat  전략 월수익
#' @param ctl    무신호 대조군 월수익 (build_no_signal_control()$ret)
#' @param bm     벤치마크 월수익
#' @return list — 전략/대조군 각각의 alpha·beta·t(alpha)·PORT_t, 차이의 NW-t, verdict
no_signal_gate <- function(strat, ctl, bm) {
  suppressPackageStartupMessages({library(sandwich); library(lmtest)})
  k <- which(is.finite(strat) & is.finite(ctl) & is.finite(bm))
  if (length(k) < 24L) stop("no_signal_gate: 공통 관측 24개월 미만 — 판정 불가")
  s <- strat[k]; c_ <- ctl[k]; b <- bm[k]
  .nw1 <- function(x) { m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
  .ab  <- function(x) { f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
                        c(alpha_ann = 12*ct[1,1], beta = ct[2,1], t_alpha = ct[1,3]) }
  as_ <- .ab(s); ac <- .ab(c_)
  d <- s - c_
  diff_t <- .nw1(d)
  # ★verdict: 전략이 무신호 대조를 유의하게 넘어야 '신호 기여 실증'
  verdict <- if (diff_t >= 1.96) "SIGNAL_ADDS_VALUE"
             else if (diff_t <= -1.96) "SIGNAL_HURTS"
             else "INDISTINGUISHABLE_FROM_NO_SIGNAL"
  list(n = length(k),
       strategy = c(as_, port_t = .nw1(s - b),
                    beta_contrib_ann = (as_[["beta"]] - 1) * 12 * mean(b)),
       control  = c(ac,  port_t = .nw1(c_ - b),
                    beta_contrib_ann = (ac[["beta"]] - 1) * 12 * mean(b)),
       diff_ann = 12 * mean(d), diff_nw_t = diff_t,
       corr = cor(s, c_),
       verdict = verdict,
       note = paste0("PORT_t 는 alpha 와 (beta-1)*E[bm] 을 섞는다 — ",
                     "본 결과의 beta_contrib_ann 이 그 몫이다. ",
                     "verdict 는 무신호 대조 대비 증분에만 걸린다."))
}

cat("[no_signal_control.R] Loaded — build_no_signal_control() / no_signal_gate()\n")
cat("  근거: DFA 아크 R41 — 제약 준수 생존팔이 무신호 대조와 구별 불가(NW-t 0.028)\n")
