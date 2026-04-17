#==============================================================================
# Judge Agent — Strategy Validator for Perpetual Research Engine
#
# Role: Mailbox polling + Gate 0-5 sequential validation + Near-miss repair
# IPC: agent_mailbox.R (qepm/R/orchestration/agent_mailbox.R)
# PIT: lookahead_detector.R (02_Infrastructure/lookahead_detector.R)
# Hurdle: hurdle_gate.R (02_Infrastructure/hurdle_gate.R)
#
# Commands:
#   "validate"  — full Gate 0-5 sequential validation
#   "pit_check" — C1~C12 PIT check only
#   "status"    — report agent health
#
# Gate Hierarchy (upper FAIL = skip lower):
#   Gate 0: Validity (PIT C1~C12, reproducibility)
#   Gate 1: Implementability (TO <600%, liquidity >=2B, N <=30)
#   Gate 2: Robustness (OOS retention, stress, MDD <45%)
#   Gate 3: Performance (Sharpe0, CAGR)
#   Gate 4: Statistical (FF3/C4/FF5 alpha, DSR/FDR)
#   Gate 5: Diversification (correlation with existing Grade A)
#
# Usage:
#   cd "$PROJECT_ROOT" && Rscript -e 'source("02_Infrastructure/agent_judge.R")'
#==============================================================================

cat("=== Judge Agent: Initializing ===\n")

# --- Resolve project root (Korean path safe) ---
.judge_root <- tryCatch(
  dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) {
    candidates <- c(
      "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
      Sys.getenv("QM_ROOT", unset = "")
    )
    found <- candidates[nchar(candidates) > 0 & sapply(candidates, dir.exists)]
    if (length(found) == 0) stop("[Judge] Cannot resolve PROJECT_ROOT")
    found[1]
  }
)

# --- Source infrastructure ---
tryCatch({
  source(file.path(.judge_root, "02_Infrastructure", "config.R"))
}, error = function(e) {
  cat("[Judge] config.R load failed:", conditionMessage(e), "\n")
  PROJECT_ROOT <<- .judge_root
})

MAILBOX_PATH <- file.path(.judge_root, "qepm", "R", "orchestration", "agent_mailbox.R")
if (!file.exists(MAILBOX_PATH)) stop("[Judge] agent_mailbox.R not found: ", MAILBOX_PATH)
source(MAILBOX_PATH)

LOOKAHEAD_PATH <- file.path(.judge_root, "02_Infrastructure", "validation", "lookahead_detector.R")
if (file.exists(LOOKAHEAD_PATH)) {
  source(LOOKAHEAD_PATH)
  cat("[Judge] lookahead_detector.R loaded\n")
} else {
  cat("[Judge] WARNING: lookahead_detector.R not found\n")
}

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

cat(sprintf("[Judge] PROJECT_ROOT: %s\n", .judge_root))

.judge_start_time <- Sys.time()

#==============================================================================
# CONSTANTS
#==============================================================================

AGENT_NAME     <- "judge"
POLL_INTERVAL  <- 15  # seconds

# Hard fail thresholds
HARD_TURNOVER_MAX  <- 600    # % annualized
HARD_MDD_MAX       <- 0.45   # 45%
HARD_MAX_HOLDINGS  <- 30
LIQ_THRESHOLD      <- 2e8    # 20-day avg trading value >= 2 billion KRW

# Near-miss thresholds (for repair ticket generation)
NEAR_MISS_MDD_UPPER    <- 0.45
NEAR_MISS_MDD_LOWER    <- 0.40
NEAR_MISS_CAGR_TARGET  <- 0.16
NEAR_MISS_CAGR_CLOSE   <- 0.02  # within 2%p of target
NEAR_MISS_SHARPE_TARGET <- 0.80
NEAR_MISS_SHARPE_CLOSE  <- 0.10

#==============================================================================
# GATE 0: VALIDITY — C1~C12 PIT Check
#==============================================================================

