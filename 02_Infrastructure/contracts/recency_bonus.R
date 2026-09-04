#!/usr/bin/env Rscript
#==============================================================================
# recency_bonus.R — 최근 실적 개선에 대한 가점 (도훈 지시 2026-09-04)
#
# 도훈 원문: "최근에 실적 개선이 된 그 사실 자체에 가점을 주라고" · "등급 변동까지 가능하게끔"
#
# ★이것은 **예측 주장이 아니다.** 실측으로 개선폭은 다음 구간 성과를 예측하지 않는다
#   (수준 통제 시 기울기 −0.085, SE 0.025 — 오히려 평균회귀). 그래도 가점을 주는 이유는
#   등급이 "이 전략이 무엇인가"의 요약이고, **최근에 좋아졌다는 것은 그 시계열의 실재 속성**
#   이기 때문이다. 전기간 평균 하나는 그 속성을 통째로 뭉갠다.
#   ⇒ 그래서 예측력으로 크기를 보정하지 않는다. 대신 두 가지를 지킨다:
#      ① 기본 등급과 가점분을 **분리 기록**한다 — 등급은 BOOK 등재·2계층 풀 자격을 거는 데
#         쓰이므로, 소비하는 쪽이 어느 부분이 무엇에서 왔는지 알아야 한다.
#      ② 개선폭이 **추정 잡음보다 클 때만** 발화한다. 잡음과 구별되지 않으면 '좋아졌다'는
#         사실 자체가 성립하지 않는다 — 예측 논리가 아니라 측정 논리다.
#
# ★비교는 **벤치마크 대비 위험조정 지표**로 한다 (도훈 지시: "샤프 칼마 변동성").
#   원시 초과수익으로 재면 안 된다 — 벤치가 최근 36개월 3.17배(연 59.5%) 가서
#   롱온리 366건 중 92%가 마이너스이고, 규칙이 국면 때문에 구조적으로 발화하지 않는다.
#   Sharpe·Calmar 차분은 전략과 벤치가 같은 구간을 겪으므로 달력 통제가 공짜로 따라온다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rb_null <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RB_FALLBACK <- list(
  enabled        = TRUE,
  window_months  = 36L,     # 최근/직전 창 길이
  min_months     = 24L,     # 창당 최소 관측
  metric         = "sharpe",# 개선을 재는 축 (sharpe | calmar)
  one_sided      = TRUE,    # 가점만 — 악화에 감점하지 않는다(도훈: "가점")
  se_multiple    = 1.0,     # 개선폭이 SE 의 몇 배를 넘어야 '성립'인가
  boot_n         = 300L,    # 잡음 추정 부트스트랩 횟수
  t_per_unit     = 1.0,     # ΔSharpe 1.0 당 PORT_t 가산량
  cap_t          = 1.0      # 가산 상한 (한 등급대 이상 못 넘게)
)

#' 설정 로드 — 수치는 등록부에서 온다(하드코딩 금지)
rb_params <- function(root = Sys.getenv("QM_ROOT", getwd()), refresh = FALSE) {
  p <- file.path(root, "06_Registry/recency_bonus.json")
  cfg <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE),
                                      error = function(e) NULL) else NULL
  out <- RB_FALLBACK
  if (!is.null(cfg)) for (k in names(RB_FALLBACK))
    if (!is.null(cfg[[k]]) && length(cfg[[k]])) out[[k]] <- cfg[[k]]
  out
}

# 월수익 벡터 -> 위험조정 지표
.rb_mets <- function(v) {
  if (length(v) < 6L || !is.finite(sd(v)) || sd(v) == 0) return(list(sr = NA_real_, cal = NA_real_))
  nav <- cumprod(1 + v); mdd <- max(1 - nav / cummax(nav))
  cg  <- prod(1 + v)^(12 / length(v)) - 1
  list(sr = mean(v) / sd(v) * sqrt(12),
       cal = if (is.finite(mdd) && mdd > 1e-6) cg / mdd else NA_real_)
}
.rb_delta <- function(s, k, metric) {
  a <- .rb_mets(s); b <- .rb_mets(k)
  if (identical(metric, "calmar")) a$cal - b$cal else a$sr - b$sr
}

