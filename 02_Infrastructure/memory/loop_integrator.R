#!/usr/bin/env Rscript
# =============================================================================
# Loop Integrator — _deleted_FreshIdea hostile reviews + perpetual engine 통합
#
# _deleted_FreshIdea의 정성적 비판과 QEPM의 정량적 파이프라인을 연결하여
# 자가발전 루프를 강화한다.
#
# Functions:
#   loop_session_brief()                       — 세션 시작 브리핑
#   loop_post_strategy_review(strategy_id, hr) — 전략 완료 후 hostile review
#   loop_generate_hypotheses(n)                — 다음 가설 자동 생성
#   loop_check_direction(family, max_fail)     — 방향 전환 검사
#   loop_status()                              — 전체 루프 현황
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/loop_integrator.R")
#   loop_session_brief()
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("data.table required")
})

# --- Paths ---
if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}
.LI_ROOT       <- PROJECT_ROOT
.LI_FRESHIDEA  <- file.path(.LI_ROOT, "_deleted_FreshIdea")
.LI_QEPM       <- file.path(.LI_ROOT, "qepm")
.LI_REGISTRY   <- file.path(.LI_QEPM, "registry")
.LI_MEMORY     <- file.path(.LI_QEPM, "memory")
.LI_STRATEGIES <- file.path(.LI_ROOT, "04_Research", "strategies")

# Claude memory directory (cross-machine)
.LI_CLAUDE_MEM <- tryCatch({
  candidates <- c(
    "C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory",
    "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory",
    "/home/quant/.claude/projects/-mnt-c-Users-99922-OneDrive-------Quant-Module-Moltbot/memory"
  )
  found <- candidates[sapply(candidates, dir.exists)]
  if (length(found) > 0) found[1] else candidates[1]
}, error = function(e) "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory")

# --- Helpers ---
.li_read_json <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyDataFrame = FALSE),
           error = function(e) NULL)
}

.li_write_json <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(obj, path, auto_unbox = TRUE, pretty = TRUE)
}

.li_timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")

.li_date_stamp <- function() format(Sys.Date(), "%Y-%m-%d")

# =============================================================================
# 1. loop_session_brief() — 세션 시작 브리핑
# =============================================================================