#' Run C1~C12 lookahead detection on strategy directory
#'
#' @param strategy_dir Path to strategy directory (contains run_all.R)
#' @return list(clean, violations, n_violations, details)
check_lookahead <- function(strategy_dir) {
  result <- list(
    clean       = TRUE,
    violations  = list(),
    n_violations = 0L,
    details     = "No R files found or detector unavailable"
  )

  if (!dir.exists(strategy_dir)) {
    result$details <- paste("Directory not found:", strategy_dir)
    return(result)
  }

  # Use detect_lookahead_dir if available (scans all .R files)
  if (exists("detect_lookahead_dir") && is.function(detect_lookahead_dir)) {
    tryCatch({
      la_result <- detect_lookahead_dir(strategy_dir, verbose = TRUE)
      result$clean        <- la_result$clean
      result$violations   <- la_result$violations
      result$n_violations <- la_result$n_violations
      result$details      <- sprintf("Scanned %d files, %d violations",
                                      la_result$n_files, la_result$n_violations)
    }, error = function(e) {
      result$details <- paste("Detector error:", conditionMessage(e))
    })
  } else {
    # Fallback: scan run_all.R only
    run_all_path <- file.path(strategy_dir, "run_all.R")
    if (file.exists(run_all_path) && exists("detect_lookahead") &&
        is.function(detect_lookahead)) {
      tryCatch({
        la_result <- detect_lookahead(run_all_path, verbose = TRUE)
        result$clean        <- la_result$clean
        result$violations   <- la_result$violations
        result$n_violations <- la_result$n_violations
        result$details      <- sprintf("Scanned run_all.R (%d lines), %d violations",
                                        la_result$n_lines, la_result$n_violations)
      }, error = function(e) {
        result$details <- paste("Detector error:", conditionMessage(e))
      })
    }
  }

  result
}

#==============================================================================
# GATE 1: IMPLEMENTABILITY
#==============================================================================

#' Check implementability constraints
#'
#' @param hurdle Hurdle result (from hurdle_result.json)
#' @param strategy_dir Strategy directory
#' @return list(pass, violations)
check_implementability <- function(hurdle, strategy_dir = NULL) {
  violations <- list()
  metrics <- hurdle$metrics %||% list()

  # 1a. Turnover < 600%
  turnover <- as.numeric(metrics$Turnover_Ann %||% 0)
  if (turnover > HARD_TURNOVER_MAX) {
    violations[[length(violations) + 1]] <- list(
      gate = "G1", check = "turnover",
      msg = sprintf("Annualized turnover %.0f%% > %d%% limit", turnover, HARD_TURNOVER_MAX),
      value = turnover, threshold = HARD_TURNOVER_MAX
    )
  }

  # 1b. Max holdings <= 30
  # Check from portfolio log if available
  if (!is.null(strategy_dir)) {
    plog_path <- file.path(strategy_dir, "output", "portfolio_log.csv")
    if (!file.exists(plog_path)) plog_path <- file.path(strategy_dir, "portfolio_log.csv")
    if (file.exists(plog_path)) {
      tryCatch({
        plog <- fread(plog_path)
        if ("N_stocks" %in% names(plog)) {
          max_n <- max(plog$N_stocks, na.rm = TRUE)
          if (max_n > HARD_MAX_HOLDINGS) {
            violations[[length(violations) + 1]] <- list(
              gate = "G1", check = "max_holdings",
              msg = sprintf("Max holdings %d > %d limit", max_n, HARD_MAX_HOLDINGS),
              value = max_n, threshold = HARD_MAX_HOLDINGS
            )
          }
        }
      }, error = function(e) NULL)
    }
  }

  # 1c. Liquidity: check if liquidity filter was applied
  # (heuristic: look for LIQ_THRESHOLD in code)
  if (!is.null(strategy_dir)) {
    run_all_path <- file.path(strategy_dir, "run_all.R")
    if (file.exists(run_all_path)) {
      code <- tryCatch(readLines(run_all_path, warn = FALSE), error = function(e) "")
      code_text <- paste(code, collapse = "\n")
      has_liq_filter <- grepl("LIQ_THRESHOLD|liq_filter|AvgTV|avg_tv|TradingValue",
                               code_text, ignore.case = TRUE)
      if (!has_liq_filter) {
        violations[[length(violations) + 1]] <- list(
          gate = "G1", check = "liquidity_filter",
          msg = "No liquidity filter detected in code (LIQ_THRESHOLD >= 2e8 required)",
          value = NA, threshold = LIQ_THRESHOLD
        )
      }
    }
  }

  list(pass = length(violations) == 0, violations = violations)
}

