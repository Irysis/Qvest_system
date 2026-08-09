# =============================================================================
# moment_fragility.R — 적률 기반 통계량(왜도·첨도)의 이상치 취약성 자동 점검
#
# 왜 필요한가 (2026-08-09 FQ-182 실사고):
#   Q-Lead 가 "낙폭 뒤 forward 왜도가 부호를 뒤집는다(-0.31 -> +0.27)" 를 보고했고,
#   근거로 "왜도는 **스케일 불변**이라 변동성 확대의 산술적 산물이 아니다" 를 들었다.
#   스케일 불변인 것은 맞으나 **이상치 지배는 별개 축**이고 그 점검이 사전등록에 없었다.
#   적대검증 실측: 극단값 1개 제거 시 ON 왜도 +0.272 -> +0.014, 2개 제거 시 **-0.044(부호 반전)**.
#   분위 기반 강건 측도에서는 효과 소멸 — Bowley p=0.437 · octile p=0.184 (3차 적률조차 p=0.096).
#
#   ★계통: 스케일 불변성을 강건성으로 오독했다. 3차 적률은 편차의 **세제곱**이라
#     이상치 지배가 정의상 구조적이다. 사람이 매번 기억할 게 아니라 **함수가 같이 내야 한다**.
#
# 규약: 적률 기반 통계량(skew/kurt)을 판정에 쓰는 라운드는 이 파일의 assert 를 경유하고
#   ①강건 대응물 ②drop-k 민감도 를 **함께 보고**한다. 단독 보고는 규약 위반.
#
# 자매 규칙: required_effect_size.R (검정력) · canonical_screen_bt.R (실측 경로)
# =============================================================================

#' 분위 기반 강건 왜도 2종 — 이상치에 지배되지 않는다
#' @param x numeric
#' @return list(bowley=, octile=)  둘 다 [-1, 1] 유계
robust_skew <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 20L) return(list(bowley = NA_real_, octile = NA_real_))
  q <- stats::quantile(x, c(0.125, 0.25, 0.5, 0.75, 0.875), names = FALSE, type = 7)
  d_bow <- q[4] - q[2]
  d_oct <- q[5] - q[1]
  list(
    # Bowley (quartile) skewness: (Q3 + Q1 - 2*median) / (Q3 - Q1)
    bowley = if (is.finite(d_bow) && d_bow > 0) (q[4] + q[2] - 2 * q[3]) / d_bow else NA_real_,
    # Octile skewness (Hinkley): (P87.5 + P12.5 - 2*median) / (P87.5 - P12.5)
    octile = if (is.finite(d_oct) && d_oct > 0) (q[5] + q[1] - 2 * q[3]) / d_oct else NA_real_)
}

.m3_skew <- function(x) {
  x <- x[is.finite(x)]; n <- length(x); s <- stats::sd(x)
  if (n < 3L || !is.finite(s) || s == 0) return(NA_real_)
  sum((x - mean(x))^3) / n / s^3
}
.m4_kurt <- function(x) {
  x <- x[is.finite(x)]; n <- length(x); s <- stats::sd(x)
  if (n < 4L || !is.finite(s) || s == 0) return(NA_real_)
  sum((x - mean(x))^4) / n / s^4 - 3
}

#' drop-k 민감도 — 절대편차 상위 k 개를 빼면 통계량이 얼마나 움직이나
#' @param x numeric · @param stat "skew" 또는 "kurt" · @param k_max 최대 제거 개수
#' @return data.frame(k, value, sign_flipped, frac_of_base)
moment_dropk <- function(x, stat = c("skew", "kurt"), k_max = 5L) {
  stat <- match.arg(stat)
  f <- if (stat == "skew") .m3_skew else .m4_kurt
  x <- x[is.finite(x)]
  base <- f(x)
  ord <- order(abs(x - mean(x)), decreasing = TRUE)
  out <- data.frame(k = 0:k_max, value = NA_real_)
  out$value[1] <- base
  for (k in seq_len(k_max)) {
    if (length(x) - k < 20L) break
    out$value[k + 1L] <- f(x[-ord[seq_len(k)]])
  }
  out$sign_flipped <- is.finite(out$value) & is.finite(base) & (sign(out$value) != sign(base))
  out$frac_of_base <- if (is.finite(base) && base != 0) out$value / base else NA_real_
  out
}