#' Session start briefing: L-codes, Grade A count, top strategies, pending hypotheses
#' @export
loop_session_brief <- function() {
  cat("\n")
  cat("===================================================================\n")
  cat("  LOOP INTEGRATOR — Session Briefing\n")
  cat("  ", format(Sys.time(), "%Y-%m-%d %H:%M KST"), "\n")
  cat("===================================================================\n\n")

  # --- A. L-code summary from methodology_memory.md ---
  meth_path <- file.path(.LI_CLAUDE_MEM, "methodology_memory.md")
  l_codes <- list(total = 0, recent = character(0))
  if (file.exists(meth_path)) {
    lines <- tryCatch(readLines(meth_path, warn = FALSE), error = function(e) character(0))
    l_lines <- grep("^### L-\\d+:", lines, value = TRUE)
    l_codes$total <- length(l_lines)
    # Last 5 L-codes
    if (length(l_lines) > 0) {
      last_n <- tail(l_lines, 5)
      l_codes$recent <- gsub("^### ", "", last_n)
    }
  }
  cat("[L-codes] Total:", l_codes$total, "lessons recorded\n")
  if (length(l_codes$recent) > 0) {
    cat("  Recent:\n")
    for (lc in l_codes$recent) cat("    ", lc, "\n")
  }

  # --- B. Strategy registry summary ---
  exp_path <- file.path(.LI_REGISTRY, "experiments.json")
  exps <- .li_read_json(exp_path)
  if (is.null(exps)) exps <- list()

  n_total <- length(exps)
  grades <- sapply(exps, function(e) e$grade %||% "F")
  grade_counts <- table(factor(grades, levels = c("A", "B", "C", "F")))

  cat("\n[Registry] Total:", n_total, "experiments\n")
  cat("  Grade A:", grade_counts["A"],
      "| B:", grade_counts["B"],
      "| C:", grade_counts["C"],
      "| F:", grade_counts["F"], "\n")

  # Top 3 by score
  if (n_total > 0) {
    scores <- sapply(exps, function(e) as.numeric(e$score %||% e$total_score %||% 0))
    top_idx <- head(order(scores, decreasing = TRUE), 3)
    cat("  Top strategies:\n")
    for (idx in top_idx) {
      e <- exps[[idx]]
      sid <- e$strategy_id %||% e$strategy_name %||% names(exps)[idx] %||% "?"
      sc  <- as.numeric(e$score %||% e$total_score %||% 0)
      gr  <- e$grade %||% "?"
      sh  <- as.numeric(e$metrics$Sharpe %||% e$metrics$sharpe0_m_ann %||% 0)
      cat(sprintf("    %s: Score %.1f (%s) Sharpe %.3f\n", sid, sc, gr, sh))
    }
  }

  # --- C. Family tracker ---
  fam_path <- file.path(.LI_REGISTRY, "families.json")
  families <- .li_read_json(fam_path)
  if (!is.null(families) && length(families) > 0) {
    fail_streaks <- sapply(families, function(f) f$fail_streak %||% 0)
    high_fail <- names(fail_streaks[fail_streaks >= 3])
    cat("\n[Families]", length(families), "tracked\n")
    if (length(high_fail) > 0) {
      cat("  WARNING — fail_streak >= 3:", paste(high_fail, collapse = ", "), "\n")
      cat("  Consider direction change (loop_check_direction)\n")
    }
  }

  # --- D. Pending hypotheses from backlog ---
  bl_path <- file.path(.LI_REGISTRY, "backlog.json")
  backlog <- .li_read_json(bl_path)
  if (is.null(backlog)) backlog <- list()

  # Handle column-major format (backlog$status is a character vector)
  n_pending <- 0L
  if (!is.null(backlog[["status"]]) && is.character(backlog[["status"]])) {
    pending_idx <- which(backlog[["status"]] == "pending")
    n_pending <- length(pending_idx)
    cat("\n[Backlog]", n_pending, "pending hypotheses\n")
    if (n_pending > 0) {
      top3 <- head(pending_idx, 3)
      for (i in top3) {
        cat(sprintf("  - [%.2f] %s (%s)\n",
            as.numeric(backlog[["priority_score"]][i] %||% 0),
            backlog[["objective"]][i] %||% "(none)",
            backlog[["task_family"]][i] %||% "general"))
      }
      if (n_pending > 3) cat(sprintf("  ... +%d more\n", n_pending - 3))
    }
  } else {
    # Row-major format (list of records)
    pending_list <- Filter(function(b) (b[["status"]] %||% "pending") == "pending", backlog)
    n_pending <- length(pending_list)
    cat("\n[Backlog]", n_pending, "pending hypotheses\n")
    if (n_pending > 0) {
      for (p in head(pending_list, 3)) {
        cat(sprintf("  - [%.2f] %s (%s)\n",
            as.numeric(p[["priority_score"]] %||% p[["priority"]] %||% 0),
            p[["objective"]] %||% "(none)",
            p[["task_family"]] %||% "general"))
      }
      if (n_pending > 3) cat(sprintf("  ... +%d more\n", n_pending - 3))
    }
  }

  # --- E. _deleted_FreshIdea status ---
  fi_reviews <- length(list.files(file.path(.LI_FRESHIDEA, "01_Mad_Reviews"),
                                   pattern = "\\.md$", recursive = FALSE))
  fi_seeds <- length(list.files(file.path(.LI_FRESHIDEA, "03_Mutation_Seeds"),
                                 pattern = "\\.md$", recursive = FALSE))
  fi_canon <- length(list.files(file.path(.LI_FRESHIDEA, "10_Seed_Canon"),
                                 pattern = "\\.md$", recursive = FALSE))
  cat("\n[_deleted_FreshIdea] Reviews:", fi_reviews,
      "| Mutation Seeds:", fi_seeds,
      "| Canon Seeds:", fi_canon, "\n")

  # --- F. Target gaps ---
  cat("\n[Targets]\n")
  if (n_total > 0) {
    grade_a <- Filter(function(e) identical(e$grade, "A"), exps)
    if (length(grade_a) == 0) grade_a <- exps

    best_sharpe <- max(sapply(grade_a, function(e) {
      as.numeric(e$metrics$Sharpe %||% e$metrics$sharpe0_m_ann %||% 0)
    }), na.rm = TRUE)

    best_mdd <- min(sapply(grade_a, function(e) {
      m <- as.numeric(e$metrics$MDD %||% e$metrics$mdd %||% 100)
      if (m > 1) m <- m / 100
      m
    }), na.rm = TRUE)

    best_cagr <- max(sapply(grade_a, function(e) {
      c <- as.numeric(e$metrics$CAGR %||% e$metrics$net_cagr %||% 0)
      if (c > 1) c <- c / 100
      c
    }), na.rm = TRUE)

    sharpe_gap <- 2.5 - best_sharpe  # SR target 2.0→2.5 (2026-05-29)
    mdd_gap    <- best_mdd - 0.25
    cagr_gap   <- 0.16 - best_cagr

    cat(sprintf("  Sharpe: %.3f (gap %+.3f) %s\n", best_sharpe, sharpe_gap,
        if (sharpe_gap <= 0) "MET" else ""))
    cat(sprintf("  MDD:    %.1f%% (gap %+.1f%%p) %s\n", best_mdd * 100, mdd_gap * 100,
        if (mdd_gap <= 0) "MET" else ""))
    cat(sprintf("  CAGR:   %.1f%% (gap %+.1f%%p) %s\n", best_cagr * 100, cagr_gap * 100,
        if (cagr_gap <= 0) "MET" else ""))
  } else {
    cat("  No experiments in registry yet.\n")
  }

  cat("\n===================================================================\n\n")
  invisible(list(l_codes = l_codes, n_experiments = n_total,
                 grade_counts = grade_counts, n_pending = n_pending))
}


