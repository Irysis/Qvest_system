#==============================================================================
# v55 Stage Gate Extensions
#
# 기존 stage_gate_engine.R (3종 role)을 6종 role 지원으로 확장.
# 원본은 그대로 두고, v55 wrapper 함수들을 overload.
#
# Usage:
#   source("02_Infrastructure/stage_gate_engine.R")
#   source("02_Infrastructure/pipeline/v55_stage_gate_extensions.R")
#==============================================================================

`%||%` <- function(a, b) if (is.null(a) || is.na(a) || length(a) == 0) b else a

# 6종 role enum
V55_ROLES <- c("core_alpha", "diversifier", "defense",
               "cash_allocation", "regime_adaptive", "ml_predictive")

# 3종 trail enum
V55_TRAILS <- c("standard", "ml_empirical_first", "kr_statistical")

# 4축 gap axes
V55_GAP_AXES <- c("SR", "MDD_regime", "KR_structural", "cash_efficiency")

#==============================================================================
# sg_determine_role_v55 — 6종 role 판정 wrapper
#==============================================================================
sg_determine_role_v55 <- function(s0_record = NULL, s2, s3, s4) {
  # Priority 1: s0_record hint (신규 3종 role은 hint 신뢰)
  hint_role <- s0_record$expected_role %||% NULL
  if (!is.null(hint_role) && hint_role %in% c("cash_allocation", "regime_adaptive", "ml_predictive")) {
    return(hint_role)
  }

  # Priority 2: 기존 3종 판정 로직 (stage_gate_engine의 sg_determine_role 호출)
  if (exists("sg_determine_role", mode = "function")) {
    return(sg_determine_role(s2, s3, s4))
  }

  # Fallback
  "diversifier"
}

#==============================================================================
# sg_role_admission_v55 — 6종 role admission check
#==============================================================================
sg_role_admission_v55 <- function(provisional_role, s4, s3 = NULL, s0_record = NULL) {

  if (!provisional_role %in% V55_ROLES) {
    return(list(ok = FALSE, reason = sprintf("invalid role: %s", provisional_role)))
  }

  # 신규 role 3종은 별도 admission
  if (provisional_role == "cash_allocation") {
    cc <- s0_record$cash_component %||% list()
    max_cw <- cc$max_cash_weight %||% 0
    if (max_cw <= 0 || max_cw > 0.5) {
      return(list(ok = FALSE, reason = "cash_allocation role requires cash_component.max_cash_weight in (0, 0.5]"))
    }
    return(list(ok = TRUE, reason = "cash_allocation admitted",
                sleeve = "Cash", opportunity_cost_required = TRUE))
  }

  if (provisional_role == "regime_adaptive") {
    # switching_alpha, transition_cost 필드 필요
    return(list(ok = TRUE, reason = "regime_adaptive admitted",
                sleeve = "RegimeAdaptive",
                s1_gate = "switching_alpha_check + transition_cost_check"))
  }

  if (provisional_role == "ml_predictive") {
    trail <- s0_record$trail %||% "standard"
    if (trail != "ml_empirical_first") {
      return(list(ok = FALSE,
                  reason = "ml_predictive role requires trail=ml_empirical_first"))
    }
    return(list(ok = TRUE, reason = "ml_predictive admitted",
                sleeve = "ML",
                s1_gate = "SR_OOS/SR_IS>0.70 + feature_concentration<0.4 + holdout_12M+"))
  }

  # 기존 3종 admission은 기존 sg_role_admission (있으면)
  if (exists("sg_role_admission", mode = "function")) {
    return(sg_role_admission(provisional_role, s4, s3))
  }

  list(ok = TRUE, reason = sprintf("%s admitted (v55 default)", provisional_role))
}

#==============================================================================
# validate_v55_artifact_fields — Artifact 스키마 v55 체크
#==============================================================================
validate_v55_s0_record <- function(s0_record) {
  errors <- c()

  # expected_role
  role <- s0_record$expected_role %||% ""
  if (nchar(role) == 0) {
    errors <- c(errors, "expected_role missing")
  } else if (!role %in% V55_ROLES) {
    errors <- c(errors, sprintf("expected_role='%s' invalid (must be one of %s)",
                                role, paste(V55_ROLES, collapse = ", ")))
  }

  # trail
  trail <- s0_record$trail %||% ""
  if (nchar(trail) > 0 && !trail %in% V55_TRAILS) {
    errors <- c(errors, sprintf("trail='%s' invalid", trail))
  }

  # gap_targeting_axes
  axes <- s0_record$gap_targeting_axes %||% list()
  if (length(axes) == 0) {
    errors <- c(errors, "gap_targeting_axes missing (array of 1+)")
  } else {
    invalid_axes <- setdiff(unlist(axes), V55_GAP_AXES)
    if (length(invalid_axes) > 0) {
      errors <- c(errors, sprintf("gap_targeting_axes invalid: %s",
                                  paste(invalid_axes, collapse=", ")))
    }
  }

  # cash_component for cash_allocation
  if (role == "cash_allocation") {
    cc <- s0_record$cash_component %||% list()
    if (length(cc) == 0 || is.null(cc$max_cash_weight)) {
      errors <- c(errors, "role=cash_allocation requires cash_component.max_cash_weight")
    }
  }

  list(ok = length(errors) == 0, errors = errors)
}