#==============================================================================
# GATE 2: ROBUSTNESS
#==============================================================================

#' Check robustness metrics
#'
#' @param hurdle Hurdle result
#' @return list(pass, violations)
check_robustness <- function(hurdle) {
  violations <- list()
  metrics <- hurdle$metrics %||% list()
  breakdown <- hurdle$score_breakdown %||% list()

  # 2a. MDD < 45%
  mdd <- as.numeric(metrics$MDD %||% 0) / 100
  if (mdd > HARD_MDD_MAX) {
    violations[[length(violations) + 1]] <- list(
      gate = "G2", check = "mdd",
      msg = sprintf("MDD %.1f%% > %.0f%% hard limit", mdd * 100, HARD_MDD_MAX * 100),
      value = mdd, threshold = HARD_MDD_MAX
    )
  }

  # 2b. OOS retention (from hurdle breakdown)
  oos_val <- tryCatch(
    as.numeric(breakdown$oos$value),
    error = function(e) NA_real_
  )
  if (!is.na(oos_val) && oos_val < 0.3) {
    violations[[length(violations) + 1]] <- list(
      gate = "G2", check = "oos_retention",
      msg = sprintf("OOS retention %.2f < 0.30 (severe overfitting)", oos_val),
      value = oos_val, threshold = 0.3
    )
  }

  # 2c. 3Y rolling Sharpe > 0 ratio
  roll_pos <- as.numeric(metrics$Rolling3Y_Pos %||% 0)
  if (roll_pos < 30) {
    violations[[length(violations) + 1]] <- list(
      gate = "G2", check = "rolling_sharpe",
      msg = sprintf("3Y rolling Sharpe>0 ratio %.1f%% < 30%% (unstable)", roll_pos),
      value = roll_pos, threshold = 30
    )
  }

  list(pass = length(violations) == 0, violations = violations)
}

#==============================================================================
# GATE 3: PERFORMANCE
#==============================================================================

#' Check performance metrics
#'
#' @param hurdle Hurdle result
#' @return list(pass, violations, near_miss)
check_performance <- function(hurdle) {
  violations <- list()
  near_miss  <- list()
  metrics    <- hurdle$metrics %||% list()

  sharpe <- as.numeric(metrics$Sharpe %||% 0)
  cagr   <- as.numeric(metrics$CAGR %||% 0) / 100  # stored as percentage

  # 3a. Sharpe >= 0 (absolute minimum)
  if (sharpe <= 0) {
    violations[[length(violations) + 1]] <- list(
      gate = "G3", check = "sharpe_positive",
      msg = sprintf("Sharpe %.3f <= 0 (negative risk-adjusted return)", sharpe),
      value = sharpe, threshold = 0
    )
  }

  # 3b. Near-miss detection for CAGR
  if (cagr > 0 && cagr < NEAR_MISS_CAGR_TARGET &&
      cagr >= NEAR_MISS_CAGR_TARGET - NEAR_MISS_CAGR_CLOSE) {
    near_miss[[length(near_miss) + 1]] <- list(
      metric = "CAGR",
      value  = cagr,
      target = NEAR_MISS_CAGR_TARGET,
      gap    = NEAR_MISS_CAGR_TARGET - cagr,
      suggestion = "Add complementary sleeve or adjust regime conditioning"
    )
  }

  # 3c. Near-miss detection for Sharpe
  if (sharpe > 0 && sharpe < NEAR_MISS_SHARPE_TARGET &&
      sharpe >= NEAR_MISS_SHARPE_TARGET - NEAR_MISS_SHARPE_CLOSE) {
    near_miss[[length(near_miss) + 1]] <- list(
      metric = "Sharpe",
      value  = sharpe,
      target = NEAR_MISS_SHARPE_TARGET,
      gap    = NEAR_MISS_SHARPE_TARGET - sharpe,
      suggestion = "Reduce volatility via vol targeting or add defensive sleeve"
    )
  }

  list(pass = length(violations) == 0, violations = violations,
       near_miss = near_miss)
}