#' ★assert — 적률 통계량의 두 집단 차이가 강건한가
#'
#' 판정 3축을 **전부** 반환한다(호출자가 하나만 골라 쓰는 것을 막기 위해 단일 스칼라를 주지 않는다).
#'   A. moment_diff  : 적률 기반 차이 (관측)
#'   B. robust_diff  : Bowley·octile 기반 차이 — 부호가 다르거나 크기가 1/3 미만이면 취약
#'   C. dropk        : 상위 |편차| k개 제거 시 부호 반전 여부
#'
#' @return list(...) + verdict 문자열
#'   "ROBUST"            = 강건 측도 부호 일치 ∧ drop-k 부호 유지
#'   "OUTLIER_DRIVEN"    = drop-k 에서 부호 반전 (k <= 2)
#'   "ROBUST_MEASURE_DISAGREES" = 강건 측도가 부호 불일치 또는 크기 급감
#'   "INSUFFICIENT"      = 표본 부족
assert_moment_robust <- function(x_on, x_off, stat = c("skew", "kurt"), k_max = 5L) {
  stat <- match.arg(stat)
  f <- if (stat == "skew") .m3_skew else .m4_kurt
  x_on <- x_on[is.finite(x_on)]; x_off <- x_off[is.finite(x_off)]
  if (length(x_on) < 50L || length(x_off) < 50L)
    return(list(verdict = "INSUFFICIENT", n_on = length(x_on), n_off = length(x_off)))

  mom <- f(x_on) - f(x_off)
  rs_on <- robust_skew(x_on); rs_off <- robust_skew(x_off)
  rob_bow <- rs_on$bowley - rs_off$bowley
  rob_oct <- rs_on$octile - rs_off$octile
  dk <- moment_dropk(x_on, stat, k_max)
  flip_k <- if (any(dk$sign_flipped, na.rm = TRUE)) min(dk$k[which(dk$sign_flipped)]) else NA_integer_

  ## 강건 측도는 유계([-1,1])라 적률과 스케일이 다르다 — **직접 크기 비교 금지**.
  sign_ok <- is.finite(rob_bow) && is.finite(rob_oct) && is.finite(mom) &&
             sign(rob_bow) == sign(mom) && sign(rob_oct) == sign(mom)

  ## ★2026-08-09 수리: 부호만 보면 **FQ-182 실사고 자체를 놓친다**.
  ##   실사고 수치 = Bowley diff 0.032 (거의 0이나 **부호는 일치**) vs 적률 diff 0.581.
  ##   초판 로직은 sign_ok=TRUE 로 ROBUST 를 냈다 — 원래 오류와 **같은 사각**(수리가 새 오답을 낳음).
  ##   ⇒ 스케일 비교 대신 **drop-k 크기 붕괴**를 본다: 소수 관측 제거로 |통계량| 이 반감하면 이상치 지배.
  ##   (붕괴는 스케일 무관 비율이라 적률/강건 측도 간 스케일 문제를 우회한다.)
  collapse_k <- NA_integer_
  if (is.finite(mom) && is.finite(dk$value[1]) && abs(dk$value[1]) > 1e-12) {
    fr <- abs(dk$value) / abs(dk$value[1])
    hit <- which(is.finite(fr) & fr < 0.5 & dk$k > 0 & dk$k <= 2L)
    if (length(hit)) collapse_k <- min(dk$k[hit])
  }
  outlier_driven <- (is.finite(flip_k) && flip_k <= 2L) || is.finite(collapse_k)

  verdict <- if (outlier_driven) "OUTLIER_DRIVEN"
             else if (!sign_ok) "ROBUST_MEASURE_DISAGREES"
             else "ROBUST"

  list(verdict = verdict, stat = stat,
       moment_on = f(x_on), moment_off = f(x_off), moment_diff = mom,
       bowley_on = rs_on$bowley, bowley_off = rs_off$bowley, bowley_diff = rob_bow,
       octile_on = rs_on$octile, octile_off = rs_off$octile, octile_diff = rob_oct,
       dropk = dk, first_sign_flip_k = flip_k, first_collapse_k = collapse_k,
       n_on = length(x_on), n_off = length(x_off),
       note = paste0(
         "적률 기반 왜도/첨도는 **스케일 불변이지만 이상치에 지배된다** — 두 성질은 별개다. ",
         "판정에 쓰려면 강건 대응물(Bowley/octile)과 drop-k 를 함께 보고할 것. ",
         "(2026-08-09 FQ-182: drop-2 에서 부호 반전, 강건 측도 p 0.44/0.18 로 효과 소멸)"))
}

cat("[moment_fragility.R] Loaded — robust_skew() / moment_dropk() / assert_moment_robust()\n")
cat("  규약: 적률 기반 통계량(skew/kurt)을 판정에 쓰는 라운드는 강건 대응물 + drop-k 병기 의무\n")
