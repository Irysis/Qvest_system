#!/usr/bin/env Rscript
#==============================================================================
# rf_rebalance.R — 집행 주기·회전 통제 축 (B6) · 2026-09-21 신설 (도훈 승인)
#
# ★왜 이 축이 생겼나 (실측 2026-09-21 · promo2 B1_2)
#   총액 CAGR 28.97% vs 순 25.84% — **연 3.13%p 가 비용으로 나간다**. 월 회전율 0.678
#   (연 8.1회)이라 25종 포트가 매달 3분의 2씩 갈린다. A 를 막는 Calmar(0.490 < 0.64)는
#   분모(MDD)뿐 아니라 **분자(CAGR)** 로도 칠 수 있고, 이 계보에서 분모 쪽(오버레이)은
#   적대검증 29칸 0 pass 로 막혀 있다. 비용 절감은 '타이밍 주장' 이 아니라 체결 규칙이라
#   플라시보(T3)로 죽는 종류가 아니다. 과거 기록도 같은 방향이다 — DIST-RAMP-013:
#   "리밸 주기를 분기로 바꾸니 oos_retention −0.27 → −0.02 · 회전 절반"(추정치).
#
# ★왜 하네스를 안 고쳐도 되나
#   replication_harness 는 리밸 시점을 **엔진이 낸 시그널 날짜**(sig_dates = unique(W$Date))
#   에서 받고, 보유 구간은 Return.portfolio(rebalance_on = NA) 로 **드리프트**시킨다.
#   즉 "몇 달마다 비중을 낼지" 만 정하면 주기가 바뀌고 비용도 그 시점 회전율로만 부과된다.
#
# ★PIT — 네 규칙 전부 과거·현재만 본다
#   interval 은 달력 인덱스(신호일 순번)만 쓴다. band/cap 의 문턱은 **자기 과거 거리의
#   확장창 통계**다(미래 없음 · 리터럴 문턱 없음). rank_buffer 는 그날의 점수 순위와
#   **직전 보유**만 본다. 어느 규칙도 H$fwd·미래 수익을 읽지 않는다.
#
# 계약 (엔진 rf_cell_engine.R 이 두 지점에서 부른다)
#   ① 선정 직후      SEL  <- rf_rb_select(PANEL, SEL, rule, n_max)   # rank_buffer
#   ② 배출 직전      PORT <- rf_rb_emit(PORT, rule)                  # interval·band·cap
#   규칙이 없으면(NULL) 두 함수 모두 **입력을 그대로** 돌려준다(무처치 = 월간 그대로).
#==============================================================================
suppressMessages(library(data.table))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RF_RB_KINDS <- c("interval", "no_trade_band", "turnover_cap", "rank_buffer")

#' 규칙 파싱 — 모르는 kind·불가능한 파라미터는 **조용히 무시하지 않고 stop**
#'   (침묵 무처치 금지: 규칙이 안 먹은 채 '주기를 쟀다' 고 기록되면 그 칸은 거짓이다)
rf_rb_parse <- function(rb) {
  if (is.null(rb)) return(NULL)
  kind <- as.character(rb$kind %||% "")
  if (!nzchar(kind)) return(NULL)
  if (!kind %in% RF_RB_KINDS)
    stop(sprintf("[rf_rebalance] 미지원 kind=%s (지원: %s)", kind, paste(RF_RB_KINDS, collapse = ", ")))
  out <- list(kind = kind, label = as.character(rb$label %||% kind))
  if (identical(kind, "interval")) {
    out$k <- suppressWarnings(as.integer(rb$k %||% NA_integer_))
    out$phase <- suppressWarnings(as.integer(rb$phase %||% 0L))
    if (!is.finite(out$k) || out$k < 2L) stop("[rf_rebalance] interval 은 k >= 2 가 필요하다")
    if (!is.finite(out$phase) || out$phase < 0L || out$phase >= out$k)
      stop(sprintf("[rf_rebalance] phase 는 0..%d 여야 한다", out$k - 1L))
  } else if (identical(kind, "rank_buffer")) {
    out$mult <- suppressWarnings(as.numeric(rb$mult %||% NA_real_))
    if (!is.finite(out$mult) || out$mult <= 1) stop("[rf_rebalance] rank_buffer 는 mult > 1 이 필요하다")
  } else {
    out$stat <- as.character(rb$stat %||% "expanding_median")
    out$q <- suppressWarnings(as.numeric(rb$q %||% 0.5))
    out$min_hist <- suppressWarnings(as.integer(rb$min_hist %||% 12L))
    if (!out$stat %in% c("expanding_median", "expanding_quantile"))
      stop("[rf_rebalance] stat 은 expanding_median · expanding_quantile 만")
    if (!is.finite(out$q) || out$q <= 0 || out$q >= 1) stop("[rf_rebalance] q 는 (0,1)")
    if (!is.finite(out$min_hist) || out$min_hist < 3L) stop("[rf_rebalance] min_hist >= 3")
  }
  out
}