#==============================================================================
# audit_cash_allocation — Cash sleeve role honesty audit
#==============================================================================
audit_cash_allocation <- function(cash_weights, rates_3m_annualized,
                                   strategy_returns = NULL,
                                   bench_returns = NULL) {
  # cash_weights: monthly cash % (0-1)
  # rates_3m_annualized: 3M rate annualized (0.0325 for 3.25%)

  n <- length(cash_weights)
  if (n == 0) return(list(ok = FALSE, reason = "no cash weights"))

  # Opportunity cost: cash%  × rate_spread vs risky asset return
  if (!is.null(bench_returns)) {
    bench_ann <- mean(bench_returns, na.rm = TRUE) * 12  # monthly → annual
    rate_spread <- bench_ann - rates_3m_annualized
    opp_cost_bps_ann <- mean(cash_weights) * rate_spread * 10000
  } else {
    # Fallback: just cash × rate (passive drag)
    opp_cost_bps_ann <- mean(cash_weights) * rates_3m_annualized * 10000
  }

  # Tail risk of cash sleeve alone = 0
  tail_risk <- 0

  # PASS: opportunity cost < 20bps threshold
  passed <- opp_cost_bps_ann < 20

  list(
    role = "cash_allocation",
    opportunity_cost_bps_annualized = round(opp_cost_bps_ann, 2),
    tail_risk = tail_risk,
    avg_cash_pct = round(mean(cash_weights) * 100, 2),
    max_cash_pct = round(max(cash_weights) * 100, 2),
    passed = passed,
    threshold = "opp_cost < 20bps",
    reason = if (passed) "Cash sleeve efficient" else sprintf("opp_cost=%.2fbps exceeds 20bps", opp_cost_bps_ann)
  )
}

#==============================================================================
# audit_defense_v2 — AX-001 v2 Defense 조건부 평가
#==============================================================================
audit_defense_v2 <- function(strategy_returns_ts, core_returns_ts = NULL,
                              regime_series = NULL,
                              ic_by_regime = NULL,
                              crisis_periods = list(
                                "2008_gfc"   = c(as.Date("2007-10-01"), as.Date("2009-03-31")),
                                "2011_eu"    = c(as.Date("2011-07-01"), as.Date("2011-12-31")),
                                "2020_covid" = c(as.Date("2020-02-01"), as.Date("2020-04-30")),
                                "2022_rate"  = c(as.Date("2022-01-01"), as.Date("2022-10-31"))
                              )) {
  result <- list(role = "defense", version = "v2", passed = FALSE)

  # Gate 2b: crisis_alpha (core 대비)
  if (!is.null(core_returns_ts) && "Date" %in% names(strategy_returns_ts)) {
    crisis_alphas <- sapply(names(crisis_periods), function(name) {
      period <- crisis_periods[[name]]
      mask_s <- strategy_returns_ts$Date >= period[1] & strategy_returns_ts$Date <= period[2]
      mask_c <- core_returns_ts$Date >= period[1] & core_returns_ts$Date <= period[2]
      if (sum(mask_s) == 0 || sum(mask_c) == 0) return(NA)
      s_ret <- mean(strategy_returns_ts$ret[mask_s], na.rm = TRUE) * 252
      c_ret <- mean(core_returns_ts$ret[mask_c], na.rm = TRUE) * 252
      s_ret - c_ret
    })
    result$crisis_alpha_test <- list(
      alphas = as.list(crisis_alphas),
      all_positive = all(crisis_alphas > 0, na.rm = TRUE),
      passed = all(crisis_alphas > 0, na.rm = TRUE)
    )
  }

  # Gate 2c: bad/normal IC ratio
  if (!is.null(ic_by_regime)) {
    ic_bad_crisis <- mean(c(ic_by_regime$Bad %||% 0, ic_by_regime$Crisis %||% 0), na.rm = TRUE)
    ic_good_normal <- mean(c(ic_by_regime$Good %||% 0, ic_by_regime$Normal %||% 0), na.rm = TRUE)
    ratio <- if (abs(ic_good_normal) > 0.001) ic_bad_crisis / ic_good_normal else NA
    result$bad_normal_ic_ratio <- list(
      ic_bad_crisis = round(ic_bad_crisis, 4),
      ic_good_normal = round(ic_good_normal, 4),
      ratio = round(ratio, 3),
      passed = !is.na(ratio) && ratio > 0.6
    )
  }

  # Overall pass: both crisis_alpha AND ic_ratio 통과
  passed_gates <- c()
  if (!is.null(result$crisis_alpha_test)) {
    passed_gates <- c(passed_gates, result$crisis_alpha_test$passed)
  }
  if (!is.null(result$bad_normal_ic_ratio)) {
    passed_gates <- c(passed_gates, result$bad_normal_ic_ratio$passed)
  }
  result$passed <- length(passed_gates) > 0 && all(passed_gates, na.rm = TRUE)

  result
}

cat("[v55_stage_gate_extensions] Loaded. Functions: sg_determine_role_v55, sg_role_admission_v55, validate_v55_s0_record, audit_cash_allocation, audit_defense_v2\n")
