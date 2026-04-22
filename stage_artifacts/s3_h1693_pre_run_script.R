#==============================================================================
# S3 Orthogonality Pre-Run Script — H_1693 (STR_1687)
#==============================================================================
# Created: 2026-04-19 Session 68 Day 2
# Author: Scout
# Task: #26 H_1693 VERDICT 77 APPROVE_CONDITIONAL — S3 pre-run script 준비
#
# Purpose: H_1693/STR_1687 S1 Forge 완료 직후 즉시 실행 가능한
#          7-step S3 orthogonality measurement pipeline.
#
# Activation trigger:
#   1) 04_Research/strategies/STR_1687/output/daily_returns.csv 생성
#   2) Gate 14 sub_gate_14a net_IC_transmission_ratio > 0.6 PASS
#   3) qepm/mailbox/scout/inbox/TODO_S3_STR_1687.json 수신
#
# Usage (post-trigger):
#   cd 04_Research/strategies/STR_1687
#   Rscript -e 'source("../../../stage_artifacts/s3_h1693_pre_run_script.R")'
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(tidyverse)
  # t-copula MLE는 copula package 사용 (CRAN)
  if (!requireNamespace("copula", quietly = TRUE)) {
    stop("[S3] copula package 미설치 — install.packages('copula') 필요")
  }
  library(copula)
  # DCC-GARCH는 rmgarch 사용
  if (!requireNamespace("rmgarch", quietly = TRUE)) {
    warning("[S3] rmgarch 미설치 — DCC-GARCH step 6 건너뜀")
  }
})

#==============================================================================
# CONFIG
#==============================================================================

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_ID  <- "STR_1687"
HYPOTHESIS_ID <- "H_1693"

BENCHMARK_PATHS <- list(
  STR_1631_SYN_05        = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_SYN_05/output/daily_returns.csv"),
  STR_1656_MLRA_M05      = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA_M05/output/daily_returns.csv"),
  STR_1679v3             = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1679v3/output/daily_returns.csv"),
  STR_1661_XGB_GPU_V2    = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1661_XGB_GPU/output/nav_V2.csv"),
  STR_1689_v3_variant_1  = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1689_v3_variant_1/output/daily_returns.csv"),
  STR_1689_v3_variant_2  = file.path(PROJECT_ROOT, "04_Research/strategies/STR_1689_v3_variant_2/output/daily_returns.csv")
)

TARGET_PATH <- file.path(PROJECT_ROOT, sprintf("04_Research/strategies/%s/output/daily_returns.csv", STRATEGY_ID))

REGIME_PATH <- file.path(PROJECT_ROOT, ".cache/unified_regime_signal.parquet")
OUTPUT_DIR  <- file.path(PROJECT_ROOT, sprintf("04_Research/strategies/%s/output", STRATEGY_ID))
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts")

GATE_11_TDC_THRESHOLD       <- 0.50  # Admission Rule v3.5.2
GATE_SEQ_CRISIS_THRESHOLD   <- 0.30  # L-156 v2 Sequential Admission

#==============================================================================
# STEP 1: daily_returns merge
#==============================================================================