#' 최근 실적 개선 측정
#' @param period_returns   data.table(date, ret_net)
#' @param benchmark_returns data.table(date, benchmark_ret)
#' @return list(...) — status 가 "ok" 일 때만 bonus_t 가 유효
rb_improvement <- function(period_returns, benchmark_returns, params = rb_params()) {
  na <- function(why) list(status = why, bonus_t = 0, established = FALSE,
                           d_recent = NA_real_, d_prior = NA_real_, improve = NA_real_,
                           se = NA_real_, n_recent = 0L, n_prior = 0L, metric = params$metric)
  if (!isTRUE(params$enabled)) return(na("disabled"))
  pr <- tryCatch(as.data.table(period_returns), error = function(e) NULL)
  br <- tryCatch(as.data.table(benchmark_returns), error = function(e) NULL)
  if (is.null(pr) || is.null(br)) return(na("no_series"))
  if (!all(c("date", "ret_net") %in% names(pr)) ||
      !all(c("date", "benchmark_ret") %in% names(br))) return(na("schema"))
  x <- merge(pr[, .(date = as.Date(date), ret_net)],
             br[, .(date = as.Date(date), benchmark_ret)], by = "date")
  x <- x[is.finite(ret_net) & is.finite(benchmark_ret)]
  if (nrow(x) < 60L) return(na("too_short"))
  x[, ym := format(date, "%Y-%m")]
  m <- x[, .(s = prod(1 + ret_net) - 1, k = prod(1 + benchmark_ret) - 1), by = ym][order(ym)]
  W <- as.integer(params$window_months)
  if (nrow(m) < 2L * as.integer(params$min_months)) return(na("too_few_months"))
  n <- nrow(m)
  rec <- m[max(1L, n - W + 1L):n]
  pri <- m[max(1L, n - 2L * W + 1L):max(1L, n - W)]
  if (nrow(rec) < params$min_months || nrow(pri) < params$min_months) return(na("window_short"))

  d_rec <- .rb_delta(rec$s, rec$k, params$metric)
  d_pri <- .rb_delta(pri$s, pri$k, params$metric)
  if (!is.finite(d_rec) || !is.finite(d_pri)) return(na("metric_na"))
  improve <- d_rec - d_pri

  # ── 잡음 규모 — 블록 부트스트랩 (분석식 대신: 두 창의 상관·왜도를 그대로 안고 간다)
  B <- as.integer(params$boot_n); bl <- 6L
  sim <- numeric(B)
  set.seed(20260904L)
  for (i in seq_len(B)) {
    .rs <- function(dt) {
      nb <- ceiling(nrow(dt) / bl)
      st <- sample.int(max(1L, nrow(dt) - bl + 1L), nb, replace = TRUE)
      idx <- unlist(lapply(st, function(j) j:(j + bl - 1L)))
      idx <- idx[idx <= nrow(dt)][1:nrow(dt)]
      dt[idx[!is.na(idx)]]
    }
    a <- .rs(rec); b <- .rs(pri)
    v <- .rb_delta(a$s, a$k, params$metric) - .rb_delta(b$s, b$k, params$metric)
    sim[i] <- if (is.finite(v)) v else NA_real_
  }
  se <- stats::sd(sim, na.rm = TRUE)
  established <- is.finite(se) && se > 0 && improve > as.numeric(params$se_multiple) * se

  bonus <- 0
  if (isTRUE(established)) {
    bonus <- as.numeric(params$t_per_unit) * improve
    if (isTRUE(params$one_sided)) bonus <- max(0, bonus)
    bonus <- max(-abs(params$cap_t), min(abs(params$cap_t), bonus))
  }
  list(status = "ok", metric = params$metric,
       d_recent = d_rec, d_prior = d_pri, improve = improve, se = se,
       established = established, bonus_t = bonus,
       n_recent = nrow(rec), n_prior = nrow(pri),
       window_months = W,
       note = sprintf("%s 벤치대비 %s: 직전창 %+.3f -> 최근창 %+.3f (개선 %+.3f, SE %.3f) %s",
                      if (isTRUE(established)) "성립" else "미성립",
                      params$metric, d_pri, d_rec, improve, se,
                      if (isTRUE(established)) sprintf("-> 가점 %+.3f", bonus) else "-> 가점 없음"))
}
