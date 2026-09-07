#!/usr/bin/env Rscript
#==============================================================================
# defensive_score.R — 방어형 스코어 (도훈 지시 2026-09-04)
#
# ★정의: **벤치마크가 실제로 마이너스를 기록한 국면에서 아웃퍼폼한 전략**.
#   국면엔진 라벨 기준이 아니다(도훈 지시로 폐기). 근거: 국면 라벨은 이 시스템의 알려진
#   병목이고, 라벨 품질이 방어형 판정의 상한을 정하면 전략이 아니라 계기를 재게 된다.
#   실현된 벤치 하락월은 관측이지 추정이 아니므로 그 의존을 통째로 우회한다.
#
# 왜 필요한가(실측 2026-09-04, 380건):
#   방어형 184건(48%) 중 **B 이상이 0건** — 전부 C(92) 또는 F(92) 였다.
#   방어형 vs 비방어형:  하락월 초과 +1.81% vs -0.12% · 벤치 -10% 이하 +5.64% vs -0.43%
#   우위가 심도에 따라 커진다(볼록성) — 선형 베타 효과가 아니라 실제 방어 기전이다.
#
# 경계: **essence 등급을 건드리지 않는다.** 산출은 기록이고, 소비는 2계층 풀 자격이다
#   (도훈 선택 2026-09-04). 단독 알파가 약한 것은 사실이고, 값어치는 조합 안에서 나온다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.ds_null <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

DS_FALLBACK <- list(
  enabled        = TRUE,
  min_down_months = 12L,   # 하락월이 이보다 적으면 판정 불가(NA)
  deep_threshold = -0.10,  # '심한 하락' 정의 (벤치 월수익)
  mid_threshold  = -0.05,
  min_excess     = 0,      # 하락월 평균 초과수익 하한
  min_t          = 1.5,    # 하락월 초과수익 t 하한
  min_hit        = 0.5     # 하락월 중 초과수익 양수 비율 하한
)

ds_params <- function(root = Sys.getenv("QM_ROOT", getwd())) {
  p <- file.path(root, "06_Registry/defensive_score.json")
  cfg <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL) else NULL
  out <- DS_FALLBACK
  if (!is.null(cfg)) for (k in names(DS_FALLBACK))
    if (!is.null(cfg[[k]]) && length(cfg[[k]])) out[[k]] <- cfg[[k]]
  out
}

.ds_seg <- function(d) {
  if (nrow(d) < 3L) return(list(n = nrow(d), excess = NA_real_, hit = NA_real_,
                                t = NA_real_, capture = NA_real_))
  sdv <- stats::sd(d$ex)
  list(n = nrow(d), excess = mean(d$ex), hit = mean(d$ex > 0),
       t = if (is.finite(sdv) && sdv > 0) mean(d$ex)/(sdv/sqrt(nrow(d))) else NA_real_,
       capture = if (mean(d$k) != 0) mean(d$s)/mean(d$k) else NA_real_)
}

