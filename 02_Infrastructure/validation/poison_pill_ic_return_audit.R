#==============================================================================
# V7 Research Engine — Poison Pill IC-Return Audit (Gate 12)
# poison_pill_ic_return_audit.R
#
# Detects L-163 family pattern: composite Defense factors containing
# "poison pill" sub-factors whose stress_icir is sharply negative such that
# weight × stress_icir < -0.05 → admission HARD_FAIL.
#
# Quantified rule (L-163 ACTIVE, Scout Option α 채택 2026-04-18):
#   For each factor f in composite:
#     stress_icir(f) × weight(f) >= -0.05         (HARD_FAIL threshold)
#   Else:
#     auto action: weight cap 10% OR factor exclusion → variant_comparison
#
# Evidence case (L-144 → L-163):
#   Q24_Altman_Z: stress_icir = -0.695, weight = 0.25
#   product = -0.174  → 한도 -0.05 대비 3.48x 초과 → HARD_FAIL
#
# Sub-gates (3):
#   12a per_factor_pill_check     stress_icir × weight ≥ -0.05 (L-163 main rule)
#   12b composite_pill_count      hard_fail factor 수 ≤ 0
#   12c regime_conditional_amplification  bear/crisis stress_icir 증폭 비교
#
# Verdict aggregation:
#   PASS         — 모든 sub-gates PASS
#   CONDITIONAL  — 12a PASS이나 12c regime amplification flag (S6 monitor)
#   HARD_FAIL    — 12a 또는 12b HARD_FAIL → variant_comparison 강제
#
# Reference:
#   methodology_memory.md L-144 (Q24 single-factor evidence)
#   methodology_memory.md L-163 (composite weight quantified rule)
#   qepm/memory/registry/families.json poison_pill_factors section
#   AX-005 (Defense standalone failure meta)
#   Scout H_1689 v3 handoff kit (initiator)
#
# Usage:
#   source("02_Infrastructure/validation/poison_pill_ic_return_audit.R")
#   r <- audit_poison_pill_ic_return(
#          strategy_id     = "H_1689_v3_variant_1",
#          factor_weights  = list(Q01_GPA = 0.33, Q04_Piotroski_F = 0.33, Q25_Distress = 0.34),
#          stress_icir_map = list(Q01_GPA = 0.12, Q04_Piotroski_F = 0.18, Q25_Distress = 0.21),
#          regime_icir_map = list(  # optional: per-regime stress_icir for sub-gate 12c
#            Q01_GPA  = list(bull = 0.10, bear = 0.18, crisis = 0.22),
#            Q04_Piotroski_F = list(bull = 0.15, bear = 0.20, crisis = 0.25),
#            Q25_Distress = list(bull = 0.18, bear = 0.22, crisis = 0.28)
#          ),
#          output_dir = "04_Research/strategies/STR_1689/output"
#        )
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ─── Thresholds (L-163 ACTIVE, Scout Option α + Judge 승격) ──────────────────
.PP_PRODUCT_HARD_FAIL  <- -0.05   # stress_icir × weight 한도 (L-163)
.PP_PRODUCT_WARN       <- -0.03   # 경고 영역 (CONDITIONAL)
.PP_REGIME_AMPL_FACTOR <- 1.5     # crisis stress_icir이 baseline 1.5x 악화 시 amplification flag
.PP_WEIGHT_CAP_AFTER_VIOLATION <- 0.10  # auto action: 10% cap

# Known poison-pill factors (families.json mirror, fast lookup)
.PP_KNOWN_POISON_PILL <- list(
  Q24_Altman_Z = list(stress_icir = -0.695, l_code = "L-144",
                      reason = "KR crisis 역방향 IC 증폭")
)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ─── Sub-gate 12a: per-factor poison pill check ──────────────────────────────
.pp_sub_a_per_factor <- function(factor_weights, stress_icir_map) {
  if (length(factor_weights) == 0L) {
    return(list(verdict = "INSUFFICIENT_DATA", n_violations = NA_integer_,
                detail = "no factors provided", per_factor = list()))
  }
  factor_names <- names(factor_weights)
  per_factor   <- vector("list", length(factor_names))
  names(per_factor) <- factor_names

  n_violations <- 0L
  n_warn       <- 0L
  for (f in factor_names) {
    w  <- as.numeric(factor_weights[[f]])
    si <- as.numeric(stress_icir_map[[f]] %||% NA_real_)
    if (is.na(si)) {
      per_factor[[f]] <- list(weight = w, stress_icir = NA_real_,
                              product = NA_real_, status = "MISSING_STRESS_ICIR")
      next
    }
    product <- si * w
    status <- if (product < .PP_PRODUCT_HARD_FAIL) "HARD_FAIL"
              else if (product < .PP_PRODUCT_WARN) "WARN"
              else "PASS"
    if (status == "HARD_FAIL") n_violations <- n_violations + 1L
    if (status == "WARN")      n_warn       <- n_warn       + 1L

    is_known_pill <- f %in% names(.PP_KNOWN_POISON_PILL)
    per_factor[[f]] <- list(
      weight        = round(w, 4),
      stress_icir   = round(si, 4),
      product       = round(product, 4),
      threshold     = .PP_PRODUCT_HARD_FAIL,
      status        = status,
      known_poison_pill = is_known_pill,
      l_code_ref    = if (is_known_pill) .PP_KNOWN_POISON_PILL[[f]]$l_code else NA_character_,
      auto_action   = if (status == "HARD_FAIL")
        sprintf("weight_cap_%.0fpct OR exclude", .PP_WEIGHT_CAP_AFTER_VIOLATION * 100)
        else NA_character_
    )
  }

  verdict <- if (n_violations > 0L) "HARD_FAIL"
             else if (n_warn > 0L) "CONDITIONAL"
             else "PASS"

  list(verdict = verdict, n_violations = n_violations, n_warn = n_warn,
       n_factors = length(factor_names),
       detail = sprintf("%d/%d factors violate (product < %.2f), %d warn",
                        n_violations, length(factor_names),
                        .PP_PRODUCT_HARD_FAIL, n_warn),
       per_factor = per_factor)
}

