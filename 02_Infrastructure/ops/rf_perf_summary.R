#!/usr/bin/env Rscript
#==============================================================================
# rf_perf_summary.R — 무인 통보용 **성과 요약 kv + 차트** (도훈 지시 2026-08-30)
#
# 도훈 원문: "차트 밑에 예전 알파 서치 모드 있을 때 보내주던 통계값 포맷 텔레그램도
#            같이 보내주게 수정해줘."
#
# ★정본은 `run_alpha_search.R::.send_alpha_search_brief` 의 kv "성과 요약" 이다.
#   그 함수는 run_alpha_search 내부 상태(m·sdef·hg·fmt·auth)에 묶여 있어 그대로 못 부른다.
#   ⇒ **수치를 재계산하지 않는다** — 표준 계약 산출물에서 읽기만 한다:
#     06_metrics.csv · 07_benchmark_compare.csv · authoritative_remeasure.json
#   손계산 금지(v9.21 등급 일원화) 정합. 여기서 새로 만드는 수치는 하나도 없다.
#
# 사용: source(...); rf_perf_kv(artifact_dir) / rf_perf_charts(dir) / rf_perf_weak(dir)
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                            (length(a) == 1L && is.na(a))) b else a

.rfp_metrics <- function(dir) {
  f <- file.path(dir, "06_metrics.csv")
  if (!file.exists(f)) return(list())
  d <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(list())
  setNames(as.list(suppressWarnings(as.numeric(d$metric_value))), d$metric_name)
}

.rfp_bench <- function(dir) {
  f <- file.path(dir, "07_benchmark_compare.csv")
  if (!file.exists(f)) return(list())
  d <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(list())
  list(strategy = setNames(as.list(suppressWarnings(as.numeric(d$strategy_value))), d$metric_name),
       active   = setNames(as.list(suppressWarnings(as.numeric(d$active_value))),   d$metric_name))
}

.rfp_auth <- function(dir) {
  f <- file.path(dir, "authoritative_remeasure.json")
  if (!file.exists(f)) return(list())
  tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) list())
}

.pc <- function(x, d = 1) if (is.null(x) || !is.finite(x)) "n/a" else sprintf(paste0("%.", d, "f%%"), 100 * x)
.nm <- function(x, d = 2) if (is.null(x) || !is.finite(x)) "n/a" else sprintf(paste0("%.", d, "f"), x)

#' 성과 요약 kv — 예전 알파 서치 포맷. 전부 계약 산출값 읽기.
rf_perf_kv <- function(dir, universe = "K200\u222aKQ150") {
  m <- .rfp_metrics(dir); b <- .rfp_bench(dir); a <- .rfp_auth(dir)
  es <- a$essence %||% list()
  kv <- list()
  kv[["\uc720\ub2c8\ubc84\uc2a4"]]        <- sprintf("%s \u00b7 \ud3c9\uade0 %s\uc885\ubaa9",
                                                universe, .nm(m$Average_N_Holdings, 0))
  kv[["\ub4f1\uae09"]]                    <- as.character(a$essence_grade %||% "NA")
  kv[["\ub2e4\uc911\uac80\uc815 t\uac12"]] <- .nm(es$portfolio_alpha_t_nw_lag3 %||%
                                                b$strategy$Portfolio_Alpha_t_NW_lag3)
  kv[["\uc0e4\ud504\uc9c0\uc218"]]        <- .nm(m$Sharpe)
  kv[["\uc5f0\ubcf5\ub9ac\uc218\uc775\ub960"]] <- .pc(m$CAGR)
  kv[["\ucd5c\ub300\ub099\ud3ed"]]        <- .pc(-abs(m$MDD %||% NA_real_))
  kv[["\uce7c\ub9c8\uc9c0\uc218"]]        <- .nm(m$Calmar)
  kv[["\uc815\ubcf4\ube44\uc728"]]        <- .nm(b$active$Information_Ratio)
  kv[["\uc5f0\ud658\uc0b0\uc54c\ud30c"]]  <- .pc(b$active$Alpha_Annualized)
  kv[["\ud68c\uc804\uc728"]]              <- .pc(m$Annualized_Turnover, 0)
  kv[["\ubca4\uce58\ub9c8\ud06c\uc0c1\uad00"]] <- .nm(b$strategy$Correlation)
  kv[["\ud45c\ubcf8\uc678 \uc720\uc9c0\uc728"]] <- .nm(es$oos_retention)
  dsr <- suppressWarnings(as.numeric(es$dsr %||% NA))
  if (is.finite(dsr)) kv[["\uac10\uac00\uc0e4\ud504\uc9c0\uc218"]] <- .nm(dsr)
  kv[vapply(kv, function(x) !identical(x, "n/a"), logical(1))]
}

#' 주의/약점 — 예전 포맷의 weak 규칙 그대로(임계값 도훈 승인분 유지)
rf_perf_weak <- function(dir) {
  m <- .rfp_metrics(dir); b <- .rfp_bench(dir); a <- .rfp_auth(dir)
  es <- a$essence %||% list(); w <- character(0)
  to <- m$Annualized_Turnover %||% NA_real_
  if (is.finite(to) && to > 3)
    w <- c(w, sprintf("\ud68c\uc804\uc728 \ub192\uc74c(\uc5f0 %s) \u2014 \uac70\ub798\ube44\uc6a9 \ubbfc\uac10", .pc(to, 0)))
  md <- m$MDD %||% NA_real_
  if (is.finite(md) && abs(md) > 0.30)
    w <- c(w, sprintf("\ucd5c\ub300\ub099\ud3ed \ud07c(%s)", .pc(-abs(md))))
  ir <- b$active$Information_Ratio %||% NA_real_
  if (is.finite(ir) && ir <= 0)
    w <- c(w, "\ubca4\uce58\ub9c8\ud06c \ub300\ube44 \ucd08\uacfc\uc218\uc775 \ubbf8\ud655\ubcf4")
  if (isTRUE(a$structural_drawdown))
    w <- c(w, "\uad6c\uc870 \ub099\ud3ed \ub77c\ubca8 \u2014 \ud310\uc815 \uc544\ub2c8\ub77c \ub77c\uc6b0\ud305 \uadfc\uac70")
  bc <- b$strategy$Correlation %||% NA_real_
  if (is.finite(bc) && is.finite(md) && abs(md) > 0.35 && bc >= 0.7)
    w <- c(w, "\uc704\uae30 \ub3d9\uc870 \ub099\ud3ed \u2014 \uad6d\uba74\ud544\ud130 \ubd80\uc7ac")
  if (length(w) < 2) w <- c(w, "\ud2b9\uc774 \uc704\ud5d8\uc694\uc778 \uc81c\ud55c\uc801", "\ucd94\uac00 \uc815\ubc00\uac80\uc99d \uad8c\uace0")
  substr(head(w, 4L), 1, 78)
}

#' 차트 3종. ★빈 그림은 붙이지 않되 **무엇을 뺐는지 알린다**(무성 절삭 금지).
rf_perf_charts <- function(dir, min_bytes = 2000L) {
  p <- file.path(dir, c("equity_curve.png", "annual_returns.png", "drawdown.png"))
  p <- p[file.exists(p)]
  if (!length(p)) return(character(0))
  sz <- file.info(p)$size
  drop <- p[sz < min_bytes]
  if (length(drop))
    cat(sprintf("[rf_perf] \ube48 \ucc28\ud2b8 \uc81c\uc678: %s (%s bytes)\n",
                paste(basename(drop), collapse = ","), paste(sz[sz < min_bytes], collapse = ",")))
  p[sz >= min_bytes]
}
