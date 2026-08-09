## proxy_axis.R — 대리 축(proxy axis)이 원 라벨을 재현하는지 강제 확인
##
## 왜 계약인가 (2026-08-09 실사고 3연속, 한 아크 안에서):
##  ①`Active_Layers` **한 이름만** is.numeric 검사하고 "수치 강도 컬럼 부재 → 착수 불가" 선언.
##    실제로는 연속 축이 7개 있었다. ⇒ 한 이름 조회는 **존재 검사**이지 정체 검사가 아니다.
##  ②대리 축 **방향을 확인 없이** 상위 분위를 ON 으로 가정. 실제 phi **−0.394**(무작위 기대보다 낮은 일치율).
##  ③`setorder(R, -phi)` 로 최적 축을 뽑았는데 **NA 가 최대처럼 정렬**돼 완벽한 축(phi 1.000)을 놓칠 뻔.
## ★핵심 오독: **발화율을 맞추는 것은 재현이 아니다** — 같은 비율로 **다른 달**을 고를 수 있다.
##   실측: 발화율을 71.7% 로 정확히 맞췄는데 월 일치율이 43.5%(무작위 기대 59.5% 보다 낮음)였다.
## ⇒ 대리 축을 쓸 때는 이 함수를 통과시켜라. 통과 없이 쓴 수치는 원 라벨의 수치가 아니다.
##
## SOT 메모리: [[feedback-identify-before-existence-check]] 2026-08-09 저녁 절

suppressPackageStartupMessages({ library(data.table) })

#' 무작위 두 라벨의 기대 일치율 — 발화율 p 에서 p^2 + (1-p)^2
#' ★재현율을 이 값과 비교하지 않으면 "일치 60%" 가 좋아 보인다(발화율 70% 면 우연 기대가 58%).
proxy_expected_agreement <- function(p) p^2 + (1 - p)^2

#' 연속 축 후보를 **전수 열거** (한 이름 조회 금지 — 실사고 ①)
#' @param dt data.frame · @param min_unique 이산 제외 문턱
proxy_numeric_axes <- function(dt, min_unique = 10L, exclude = character(0)) {
  d <- as.data.table(dt)
  nm <- names(d)[vapply(d, is.numeric, TRUE)]
  nm <- setdiff(nm, exclude)
  nm[vapply(nm, function(c0) data.table::uniqueN(d[[c0]]) >= min_unique, TRUE)]
}

#' ★원 라벨 vs 대리 축 문턱 라벨의 재현율
#' @param orig logical — 원 이진 라벨
#' @param axis numeric — 대리 연속 축 (orig 와 같은 길이·같은 순서)
#' @param direction "low"|"high" — 축의 어느 쪽을 ON 으로 볼지 (실사고 ②)
#' @return list(agree, phi, jaccard, expected, excess, qualified, ...)
proxy_reproduction <- function(orig, axis, direction = c("low","high")) {
  direction <- match.arg(direction)
  stopifnot(length(orig) == length(axis))
  o <- as.logical(orig); v <- suppressWarnings(as.numeric(axis))
  keep <- !is.na(o) & is.finite(v)
  o <- o[keep]; v <- v[keep]
  n <- length(o)
  if (n < 12L) return(list(qualified = FALSE, n = n, note = "n<12 — 재현 판정 불가"))
  p <- mean(o)
  th <- if (direction == "low") stats::quantile(v, p, names = FALSE)
        else stats::quantile(v, 1 - p, names = FALSE)
  lb <- if (direction == "low") v <= th else v >= th
  agree <- mean(o == lb)
  phi <- suppressWarnings(stats::cor(as.integer(o), as.integer(lb)))
  jac <- sum(o & lb) / max(sum(o | lb), 1L)
  exp_ag <- proxy_expected_agreement(p)
  list(n = n, fire_rate = p, direction = direction, threshold = th,
       agree = agree, phi = phi, jaccard = jac,
       expected_agreement = exp_ag, excess = agree - exp_ag,
       qualified = is.finite(phi) && phi > 0.4 && (agree - exp_ag) > 0.10,
       note = "qualified = phi>0.4 AND 일치율이 무작위 기대를 +10%p 초과")
}

#' ★축 x 방향 **전수 탐색** 후 최적 선택 (NA 안전 정렬 — 실사고 ③)
proxy_select_axis <- function(orig, dt, axes = NULL, min_unique = 10L, exclude = character(0)) {
  d <- as.data.table(dt)
  if (is.null(axes)) axes <- proxy_numeric_axes(d, min_unique, exclude)
  if (!length(axes)) return(list(best = NULL, table = data.table(), note = "수치 축 0개"))
  rows <- list()
  for (a in axes) for (dir in c("low","high")) {
    r <- proxy_reproduction(orig, d[[a]], dir)
    if (isTRUE(r$qualified) || is.finite(r$phi %||% NA_real_) || !is.null(r$agree))
      rows[[length(rows)+1L]] <- data.table(axis = a, direction = dir,
        agree = r$agree %||% NA_real_, phi = r$phi %||% NA_real_,
        jaccard = r$jaccard %||% NA_real_, excess = r$excess %||% NA_real_,
        qualified = isTRUE(r$qualified))
  }
  T <- rbindlist(rows, fill = TRUE)
  ## ★NA 제거 후 정렬 — `-phi` 정렬에서 NA 는 조용히 앞에 온다(실사고 ③)
  Tv <- T[is.finite(phi)]
  if (!nrow(Tv)) return(list(best = NULL, table = T, note = "유한 phi 0개 — 재현 가능한 축 없음"))
  setorder(Tv, -phi, -agree)
  list(best = as.list(Tv[1]), table = T[order(-phi, na.last = TRUE)],
       note = sprintf("최적 %s/%s · phi %.3f · 일치 %.1f%% (기대 대비 %+.1f%%p)",
                      Tv$axis[1], Tv$direction[1], Tv$phi[1], 100*Tv$agree[1], 100*Tv$excess[1]))
}

#' 강제 게이트 — 재현 실패 시 stop
assert_proxy_reproduces <- function(orig, axis, direction = c("low","high"), label = "proxy") {
  r <- proxy_reproduction(orig, axis, direction)
  if (!isTRUE(r$qualified)) {
    stop(sprintf(paste0("assert_proxy_reproduces[%s]: 대리 축이 원 라벨을 재현하지 못한다 — ",
      "일치 %.1f%% (무작위 기대 %.1f%%, 초과 %+.1f%%p) · phi %s · Jaccard %s. ",
      "★발화율을 맞추는 것은 재현이 아니다 — 같은 비율로 다른 달을 고를 수 있다. ",
      "축·방향을 proxy_select_axis() 로 전수 탐색하라."),
      label, 100*(r$agree %||% NA_real_), 100*(r$expected_agreement %||% NA_real_),
      100*(r$excess %||% NA_real_),
      if (is.null(r$phi)) "NA" else sprintf("%.3f", r$phi),
      if (is.null(r$jaccard)) "NA" else sprintf("%.3f", r$jaccard)))
  }
  invisible(r)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
cat("[proxy_axis.R] Loaded — proxy_numeric_axes() / proxy_reproduction() / proxy_select_axis() / assert_proxy_reproduces()\n")