# ─── Sub-gate 12b: composite pill count ──────────────────────────────────────
# Defense composite admission rule: HARD_FAIL violation 0건 강제
.pp_sub_b_composite_count <- function(sub_a_result) {
  if (sub_a_result$verdict == "INSUFFICIENT_DATA") {
    return(list(verdict = "INSUFFICIENT_DATA", count = NA_integer_,
                detail = "sub-gate 12a insufficient"))
  }
  count <- sub_a_result$n_violations
  verdict <- if (count == 0L) "PASS" else "HARD_FAIL"
  list(verdict = verdict, count = count,
       detail  = sprintf("%d hard_fail factors in composite (must be 0)", count))
}

# ─── Sub-gate 12c: regime-conditional amplification flag ─────────────────────
# Bull/normal stress_icir vs crisis stress_icir.
# Crisis stress_icir이 baseline 대비 1.5x 이상 악화 시 amplification flag.
.pp_sub_c_regime_amplification <- function(factor_weights, regime_icir_map) {
  if (is.null(regime_icir_map) || length(regime_icir_map) == 0L) {
    # 12c는 optional S6 monitor — 미제공 시 NOT_APPLIED (aggregate에 영향 없음)
    return(list(verdict = "NOT_APPLIED", n_amplified = NA_integer_,
                detail = "regime_icir_map not provided (S6 optional monitor)"))
  }
  factor_names <- names(factor_weights)
  amplified    <- character(0)
  per_factor   <- list()

  for (f in factor_names) {
    rm <- regime_icir_map[[f]]
    if (is.null(rm) || length(rm) == 0L) {
      per_factor[[f]] <- list(status = "NO_REGIME_DATA")
      next
    }
    bull   <- as.numeric(rm$bull   %||% rm$normal %||% NA_real_)
    crisis <- as.numeric(rm$crisis %||% rm$bear   %||% NA_real_)
    if (!is.finite(bull) || !is.finite(crisis) || abs(bull) < 1e-6) {
      per_factor[[f]] <- list(status = "INSUFFICIENT_REGIME_DATA",
                              bull = bull, crisis = crisis)
      next
    }
    # negative stress_icir: crisis 더 negative이면 악화. positive이면 부호 변화 체크
    is_amplified <- if (crisis < 0 && bull < 0) {
      abs(crisis) >= .PP_REGIME_AMPL_FACTOR * abs(bull)
    } else if (crisis < 0 && bull >= 0) {
      TRUE  # bull positive였는데 crisis flip → amplification
    } else FALSE

    if (is_amplified) amplified <- c(amplified, f)
    per_factor[[f]] <- list(
      bull        = round(bull, 4),
      crisis      = round(crisis, 4),
      ratio       = round(crisis / bull, 4),
      amplified   = is_amplified,
      status      = if (is_amplified) "AMPLIFIED" else "STABLE"
    )
  }

  verdict <- if (length(amplified) == 0L) "PASS"
             else "CONDITIONAL"  # 12c는 hard_fail 아님 (S6 monitor)
  list(verdict = verdict, n_amplified = length(amplified),
       amplified_factors = amplified,
       detail = sprintf("%d factors with regime amplification (crisis ≥ %.1fx bull)",
                        length(amplified), .PP_REGIME_AMPL_FACTOR),
       per_factor = per_factor)
}