# =============================================================================
# 2. loop_post_strategy_review() — _deleted_FreshIdea hostile review 자동 트리거
# =============================================================================

#' After a strategy completes, generate a _deleted_FreshIdea hostile review
#' @param strategy_id Strategy identifier (e.g., "STR_803")
#' @param hurdle_result Hurdle gate result list
#' @return Path to the saved review file
#' @export
loop_post_strategy_review <- function(strategy_id, hurdle_result) {
  cat(sprintf("\n--- _deleted_FreshIdea Hostile Review: %s ---\n", strategy_id))

  grade  <- hurdle_result$grade %||% "F"
  score  <- as.numeric(hurdle_result$total_score %||% hurdle_result$score %||% 0)
  cagr   <- as.numeric(hurdle_result$metrics$CAGR %||% hurdle_result$CAGR %||% 0)
  sharpe <- as.numeric(hurdle_result$metrics$Sharpe %||% hurdle_result$Sharpe %||% 0)
  mdd    <- as.numeric(hurdle_result$metrics$MDD %||% hurdle_result$MDD %||% 0)
  to     <- as.numeric(hurdle_result$metrics$Turnover %||% hurdle_result$turnover %||% 0)
  family <- hurdle_result$family %||% "unknown"

  # --- Build hostile review ---
  review <- list(
    metadata = list(
      date = .li_date_stamp(),
      strategy_id = strategy_id,
      family = family,
      grade = grade,
      score = score,
      generated_by = "loop_integrator"
    ),
    numeric_snapshot = list(
      cagr = cagr, sharpe = sharpe, mdd = mdd, turnover = to
    ),
    # Automated hostile analysis
    hostile_analysis = list()
  )

  # ---- Overfitting risk ----
  oos_ret <- as.numeric(hurdle_result$oos_retention %||%
                         hurdle_result$metrics$oos_retention %||% NA)
  if (!is.na(oos_ret)) {
    if (oos_ret < 0.5) {
      review$hostile_analysis$overfitting <- sprintf(
        "DANGER: OOS retention %.3f < 0.50 — high overfitting probability", oos_ret)
    } else if (oos_ret < 0.65) {
      review$hostile_analysis$overfitting <- sprintf(
        "WARNING: OOS retention %.3f — moderate overfitting risk", oos_ret)
    } else {
      review$hostile_analysis$overfitting <- sprintf(
        "OK: OOS retention %.3f — acceptable", oos_ret)
    }
  } else {
    review$hostile_analysis$overfitting <- "UNKNOWN: No OOS retention data available"
  }

  # ---- Regime dependency ----
  review$hostile_analysis$regime_dependency <- paste0(
    "Strategy may depend on specific market regimes. ",
    "If backtested during prolonged bull market, MDD ",
    sprintf("%.1f%%", mdd), " may understate true tail risk. ",
    "Verify performance during 2008 GFC, 2020 COVID, 2022 rate shock independently."
  )

  # ---- Sharpe inflation check ----
  if (sharpe > 1.5 && mdd < 20) {
    review$hostile_analysis$sharpe_inflation <- paste0(
      "HIGH SHARPE + LOW MDD combination may indicate: ",
      "(1) aggressive DD brake clipping volatility but also clipping returns in recovery, ",
      "(2) vol targeting compressing realized vol artificially, ",
      "(3) parameter tuning to specific drawdown events in-sample. ",
      sprintf("Sharpe %.3f / MDD %.1f%% — interrogate the risk overlay parameters.", sharpe, mdd)
    )
  }

  # ---- Turnover check ----
  if (to > 300) {
    review$hostile_analysis$turnover <- sprintf(
      "DANGER: Turnover %.0f%% — transaction costs may erode alpha in live trading", to)
  } else if (to > 150) {
    review$hostile_analysis$turnover <- sprintf(
      "WARNING: Turnover %.0f%% — monitor net-of-cost performance carefully", to)
  }

  # ---- Parameter count check ----
  n_params <- hurdle_result$n_parameters %||% NA
  if (!is.na(n_params) && n_params > 8) {
    review$hostile_analysis$parameter_risk <- sprintf(
      "DANGER: %d parameters — high degrees of freedom. Harvey(2016) t>3.0 required.", n_params)
  }

  # ---- Family fatigue check ----
  fam_data <- .li_read_json(file.path(.LI_REGISTRY, "families.json"))
  fam_info <- if (!is.null(fam_data)) fam_data[[family]] else NULL
  if (!is.null(fam_info)) {
    trials <- fam_info$trial_count %||% 0
    if (trials >= 10) {
      review$hostile_analysis$family_fatigue <- sprintf(
        "Family '%s' has %d trials — diminishing returns likely. Consider new alpha direction.", family, trials)
    }
  }

  # ---- One-sentence verdict ----
  if (grade == "A" && score >= 90) {
    review$verdict <- sprintf(
      "%s scores %.1f but ask: is this strategy robust to regime change, or optimized to known crises?",
      strategy_id, score)
  } else if (grade == "A") {
    review$verdict <- sprintf(
      "%s passes hurdle (Grade A, %.1f) — verify the alpha source is not a known factor in disguise.",
      strategy_id, score)
  } else if (grade == "B") {
    review$verdict <- sprintf(
      "%s is Grade B (%.1f) — the gap to Grade A may be structural, not parametric. New factor needed?",
      strategy_id, score)
  } else {
    review$verdict <- sprintf(
      "%s failed (Grade %s, %.1f). Extract the one thing that did work, discard the rest.",
      strategy_id, grade, score)
  }

  # ---- Mutation seed for Grade F ----
  mutation_seed <- NULL
  if (grade == "F") {
    mutation_seed <- list(
      source_strategy = strategy_id,
      source_family = family,
      failure_mode = "hurdle_fail",
      mutation_type = "inversion",
      suggestion = paste0(
        "Invert the core signal of ", strategy_id, " (", family, "). ",
        "If the strategy buys low-X, try high-X with a regime guard. ",
        "If multi-factor, isolate which component dragged performance."
      ),
      created_at = .li_timestamp()
    )
    review$mutation_seed <- mutation_seed
  }

  # --- Save review ---
  review_dir <- file.path(.LI_FRESHIDEA, "01_Mad_Reviews")
  dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)
  fingerprint <- substr(digest::digest(paste(strategy_id, .li_timestamp()), algo = "md5"), 1, 12)
  review_filename <- sprintf("AE_%s_%s_%s.md",
    .li_date_stamp(), strategy_id, fingerprint)
  review_path <- file.path(review_dir, review_filename)

  # Write as markdown
  md_lines <- c(
    sprintf("# _deleted_FreshIdea Hostile Review: %s", strategy_id),
    "",
    sprintf("Date: %s", .li_date_stamp()),
    sprintf("Grade: %s | Score: %.1f | Family: %s", grade, score, family),
    sprintf("Generated by: loop_integrator.R"),
    "",
    "## Numeric Snapshot",
    sprintf("- CAGR: %.2f%%", cagr),
    sprintf("- Sharpe: %.3f", sharpe),
    sprintf("- MDD: %.2f%%", mdd),
    sprintf("- Turnover: %.0f%%", to),
    "",
    "## Verdict",
    sprintf("- %s", review$verdict),
    "",
    "## Hostile Analysis",
    ""
  )

  for (key in names(review$hostile_analysis)) {
    md_lines <- c(md_lines,
      sprintf("### %s", gsub("_", " ", tools::toTitleCase(key))),
      review$hostile_analysis[[key]],
      "")
  }

  if (!is.null(mutation_seed)) {
    md_lines <- c(md_lines,
      "## Mutation Seed (Grade F)",
      sprintf("- Type: %s", mutation_seed$mutation_type),
      sprintf("- Suggestion: %s", mutation_seed$suggestion),
      "")

    # Also save to 03_Mutation_Seeds
    seed_dir <- file.path(.LI_FRESHIDEA, "03_Mutation_Seeds")
    dir.create(seed_dir, recursive = TRUE, showWarnings = FALSE)
    seed_path <- file.path(seed_dir, sprintf("SEED_%s_%s_%s.md",
      .li_date_stamp(), strategy_id, fingerprint))
    seed_md <- c(
      sprintf("# Mutation Seed: %s", strategy_id),
      "",
      sprintf("Source: %s (Grade %s, Score %.1f)", strategy_id, grade, score),
      sprintf("Family: %s", family),
      sprintf("Type: %s", mutation_seed$mutation_type),
      "",
      "## Suggestion",
      mutation_seed$suggestion,
      "",
      sprintf("Created: %s", .li_timestamp())
    )
    writeLines(seed_md, seed_path)
    cat(sprintf("  Mutation seed saved: %s\n", basename(seed_path)))
  }

  writeLines(md_lines, review_path)
  cat(sprintf("  Review saved: %s\n", basename(review_path)))
  cat(sprintf("  Verdict: %s\n", review$verdict))

  # Also save structured JSON alongside for programmatic access
  json_path <- sub("\\.md$", ".json", review_path)
  .li_write_json(review, json_path)

  invisible(review_path)
}


