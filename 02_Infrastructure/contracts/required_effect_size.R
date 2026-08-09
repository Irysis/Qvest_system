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
#'
#' ★2026-08-08 구조 보강 (WT-001 적대검증 렌즈1 적발): 이 함수는 호출자가 넘긴 `sd_monthly`
#' 로 바를 만드는데, **그 sd 가 arm 자신의 계열 sd 면 바가 t 검정의 재진술로 퇴화**한다.
#'   required = t_threshold x sd/sqrt(n) x nw_inflation 이므로 sd 가 arm 자신이면
#'   required = t_threshold x nw_inflation x se_arm  ⇒  NEGATIVE_POWERED 는
#'   |t| >= 2.5 이면서 동시에 |t| < 2.0 을 요구 = **논리적으로 도달 불가**.
#'   그 결과 |t|<2 인 모든 셀이 기계적으로 INCONCLUSIVE_UNDERPOWERED 가 되어
#'   라벨이 '|t| < 문턱' 이상의 정보를 담지 못한다(WT-D20260808_001 P1/P2 12셀 전건).
#' ⇒ 관측 t 와 관측 효과에서 se_arm 을 역산해 **바가 무엇을 재는지 항상 보고**한다.
#'   `implied_t_threshold` = required_monthly / se_arm = "이 바는 arm 자신의 se 기준 t 몇 짜리인가".
#'     - 문턱 근방([t, t x 1.6]) => 바 = t 검정 재진술. NEGATIVE_POWERED 도달 불가 → 별도 판정 발행.
#'     - 문턱보다 훨씬 큼      => 외부(배포) 노이즈 기준의 진짜 바. 기존 의미 유지.
#'     - 문턱보다 훨씬 작음    => 바가 느슨. NEGATIVE_POWERED 가 정상 도달 가능.
#'
#' @param observed_t 실측 t · @param observed_monthly 실측 월평균 효과
verdict_with_power <- function(observed_t, observed_monthly, n, t_threshold = 2.0, ...) {
  req <- required_effect(n = n, t_threshold = t_threshold, ...)

  ## se_arm 역산 — 관측 t 가 유효할 때만. 0/비유한이면 진단 불가로 표기(추측 금지).
  se_arm <- if (is.finite(observed_t) && abs(observed_t) > 1e-12)
              abs(observed_monthly) / abs(observed_t) else NA_real_
  implied_t <- if (is.finite(se_arm) && se_arm > 0) req$required_monthly / se_arm else NA_real_
  ## NEGATIVE_POWERED 도달 가능 ⟺ 바가 t 검정보다 느슨해야 함
  reachable <- if (is.finite(implied_t)) implied_t < t_threshold else NA
  ## 바가 t 검정의 재진술인 구간 (nw_inflation 만큼만 더 엄격한 경우)
  restates_t <- if (is.finite(implied_t)) (implied_t >= t_threshold && implied_t <= t_threshold * 1.6) else FALSE

  diag <- list(se_arm = se_arm, implied_t_threshold = implied_t,
               negative_powered_reachable = reachable, bar_restates_t = restates_t)

  if (is.finite(observed_t) && observed_t >= t_threshold) {
    return(c(list(verdict = "PASS", note = "문턱 통과", required = req), diag))
  }

  if (isTRUE(restates_t)) {
    return(c(list(verdict = "INCONCLUSIVE_BAR_RESTATES_T",
      note = sprintf(paste0("바가 arm 자신의 se 기준 t=%.2f 에 해당 — 문턱 %.2f 의 재진술이라 ",
                            "NEGATIVE_POWERED 가 도달 불가하다. 이 라벨은 '|t| < %.2f' 이상의 정보를 담지 않는다. ",
                            "검정력을 실제로 논하려면 sd_monthly 에 **외부 기준 계열**(배포 노이즈 등)을 넣어라."),
                     implied_t, t_threshold, t_threshold),
      required = req), diag))
  }

  if (abs(observed_monthly) < req$required_monthly) {
    return(c(list(verdict = "INCONCLUSIVE_UNDERPOWERED",
      note = sprintf("실측 효과 %.4f/월(연 %.2f%%)가 문턱 도달 필요치 %.4f/월(연 %.2f%%) 미만 — 효과 부재가 아니라 검정력 부족",
                     observed_monthly, observed_monthly*12*100, req$required_monthly, req$required_annual*100),
      required = req), diag))
  }

  c(list(verdict = "NEGATIVE_POWERED",
         note = "효과크기는 검출 가능 범위인데 t 미달 — 효과 부재로 읽을 수 있음", required = req), diag)
}

if (sys.nframe() == 0L) {
  cat("required_effect 표 (문턱 t=2.0, sd=0.0394, NW k=1.25)\n")
  for (d in c("full","split","interaction")) for (n in c(24,28,40,60,80,163,269)) {
    r <- required_effect(n, design = d)
    cat(sprintf("  %-12s n=%3d  유효n=%6.1f  필요 연 %+.2f%%\n", d, n, r$effective_n, r$required_annual*100))
  }
}