#==============================================================================
# GATE 4: STATISTICAL (FF3/C4/FF5 alpha significance)
#==============================================================================

#' Check factor model alpha significance
#'
#' @param hurdle Hurdle result
#' @param strategy_dir Strategy directory (for ff_results.csv)
#' @return list(pass, violations, alpha_data)
check_statistical <- function(hurdle, strategy_dir = NULL) {
  violations  <- list()
  alpha_data  <- list()

  # Check for factor regression results
  if (!is.null(strategy_dir)) {
    ff_paths <- c(
      file.path(strategy_dir, "output", "ff_results.csv"),
      file.path(strategy_dir, "output", "analysis_ff.csv"),
      file.path(strategy_dir, "ff_results.csv")
    )
    ff_path <- ff_paths[file.exists(ff_paths)]

    if (length(ff_path) > 0) {
      tryCatch({
        ff_dt <- fread(ff_path[1])
        # Look for alpha row (intercept)
        alpha_rows <- ff_dt[grepl("alpha|intercept|\\(Intercept\\)", ff_dt[[1]],
                                   ignore.case = TRUE)]
        if (nrow(alpha_rows) > 0) {
          for (i in seq_len(nrow(alpha_rows))) {
            model_name <- alpha_rows[[1]][i]
            # Try to extract t-stat or p-value
            t_val <- tryCatch(
              as.numeric(alpha_rows[i, grepl("t.value|t_stat|t", names(alpha_rows),
                                              ignore.case = TRUE), with = FALSE][[1]]),
              error = function(e) NA_real_
            )
            p_val <- tryCatch(
              as.numeric(alpha_rows[i, grepl("p.value|pvalue|Pr", names(alpha_rows),
                                              ignore.case = TRUE), with = FALSE][[1]]),
              error = function(e) NA_real_
            )
            alpha_val <- tryCatch(
              as.numeric(alpha_rows[i, grepl("Estimate|coef|alpha", names(alpha_rows),
                                              ignore.case = TRUE), with = FALSE][[1]]),
              error = function(e) NA_real_
            )

            alpha_data[[model_name]] <- list(
              alpha = alpha_val, t_stat = t_val, p_value = p_val
            )
          }
        }
      }, error = function(e) {
        cat("[Judge] FF results parse error:", conditionMessage(e), "\n")
      })
    }
  }

  # Check DSR from hurdle
  stat_def <- hurdle$statistical_defense %||% list()
  dsr_val  <- stat_def$dsr %||% NA_real_
  dsr_sig  <- stat_def$dsr_significant %||% FALSE

  if (!is.na(dsr_val) && !dsr_sig && dsr_val < 0.50) {
    violations[[length(violations) + 1]] <- list(
      gate = "G4", check = "dsr",
      msg = sprintf("DSR p=%.4f < 0.50, not significant (multiple testing concern)", dsr_val),
      value = dsr_val, threshold = 0.50
    )
  }

  list(pass = length(violations) == 0, violations = violations,
       alpha_data = alpha_data)
}

#==============================================================================
# GATE 5: DIVERSIFICATION
#==============================================================================

#' Check diversification vs existing Grade A strategies
#'
#' @param hurdle Hurdle result
#' @return list(pass, violations, max_corr)
check_diversification <- function(hurdle) {
  violations <- list()
  metrics <- hurdle$metrics %||% list()

  max_corr <- as.numeric(metrics$GradeA_Corr %||% NA_real_)

  if (!is.na(max_corr) && max_corr > 0.95) {
    violations[[length(violations) + 1]] <- list(
      gate = "G5", check = "grade_a_correlation",
      msg = sprintf("Correlation with Grade A composite %.3f > 0.95 (redundant)",
                     max_corr),
      value = max_corr, threshold = 0.95
    )
  }

  list(pass = length(violations) == 0, violations = violations,
       max_corr = max_corr)
}

#==============================================================================
# NEAR-MISS REPAIR TICKET GENERATOR (Lawbook 8.4)
#==============================================================================

