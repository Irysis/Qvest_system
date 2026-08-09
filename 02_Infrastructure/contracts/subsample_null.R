## subsample_null.R — 창을 자르는 주장의 선행 게이트 + 대조군 갈림 게이트
##
## 왜 계약인가 (2026-08-09 실사고, 6라운드 비용):
##  계약 슬리브의 "국면 ON월 직교성"(전체 rho 0.369 → ON월 0.186)을 기전으로 확립하고
##  그 위에서 설명 후보 **7종**을 기각하며 아크를 돌았다. 마지막에 무작위 26개월 부분집합
##  **1000회** 귀무분포를 그리니 관측 Δrho −0.183 의 백분위가 **14.8%**, 5재료 전건이 분포 안이었다.
##  ⇒ **설명할 현상이 없었다.** 73개월에서 26개월을 뽑는 것만으로 rho 가 ±0.2~0.3 흔들린다.
##
##  근본 원인은 데이터가 아니라 판독이었다 — 두 대조가 갈렸는데(무작위 **신호** 0% vs 무작위 **타이밍** 15%)
##  **낮은 쪽을 기전으로 채택**했다. 갈림 자체가 "창이 아니라 신호가 특별" 이라는 답이었다.
##
## ⇒ 두 게이트:
##  ①`assert_subsample_null()` — 창(국면·부분표본)을 잘라 통계 차이를 주장하기 전에
##    같은 개수 무작위 부분집합 귀무분포를 강제. 1000회에 수 초라 비용이 없다.
##  ②`assert_controls_agree()` — 대조 둘 이상이 갈리면 **보수적인(높은 백분위) 쪽으로 판정**하고 경고.
##
## SOT 메모리: [[feedback-two-controls-disagree-that-is-the-signal]]

suppressPackageStartupMessages({ library(data.table) })

#' ★부분표본 귀무분포 — 창을 자른 통계가 표본 변동 안인가
#' @param x,y numeric — 전체 표본의 두 계열 (같은 길이)
#' @param subset logical — 주장하려는 부분표본 (같은 길이). TRUE 인 곳이 창.
#' @param stat function(x,y) — 검정 통계(기본 상관). 창 통계 − 전체 통계로 Δ 를 만든다.
#' @param n_draw 무작위 부분집합 반복
subsample_null <- function(x, y, subset, stat = function(a, b) stats::cor(a, b),
                           n_draw = 1000L, seed = 20260809L) {
  keep <- is.finite(x) & is.finite(y) & !is.na(subset)
  x <- x[keep]; y <- y[keep]; s <- as.logical(subset)[keep]
  n <- length(x); k <- sum(s)
  if (n < 24L || k < 8L || k >= n)
    return(list(available = FALSE, n = n, k = k,
                note = "n<24 또는 k<8 또는 k>=n — 귀무분포 산출 불가"))
  full <- stat(x, y); win <- stat(x[s], y[s])
  obs <- win - full
  set.seed(seed)
  d <- vapply(seq_len(n_draw), function(i) { idx <- sample.int(n, k); stat(x[idx], y[idx]) - full },
              numeric(1))
  d <- d[is.finite(d)]
  if (length(d) < 100L) return(list(available = FALSE, note = "유효 draw 부족"))
  pct <- 100 * mean(d < obs)
  list(available = TRUE, n = n, k = k, n_draw = length(d),
       stat_full = full, stat_window = win, delta = obs,
       null_q05 = unname(stats::quantile(d, 0.05)), null_q50 = unname(stats::quantile(d, 0.50)),
       null_q95 = unname(stats::quantile(d, 0.95)), null_sd = stats::sd(d),
       percentile = pct,
       inside = pct > 5 && pct < 95,
       note = paste0("inside=TRUE 면 관측 Δ 가 **같은 개수 무작위 부분집합의 통상 변동** 안이다 — ",
                     "창이 특별하다는 주장 불가. 창 크기가 작을수록 귀무 폭이 넓다."))
}

#' 강제 게이트 — 창이 특별하지 않으면 stop
assert_subsample_null <- function(x, y, subset, label = "window", ...) {
  r <- subsample_null(x, y, subset, ...)
  if (!isTRUE(r$available))
    stop(sprintf("assert_subsample_null[%s]: 귀무분포 산출 불가 — %s", label, r$note))
  if (isTRUE(r$inside))
    stop(sprintf(paste0("assert_subsample_null[%s]: 관측 Δ %+.4f 가 무작위 부분집합 귀무분포 **안**이다 ",
      "(백분위 %.1f%% · 귀무 [%+.4f, %+.4f] · n %d 중 k %d). ",
      "★창이 특별하다는 주장은 성립하지 않는다 — 부분표본 크기가 작으면 통계는 자체로 흔들린다. ",
      "실사고: 73개월 중 26개월에서 rho 가 ±0.2~0.3 흔들려 관측 −0.183 이 14.8 백분위였다."),
      label, r$delta, r$percentile, r$null_q05, r$null_q95, r$n, r$k))
  invisible(r)
}

#' ★대조군 갈림 — 둘 이상 대조의 백분위가 크게 다르면 경고하고 **보수적 쪽**을 반환
#' @param controls named numeric — 대조별 백분위(0~100). 낮을수록 "특별함" 을 뜻하는 관례.
#' @param tol 갈림으로 볼 백분위 차
assert_controls_agree <- function(controls, tol = 10, label = "controls", hard = FALSE) {
  v <- unlist(controls)
  v <- v[is.finite(v)]
  if (length(v) < 2L) return(invisible(list(agree = NA, note = "대조 2개 미만 — 판정 불가")))
  spread <- max(v) - min(v)
  conservative <- names(v)[which.max(v)]
  out <- list(agree = spread <= tol, spread = spread, values = v,
              conservative = conservative, conservative_pct = unname(max(v)),
              note = paste0("갈리면 **보수적인(백분위 높은) 대조로 판정**한다. ",
                "두 대조는 서로 다른 것을 무효화하므로 갈림 자체가 '무엇이 특별한가' 의 답이다."))
  if (!out$agree) {
    msg <- sprintf(paste0("assert_controls_agree[%s]: 대조가 갈린다 — %s (폭 %.1f%%p > 허용 %.1f). ",
      "★낮은 쪽을 기전으로 채택하지 말 것. 보수적 대조 **%s = %.1f%%** 로 판정하고 ",
      "갈림의 의미를 명시 서술하라. 실사고: 무작위 신호 0%% vs 무작위 타이밍 15%% 에서 낮은 쪽을 ",
      "채택해 없는 현상에 설명 7종을 붙였다."),
      label, paste(sprintf("%s=%.1f%%", names(v), v), collapse=" · "), spread, tol,
      conservative, max(v))
    if (isTRUE(hard)) stop(msg) else warning(msg, call. = FALSE)
  }
  invisible(out)
}

cat("[subsample_null.R] Loaded — subsample_null() / assert_subsample_null() / assert_controls_agree()\n")
