#==============================================================================
# Promote to Production — Grade A 전략 프로덕션 승격
#
# Usage:
#   source("02_Infrastructure/promote_to_production.R")
#   promote_to_production("STR_952")
#   promote_to_production("STR_952", slot_name = "2-3.STR_952_Defense")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[promote_to_production] Loaded.\n")

#' Promote a Grade A strategy to 05_Production
#'
#' @param strategy_id  character: e.g. "STR_952"
#' @param slot_name    character: production slot name (auto-generated if NULL)
#' @param send_telegram logical: send notification (default TRUE)
#' @return invisible(list) promotion result
promote_to_production <- function(strategy_id, slot_name = NULL, send_telegram = TRUE) {

  cat(sprintf("\n[promote] Starting promotion for %s...\n", strategy_id))

  # ── 1. Find strategy directory ──
  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  candidates <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matched <- candidates[grepl(strategy_id, basename(candidates), fixed = TRUE)]

  if (length(matched) == 0) {
    stop(sprintf("[promote] Strategy %s not found in 04_Research/strategies/", strategy_id))
  }
  strat_dir <- matched[which.max(file.mtime(matched))]
  output_dir <- file.path(strat_dir, "output")

  # ── 2. Verify Grade A ──
  hurdle_path <- file.path(output_dir, "hurdle_result.json")
  if (!file.exists(hurdle_path)) {
    # Fallback: search recursively under strat_dir
    hurdle_candidates <- list.files(strat_dir, "hurdle_result.json",
                                    recursive = TRUE, full.names = TRUE)
    if (length(hurdle_candidates) > 0) {
      hurdle_path <- hurdle_candidates[which.max(file.mtime(hurdle_candidates))]
      output_dir <- dirname(hurdle_path)
      cat(sprintf("[promote] Found hurdle at: %s\n", hurdle_path))
    } else {
      stop(sprintf("[promote] hurdle_result.json not found for %s", strategy_id))
    }
  }
  hurdle <- fromJSON(hurdle_path, simplifyVector = FALSE)
  if ((hurdle$grade %||% "F") != "A") {
    stop(sprintf("[promote] %s is Grade %s, not A. Cannot promote.", strategy_id, hurdle$grade))
  }
  cat(sprintf("[promote] Verified: Grade A | Score %.1f | %s\n",
              hurdle$total_score %||% 0, hurdle$role %||% "core"))

  # ── 3. Determine production slot ──
  prod_base <- file.path(PROJECT_ROOT, "05_Production", "2.Factor_Model")
  if (!dir.exists(prod_base)) dir.create(prod_base, recursive = TRUE)

  if (is.null(slot_name)) {
    existing_slots <- list.dirs(prod_base, recursive = FALSE, full.names = FALSE)
    # "2-N." 패턴에서 N 추출
    sub_nums <- as.integer(gsub("^2-(\\d+)\\..*", "\\1", existing_slots))
    sub_nums <- sub_nums[!is.na(sub_nums)]
    next_sub <- if (length(sub_nums) > 0) max(sub_nums) + 1L else 1L
    strat_label <- gsub("^STR_\\d+_?", "", basename(strat_dir))
    if (nchar(strat_label) == 0) strat_label <- strategy_id
    slot_name <- sprintf("2-%d.%s_%s", next_sub, strategy_id, strat_label)
  }

  prod_dir <- file.path(prod_base, slot_name)
  if (dir.exists(prod_dir)) {
    cat(sprintf("[promote] WARNING: Slot %s already exists. Overwriting.\n", slot_name))
  }
  dir.create(prod_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 4. Copy files ──
  # Essential files from strategy directory
  essential_patterns <- c("run_all\\.R$", "sim_result\\.rds$", "sim_sleeve_.*\\.rds$",
                          "factor_engine\\.R$", "config.*\\.R$")
  strat_files <- list.files(strat_dir, full.names = TRUE, recursive = FALSE)
  for (pat in essential_patterns) {
    matches <- strat_files[grepl(pat, basename(strat_files))]
    for (f in matches) {
      file.copy(f, file.path(prod_dir, basename(f)), overwrite = TRUE)
      cat(sprintf("  Copied: %s\n", basename(f)))
    }
  }

  # Copy entire output directory
  prod_output <- file.path(prod_dir, "output")
  dir.create(prod_output, recursive = TRUE, showWarnings = FALSE)
  output_files <- list.files(output_dir, full.names = TRUE, recursive = FALSE)
  for (f in output_files) {
    file.copy(f, file.path(prod_output, basename(f)), overwrite = TRUE)
  }
  cat(sprintf("  Copied: output/ (%d files)\n", length(output_files)))

  # ── 5. Generate report (HTML only, no TG) ──
  report_gen_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "report_generator.R")
  reports_generated <- FALSE
  if (file.exists(report_gen_path)) {
    tryCatch({
      source(report_gen_path)
      generate_strategy_report(strategy_id, output_dir = prod_output,
                                send_telegram = FALSE)
      reports_generated <- TRUE
      cat("[promote] Reports generated (EN + KR HTML)\n")
    }, error = function(e) {
      cat(sprintf("[promote] Report generation skipped: %s\n", conditionMessage(e)))
    })
  }

  # ── 6. Telegram notification ──
  if (send_telegram) {
    tryCatch({
      tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R")
      if (!exists("tg_send") && file.exists(tg_path)) source(tg_path)
      if (exists("tg_send")) {
        m <- hurdle$metrics %||% list()
        tg_send(sprintf(
          "[PRODUCTION] %s promoted\nSlot: %s\nScore: %.1f | Grade: A | Role: %s\nCAGR: %.1f%% | SR: %.3f | MDD: %.1f%%",
          strategy_id, slot_name,
          hurdle$total_score %||% 0, hurdle$role %||% "core",
          as.numeric(m$CAGR %||% 0), as.numeric(m$Sharpe %||% 0),
          as.numeric(m$MDD %||% 0)
        ))
        cat("[promote] Telegram notification sent.\n")
      }
    }, error = function(e) cat(sprintf("[promote] TG error: %s\n", conditionMessage(e))))
  }

  result <- list(
    strategy_id = strategy_id,
    slot_name = slot_name,
    prod_dir = prod_dir,
    grade = "A",
    score = hurdle$total_score %||% 0,
    reports = reports_generated
  )

  cat(sprintf("\n[promote] %s -> %s COMPLETE\n\n", strategy_id, slot_name))
  invisible(result)
}
