## census_helper.R — census 3규약 (2026-08-22 신설)
## ─────────────────────────────────────────────────────────────────────────────
## 왜 필요한가 — **하루에 6회** 같은 계통을 밟았다:
##   ① KQ150 퇴출 0 → 편입을 안 세서 편향 방향까지 오진
##   ② screen 필드 0 → 잘못된 레지스트리를 봄(라벨은 다른 곳에 산다)
##   ③ auto_spawn verdict=None → 이월 엔트리가 신규 경로를 우회
##   ④ 사본 dir 부재 → 최상위 on.exit 로 선삭제(가드는 통과했는데 시점이 틀림)
##   ⑤ NOT_AUDITED 2건 → '판정 불가' 로 넘겼으면 통과 후보(NW-t 3.248)를 버릴 뻔
##   ⑥ 형식 census 표본 120/500 에서 비계약 0 → **내가 아는 반례**를 표본이 놓침
##
## 공통 기전 = **"0 을 관측했다" 를 "0 이다" 로 읽는다.**
## 이 파일은 그 셋을 기계화한다:
##   (A) 기지 반례가 모집단에 들어왔는지 **먼저** 확인 — 없으면 census 범위가 틀린 것이다
##   (B) 모집단이 작으면 **전수**, 클 때만 표본
##   (C) 표본 0건에 **신뢰 상한 병기** — "0건" 과 "없음" 은 다르다
## ─────────────────────────────────────────────────────────────────────────────

#' (A) census 범위 검증 — 기지 반례가 모집단에 있는가
#'
#' @param population  chr/vector — census 대상 전체(경로·id 등)
#' @param known       chr/vector — 반드시 포함돼야 하는 기지 사례(반례·양성 대조)
#' @param strict      TRUE 면 누락 시 stop, FALSE 면 경고 후 결과 반환
#' @return list(ok, missing, n_pop, n_known)
census_assert_scope <- function(population, known = character(0), strict = TRUE) {
  population <- as.character(population); known <- as.character(known)
  miss <- setdiff(known, population)
  ok <- length(miss) == 0L
  msg <- sprintf("[census_scope] 모집단 %d · 기지사례 %d · 누락 %d",
                 length(population), length(known), length(miss))
  if (!ok) {
    msg <- paste0(msg, "\n  ★누락: ", paste(utils::head(miss, 5), collapse = ", "),
                  if (length(miss) > 5) sprintf(" 외 %d", length(miss) - 5) else "",
                  "\n  ⇒ census **범위가 틀렸다**. 결과의 '0건' 은 신뢰할 수 없다.")
    if (isTRUE(strict)) stop(msg)
    warning(msg)
  }
  cat(msg, "\n")
  list(ok = ok, missing = miss, n_pop = length(population), n_known = length(known))
}

#' (B) 전수/표본 결정 — 작으면 전수, 클 때만 표본
#'
#' @param population chr/vector
#' @param full_below 이 이하면 전수 (기본 200)
#' @param n_sample   표본 크기 (기본 150)
#' @param must_include 표본에 **반드시 포함**할 원소(기지 사례) — 표본이 반례를 놓치는 것을 막는다
#' @param seed       재현용
#' @return list(items, mode, n_pop, n_used, coverage)
census_draw <- function(population, full_below = 200L, n_sample = 150L,
                        must_include = character(0), seed = 20260822L) {
  population <- as.character(population); N <- length(population)
  if (N <= full_below) {
    cat(sprintf("[census_draw] 전수 %d (<= %d)\n", N, full_below))
    return(list(items = population, mode = "FULL", n_pop = N, n_used = N, coverage = 1))
  }
  set.seed(seed)
  must <- intersect(as.character(must_include), population)
  rest <- setdiff(population, must)
  k <- max(0L, min(n_sample - length(must), length(rest)))
  items <- c(must, if (k > 0L) sample(rest, k) else character(0))
  cat(sprintf("[census_draw] 표본 %d / %d (%.0f%%) · 강제 포함 %d\n",
              length(items), N, 100 * length(items) / N, length(must)))
  list(items = items, mode = "SAMPLE", n_pop = N, n_used = length(items),
       coverage = length(items) / N)
}

#' (C) 표본 0건의 신뢰 상한 — "0건" 과 "없음" 을 구분한다
#'
#' 표본 n 에서 사건이 0건일 때, 모집단 비율 p 의 상한(단측 conf).
#' 규칙 셋(rule of three)의 정확판: p_upper = 1 - (1-conf)^(1/n)
#' @return list(p_upper, n_upper_est, text)
census_zero_bound <- function(n_sample, n_population = NA_integer_, conf = 0.95) {
  stopifnot(is.numeric(n_sample), n_sample >= 1)
  p <- 1 - (1 - conf)^(1 / n_sample)
  n_up <- if (is.finite(n_population)) ceiling(p * n_population) else NA_real_
  txt <- sprintf("표본 %d 에서 0건 — 모집단 비율 %.0f%% 상한 = %.2f%%%s",
                 n_sample, 100 * conf, 100 * p,
                 if (is.finite(n_up)) sprintf(" (최대 약 %d건)", n_up) else "")
  list(p_upper = p, n_upper_est = n_up, text = txt, conf = conf)
}

#' 편의 래퍼 — 세 규약을 한 번에
#' @return list(scope, draw, note) — 실제 분류는 호출자가 draw$items 로 수행
census_prepare <- function(population, known = character(0),
                           full_below = 200L, n_sample = 150L, strict = TRUE, seed = 20260822L) {
  sc <- census_assert_scope(population, known, strict = strict)
  dr <- census_draw(population, full_below = full_below, n_sample = n_sample,
                    must_include = known, seed = seed)
  list(scope = sc, draw = dr,
       note = paste0("census 3규약 적용 — (A) 기지사례 범위 검증 ",
                     if (sc$ok) "PASS" else "FAIL",
                     " · (B) ", dr$mode, " · (C) 0건 보고 시 census_zero_bound() 병기 의무"))
}

cat("[census_helper.R] Loaded — census_assert_scope() / census_draw() / census_zero_bound() / census_prepare()\n")
cat("  근거: 2026-08-22 하루 6회 '0 을 관측했다' 를 '0 이다' 로 읽은 계통\n")