#' 방어형 스코어
#' @return list(status, defensive, down/deep/mid/up 세그먼트, reason)
ds_score <- function(period_returns, benchmark_returns, params = ds_params()) {
  na <- function(why) list(status = why, defensive = NA, down = NULL, deep = NULL,
                           mid = NULL, up = NULL, reason = why)
  if (!isTRUE(params$enabled)) return(na("disabled"))
  pr <- tryCatch(as.data.table(period_returns), error = function(e) NULL)
  br <- tryCatch(as.data.table(benchmark_returns), error = function(e) NULL)
  if (is.null(pr) || is.null(br)) return(na("no_series"))
  if (!all(c("date","ret_net") %in% names(pr)) ||
      !all(c("date","benchmark_ret") %in% names(br))) return(na("schema"))
  x <- merge(pr[is.finite(ret_net), .(date = as.Date(date), ret_net)],
             br[is.finite(benchmark_ret), .(date = as.Date(date), benchmark_ret)], by = "date")
  if (nrow(x) < 60L) return(na("too_short"))
  x[, ym := format(date, "%Y-%m")]
  m <- x[, .(s = prod(1+ret_net)-1, k = prod(1+benchmark_ret)-1), by = ym][order(ym)]
  m[, ex := s - k]

  down <- .ds_seg(m[k < 0]); up <- .ds_seg(m[k >= 0])
  mid  <- .ds_seg(m[k < params$mid_threshold])
  deep <- .ds_seg(m[k < params$deep_threshold])

  if (!is.finite(down$n) || down$n < as.integer(params$min_down_months))
    return(c(na(sprintf("하락월 %d < %d — 판정 불가", down$n, params$min_down_months)),
             list(down = down, up = up, mid = mid, deep = deep)))

  ok <- is.finite(down$excess) && down$excess > params$min_excess &&
        is.finite(down$t) && down$t >= params$min_t &&
        is.finite(down$hit) && down$hit >= params$min_hit
  ## ★볼록성 플래그 폐기 (도훈 결정 2026-09-07) — 구판: convex <- deep$excess > down$excess
  ##   폐기 사유는 실측이다:
  ##   ①**무신호에서 더 잘 켜진다** — 실제 전략 57/179(32%) vs 무작위 25종 대조 25/48(52%).
  ##     저베타 판은 정의상 deep$excess > down$excess 를 만족하므로, 이 플래그는 방어 기전이 아니라
  ##     베타 부족을 재고 있었다. 구판 주석("선형 베타 효과가 아니라 실제 방어 기전")은 반증됐다.
  ##   ②**진짜 볼록은 0건** — Henriksson-Merton 회귀(s = a + b·k + γ·max(−k,0))로 재니 실제 179건 전부
  ##     up-β 0.42 < down-β 1.06(γ 중앙 −0.608 · γ_t 179/179 ≤ −1.5)로 **오목**이었다. 하락이 깊을수록
  ##     오히려 더 실린다 — "심도↑ 우위↑" 라는 문구가 사실과 반대였다.
  ##   ③**표본이 못 버틴다** — 심도월(k < −10%)이 10개월뿐이고 그중 2개가 2026-03·2026-07(역대 최심도
  ##     1위·3위)이다. 판정이 사실상 두 달에 얹혀 있었다.
  ##   ⇒ 새 산출에는 이 필드를 넣지 않는다. 과거 산출물의 convex 값은 기록으로 그대로 둔다(지우지 않는다).
  ##     심도 축을 다시 세우려면 표본을 늘리거나(일별·주별 붕괴 구간) HM γ 같은 한계반응 지표를 쓸 것.
  list(status = "ok", defensive = ok,
       down = down, mid = mid, deep = deep, up = up,
       n_months = nrow(m),
       reason = sprintf(paste0("하락월 %d개: 초과 %+.2f%%/월 (t %.2f · 적중 %.0f%%) · ",
                               "벤치%.0f%% 이하 %d개: 초과 %+.2f%%/월 · 상승월 초과 %+.2f%%/월"),
                        down$n, 100*down$excess, down$t, 100*down$hit,
                        100*params$deep_threshold, deep$n,
                        100*(deep$excess %||% NA_real_), 100*(up$excess %||% NA_real_)))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#==============================================================================
# 2계층 로테이션 풀 자격 (도훈 선택 2026-09-04 · 소비자 배선 2026-09-07)
#
# ★소비자가 생겼다 — `02_Infrastructure/regime/l2_pool_admission.R::l2_admit()` 가
#   이 함수를 경유하고, `build_module_performance.R` 이 그것으로 풀을 조립한다.
#   2026-09-04~09-07 사이에는 풀 조립부가 `.defensive_ok()` 라는 **자체 술어**를 따로
#   갖고 있었다 = 자격 술어가 둘로 갈린 상태. 그 사본은 제거됐다.
#   (규약: 자격 술어는 소비자의 함수여야 한다 — 소비자가 자기 사본을 들면 두 판정이 갈린다.)
#
# 규약: essence 등급 floor(B+) 를 **대체하지 않고 병렬 경로**로 연다.
#   방어형은 단독 알파가 약한 것이 사실이고(실측: 방어형 184건 중 B 이상 0건),
#   값어치는 조합 안에서 나온다. 그래서 등급이 아니라 풀 자격에서만 인정한다.
#   이는 2026-08-29 'F-overall specialist 풀 부적격' 결정을 **방어형에 한해** 되돌린다.
#
# ★부재와 거짓을 가른다 — `code` 로 구분한다.
#   `dscore_absent`(한 번도 산출된 적 없음) ≠ `not_defensive`(재서 아니었음)
#   ≠ `dscore_not_ok`(재려 했으나 표본 부족 등으로 판정 불가). 셋을 한 칸에 합치면
#   "배선이 안 됐다" 와 "배선은 됐는데 자격이 없다" 가 같은 숫자가 된다.
#==============================================================================
#' @param grade essence 등급 (구제 후 값)
#' @param dscore ds_score() 결과 (또는 카탈로그에 실린 그 사본). NULL = 미산출.
#' @param params ds_params()
#' @param floor 등급 floor — "B"(기본) / "A" / "OFF"(진단). 소비자의 env
#'   `QVEST_L2_GRADE_FLOOR` 를 **호출자가** 넘긴다(이 함수가 env 를 읽지 않는다 —
#'   읽으면 검사가 운영 env 를 빌리게 된다).
#' @param defensive_route 방어형 병렬 경로 on/off (kill switch `QVEST_L2_DEFENSIVE_ROUTE`).
#' @return list(eligible, route, code, reason)
ds_pool_eligible <- function(grade, dscore, params = ds_params(),
                             floor = "B", defensive_route = TRUE) {
  ## sprintf 는 인자 하나가 길이 0이면 문자열 전체를 없앤다 — 스칼라화를 강제한다.
  .one <- function(x, alt = "NA") {
    v <- suppressWarnings(as.character(x)[1])
    if (length(v) != 1L || is.na(v) || !nzchar(v)) alt else v
  }
  g  <- .one(grade %||% NA)
  fl <- toupper(.one(floor, "B"))
  floor_set <- if (identical(fl, "A")) "A" else c("A", "B")

  if (identical(fl, "OFF"))
    return(list(eligible = TRUE, route = "grade_floor", code = "floor_off",
                reason = sprintf("등급 floor OFF(진단 모드) — 등급 %s 무관 편입", g)))
  if (g %in% floor_set)
    return(list(eligible = TRUE, route = "grade_floor", code = "grade_floor",
                reason = sprintf("essence 등급 %s — 등급 floor(%s) 통과", g, fl)))
  if (!isTRUE(defensive_route))
    return(list(eligible = FALSE, route = NA_character_, code = "route_off",
                reason = sprintf("등급 %s · 방어형 경로 해제(QVEST_L2_DEFENSIVE_ROUTE=OFF)", g)))
  if (is.null(dscore) || length(dscore) == 0L)
    return(list(eligible = FALSE, route = NA_character_, code = "dscore_absent",
                reason = sprintf("등급 %s · 방어형 **미산출**(부재 — '아님'이 아니다)", g)))
  st <- .one(dscore$status, "미산출")
  if (!identical(st, "ok"))
    return(list(eligible = FALSE, route = NA_character_, code = "dscore_not_ok",
                reason = sprintf("등급 %s · 방어형 판정 불가(%s)", g, st)))
  if (isTRUE(dscore$defensive))
    return(list(eligible = TRUE, route = "defensive_specialist", code = "defensive_specialist",
                reason = sprintf("등급 %s 이나 방어형 자격 — %s", g, .one(dscore$reason, "사유 미기록"))))
  list(eligible = FALSE, route = NA_character_, code = "not_defensive",
       reason = sprintf("등급 %s · 방어형 아님 — %s", g, .one(dscore$reason, "사유 미기록")))
}