# =============================================================================
# 3. loop_generate_hypotheses() — 다음 가설 자동 생성
# =============================================================================

#' Generate next hypotheses based on accumulated memory
#' @param n Number of hypotheses to generate
#' @return List of hypothesis items (also registered in backlog)
#' @export
loop_generate_hypotheses <- function(n = 5) {
  cat(sprintf("\n--- Generating %d hypotheses ---\n", n))

  hypotheses <- list()

  # --- A. Read methodology_memory.md for recent L-codes ---
  meth_path <- file.path(.LI_CLAUDE_MEM, "methodology_memory.md")
  recent_lessons <- character(0)
  discovery_codes <- character(0)
  if (file.exists(meth_path)) {
    lines <- readLines(meth_path, warn = FALSE)
    l_lines <- grep("^### L-\\d+:", lines, value = TRUE)
    recent_lessons <- tail(l_lines, 10)

    # Find [DISCOVERY] L-codes for high-value follow-ups
    disc_lines <- grep("\\[DISCOVERY\\]", l_lines, value = TRUE)
    discovery_codes <- gsub("^### (L-\\d+):.*", "\\1", disc_lines)
  }

  # --- B. Read family tracker for fail_streak patterns ---
  fam_data <- .li_read_json(file.path(.LI_REGISTRY, "families.json"))
  if (is.null(fam_data)) fam_data <- list()

  failing_families <- names(Filter(function(f) (f$fail_streak %||% 0) >= 2, fam_data))
  passing_families <- names(Filter(function(f) (f$pass_count %||% 0) > 0, fam_data))
  cooldown_families <- names(Filter(function(f) (f$fail_streak %||% 0) >= 3, fam_data))

  # --- C. Read backlog for existing pending ideas ---
  backlog <- .li_read_json(file.path(.LI_REGISTRY, "backlog.json"))
  if (is.null(backlog)) backlog <- list()
  existing_objectives <- sapply(backlog, function(b) tolower(b$objective %||% ""))

  # --- D. Read experiments registry for target gaps ---
  exps <- .li_read_json(file.path(.LI_REGISTRY, "experiments.json"))
  if (is.null(exps)) exps <- list()
  grade_a <- Filter(function(e) identical(e$grade, "A"), exps)

  best_sharpe <- 0; best_mdd <- 1; best_cagr <- 0
  if (length(grade_a) > 0) {
    best_sharpe <- max(sapply(grade_a, function(e)
      as.numeric(e$metrics$Sharpe %||% e$metrics$sharpe0_m_ann %||% 0)), na.rm = TRUE)
    best_mdd <- min(sapply(grade_a, function(e) {
      m <- as.numeric(e$metrics$MDD %||% e$metrics$mdd %||% 100)
      if (m > 1) m <- m / 100; m
    }), na.rm = TRUE)
    best_cagr <- max(sapply(grade_a, function(e) {
      c <- as.numeric(e$metrics$CAGR %||% e$metrics$net_cagr %||% 0)
      if (c > 1) c <- c / 100; c
    }), na.rm = TRUE)
  }

  sharpe_gap <- 2.5 - best_sharpe  # SR target 2.0→2.5 (2026-05-29)
  mdd_gap <- best_mdd - 0.25
  cagr_gap <- 0.16 - best_cagr

  # --- E. Read _deleted_FreshIdea mutation seeds for retry ideas ---
  seed_dir <- file.path(.LI_FRESHIDEA, "03_Mutation_Seeds")
  mutation_seeds <- list()
  if (dir.exists(seed_dir)) {
    seed_files <- list.files(seed_dir, pattern = "\\.md$", full.names = TRUE)
    for (sf in tail(seed_files, 5)) {
      lines <- tryCatch(readLines(sf, warn = FALSE, n = 15), error = function(e) character(0))
      source_line <- grep("^Source:", lines, value = TRUE)
      suggestion_lines <- grep("^## Suggestion", lines)
      suggestion <- ""
      if (length(suggestion_lines) > 0 && length(lines) > suggestion_lines[1]) {
        suggestion <- lines[suggestion_lines[1] + 1]
      }
      mutation_seeds[[length(mutation_seeds) + 1]] <- list(
        file = basename(sf),
        source = if (length(source_line) > 0) trimws(sub("^Source:", "", source_line[1])) else "",
        suggestion = suggestion
      )
    }
  }

  # --- F. Generate hypotheses ---

  # F1. Discovery follow-ups (highest priority)
  if (length(discovery_codes) > 0) {
    for (dc in tail(discovery_codes, 2)) {
      obj <- sprintf("Follow-up on %s discovery: extend to new alpha family or construction variant", dc)
      if (!any(grepl(tolower(dc), existing_objectives, fixed = TRUE))) {
        hypotheses[[length(hypotheses) + 1]] <- list(
          objective = obj,
          hypothesis = sprintf("%s revealed a breakthrough — explore adjacent parameter space and orthogonal applications", dc),
          task_family = "discovery_followup",
          exploration_mode = "exploit",
          expected_gain_axis = "Ret",
          priority_score = 0.95,
          source = "L_discovery_followup"
        )
      }
    }
  }

  # F2. Mutation seed retries (from _deleted_FreshIdea Grade F reviews)
  for (ms in head(mutation_seeds, 2)) {
    if (nzchar(ms$suggestion)) {
      obj <- sprintf("Mutation retry: %s", ms$source)
      if (!any(grepl(gsub("[^a-z0-9]", "", tolower(ms$source)),
                     gsub("[^a-z0-9]", "", existing_objectives)))) {
        hypotheses[[length(hypotheses) + 1]] <- list(
          objective = obj,
          hypothesis = ms$suggestion,
          task_family = "mutation_retry",
          exploration_mode = "counterfactual",
          expected_gain_axis = "Div",
          priority_score = 0.70,
          source = "freshidea_mutation"
        )
      }
    }
  }

  # F3. Gap-driven: largest gap gets priority
  if (sharpe_gap > 0.1) {
    hypotheses[[length(hypotheses) + 1]] <- list(
      objective = sprintf("Sharpe improvement: gap %.3f — optimize risk overlay or find new alpha", sharpe_gap),
      hypothesis = "Multi-timeframe DD brake or vol targeting refinement may close Sharpe gap",
      task_family = "risk_overlay",
      exploration_mode = "exploit",
      expected_gain_axis = "Ret",
      priority_score = 0.85 + min(sharpe_gap * 0.1, 0.1),
      source = "gap_sharpe"
    )
  }
  if (cagr_gap > 0.01) {
    hypotheses[[length(hypotheses) + 1]] <- list(
      objective = sprintf("CAGR improvement: gap %.1f%%p — new alpha source or reduced cash drag", cagr_gap * 100),
      hypothesis = "New independent alpha sleeve or less aggressive regime cashout may improve CAGR",
      task_family = "alpha_search",
      exploration_mode = "orthogonal",
      expected_gain_axis = "Ret",
      priority_score = 0.80,
      source = "gap_cagr"
    )
  }

  # F4. Passing family extensions (exploit proven families)
  for (pf in head(setdiff(passing_families, cooldown_families), 2)) {
    fam_trials <- fam_data[[pf]]$trial_count %||% 0
    if (fam_trials < 5) {
      hypotheses[[length(hypotheses) + 1]] <- list(
        objective = sprintf("Extend '%s' family: %d trials, has PASS — try alternative construction", pf, fam_trials),
        hypothesis = sprintf("Family '%s' has demonstrated edge — unexplored constructions may improve", pf),
        task_family = pf,
        exploration_mode = "exploit",
        expected_gain_axis = "Ret",
        priority_score = 0.75,
        source = "family_extension"
      )
    }
  }

  # F5. Failing family pivots
  for (ff in head(failing_families, 1)) {
    if (!(ff %in% cooldown_families)) {
      hypotheses[[length(hypotheses) + 1]] <- list(
        objective = sprintf("Pivot from '%s' (fail_streak=%d): try orthogonal approach", ff, fam_data[[ff]]$fail_streak %||% 0),
        hypothesis = sprintf("Family '%s' keeps failing — pivot to orthogonal alpha or change construction entirely", ff),
        task_family = ff,
        exploration_mode = "counterfactual",
        expected_gain_axis = "Div",
        priority_score = 0.60,
        source = "family_pivot"
      )
    }
  }

  # Filter cooldown families and sort by priority
  hypotheses <- Filter(function(h) !(h$task_family %in% cooldown_families), hypotheses)
  hypotheses <- hypotheses[order(-sapply(hypotheses, function(h) h$priority_score %||% 0))]
  if (length(hypotheses) > n) hypotheses <- hypotheses[seq_len(n)]

  # Format and register
  items <- lapply(hypotheses, function(h) {
    h$chunk_id <- paste0("LOOP_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", sample(1000:9999, 1))
    h$assignee <- "strategy_builder"
    h$cost_estimate <- "med"
    h$created_at <- .li_timestamp()
    h$status <- "pending"
    h$auto_generated <- TRUE
    h
  })

  # Append to backlog
  if (length(items) > 0) {
    bl_path <- file.path(.LI_REGISTRY, "backlog.json")
    existing <- .li_read_json(bl_path)
    if (is.null(existing)) existing <- list()
    combined <- c(existing, items)
    .li_write_json(combined, bl_path)
    cat(sprintf("  Registered %d hypotheses in backlog (total: %d)\n",
        length(items), length(combined)))
  }

  # Display
  cat("\n  Generated hypotheses:\n")
  for (i in seq_along(items)) {
    h <- items[[i]]
    cat(sprintf("  [%d] Priority %.2f | %s | %s\n",
        i, h$priority_score, h$source, h$objective))
  }
  cat("\n")

  invisible(items)
}