#' Generate repair ticket for near-miss strategies
#'
#' @param strategy_id Strategy identifier
#' @param gate_results Results from all gates
#' @param hurdle Original hurdle result
#' @return list(has_ticket, ticket) or list(has_ticket = FALSE)
generate_repair_ticket <- function(strategy_id, gate_results, hurdle) {
  near_misses <- list()

  # Collect near-misses from Gate 3
  g3 <- gate_results$gate3
  if (!is.null(g3$near_miss) && length(g3$near_miss) > 0) {
    for (nm in g3$near_miss) {
      near_misses <- c(near_misses, list(nm))
    }
  }

  # Check MDD near-miss (close to but under 45%)
  metrics <- hurdle$metrics %||% list()
  mdd_val <- as.numeric(metrics$MDD %||% 0) / 100
  if (mdd_val > NEAR_MISS_MDD_LOWER && mdd_val <= NEAR_MISS_MDD_UPPER) {
    near_misses <- c(near_misses, list(list(
      metric     = "MDD",
      value      = mdd_val,
      target     = NEAR_MISS_MDD_UPPER,
      gap        = NEAR_MISS_MDD_UPPER - mdd_val,
      suggestion = "Add drawdown brake or defensive regime overlay"
    )))
  }

  # Check OOS near-miss
  oos_val <- tryCatch(
    as.numeric(hurdle$score_breakdown$oos$value),
    error = function(e) NA_real_
  )
  if (!is.na(oos_val) && oos_val >= 0.3 && oos_val < 0.5) {
    near_misses <- c(near_misses, list(list(
      metric     = "OOS_retention",
      value      = oos_val,
      target     = 0.5,
      gap        = 0.5 - oos_val,
      suggestion = "Reduce parameters or use expanding window estimation"
    )))
  }

  if (length(near_misses) == 0) {
    return(list(has_ticket = FALSE))
  }

  # Build repair ticket
  ticket <- list(
    strategy_id = strategy_id,
    type        = "repair",
    bucket      = "stabilize",
    near_misses = near_misses,
    targets     = lapply(near_misses, function(nm) {
      list(metric = nm$metric, current = nm$value, target = nm$target)
    }),
    suggestions = paste(sapply(near_misses, function(nm) nm$suggestion), collapse = "; "),
    success_criteria = paste(
      sapply(near_misses, function(nm) {
        sprintf("%s >= %.3f", nm$metric, nm$target)
      }),
      collapse = " AND "
    ),
    created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    created_by  = "judge"
  )

  list(has_ticket = TRUE, ticket = ticket)
}

#==============================================================================
# MAIN VALIDATION PIPELINE
#==============================================================================