step_1_merge_daily_returns <- function() {
  cat("=== STEP 1: Merge daily returns ===\n")

  if (!file.exists(TARGET_PATH)) {
    stop(sprintf("[S3] H_1693 daily_returns.csv 미생성: %s\nForge S1 완료 대기", TARGET_PATH))
  }

  dr_target <- fread(TARGET_PATH)
  stopifnot("Date" %in% names(dr_target), "Return" %in% names(dr_target))
  setnames(dr_target, "Return", STRATEGY_ID)
  dr_target[, Date := as.Date(Date)]
  setkey(dr_target, Date)

  merged <- dr_target
  for (bench_name in names(BENCHMARK_PATHS)) {
    fp <- BENCHMARK_PATHS[[bench_name]]
    if (!file.exists(fp)) {
      warning(sprintf("[S3] benchmark 미존재 skip: %s (%s)", bench_name, fp))
      next
    }
    dr_b <- fread(fp)
    # nav_V2.csv 일 경우 return 컬럼 자동 탐지
    ret_col <- intersect(c("Return", "return", "daily_return", "ret"), names(dr_b))
    if (length(ret_col) == 0) {
      warning(sprintf("[S3] return 컬럼 미발견 skip: %s", bench_name))
      next
    }
    dr_b <- dr_b[, .(Date = as.Date(Date), Return = get(ret_col[1]))]
    setnames(dr_b, "Return", bench_name)
    merged <- merge(merged, dr_b, by = "Date", all = FALSE)
  }

  cat(sprintf("Merged date range: %s ~ %s (%d days, %d strategies)\n",
              format(min(merged$Date)), format(max(merged$Date)),
              nrow(merged), ncol(merged) - 1))
  return(merged)
}

#==============================================================================
# STEP 2: Monthly aggregation + Spearman
#==============================================================================

step_2_monthly_spearman <- function(merged) {
  cat("=== STEP 2: Monthly Spearman correlation ===\n")

  # 월별 누적 return
  merged[, YM := format(Date, "%Y-%m")]
  strategy_cols <- setdiff(names(merged), c("Date", "YM"))

  monthly <- merged[, lapply(.SD, function(r) prod(1 + r, na.rm = TRUE) - 1),
                    by = YM, .SDcols = strategy_cols]

  # pair-wise Spearman
  target_col <- STRATEGY_ID
  benchmarks <- setdiff(strategy_cols, target_col)

  spearman_matrix <- sapply(benchmarks, function(b) {
    cor(monthly[[target_col]], monthly[[b]], method = "spearman", use = "pairwise.complete.obs")
  })

  return(list(monthly = monthly, spearman = spearman_matrix))
}

#==============================================================================
# STEP 3: Daily Pearson
#==============================================================================

step_3_daily_pearson <- function(merged) {
  cat("=== STEP 3: Daily Pearson correlation ===\n")

  target_col <- STRATEGY_ID
  benchmarks <- setdiff(names(merged), c("Date", "YM", target_col))

  pearson_matrix <- sapply(benchmarks, function(b) {
    cor(merged[[target_col]], merged[[b]], method = "pearson", use = "pairwise.complete.obs")
  })
  return(pearson_matrix)
}

#==============================================================================
# STEP 4: t-copula MLE → TDC
#==============================================================================

# Empirical CDF → uniform marginals → t-copula fit → upper TDC
# TDC_upper = 2 * pt(-sqrt((nu+1)*(1-rho)/(1+rho)), df=nu+1)
compute_tdc_tcopula <- function(x, y) {
  # NA 제거
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]; y <- y[ok]
  if (length(x) < 250) return(list(tdc_upper = NA_real_, nu = NA_real_, rho = NA_real_))

  # PIT (empirical rank → uniform)
  u <- pobs(cbind(x, y))

  fit <- tryCatch({
    fitCopula(tCopula(dim = 2, dispstr = "un"),
              data = u, method = "mpl")
  }, error = function(e) NULL)

  if (is.null(fit)) return(list(tdc_upper = NA_real_, nu = NA_real_, rho = NA_real_))

  rho <- coef(fit)[1]
  nu  <- coef(fit)[2]
  # Upper tail dependence (symmetric for t-copula)
  tdc <- 2 * pt(-sqrt((nu + 1) * (1 - rho) / (1 + rho)), df = nu + 1)
  return(list(tdc_upper = tdc, nu = nu, rho = rho))
}