# =============================================================================
# 4. loop_check_direction() — 방향 전환 검사
# =============================================================================

#' Check if a family has failed too many times and suggest a pivot
#' @param family_name Family to check
#' @param max_fail_streak Maximum allowed consecutive failures (default 3)
#' @return List with should_pivot, suggestion, and inspiration from other families
#' @export
loop_check_direction <- function(family_name, max_fail_streak = 3) {
  cat(sprintf("\n--- Direction Check: %s ---\n", family_name))

  fam_data <- .li_read_json(file.path(.LI_REGISTRY, "families.json"))
  if (is.null(fam_data) || is.null(fam_data[[family_name]])) {
    cat(sprintf("  Family '%s' not found in tracker.\n", family_name))
    return(invisible(list(should_pivot = FALSE, reason = "not_found")))
  }

  fam <- fam_data[[family_name]]
  streak <- fam$fail_streak %||% 0
  trials <- fam$trial_count %||% 0
  passes <- fam$pass_count %||% 0

  cat(sprintf("  Trials: %d | Passes: %d | Fail streak: %d / %d max\n",
      trials, passes, streak, max_fail_streak))

  if (streak < max_fail_streak) {
    cat(sprintf("  Result: CONTINUE (fail_streak %d < %d)\n\n", streak, max_fail_streak))
    return(invisible(list(
      should_pivot = FALSE,
      reason = "below_threshold",
      fail_streak = streak
    )))
  }

  cat(sprintf("  PIVOT RECOMMENDED: fail_streak %d >= %d\n", streak, max_fail_streak))

  # Find inspiration from successful families
  inspiration <- list()
  passing_fams <- names(Filter(function(f) (f$pass_count %||% 0) > 0, fam_data))
  passing_fams <- setdiff(passing_fams, family_name)

  if (length(passing_fams) > 0) {
    cat("  Inspiration from successful families:\n")
    for (pf in head(passing_fams, 3)) {
      pfam <- fam_data[[pf]]
      cat(sprintf("    - '%s': %d passes / %d trials\n",
          pf, pfam$pass_count %||% 0, pfam$trial_count %||% 0))
      inspiration[[pf]] <- list(
        passes = pfam$pass_count %||% 0,
        trials = pfam$trial_count %||% 0
      )
    }
  }

  # Check _deleted_FreshIdea for family dossier
  dossier_dir <- file.path(.LI_FRESHIDEA, "08_Family_Dossiers")
  dossier_msg <- NULL
  if (dir.exists(dossier_dir)) {
    dossier_files <- list.files(dossier_dir, pattern = "^FAMILY_.*\\.md$", full.names = TRUE)
    for (df in dossier_files) {
      if (grepl(gsub("_", ".*", family_name), basename(df), ignore.case = TRUE)) {
        lines <- tryCatch(readLines(df, warn = FALSE, n = 10), error = function(e) character(0))
        content <- lines[!grepl("^#|^$|^---", lines)]
        if (length(content) > 0) {
          dossier_msg <- trimws(content[1])
          cat(sprintf("  _deleted_FreshIdea dossier: %s\n", dossier_msg))
        }
        break
      }
    }
  }

  suggestions <- c(
    sprintf("Stop exploring '%s' — %d consecutive failures indicate structural limitation.", family_name, streak),
    "Consider: (1) orthogonal alpha source, (2) different market microstructure signal, (3) ensemble with proven families."
  )
  cat("  ", paste(suggestions, collapse = "\n  "), "\n\n")

  invisible(list(
    should_pivot = TRUE,
    reason = "fail_streak_exceeded",
    fail_streak = streak,
    trials = trials,
    passes = passes,
    inspiration = inspiration,
    dossier = dossier_msg,
    suggestions = suggestions
  ))
}


