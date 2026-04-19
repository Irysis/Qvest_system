#==============================================================================
# v55 Blender Scaffold Extensions — 5-Sleeve Matrix + Sequential TDC
#
# 기존 qepm/R/blender_scaffold.R (3-sleeve 기반)을 5-sleeve 지원으로 확장.
# Usage:
#   source("qepm/R/blender_scaffold.R")
#   source("qepm/R/blender_scaffold_v55.R")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# v55 5-sleeve 정의
V55_SLEEVES <- c("Core", "Diversifier", "Defense", "Cash", "ML")

V55_SLEEVE_ROLE_MAP <- list(
  Core        = "core_alpha",
  Diversifier = "diversifier",
  Defense     = "defense",
  Cash        = "cash_allocation",
  ML          = "ml_predictive"
)

# v55 regime × sleeve 기본 matrix
V55_REGIME_MATRIX_DEFAULT <- list(
  Good    = list(Core = 0.40, Diversifier = 0.30, Defense = 0.10, Cash = 0.00, ML = 0.20),
  Normal  = list(Core = 0.35, Diversifier = 0.30, Defense = 0.15, Cash = 0.05, ML = 0.15),
  Bad     = list(Core = 0.25, Diversifier = 0.25, Defense = 0.25, Cash = 0.15, ML = 0.10),
  Crisis  = list(Core = 0.15, Diversifier = 0.15, Defense = 0.30, Cash = 0.30, ML = 0.10)
)

#==============================================================================
# blender_check_activation_v55 — 5-sleeve 활성화 조건
#==============================================================================
#' Check v55 activation: Grade A 5+ across at least 3 distinct sleeves
blender_check_activation_v55 <- function(min_n = 5L, min_distinct_sleeves = 3L) {
  if (!exists("blender_check_activation", mode = "function")) {
    stop("기존 blender_scaffold.R 먼저 source 필요")
  }

  base <- blender_check_activation(min_n = min_n)
  if (!base$activated) {
    return(base)
  }

  # v55 추가 조건: 3개 이상 distinct sleeve에 Grade A 분산
  root <- if (exists(".blender_root", mode = "function")) .blender_root() else getwd()
  catalog_path <- file.path(root, "04_Research/grade_a_catalog.json")

  if (!file.exists(catalog_path)) {
    return(list(activated = FALSE,
                reason = "grade_a_catalog.json 누락 (v55 check)"))
  }

  catalog <- jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
  strategies <- catalog$strategies %||% list()

  # role 추출
  roles <- sapply(strategies, function(s) s$role %||% s$RoleBias %||% "unknown")
  distinct_roles <- unique(roles[roles != "unknown"])

  if (length(distinct_roles) < min_distinct_sleeves) {
    return(list(
      activated = FALSE,
      n_candidates = length(strategies),
      distinct_roles = distinct_roles,
      min_distinct_sleeves = min_distinct_sleeves,
      reason = sprintf("Grade A 분포: %d개 role, %d개 필요 (v55 5-sleeve)",
                       length(distinct_roles), min_distinct_sleeves)
    ))
  }

  list(
    activated = TRUE,
    n_candidates = length(strategies),
    distinct_roles = distinct_roles,
    roles_table = table(roles),
    v55_ready = TRUE,
    sleeves_populated = intersect(V55_SLEEVES, sapply(distinct_roles, function(r) {
      match_sleeve <- names(V55_SLEEVE_ROLE_MAP)[sapply(V55_SLEEVE_ROLE_MAP, function(x) x == r)]
      if (length(match_sleeve) > 0) match_sleeve[1] else NA
    }))
  )
}

#==============================================================================
# pairwise_tdc_check — Sequential TDC (Admission Rule v3.5.2 Gate 11)
#==============================================================================
#' Compute pairwise Tail Dependence Coefficient between two return series
#' @param ret_a numeric vector
#' @param ret_b numeric vector
#' @param threshold numeric (quantile, default 0.05 for lower tail)
#' @return numeric TDC (0~1)
compute_tdc <- function(ret_a, ret_b, threshold = 0.05) {
  # Empirical lower tail dependence
  # TDC = P(F_a <= q | F_b <= q) as q -> 0
  n <- length(ret_a)
  if (n != length(ret_b) || n < 24) return(NA)

  q_a <- quantile(ret_a, threshold, na.rm = TRUE)
  q_b <- quantile(ret_b, threshold, na.rm = TRUE)

  in_tail_a <- ret_a <= q_a
  in_tail_b <- ret_b <= q_b

  both_in <- sum(in_tail_a & in_tail_b, na.rm = TRUE)
  any_b <- sum(in_tail_b, na.rm = TRUE)

  if (any_b == 0) return(0)
  round(both_in / any_b, 3)
}

