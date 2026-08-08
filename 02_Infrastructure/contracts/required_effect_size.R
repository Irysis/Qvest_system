# =============================================================================
# required_effect_size.R — 사전등록용 검정력 보조: 표본 n 에서 문턱 t 에 필요한 효과크기
#
# 왜: null 결과를 '효과 부재'로 읽으려면 그 표본이 현실적 효과를 검출할 수 있었어야 한다.
#     검정력 계산 없는 사전등록은 무검정력 null 을 기각으로 오독하게 만든다(2026-08-08 FQ-138f 실증).
#
# 기준 변동성(실측, 2026-08-08): K200∪KQ150 유니버스에서 top-25 EW 바스켓 2개의 월 수익차
#   sd = 0.0394 (무작위 쌍 120 draw 중앙값 · 5~95% 0.0330~0.0448 · 창 2019-12~2026-07)
#   출처: stage_artifacts/fq141_precheck_20260808/np_fq138f_power.R
# =============================================================================

SPREAD_SD_MONTHLY_25EW <- 0.0394          # 두 top-25 EW 바스켓 수익차의 월 sd (실측)
SPREAD_SD_BAND         <- c(0.0330, 0.0448)
NW_INFLATION_DEFAULT   <- 1.25            # NW(lag3) SE 팽창 근사

#' required_effect — 문턱 t 도달에 필요한 월평균/연환산 효과크기
#' @param n 관측 개월수
#' @param t_threshold 판정 문턱 (기본 2.0)
#' @param sd_monthly 대상 계열의 월 sd (기본 = 25EW 스프레드 실측)
#' @param design "full" 전표본 · "split" 부분표본 분할(분산 2배 근사) · "interaction" 국면 상호작용
#' @param regime_frac design="interaction" 일 때 국면 ON 비율
required_effect <- function(n, t_threshold = 2.0, sd_monthly = SPREAD_SD_MONTHLY_25EW,
                            design = c("full","split","interaction"), regime_frac = 0.35,
                            nw_inflation = NW_INFLATION_DEFAULT) {
  design <- match.arg(design)
  eff_n <- switch(design,
    full        = n,
    split       = n / 2,                                  # 분산 2배 ≒ 유효 n 절반
    interaction = n * regime_frac * (1 - regime_frac))    # 더미 계수의 유효 표본
  se <- sd_monthly / sqrt(eff_n) * nw_inflation
  m  <- t_threshold * se
  list(n = n, design = design, effective_n = eff_n,
       required_monthly = m, required_annual = m * 12,
       sd_monthly = sd_monthly, t_threshold = t_threshold)
}

#' verdict_with_power — null 판정 시 '효과 부재' vs '검정력 부족' 구별
#' @param observed_t 실측 t · @param observed_monthly 실측 월평균 효과
verdict_with_power <- function(observed_t, observed_monthly, n, t_threshold = 2.0, ...) {
  req <- required_effect(n = n, t_threshold = t_threshold, ...)
  if (is.finite(observed_t) && observed_t >= t_threshold) {
    return(list(verdict = "PASS", note = "문턱 통과", required = req))
  }
  if (abs(observed_monthly) < req$required_monthly) {
    return(list(verdict = "INCONCLUSIVE_UNDERPOWERED",
      note = sprintf("실측 효과 %.4f/월(연 %.2f%%)가 문턱 도달 필요치 %.4f/월(연 %.2f%%) 미만 — 효과 부재가 아니라 검정력 부족",
                     observed_monthly, observed_monthly*12*100, req$required_monthly, req$required_annual*100),
      required = req))
  }
  list(verdict = "NEGATIVE_POWERED",
       note = "효과크기는 검출 가능 범위인데 t 미달 — 효과 부재로 읽을 수 있음", required = req)
}

if (sys.nframe() == 0L) {
  cat("required_effect 표 (문턱 t=2.0, sd=0.0394, NW k=1.25)\n")
  for (d in c("full","split","interaction")) for (n in c(24,28,40,60,80,163,269)) {
    r <- required_effect(n, design = d)
    cat(sprintf("  %-12s n=%3d  유효n=%6.1f  필요 연 %+.2f%%\n", d, n, r$effective_n, r$required_annual*100))
  }
}