# =============================================================================
# 5. loop_status() — 전체 루프 현황
# =============================================================================

#' Full loop status report: memory, registry, _deleted_FreshIdea, pipeline
#' @return Invisible status list
#' @export
loop_status <- function() {
  cat("\n")
  cat("===================================================================\n")
  cat("  LOOP INTEGRATOR — Full Status Report\n")
  cat("  ", format(Sys.time(), "%Y-%m-%d %H:%M KST"), "\n")
  cat("===================================================================\n\n")

  status <- list()

  # --- A. Memory health ---
  cat("[Memory Health]\n")
  mem_files <- c(
    "MEMORY.md", "methodology_memory.md", "strategy_catalog.md",
    "infrastructure_state.md", "evolution_roadmap.md"
  )
  for (mf in mem_files) {
    mf_path <- file.path(.LI_CLAUDE_MEM, mf)
    if (file.exists(mf_path)) {
      info <- file.info(mf_path)
      age_hours <- as.numeric(difftime(Sys.time(), info$mtime, units = "hours"))
      lines <- length(readLines(mf_path, warn = FALSE))
      freshness <- if (age_hours < 24) "FRESH" else if (age_hours < 72) "OK" else "STALE"
      cat(sprintf("  %-30s %5d lines | %.0fh ago | %s\n", mf, lines, age_hours, freshness))
      status[[paste0("mem_", gsub("\\.md$", "", mf))]] <- list(
        lines = lines, age_hours = round(age_hours, 1), freshness = freshness)
    } else {
      cat(sprintf("  %-30s MISSING\n", mf))
    }
  }

  # L-code count
  meth_path <- file.path(.LI_CLAUDE_MEM, "methodology_memory.md")
  l_count <- 0
  if (file.exists(meth_path)) {
    lines <- readLines(meth_path, warn = FALSE)
    l_count <- length(grep("^### L-\\d+:", lines))
  }
  cat(sprintf("  L-codes: %d total\n", l_count))
  status$l_code_count <- l_count

  # --- B. Registry health ---
  cat("\n[Registry Health]\n")
  exps <- .li_read_json(file.path(.LI_REGISTRY, "experiments.json"))
  if (is.null(exps)) exps <- list()
  grades <- sapply(exps, function(e) e$grade %||% "F")
  grade_tab <- table(factor(grades, levels = c("A", "B", "C", "F")))
  cat(sprintf("  Strategies: %d total | A:%d B:%d C:%d F:%d\n",
      length(exps), grade_tab["A"], grade_tab["B"], grade_tab["C"], grade_tab["F"]))
  status$registry <- list(total = length(exps), grades = as.list(grade_tab))

  # Recent additions (last 5)
  if (length(exps) > 0) {
    dates <- sapply(exps, function(e) e$registered_at %||% e$timestamp %||% "")
    recent_idx <- tail(order(dates), 5)
    cat("  Recent:\n")
    for (idx in rev(recent_idx)) {
      e <- exps[[idx]]
      cat(sprintf("    %s: Grade %s (%.1f)\n",
          e$strategy_id %||% "?", e$grade %||% "?",
          as.numeric(e$score %||% e$total_score %||% 0)))
    }
  }

  # --- C. _deleted_FreshIdea health ---
  cat("\n[_deleted_FreshIdea Health]\n")
  fi_dirs <- c(
    "01_Mad_Reviews", "02_Lens_Ledger", "03_Mutation_Seeds",
    "05_Long_Memory", "06_Auto_Eval", "08_Family_Dossiers",
    "10_Seed_Canon", "13_Anti_Seed_Canon"
  )
  fi_counts <- list()
  for (fd in fi_dirs) {
    fd_path <- file.path(.LI_FRESHIDEA, fd)
    count <- if (dir.exists(fd_path)) length(list.files(fd_path, pattern = "\\.(md|json)$")) else 0
    fi_counts[[fd]] <- count
    cat(sprintf("  %-25s %3d files\n", fd, count))
  }
  status$freshidea <- fi_counts

  # --- D. Pipeline status ---
  cat("\n[Pipeline]\n")
  backlog <- .li_read_json(file.path(.LI_REGISTRY, "backlog.json"))
  if (is.null(backlog)) backlog <- list()
  pending <- Filter(function(b) (b$status %||% "pending") == "pending", backlog)
  completed <- Filter(function(b) (b$status %||% "") == "completed", backlog)
  cat(sprintf("  Backlog: %d total | %d pending | %d completed\n",
      length(backlog), length(pending), length(completed)))
  status$pipeline <- list(backlog_total = length(backlog),
                           pending = length(pending), completed = length(completed))

  # QEPM memory layers
  layers <- c("raw_artifacts", "episodes", "families", "evidence", "regime_payoff",
              "portfolio_policy", "post_trade")
  layer_names <- c("R0", "R1", "R2", "R3", "R4", "R5", "R6")
  cat("  QEPM Memory Layers:\n")
  for (i in seq_along(layers)) {
    ldir <- file.path(.LI_MEMORY, layers[i])
    count <- if (dir.exists(ldir)) length(list.files(ldir, recursive = TRUE)) else 0
    cat(sprintf("    %s (%s): %d\n", layer_names[i], layers[i], count))
  }

  # --- E. Family direction summary ---
  cat("\n[Family Direction]\n")
  fam_data <- .li_read_json(file.path(.LI_REGISTRY, "families.json"))
  if (!is.null(fam_data) && length(fam_data) > 0) {
    for (fn in names(fam_data)) {
      f <- fam_data[[fn]]
      streak <- f$fail_streak %||% 0
      passes <- f$pass_count %||% 0
      trials <- f$trial_count %||% 0
      flag <- if (streak >= 3) "PIVOT" else if (streak >= 2) "CAUTION" else "OK"
      cat(sprintf("  %-25s trials=%2d pass=%2d fail_streak=%d [%s]\n",
          fn, trials, passes, streak, flag))
    }
  }

  cat("\n===================================================================\n\n")
  invisible(status)
}


cat("[loop_integrator.R] Loaded. Functions:\n")
cat("  loop_session_brief()                          — Session start briefing\n")
cat("  loop_post_strategy_review(strategy_id, hr)    — _deleted_FreshIdea hostile review\n")
cat("  loop_generate_hypotheses(n = 5)               — Auto-generate hypotheses\n")
cat("  loop_check_direction(family, max_fail = 3)    — Direction change check\n")
cat("  loop_status()                                 — Full status report\n")
