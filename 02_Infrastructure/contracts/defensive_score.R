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
  # 볼록성 — 심도가 깊어질수록 우위가 커지는가 (선형 베타와 구분)
  convex <- is.finite(deep$excess) && is.finite(down$excess) && deep$excess > down$excess

  list(status = "ok", defensive = ok, convex = convex,
       down = down, mid = mid, deep = deep, up = up,
       n_months = nrow(m),
       reason = sprintf(paste0("하락월 %d개: 초과 %+.2f%%/월 (t %.2f · 적중 %.0f%%) · ",
                               "벤치%.0f%% 이하 %d개: 초과 %+.2f%%/월 · 상승월 초과 %+.2f%%/월%s"),
                        down$n, 100*down$excess, down$t, 100*down$hit,
                        100*params$deep_threshold, deep$n,
                        100*(deep$excess %||% NA_real_), 100*(up$excess %||% NA_real_),
                        if (isTRUE(convex)) " · 볼록(심도↑ 우위↑)" else ""))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#==============================================================================
# 2계층 로테이션 풀 자격 (도훈 선택 2026-09-04)
#
# ★소비자가 아직 없다. 2계층 풀 게이트는 코드로 존재하지 않고(SKILL 서술만 · L2 원장 0건),
#   이 함수는 그것이 만들어질 때 호출되라고 미리 둔 계약이다.
#   이 저장소의 상습병이 "생산자만 있고 소비자가 없는 계기" 이므로 그 사실을 여기 적어 둔다 —
#   2계층을 처음 돌리는 세션은 풀 조립부에서 **반드시 이 함수를 경유**할 것.
#
# 규약: essence 등급 floor(B+) 를 **대체하지 않고 병렬 경로**로 연다.
#   방어형은 단독 알파가 약한 것이 사실이고(실측: 방어형 184건 중 B 이상 0건),
#   값어치는 조합 안에서 나온다. 그래서 등급이 아니라 풀 자격에서만 인정한다.
#   이는 2026-08-29 'F-overall specialist 풀 부적격' 결정을 **방어형에 한해** 되돌린다.
#==============================================================================
#' @param grade essence 등급 (구제 후 값)
#' @param dscore ds_score() 결과
#' @return list(eligible, route, reason)
ds_pool_eligible <- function(grade, dscore, params = ds_params()) {
  g <- as.character(grade %||% NA)
  if (!is.na(g) && g %in% c("A", "B"))
    return(list(eligible = TRUE, route = "grade_floor",
                reason = sprintf("essence 등급 %s — 기존 B+ floor 통과", g)))
  if (is.null(dscore) || !identical(dscore$status, "ok"))
    return(list(eligible = FALSE, route = NA_character_,
                reason = sprintf("등급 %s 이고 방어형 판정 불가(%s)", g,
                                 as.character(dscore$status %||% "미산출"))))
  if (isTRUE(dscore$defensive))
    return(list(eligible = TRUE, route = "defensive_specialist",
                reason = sprintf("등급 %s 이나 방어형 자격 — %s", g, dscore$reason)))
  list(eligible = FALSE, route = NA_character_,
       reason = sprintf("등급 %s · 방어형 아님 — %s", g, dscore$reason))
}