#' Sequential TDC Gate Check — Admission Rule v3.5.2 Gate 11
pairwise_tdc_check <- function(returns_matrix,
                                 tdc_max = 0.30, tdc_block = 0.50,
                                 crisis_mask = NULL) {
  # returns_matrix: data.frame/matrix, cols = strategy_id, rows = time
  strategies <- colnames(returns_matrix)
  n <- length(strategies)

  if (n < 2) {
    return(list(ok = TRUE, reason = "n < 2, TDC check skipped"))
  }

  # Crisis 구간만 사용 (TRUE mask)
  rm <- if (!is.null(crisis_mask)) returns_matrix[crisis_mask, , drop = FALSE] else returns_matrix

  tdc_matrix <- matrix(NA, n, n, dimnames = list(strategies, strategies))
  blocks <- list()
  warnings_list <- list()

  for (i in seq_len(n - 1)) {
    for (j in seq(i + 1, n)) {
      ra <- rm[[i]]
      rb <- rm[[j]]
      tdc <- compute_tdc(ra, rb)
      tdc_matrix[i, j] <- tdc
      tdc_matrix[j, i] <- tdc

      if (!is.na(tdc)) {
        if (tdc > tdc_block) {
          blocks[[length(blocks) + 1]] <- sprintf("(%s, %s) TDC=%.3f > %.2f BLOCK",
                                                    strategies[i], strategies[j], tdc, tdc_block)
        } else if (tdc > tdc_max) {
          warnings_list[[length(warnings_list) + 1]] <- sprintf(
            "(%s, %s) TDC=%.3f > %.2f WARN", strategies[i], strategies[j], tdc, tdc_max)
        }
      }
    }
  }

  list(
    ok = length(blocks) == 0,
    tdc_matrix = tdc_matrix,
    n_pairs = n * (n - 1) / 2,
    blocks = blocks,
    warnings = warnings_list,
    tdc_max = tdc_max,
    tdc_block = tdc_block,
    reason = if (length(blocks) > 0)
               sprintf("BLOCK %d건: %s", length(blocks), paste(blocks, collapse = "; "))
             else if (length(warnings_list) > 0)
               sprintf("WARN %d건 (admission 허용)", length(warnings_list))
             else "모든 pair TDC PASS"
  )
}

#==============================================================================
# blender_5sleeve_weights — Regime × 5 Sleeve 배분 계산
#==============================================================================
#' Compute 5-sleeve weights by regime
#' @param regime_series factor vector of regimes (Good/Normal/Bad/Crisis)
#' @param matrix_override list (optional, default V55_REGIME_MATRIX_DEFAULT)
blender_5sleeve_weights <- function(regime_series,
                                      matrix_override = NULL) {
  mat <- matrix_override %||% V55_REGIME_MATRIX_DEFAULT

  regime_series <- as.character(regime_series)

  result <- data.table(
    regime = regime_series,
    Core = sapply(regime_series, function(r) mat[[r]]$Core %||% NA),
    Diversifier = sapply(regime_series, function(r) mat[[r]]$Diversifier %||% NA),
    Defense = sapply(regime_series, function(r) mat[[r]]$Defense %||% NA),
    Cash = sapply(regime_series, function(r) mat[[r]]$Cash %||% NA),
    ML = sapply(regime_series, function(r) mat[[r]]$ML %||% NA)
  )

  # Row sum check (should be 1.0)
  result[, total := Core + Diversifier + Defense + Cash + ML]
  if (any(abs(result$total - 1.0) > 0.01, na.rm = TRUE)) {
    warning("Row sum != 1.0 in some rows")
  }

  result
}

#==============================================================================
# blender_loo_v55 — 5-sleeve LOO (Leave-One-Sleeve-Out)
#==============================================================================
#' LOO validation: remove one sleeve, re-compute portfolio SR
#' @param sleeve_returns list of sleeve return vectors (5 sleeves)
#' @param weights named numeric (5 elements sum to 1)
blender_loo_v55 <- function(sleeve_returns, weights) {
  sleeves <- names(sleeve_returns)
  baseline <- Reduce("+", Map("*", sleeve_returns, weights))
  baseline_sr <- mean(baseline) / sd(baseline) * sqrt(12)

  loo_results <- lapply(sleeves, function(omit_s) {
    remaining <- setdiff(sleeves, omit_s)
    # Re-normalize weights
    remaining_w <- unlist(weights[remaining])
    remaining_w <- remaining_w / sum(remaining_w)
    portfolio <- Reduce("+", Map("*", sleeve_returns[remaining], as.list(remaining_w)))
    sr <- mean(portfolio) / sd(portfolio) * sqrt(12)
    list(
      omitted = omit_s,
      sr = round(sr, 3),
      delta_sr = round(sr - baseline_sr, 3)
    )
  })

  list(
    baseline_sr = round(baseline_sr, 3),
    loo_results = loo_results
  )
}

#==============================================================================
# blender_activate_5sleeve — 통합 Activation Entry Point
#==============================================================================
#' Full v55 Blender activation check
blender_activate_5sleeve <- function() {
  check <- blender_check_activation_v55()
  if (!check$activated) {
    cat("[blender_v55] Not activated:", check$reason, "\n")
    return(check)
  }

  cat(sprintf("[blender_v55] Activated! %d strategies across %d roles\n",
              check$n_candidates, length(check$distinct_roles)))
  cat("Sleeves populated:", paste(check$sleeves_populated, collapse = ", "), "\n")

  # Ready for next steps:
  cat("\nNext:\n")
  cat("  1. Load strategy returns\n")
  cat("  2. blender_correlation_matrix(returns_matrix)\n")
  cat("  3. pairwise_tdc_check(returns_matrix, crisis_mask = ...)\n")
  cat("  4. blender_5sleeve_weights(regime_series)\n")
  cat("  5. blender_loo_v55(sleeve_returns, weights)\n")
  cat("  6. Save pg2_allocation_5sleeve.json\n")

  check
}

cat("[blender_scaffold_v55] Loaded. Functions: blender_check_activation_v55, compute_tdc, pairwise_tdc_check, blender_5sleeve_weights, blender_loo_v55, blender_activate_5sleeve\n")