#' Run full Gate 0-5 sequential validation
#'
#' @param strategy_dir Strategy directory path
#' @param strategy_id Strategy identifier (e.g., "STR_1039")
#' @return list(grade, score, verdict, pit_clean, violations, repair_ticket, gate_details)
validate_strategy <- function(strategy_dir, strategy_id = "unknown") {

  cat(sprintf("\n[Judge] === Validating %s ===\n", strategy_id))
  cat(sprintf("[Judge] Directory: %s\n", strategy_dir))

  all_violations <- list()
  gate_details   <- list()
  stopped_at     <- NA_character_

  # --- Load hurdle_result.json ---
  hurdle <- NULL
  hurdle_paths <- c(
    file.path(strategy_dir, "output", "hurdle_result.json"),
    file.path(strategy_dir, "hurdle_result.json")
  )
  for (hp in hurdle_paths) {
    if (file.exists(hp)) {
      hurdle <- tryCatch(
        fromJSON(hp, simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (!is.null(hurdle)) {
        cat(sprintf("[Judge] Loaded hurdle from: %s\n", hp))
        break
      }
    }
  }

  if (is.null(hurdle)) {
    cat("[Judge] WARNING: hurdle_result.json not found, limited validation\n")
    hurdle <- list(
      metrics = list(), score_breakdown = list(), statistical_defense = list(),
      grade = "F", total_score = 0
    )
  }

  # ======================================================================
  # GATE 0: VALIDITY (PIT C1~C12)
  # ======================================================================
  cat("[Judge] Gate 0: Validity (C1~C12 PIT check)...\n")
  pit_result <- check_lookahead(strategy_dir)
  gate_details$gate0 <- pit_result

  if (!pit_result$clean) {
    cat(sprintf("[Judge] Gate 0 FAIL: %d PIT violations\n", pit_result$n_violations))
    all_violations <- c(all_violations, pit_result$violations)
    stopped_at <- "gate0"

    # HARD FAIL at Gate 0 -> skip all subsequent gates
    result <- list(
      grade        = "F",
      score        = 0,
      verdict      = "FAIL_LOOKAHEAD",
      pit_clean    = FALSE,
      violations   = all_violations,
      repair_ticket = list(has_ticket = FALSE),
      gate_details = gate_details,
      stopped_at   = stopped_at,
      strategy_id  = strategy_id,
      timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
    )
    print_verdict(result)
    return(result)
  }
  cat("[Judge] Gate 0 PASS: PIT clean\n")

  # ======================================================================
  # GATE 1: IMPLEMENTABILITY
  # ======================================================================
  cat("[Judge] Gate 1: Implementability (TO, liquidity, N<=30)...\n")
  g1 <- check_implementability(hurdle, strategy_dir)
  gate_details$gate1 <- g1

  if (!g1$pass) {
    cat(sprintf("[Judge] Gate 1 FAIL: %d violations\n", length(g1$violations)))
    all_violations <- c(all_violations, g1$violations)
    stopped_at <- "gate1"

    result <- list(
      grade        = "F",
      score        = hurdle$total_score %||% 0,
      verdict      = "FAIL_IMPLEMENTABILITY",
      pit_clean    = TRUE,
      violations   = all_violations,
      repair_ticket = list(has_ticket = FALSE),
      gate_details = gate_details,
      stopped_at   = stopped_at,
      strategy_id  = strategy_id,
      timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
    )
    print_verdict(result)
    return(result)
  }
  cat("[Judge] Gate 1 PASS\n")

  # ======================================================================
  # GATE 2: ROBUSTNESS
  # ======================================================================
  cat("[Judge] Gate 2: Robustness (OOS, stress, MDD)...\n")
  g2 <- check_robustness(hurdle)
  gate_details$gate2 <- g2

  if (!g2$pass) {
    # Gate 2 fail is hard fail for MDD, soft for OOS/rolling
    has_mdd_fail <- any(sapply(g2$violations, function(v) v$check == "mdd"))
    cat(sprintf("[Judge] Gate 2 FAIL: %d violations (MDD hard fail: %s)\n",
                length(g2$violations), has_mdd_fail))
    all_violations <- c(all_violations, g2$violations)

    if (has_mdd_fail) {
      stopped_at <- "gate2"
      result <- list(
        grade        = "F",
        score        = hurdle$total_score %||% 0,
        verdict      = "FAIL_MDD",
        pit_clean    = TRUE,
        violations   = all_violations,
        repair_ticket = list(has_ticket = FALSE),
        gate_details = gate_details,
        stopped_at   = stopped_at,
        strategy_id  = strategy_id,
        timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
      )
      print_verdict(result)
      return(result)
    }
    # Non-MDD failures: continue but note violations
  }
  cat(sprintf("[Judge] Gate 2 %s\n", if (g2$pass) "PASS" else "WARN (soft violations)"))

  # ======================================================================
  # GATE 3: PERFORMANCE
  # ======================================================================
  cat("[Judge] Gate 3: Performance (Sharpe, CAGR)...\n")
  g3 <- check_performance(hurdle)
  gate_details$gate3 <- g3

  if (!g3$pass) {
    cat(sprintf("[Judge] Gate 3 FAIL: %d violations\n", length(g3$violations)))
    all_violations <- c(all_violations, g3$violations)
    stopped_at <- "gate3"

    # Check for near-miss repair
    repair <- generate_repair_ticket(strategy_id, list(gate3 = g3), hurdle)

    result <- list(
      grade        = "F",
      score        = hurdle$total_score %||% 0,
      verdict      = "FAIL_PERFORMANCE",
      pit_clean    = TRUE,
      violations   = all_violations,
      repair_ticket = repair,
      gate_details = gate_details,
      stopped_at   = stopped_at,
      strategy_id  = strategy_id,
      timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
    )
    print_verdict(result)
    return(result)
  }
  if (length(g3$near_miss) > 0) {
    cat(sprintf("[Judge] Gate 3 PASS with %d near-miss metrics\n",
                length(g3$near_miss)))
  } else {
    cat("[Judge] Gate 3 PASS\n")
  }

  # ======================================================================
  # GATE 4: STATISTICAL
  # ======================================================================
  cat("[Judge] Gate 4: Statistical (FF alpha, DSR)...\n")
  g4 <- check_statistical(hurdle, strategy_dir)
  gate_details$gate4 <- g4

  if (!g4$pass) {
    cat(sprintf("[Judge] Gate 4 WARN: %d statistical concerns\n",
                length(g4$violations)))
    all_violations <- c(all_violations, g4$violations)
    # Gate 4 failures are soft warnings, not hard fail
  } else {
    cat("[Judge] Gate 4 PASS\n")
  }

  # ======================================================================
  # GATE 5: DIVERSIFICATION
  # ======================================================================
  cat("[Judge] Gate 5: Diversification (Grade A correlation)...\n")
  g5 <- check_diversification(hurdle)
  gate_details$gate5 <- g5

  if (!g5$pass) {
    cat(sprintf("[Judge] Gate 5 FAIL: redundant with existing Grade A\n"))
    all_violations <- c(all_violations, g5$violations)
    # Diversification fail downgrades but doesn't reject
  } else {
    cat("[Judge] Gate 5 PASS\n")
  }

  # ======================================================================
  # FINAL GRADING
  # ======================================================================

  # Use hurdle grade as base, then apply Judge adjustments
  base_grade <- hurdle$grade %||% "F"
  base_score <- hurdle$total_score %||% 0

  # Downgrade if G4/G5 violations exist
  final_grade <- base_grade
  if (!g5$pass && base_grade == "A") {
    final_grade <- "B"
    cat("[Judge] Downgraded A -> B (Gate 5 diversification fail)\n")
  }
  if (!g4$pass && !g5$pass && base_grade %in% c("A", "B")) {
    final_grade <- "B"
    cat("[Judge] Confirmed B (Gate 4 + Gate 5 concerns)\n")
  }

  # Determine verdict
  verdict <- if (final_grade == "A") "PASS_STANDALONE"
             else if (final_grade == "B") "PASS_COMPONENT"
             else if (final_grade == "C") "PASS_ENSEMBLE"
             else "FAIL"

  # Generate repair ticket for near-misses
  repair <- generate_repair_ticket(strategy_id,
    list(gate3 = g3, gate2 = g2), hurdle)

  result <- list(
    grade        = final_grade,
    score        = base_score,
    verdict      = verdict,
    pit_clean    = pit_result$clean,
    violations   = all_violations,
    repair_ticket = repair,
    gate_details = gate_details,
    stopped_at   = stopped_at,
    strategy_id  = strategy_id,
    timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )

  print_verdict(result)
  save_judge_result(result, strategy_dir)

  result
}

#==============================================================================
# OUTPUT HELPERS
#==============================================================================

#' Print verdict summary to console
#'
#' @param result Judge validation result
print_verdict <- function(result) {
  cat("\n")
  cat("=== JUDGE VERDICT ===\n")
  cat(sprintf("Strategy : %s\n", result$strategy_id))
  cat(sprintf("Grade    : %s\n", result$grade))
  cat(sprintf("Score    : %.1f\n", result$score))
  cat(sprintf("Verdict  : %s\n", result$verdict))
  cat(sprintf("PIT Clean: %s\n", result$pit_clean))
  if (!is.na(result$stopped_at)) {
    cat(sprintf("Stopped  : %s\n", result$stopped_at))
  }
  if (length(result$violations) > 0) {
    cat(sprintf("Violations: %d\n", length(result$violations)))
    for (v in result$violations) {
      gate_label <- v$gate %||% v$check %||% "?"
      cat(sprintf("  [%s] %s\n", gate_label, v$msg %||% ""))
    }
  }
  if (isTRUE(result$repair_ticket$has_ticket)) {
    cat(sprintf("Repair   : %s\n", result$repair_ticket$ticket$suggestions))
  }
  cat("=====================\n\n")
}

#' Save judge result to strategy directory
#'
#' @param result Judge validation result
#' @param strategy_dir Strategy directory
save_judge_result <- function(result, strategy_dir) {
  if (!dir.exists(strategy_dir)) return(invisible(NULL))

  output_dir <- file.path(strategy_dir, "output")
  if (!dir.exists(output_dir)) output_dir <- strategy_dir

  tryCatch({
    write_json(result, file.path(output_dir, "judge_result.json"),
               auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("[Judge] Result saved: %s\n",
                file.path(output_dir, "judge_result.json")))
  }, error = function(e) {
    cat(sprintf("[Judge] Save failed: %s\n", conditionMessage(e)))
  })
}

#==============================================================================
# MAILBOX POLLING LOOP
#==============================================================================

cat("[Judge] Starting mailbox polling loop (interval:", POLL_INTERVAL, "sec)\n")
cat(sprintf("[Judge] Stop file: /tmp/STOP_JUDGE\n"))

while (!file.exists("/tmp/STOP_JUDGE") && !file.exists("/tmp/STOP_RESEARCH")) {

  tryCatch({
    # Check inbox
    msgs <- mailbox_receive(AGENT_NAME, mark_read = TRUE)

    for (msg in msgs) {
      cmd <- msg$body$cmd %||% msg$subject %||% ""
      cat(sprintf("[Judge] Received: cmd='%s' from='%s' id='%s'\n",
                  cmd, msg$from, msg$msg_id))

      if (cmd == "validate") {
        # --- Full Gate 0-5 validation ---
        strategy_dir <- msg$body$strategy_dir %||% ""
        strategy_id  <- msg$body$strategy_id %||%
                         basename(strategy_dir) %||% "unknown"

        if (!nzchar(strategy_dir) || !dir.exists(strategy_dir)) {
          mailbox_reply(msg, AGENT_NAME,
            result  = list(error = paste("Invalid strategy_dir:", strategy_dir)),
            success = FALSE
          )
          next
        }

        judge_result <- validate_strategy(strategy_dir, strategy_id)

        mailbox_reply(msg, AGENT_NAME,
          result  = judge_result,
          success = TRUE
        )
        cat(sprintf("[Judge] Validation complete: %s -> %s (Score %.1f)\n",
                    strategy_id, judge_result$grade, judge_result$score))

      } else if (cmd == "pit_check") {
        # --- C1~C12 PIT check only ---
        strategy_dir <- msg$body$strategy_dir %||% ""

        if (!nzchar(strategy_dir) || !dir.exists(strategy_dir)) {
          mailbox_reply(msg, AGENT_NAME,
            result  = list(error = paste("Invalid strategy_dir:", strategy_dir)),
            success = FALSE
          )
          next
        }

        pit_result <- check_lookahead(strategy_dir)
        mailbox_reply(msg, AGENT_NAME,
          result  = pit_result,
          success = TRUE
        )

      } else if (cmd == "status") {
        # --- Health check ---
        mailbox_reply(msg, AGENT_NAME,
          result  = list(
            agent   = AGENT_NAME,
            status  = "alive",
            uptime  = as.numeric(difftime(Sys.time(),
                        .judge_start_time, units = "mins")),
            gates   = c("G0:PIT", "G1:Impl", "G2:Robust", "G3:Perf",
                         "G4:Stat", "G5:Div")
          ),
          success = TRUE
        )

      } else {
        cat(sprintf("[Judge] Unknown command: '%s'\n", cmd))
        mailbox_reply(msg, AGENT_NAME,
          result  = list(error = paste("Unknown command:", cmd)),
          success = FALSE
        )
      }
    }
  }, error = function(e) {
    cat(sprintf("[Judge] Error in polling loop: %s\n", conditionMessage(e)))
  })

  Sys.sleep(POLL_INTERVAL)
}

cat("[Judge] Stopped.\n")