step_4_tdc_full_sample <- function(merged) {
  cat("=== STEP 4: t-copula MLE TDC (full sample) ===\n")
  target_col <- STRATEGY_ID
  benchmarks <- setdiff(names(merged), c("Date", "YM", target_col))

  tdc_list <- lapply(benchmarks, function(b) {
    res <- compute_tdc_tcopula(merged[[target_col]], merged[[b]])
    cat(sprintf("  %s vs %s: TDC=%.3f (nu=%.1f, rho=%.3f)\n",
                target_col, b, res$tdc_upper, res$nu, res$rho))
    res
  })
  names(tdc_list) <- benchmarks
  return(tdc_list)
}

#==============================================================================
# STEP 5: Regime-conditional TDC (CRISIS subset)
#==============================================================================

step_5_regime_tdc <- function(merged) {
  cat("=== STEP 5: Regime-conditional TDC (CRISIS) ===\n")

  if (!file.exists(REGIME_PATH)) {
    warning(sprintf("[S3] regime signal 미존재: %s — step 5 skip", REGIME_PATH))
    return(NULL)
  }

  regime <- tryCatch(arrow::read_parquet(REGIME_PATH), error = function(e) NULL)
  if (is.null(regime)) {
    warning("[S3] parquet 읽기 실패 (arrow 미설치?) — step 5 skip")
    return(NULL)
  }
  regime <- as.data.table(regime)
  regime[, Date := as.Date(Date)]

  # MRS >= 30 = CRISIS
  merged_r <- merge(merged, regime[, .(Date, MRS)], by = "Date", all.x = TRUE)
  crisis_mask <- merged_r$MRS >= 30
  crisis_mask[is.na(crisis_mask)] <- FALSE

  if (sum(crisis_mask) < 250) {
    warning(sprintf("[S3] CRISIS days too few (%d) — step 5 skip", sum(crisis_mask)))
    return(NULL)
  }

  merged_crisis <- merged[crisis_mask]
  target_col <- STRATEGY_ID
  benchmarks <- setdiff(names(merged_crisis), c("Date", "YM", target_col))

  tdc_crisis <- lapply(benchmarks, function(b) {
    res <- compute_tdc_tcopula(merged_crisis[[target_col]], merged_crisis[[b]])
    cat(sprintf("  CRISIS %s vs %s: TDC=%.3f\n", target_col, b, res$tdc_upper))
    res
  })
  names(tdc_crisis) <- benchmarks
  return(tdc_crisis)
}

#==============================================================================
# STEP 6: DCC-GARCH (선택적)
#==============================================================================

step_6_dcc_garch <- function(merged) {
  cat("=== STEP 6: DCC-GARCH conditional rho ===\n")
  if (!requireNamespace("rmgarch", quietly = TRUE)) {
    cat("  rmgarch 미설치 — skip\n")
    return(NULL)
  }
  cat("  DCC-GARCH 구현은 compute_dcc_rho.R helper 필요 — Forge 확장 권고\n")
  return(NULL)
}

#==============================================================================
# STEP 7: Aggregate matrix + gates verdict
#==============================================================================

