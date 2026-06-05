# lcode_schema.R — L-code 입력 품질 게이트 (v8.0 Phase 1, 3-mode axiom 엔진)
#
# validate_lcode(): 신규 L-code 적립 시점에 필수필드 + sanity bound를 검증한다.
#   위반(hard error) 시 호출부가 write를 차단 → garbage(예: -2028.7%p bm 정렬버그,
#   한 줄 템플릿) corpus 진입을 막는다. = 자동 승격 파이프라인 안전핀 #1 (INV-1 전제).
#
# r7 정합 필드(00_Lawbook/Axiom_아키텍처/r7_axiom_design.md):
#   construction_type   — Independence 축(같은 construction = 상관 1건)
#   mechanism_hypothesis — Mechanism 축(경제적 설명, 없으면 unknown)
#   falsification_attempts — Falsification 축(적극 반증 기록)
#
# 참조: .claude/rules/measurement-graduation.md(metric_type) / data_table_shift_convention.md.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

LCODE_VALID_GRADES       <- c("A", "A_NOVEL", "A_DEF", "A_CONDITIONAL", "B", "C", "F")
LCODE_VALID_METRIC_TYPES <- c("proxy", "estimated", "backtested", "unavailable")
LCODE_VALID_MODES        <- c("alpha_search", "alpha_research", "qepm_legacy",
                              "judge_gate", "governor_admission",
                              "factor_rotation", "regime_research")

# construction_type 간이 추론 (Independence 축용 — name/idea 키워드 기반)
infer_construction_type <- function(name = "", idea = "") {
  s <- tolower(paste(name %||% "", idea %||% ""))
  if (grepl("모멘텀|momentum|12-1|6-1|추세|trend", s))           return("momentum")
  if (grepl("revers|52[- ]?주\\s*(저|low)|mean.?rev|단기반전", s)) return("reversal")
  if (grepl("ml|xgb|lightgbm|딥러닝|신경망|ensemble|앙상블|rl\\b", s)) return("ml_sizing")
  if (grepl("value|밸류|per|pbr|\\bep\\b|저평가|장부", s))        return("value")
  if (grepl("quality|퀄리티|\\bgp\\b|수익성|profitab", s))        return("quality")
  if (grepl("저변동|low.?vol|변동성", s))                        return("low_vol")
  if (grepl("배당|dividend", s))                                 return("dividend")
  if (grepl("규모|size|소형|중소형|small.?cap", s))               return("size")
  return("single_factor_long_only")
}

# 반환: list(valid=TRUE/FALSE, errors=chr, warnings=chr)
validate_lcode <- function(lcode) {
  errors <- character(0); warnings <- character(0)

  req <- c("l_code", "strategy_id", "grade", "lesson_text", "research_mode", "metric_type")
  for (f in req) {
    v <- lcode[[f]]
    if (is.null(v) || (is.character(v) && !nzchar(v)))
      errors <- c(errors, sprintf("필수 필드 누락/공란: %s", f))
  }

  g  <- lcode$grade %||% ""
  mt <- lcode$metric_type %||% ""
  rm <- lcode$research_mode %||% ""
  if (nzchar(g)  && !(g  %in% LCODE_VALID_GRADES))
    errors <- c(errors, sprintf("grade='%s' 비표준 (허용: %s)", g, paste(LCODE_VALID_GRADES, collapse = "/")))
  if (nzchar(mt) && !(mt %in% LCODE_VALID_METRIC_TYPES))
    errors <- c(errors, sprintf("metric_type='%s' 비표준 (허용: %s)", mt, paste(LCODE_VALID_METRIC_TYPES, collapse = "/")))
  if (nzchar(rm) && !(rm %in% LCODE_VALID_MODES))
    errors <- c(errors, sprintf("research_mode='%s' 비표준", rm))

  .num <- function(x) { y <- suppressWarnings(as.numeric(x %||% NA)); if (length(y)) y[1] else NA_real_ }
  cagr <- .num(lcode$cagr_pct %||% lcode$cagr)
  shp  <- .num(lcode$sharpe)
  mdd  <- .num(lcode$mdd_pct %||% lcode$mdd)
  exc  <- .num(lcode$excess_cagr)
  if (!is.na(cagr) && abs(cagr) > 500)
    errors <- c(errors, sprintf("cagr=%.0f%% |.|>500%% → annualize 폭발(bm_xts 정렬/결측 산식오류)", cagr))
  if (!is.na(shp) && abs(shp) > 10)
    errors <- c(errors, sprintf("sharpe=%.2f |.|>10 → 데이터 오염", shp))
  if (!is.na(mdd) && (mdd < 0 || mdd > 100))
    errors <- c(errors, sprintf("mdd=%.1f 범위밖[0,100]%%", mdd))
  if (!is.na(exc) && abs(exc) > 1000)
    errors <- c(errors, sprintf("excess_cagr=%+.0f%%p |.|>1000 → 벤치 정렬버그(-2028%%p 류)", exc))

  if (!nzchar(lcode$construction_type %||% ""))
    warnings <- c(warnings, "construction_type 누락 → r7 Independence 축 'unknown'(승격 약화)")
  if (g %in% c("A", "A_NOVEL", "A_DEF") && !is.na(cagr) && cagr < 16)
    warnings <- c(warnings, sprintf("grade=%s인데 cagr=%.1f%%<16%% — essence_score A 기준 불일치", g, cagr))

  list(valid = length(errors) == 0L, errors = errors, warnings = warnings)
}

# selftest (Rscript lcode_schema.R 직접 실행 시)
if (sys.nframe() == 0L && !interactive()) {
  ok <- validate_lcode(list(l_code = "L-AS-X", strategy_id = "STR_AS_X", grade = "F",
    lesson_text = "t", research_mode = "alpha_search", metric_type = "proxy",
    construction_type = "momentum", cagr_pct = -20.7, sharpe = -0.57, mdd_pct = 30, excess_cagr = -2.1))
  bad <- validate_lcode(list(l_code = "L-AS-Y", strategy_id = "STR_AS_Y", grade = "F",
    lesson_text = "t", research_mode = "alpha_search", metric_type = "proxy", excess_cagr = -2028.7))
  cat(sprintf("[lcode_schema selftest] ok.valid=%s bad.valid=%s (expect TRUE FALSE)\n", ok$valid, bad$valid))
  cat("  bad.errors:", paste(bad$errors, collapse = " | "), "\n")
  stopifnot(isTRUE(ok$valid), !isTRUE(bad$valid))
  cat("  PASS\n")
}