# ─── Aggregate verdict ───────────────────────────────────────────────────────
.pp_aggregate <- function(a, b, c) {
  v <- c(a$verdict, b$verdict, c$verdict)
  v <- v[v != "NOT_APPLIED"]  # optional sub-gate 제외
  if (any(v == "HARD_FAIL"))         return("HARD_FAIL")
  if (any(v == "INSUFFICIENT_DATA")) return("INSUFFICIENT_DATA")
  if (any(v == "CONDITIONAL"))       return("CONDITIONAL")
  "PASS"
}

#==============================================================================
# Public API
#==============================================================================
audit_poison_pill_ic_return <- function(strategy_id,
                                        factor_weights,
                                        stress_icir_map,
                                        regime_icir_map = NULL,
                                        output_dir      = NULL) {
  # Weight sum sanity check (informational, not gating)
  total_w <- sum(unlist(factor_weights), na.rm = TRUE)
  if (abs(total_w - 1) > 0.01) {
    warning(sprintf("factor_weights sum=%.3f deviates from 1.00 (continuing)", total_w))
  }

  a <- .pp_sub_a_per_factor(factor_weights, stress_icir_map)
  b <- .pp_sub_b_composite_count(a)
  c_ <- .pp_sub_c_regime_amplification(factor_weights, regime_icir_map)

  overall <- .pp_aggregate(a, b, c_)

  # Compose recommended action when HARD_FAIL
  recommended_actions <- list()
  if (overall == "HARD_FAIL") {
    violators <- names(Filter(function(x) isTRUE(x$status == "HARD_FAIL"),
                              a$per_factor))
    recommended_actions <- list(
      primary    = "variant_comparison: drop or weight-cap each violator",
      violators  = violators,
      cap_target = .PP_WEIGHT_CAP_AFTER_VIOLATION,
      l_code_ref = "L-163 ACTIVE (Stage 2 enforcement)"
    )
  }

  result <- list(
    schema_version  = "v1.0",
    gate_id         = "Gate 12 (Poison Pill IC-Return)",
    strategy_id     = strategy_id,
    audited_at      = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    overall_verdict = overall,
    weight_sum      = round(total_w, 4),
    sub_gates = list(
      `12a_per_factor_pill_check`     = a,
      `12b_composite_pill_count`      = b,
      `12c_regime_amplification_flag` = c_
    ),
    recommended_actions = recommended_actions,
    rule_reference  = "L-163 ACTIVE — stress_icir × weight >= -0.05 (Defense composite)",
    related_l_codes = c("L-144", "L-146", "L-160", "L-163"),
    related_axioms  = "AX-005 (Defense standalone failure meta)",
    thresholds = list(
      product_hard_fail = .PP_PRODUCT_HARD_FAIL,
      product_warn      = .PP_PRODUCT_WARN,
      regime_ampl       = .PP_REGIME_AMPL_FACTOR,
      weight_cap        = .PP_WEIGHT_CAP_AFTER_VIOLATION
    )
  )

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(output_dir, "poison_pill_ic_return_audit.json")
    jsonlite::write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
    result$artifact_path <- out_path
  }
  result
}

#==============================================================================
# Convenience: load from families.json + s0_record handoff_kit
#==============================================================================
audit_from_handoff_kit <- function(handoff_kit_path,
                                   families_path = "qepm/memory/registry/families.json",
                                   output_dir    = NULL) {
  if (!file.exists(handoff_kit_path)) {
    return(list(overall_verdict = "INSUFFICIENT_DATA",
                detail = paste("missing handoff_kit:", handoff_kit_path)))
  }
  hk <- jsonlite::fromJSON(handoff_kit_path, simplifyVector = FALSE)
  fw <- hk$factor_weights %||% hk$composite_weights %||% NULL
  if (is.null(fw)) {
    return(list(overall_verdict = "INSUFFICIENT_DATA",
                detail = "handoff_kit missing factor_weights"))
  }

  # stress_icir source priority: handoff_kit > families.json > known_pill
  sicir <- hk$stress_icir_map %||% list()
  if (file.exists(families_path)) {
    fam <- tryCatch(jsonlite::fromJSON(families_path, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (!is.null(fam)) {
      pp <- fam$defense$poison_pill_factors %||% list()
      for (entry in pp) {
        f <- entry$factor %||% NA_character_
        if (!is.na(f) && is.null(sicir[[f]]) && !is.null(entry$stress_icir)) {
          sicir[[f]] <- entry$stress_icir
        }
      }
    }
  }
  for (f in names(.PP_KNOWN_POISON_PILL)) {
    if (is.null(sicir[[f]])) sicir[[f]] <- .PP_KNOWN_POISON_PILL[[f]]$stress_icir
  }

  audit_poison_pill_ic_return(
    strategy_id     = hk$strategy_id %||% hk$h_id %||% basename(handoff_kit_path),
    factor_weights  = fw,
    stress_icir_map = sicir,
    regime_icir_map = hk$regime_icir_map %||% NULL,
    output_dir      = output_dir
  )
}