step_7_aggregate <- function(spearman_m, pearson_m, tdc_full, tdc_crisis) {
  cat("=== STEP 7: Aggregate TDC matrix + gates verdict ===\n")

  benchmarks <- names(tdc_full)
  dt <- data.table(
    pair            = sprintf("%s vs %s", STRATEGY_ID, benchmarks),
    spearman_monthly = spearman_m[benchmarks],
    pearson_daily    = pearson_m[benchmarks],
    tdc_full         = sapply(tdc_full, `[[`, "tdc_upper"),
    tdc_crisis       = if (is.null(tdc_crisis)) NA_real_ else sapply(tdc_crisis, `[[`, "tdc_upper"),
    gate_11_verdict  = NA_character_,
    sequential_crisis_verdict = NA_character_
  )
  dt[, gate_11_verdict := ifelse(is.na(tdc_full), "NA",
                                  ifelse(tdc_full < GATE_11_TDC_THRESHOLD, "PASS", "FAIL"))]
  dt[, sequential_crisis_verdict := ifelse(is.na(tdc_crisis), "NA",
                                             ifelse(tdc_crisis < GATE_SEQ_CRISIS_THRESHOLD, "PASS", "FAIL"))]

  # 저장
  if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)
  fwrite(dt, file.path(OUTPUT_DIR, "s3_h1693_pairwise_tdc_matrix.csv"))
  cat(sprintf("Saved: %s\n", file.path(OUTPUT_DIR, "s3_h1693_pairwise_tdc_matrix.csv")))

  # novelty score (lower TDC = higher novelty)
  novelty_score <- 1 - mean(dt$tdc_full, na.rm = TRUE)

  # s3_orthogonality_H_1693_measured.json
  s3_artifact <- list(
    hypothesis_id = HYPOTHESIS_ID,
    strategy_id = STRATEGY_ID,
    measured_at = as.character(Sys.time()),
    tdc_matrix = setNames(
      lapply(seq_len(nrow(dt)), function(i) {
        list(
          tdc_full = dt$tdc_full[i],
          tdc_crisis = dt$tdc_crisis[i],
          pearson_daily = dt$pearson_daily[i],
          spearman_monthly = dt$spearman_monthly[i],
          gate_11_verdict = dt$gate_11_verdict[i],
          sequential_crisis_verdict = dt$sequential_crisis_verdict[i]
        )
      }),
      dt$pair
    ),
    novelty_score = novelty_score,
    candidate_role_hint = "defense",
    orthogonality_gate_verdict = list(
      gate_8_pairwise_tdc = if (all(dt$gate_11_verdict == "PASS", na.rm = TRUE)) "PASS" else "FAIL",
      gate_11_admission_rule_tdc = if (all(dt$gate_11_verdict == "PASS", na.rm = TRUE)) "PASS" else "FAIL"
    ),
    sequential_admission_protocol = list(
      cluster_members_q07_shared = c("STR_1679v3", "STR_1689_v3_variant_2"),
      crisis_gate_results = dt$sequential_crisis_verdict,
      primary_path_recommended = "TBD_by_governor"
    )
  )

  jsonlite::write_json(
    s3_artifact,
    file.path(ARTIFACT_DIR, "s3_orthogonality_H_1693_measured.json"),
    pretty = TRUE, auto_unbox = TRUE
  )
  cat(sprintf("Saved: %s\n", file.path(ARTIFACT_DIR, "s3_orthogonality_H_1693_measured.json")))
  return(dt)
}

#==============================================================================
# MAIN
#==============================================================================

main <- function() {
  cat(sprintf("=== S3 Orthogonality Pipeline — %s (%s) ===\n", HYPOTHESIS_ID, STRATEGY_ID))
  t0 <- Sys.time()

  merged <- step_1_merge_daily_returns()
  s2 <- step_2_monthly_spearman(merged)
  p3 <- step_3_daily_pearson(merged)
  t4 <- step_4_tdc_full_sample(merged)
  t5 <- step_5_regime_tdc(merged)
  step_6_dcc_garch(merged)
  final_dt <- step_7_aggregate(s2$spearman, p3, t4, t5)

  cat(sprintf("=== S3 Complete in %.1f min ===\n", as.numeric(Sys.time() - t0, units = "mins")))
  print(final_dt)

  # Judge S6 routing hint
  cat("\nNEXT: Judge S6 Gate 11 TDC verdict + Governor PG1 Sequential Admission\n")
}

# Activation guard — 환경변수 S3_RUN=1로만 실행
if (Sys.getenv("S3_RUN") == "1") {
  main()
} else {
  cat("[S3 pre-run script loaded] To execute: S3_RUN=1 Rscript -e 'source(\"stage_artifacts/s3_h1693_pre_run_script.R\")'\n")
  cat(sprintf("Target: %s\n", TARGET_PATH))
  cat(sprintf("Exists: %s\n", file.exists(TARGET_PATH)))
}