#' 한 방향 회전율 — 0.5 * sum|w_t - w_{t-1}| (배출 시점 기준 · 드리프트는 근사로 무시)
#'   ★근사인 이유를 적어 둔다: 실제 보유는 구간 안에서 드리프트하므로 다음 리밸 직전 비중은
#'     직전 배출값과 다르다. 하네스의 비용은 실제 체결분으로 부과되고, 여기 값은 **칸 사이
#'     비교용 진단**이다(같은 근사로 재므로 순위는 유효).
rf_rb_turnover <- function(PORT) {
  if (!is.data.table(PORT) || !nrow(PORT)) return(NA_real_)
  P <- PORT[, .(Date, Ticker, Weight)]
  ds <- sort(unique(P$Date))
  if (length(ds) < 2L) return(NA_real_)
  prev <- P[Date == ds[1L], .(Ticker, w0 = Weight)]
  tv <- numeric(0)
  for (i in seq_along(ds)[-1L]) {
    cur <- P[Date == ds[i], .(Ticker, w1 = Weight)]
    m <- merge(prev, cur, by = "Ticker", all = TRUE)
    m[is.na(w0), w0 := 0]; m[is.na(w1), w1 := 0]
    tv <- c(tv, 0.5 * sum(abs(m$w1 - m$w0)))
    prev <- cur[, .(Ticker, w0 = w1)]
  }
  mean(tv, na.rm = TRUE)
}

#' 확장창 문턱 — 과거 거리들의 중앙값/분위. 표본이 min_hist 미만이면 NA(= 규칙 미발화)
.rf_rb_thresh <- function(hist, rule) {
  if (length(hist) < rule$min_hist) return(NA_real_)
  if (identical(rule$stat, "expanding_median")) stats::median(hist, na.rm = TRUE)
  else unname(stats::quantile(hist, probs = rule$q, na.rm = TRUE, type = 7))
}

#' ① 선정 단계 규칙 — rank_buffer (히스테리시스)
#'   보유 중인 이름은 점수 순위가 mult*n_max 안에 있으면 **유지**하고, 빈 자리만 상위에서 채운다.
#'   교체가 문턱을 넘는 이름에서만 일어나므로 순위 잡음에 의한 왕복 매매가 줄어든다.
#' @param PANEL 그날의 전체 후보(Date, Ticker, Score …) — 자르기 전
#' @param SEL   기본 선정(상위 n_max) — 규칙이 없으면 이것을 그대로 돌려준다
rf_rb_select <- function(PANEL, SEL, rule, n_max) {
  if (is.null(rule) || !identical(rule$kind, "rank_buffer")) return(SEL)
  stopifnot(is.data.table(PANEL), all(c("Date", "Ticker", "Score") %in% names(PANEL)))
  n_max <- as.integer(n_max)
  keep_rank <- max(n_max + 1L, as.integer(ceiling(rule$mult * n_max)))
  P <- PANEL[is.finite(Score)][order(Date, -Score)]
  P[, .rk := seq_len(.N), by = Date]
  ds <- sort(unique(P$Date))
  held <- character(0)
  out <- vector("list", length(ds))
  for (i in seq_along(ds)) {
    d <- ds[i]
    Pi <- P[Date == d]
    stay <- Pi[Ticker %in% held & .rk <= keep_rank][order(.rk)]
    if (nrow(stay) > n_max) stay <- stay[seq_len(n_max)]
    need <- n_max - nrow(stay)
    add <- if (need > 0L) Pi[!Ticker %in% stay$Ticker][order(.rk)][seq_len(min(need, .N))] else Pi[0L]
    sel <- rbindlist(list(stay, add), use.names = TRUE)
    held <- as.character(sel$Ticker)
    out[[i]] <- sel
  }
  res <- rbindlist(out, use.names = TRUE)
  res[, .rk := NULL]
  setcolorder(res, intersect(names(SEL), names(res)))
  res[]
}