# --- 적용 한계 (2026-08-08 FQ-138h1 실사용에서 드러남) ------------------------
# verdict_with_power 는 **효과크기 대비 필요치**만 본다. 다음을 구별하지 못하므로
# 반환값을 그대로 판정으로 쓰지 말고 아래 3축을 사람이 확인할 것:
#   (a) 독립 HARD 실패 — MDD/Calmar/oos_retention 위반은 검정력과 무관하게 negative 를 유지시킨다
#       (실사례 FQ-152: MDD 59.6% >> 25% 제약. 검정력 판정과 무관하게 기각 유지)
#   (b) 다른 종류의 검정 — 라벨 품질(분류 recall/fisher) 등은 알파 크기 검정이 아니다
#       (실사례 FQ-118: 실판정은 recall 0.351<=base·fisher p=0.795. 알파 sd 적용은 범주 오류)
#   (c) 추정치가 아닌 상한/오라클 값 — look-ahead 상한은 표본분포가 다르다 (동 FQ-118 +2.10%/yr)
# 또한 SPREAD_SD_MONTHLY_25EW 는 **top-25 EW 바스켓 쌍** 실측이다. 게이트 on/off·오버레이·
# FF3 잔차 등 다른 비교축은 변동성이 다르므로 1차 스크린으로만 쓰고, 확정하려면 해당 계열의 실제 sd 를 쓸 것.
# 실사용 결과(4건): 진짜 무검정력 주장 1(FQ-064 하위 주장) · 이미 옳게 표기 1(FQ-121) ·
#                   독립 HARD 로 유지 1(FQ-152) · 도구 오적용 1(FQ-118).

# =============================================================================
# audit_input — 원장 감사 입력을 **구조로** 강제한다 (2026-08-08 오발 재발 방지)
#
# 왜 주석이 아니라 함수인가: 같은 날 필자가 두 번 틀렸다.
#   (1) 'n=20' 을 표본크기로 읽었으나 실제로는 random25_null_n_seeds(시드 개수)였다.
#       진짜 표본은 n_months=118. → n 의 **정체**를 확인하지 않고 값만 썼다.
#   (2) 요약 필드(next_action)의 센 표현을 근거로 원장을 비판했으나, 판정 필드
#       (attribution_verdict)는 신중했고 판정을 지탱하는 증거는 독립적으로 유의했다.
#   ⇒ 값과 출처를 함께 요구하면 둘 다 막힌다.
# =============================================================================

#' audit_input — 감사 입력 생성. n 의 정체와 출처 필드를 **필수 인자**로 받는다.
#' @param n_value        표본 크기 값
#' @param n_kind         "months" | "obs" | "names" | "seeds" | "trials" — months/obs 만 검정력에 유효
#' @param n_source_field 그 값을 읽은 원장 필드명 (예 "measure_result_20260726.n_months")
#' @param verdict_field  판정 정본 필드명 (요약 필드 금지: next_action / title / hypothesis)
#' @param effect_annual  보고된 연효과
audit_input <- function(n_value, n_kind, n_source_field, verdict_field, effect_annual) {
  if (missing(n_kind) || !n_kind %in% c("months","obs","names","seeds","trials"))
    stop("audit_input: n_kind 필수 — months/obs/names/seeds/trials 중 하나")
  if (!n_kind %in% c("months","obs"))
    stop(sprintf("audit_input: n_kind='%s' 는 검정력 계산의 표본이 아니다(시드/종목/시행 수). 진짜 관측수를 찾을 것.", n_kind))
  if (missing(n_source_field) || !nzchar(n_source_field))
    stop("audit_input: n 을 읽은 원장 필드명을 명시할 것 — 값만으로는 정체를 확인할 수 없다")
  if (missing(verdict_field) || !nzchar(verdict_field))
    stop("audit_input: 판정 정본 필드명을 명시할 것")
  if (grepl("next_action|title|hypothesis|summary", verdict_field, ignore.case = TRUE))
    stop(sprintf("audit_input: '%s' 는 요약 필드다. 판정 정본(verdict/attribution_verdict/measure_result)을 쓸 것 — 요약문만 보고 비판하면 없는 결함을 만든다.", verdict_field))
  list(n = n_value, n_kind = n_kind, n_source_field = n_source_field,
       verdict_field = verdict_field, effect_annual = effect_annual)
}

#' audit_verdict — audit_input 을 받아 검정력 판정. 원시 값 직접 투입 경로를 막는다.
audit_verdict <- function(ai, observed_t = NA_real_, t_threshold = 2.0, ...) {
  stopifnot(is.list(ai), !is.null(ai$n_kind))
  v <- verdict_with_power(observed_t = if (is.na(observed_t)) 0 else observed_t,
                          observed_monthly = ai$effect_annual/12, n = ai$n,
                          t_threshold = t_threshold, ...)
  v$read_from <- sprintf("n:%s(%s) · 판정:%s", ai$n_source_field, ai$n_kind, ai$verdict_field)
  v$caveat <- "1차 스크린. 독립 HARD 실패·다른 종류의 검정·상한값은 구별하지 못한다(위 적용 한계 참조)."
  v
}