#' ② 배출 단계 규칙 — interval · no_trade_band · turnover_cap
#'   배출된 날짜 = 리밸 날짜다(하네스가 그 사이를 드리프트로 보유하고 비용도 그때만 부과).
rf_rb_emit <- function(PORT, rule) {
  if (is.null(rule) || identical(rule$kind, "rank_buffer")) return(PORT)
  stopifnot(is.data.table(PORT), all(c("Date", "Ticker", "Weight") %in% names(PORT)))
  ds <- sort(unique(PORT$Date))
  if (identical(rule$kind, "interval")) {
    keep <- ds[(seq_along(ds) - 1L) %% rule$k == rule$phase]
    if (!length(keep)) stop("[rf_rebalance] interval 이 배출 날짜를 전부 지웠다")
    return(PORT[Date %in% keep][])
  }
  # band · cap 은 순차적으로 직전 **배출값**과 비교한다(과거만 본다)
  prev <- NULL; hist <- numeric(0); out <- list()
  for (d in ds) {
    cur <- PORT[Date == d]
    if (is.null(prev)) { out[[length(out) + 1L]] <- cur; prev <- cur[, .(Ticker, w0 = Weight)]; next }
    m <- merge(prev, cur[, .(Ticker, w1 = Weight)], by = "Ticker", all = TRUE)
    m[is.na(w0), w0 := 0]; m[is.na(w1), w1 := 0]
    dist <- sum(abs(m$w1 - m$w0))               # L1 (양방향 합)
    thr <- .rf_rb_thresh(hist, rule)
    hist <- c(hist, dist)
    if (identical(rule$kind, "no_trade_band")) {
      if (is.finite(thr) && dist < thr) next     # 미체결 — 직전 보유를 그대로 든다
      out[[length(out) + 1L]] <- cur; prev <- cur[, .(Ticker, w0 = Weight)]
    } else {                                     # turnover_cap
      if (is.finite(thr) && dist > thr && dist > 0) {
        lam <- thr / dist                        # 목표 쪽으로 lam 만큼만 이동
        m[, w := w0 + lam * (w1 - w0)]
        blend <- m[w > 1e-12, .(Date = d, Ticker, Weight = w)]
        s_t <- sum(cur$Weight); s_b <- sum(blend$Weight)
        if (is.finite(s_b) && s_b > 0) blend[, Weight := Weight * (s_t / s_b)]   # 노출(Σw) 보존
        if (!nrow(blend)) { out[[length(out) + 1L]] <- cur; prev <- cur[, .(Ticker, w0 = Weight)]; next }
        if ("Leg" %in% names(cur)) blend[, Leg := cur$Leg[1L]]
        out[[length(out) + 1L]] <- blend; prev <- blend[, .(Ticker, w0 = Weight)]
      } else {
        out[[length(out) + 1L]] <- cur; prev <- cur[, .(Ticker, w0 = Weight)]
      }
    }
  }
  res <- rbindlist(out, use.names = TRUE, fill = TRUE)
  if (!nrow(res)) stop("[rf_rebalance] 규칙 적용 후 배출이 비었다")
  res[]
}

#' 한 줄 진단 — 칸 로그·원장에 남길 문자열(전후 회전율·리밸 횟수)
rf_rb_report <- function(before, after, rule) {
  sprintf("rebalance=%s | 리밸 %d→%d회 · 회전율 %.3f→%.3f",
          rule$label %||% rule$kind,
          length(unique(before$Date)), length(unique(after$Date)),
          rf_rb_turnover(before), rf_rb_turnover(after))
}

if (identical(environment(), globalenv()) && !interactive())
  cat("[rf_rebalance.R] Loaded — rf_rb_parse / rf_rb_select / rf_rb_emit / rf_rb_turnover / rf_rb_report\n")
