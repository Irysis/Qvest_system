#==============================================================================
# Quant Module — LLM-Based Report Agent Launcher
# report_agent_llm.R
#
# Claude Agent를 스폰하여 전략 서술을 LLM이 직접 작성.
# 차트는 R이 렌더링, 서술은 LLM이 생성 → JSON 저장 → Rmd 조립.
#
# Usage:
#   source("02_Infrastructure/report_agent_llm.R")
#   launch_reporter("STR_904")
#   launch_reporter("STR_904", lang = c("en", "kr"))
#
# 이 함수는 Claude Code 세션 내에서만 호출 가능 (Agent tool 사용).
# R standalone으로는 fallback으로 report_agent.R 사용.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")

cat("[report_agent_llm] Loaded.\n")

#' Prepare report data bundle for Reporter Agent
#' Collects all data the LLM needs into a single JSON
prepare_report_bundle <- function(strategy_id, output_dir = NULL) {

  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  candidates <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matched <- candidates[grepl(strategy_id, basename(candidates), fixed = TRUE)]
  if (length(matched) == 0) stop(sprintf("Strategy %s not found", strategy_id))
  strat_dir <- matched[which.max(file.mtime(matched))]

  # Find output dir
  out_candidates <- c(
    file.path(strat_dir, "output", strategy_id),
    file.path(strat_dir, "output")
  )
  out_dir <- NULL
  for (oc in out_candidates) {
    if (dir.exists(oc) && file.exists(file.path(oc, "hurdle_result.json"))) {
      out_dir <- oc; break
    }
  }
  if (is.null(out_dir)) out_dir <- file.path(strat_dir, "output")
  if (!is.null(output_dir)) out_dir <- output_dir

  # Read run_all.R (first 200 lines for context)
  run_all_path <- file.path(strat_dir, "run_all.R")
  run_all_code <- if (file.exists(run_all_path)) {
    paste(head(readLines(run_all_path, warn = FALSE), 200), collapse = "\n")
  } else ""

  # Read hurdle_result.json
  hr_path <- file.path(out_dir, "hurdle_result.json")
  hurdle <- if (file.exists(hr_path)) fromJSON(hr_path, simplifyVector = FALSE) else list()

  # Read performance.csv
  perf_path <- file.path(out_dir, "performance.csv")
  perf <- if (file.exists(perf_path)) as.list(fread(perf_path)[1]) else list()

  # Read multifactor
  mf_path <- file.path(out_dir, "analysis_multifactor.csv")
  mf <- if (file.exists(mf_path)) {
    as.list(fread(mf_path))
  } else list()

  # Read stress
  stress_path <- file.path(out_dir, "analysis_stress.csv")
  stress <- if (file.exists(stress_path)) {
    lapply(seq_len(nrow(fread(stress_path))), function(i) as.list(fread(stress_path)[i]))
  } else list()

  # Sleeve detection
  sleeve_files <- list.files(strat_dir, pattern = "^sim_sleeve_.*\\.rds$")
  sleeve_names <- gsub("sim_sleeve_|\\.rds$", "", sleeve_files)

  # Classify
  source(file.path(REPORTS_DIR, "report_narrative.R"))
  cls <- classify_strategy(run_all_path)

  bundle <- list(
    strategy_id = strategy_id,
    strat_dir = strat_dir,
    output_dir = out_dir,
    classification = cls,
    hurdle = hurdle,
    performance = perf,
    multifactor = mf,
    stress = stress,
    sleeve_names = sleeve_names,
    run_all_code_preview = run_all_code
  )

  # Save bundle
  bundle_path <- file.path(out_dir, "report_bundle.json")
  write_json(bundle, bundle_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[report_agent_llm] Bundle saved: %s\n", bundle_path))

  bundle
}

#' Cleanup old reports from strategy directory
cleanup_old_reports <- function(strategy_id) {
  dirs_to_clean <- c()

  # Research output
  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  candidates <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matched <- candidates[grepl(strategy_id, basename(candidates), fixed = TRUE)]
  if (length(matched) > 0) {
    dirs_to_clean <- c(dirs_to_clean,
                       file.path(matched, "output"),
                       matched)
  }

  # Production
  prod_base <- file.path(PROJECT_ROOT, "05_Production", "2.Factor_Model")
  if (dir.exists(prod_base)) {
    prod_dirs <- list.dirs(prod_base, recursive = FALSE, full.names = TRUE)
    prod_match <- prod_dirs[grepl(strategy_id, basename(prod_dirs))]
    for (pd in prod_match) {
      dirs_to_clean <- c(dirs_to_clean, pd, file.path(pd, "output"))
    }
  }

  n_removed <- 0L
  for (d in unique(dirs_to_clean)) {
    if (!dir.exists(d)) next
    old_files <- list.files(d, pattern = "(Report|AgentReport).*\\.(html|Rmd|pdf)$",
                            full.names = TRUE, recursive = FALSE)
    # Also clean narrative JSON
    old_files <- c(old_files,
                   list.files(d, pattern = "report_narrative.*\\.json$",
                              full.names = TRUE, recursive = FALSE))
    if (length(old_files) > 0) {
      file.remove(old_files)
      n_removed <- n_removed + length(old_files)
    }
  }
  cat(sprintf("[report_agent_llm] Cleaned up %d old report files for %s\n",
              n_removed, strategy_id))
  invisible(n_removed)
}

#' Render final HTML from narrative JSON + charts
#' Called after Reporter Agent writes narrative JSON
render_report <- function(strategy_id, output_dir = NULL, lang = "en") {

  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  candidates <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matched <- candidates[grepl(strategy_id, basename(candidates), fixed = TRUE)]
  strat_dir <- matched[which.max(file.mtime(matched))]

  if (is.null(output_dir)) {
    out_candidates <- c(
      file.path(strat_dir, "output", strategy_id),
      file.path(strat_dir, "output")
    )
    for (oc in out_candidates) {
      if (dir.exists(oc) && file.exists(file.path(oc, "hurdle_result.json"))) {
        output_dir <- oc; break
      }
    }
    if (is.null(output_dir)) output_dir <- file.path(strat_dir, "output")
  }

  # Load narrative JSON (written by Reporter Agent)
  narr_path <- file.path(output_dir, sprintf("report_narrative_%s.json", lang))
  if (!file.exists(narr_path)) {
    cat(sprintf("[render] Narrative not found: %s\n", narr_path))
    return(invisible(NULL))
  }
  narrative <- fromJSON(narr_path, simplifyVector = FALSE)

  # Load classification
  source(file.path(REPORTS_DIR, "report_narrative.R"))
  cls <- classify_strategy(file.path(strat_dir, "run_all.R"))
  viz_list <- select_visualizations(cls)

  # Copy CSS
  css_src <- file.path(INFRA_DIR, "report_templates", "report_style.css")
  css_dst <- file.path(output_dir, "report_style.css")
  if (file.exists(css_src)) file.copy(css_src, css_dst, overwrite = TRUE)

  # Render
  template_path <- file.path(INFRA_DIR, "report_templates", "report_base.Rmd")
  out_rmd <- file.path(output_dir, sprintf("%s_Report_%s.Rmd", strategy_id, toupper(lang)))
  file.copy(template_path, out_rmd, overwrite = TRUE)
  out_html <- sub("\\.Rmd$", ".html", out_rmd)

  source(file.path(REPORTS_DIR, "report_charts.R"))

  render_ok <- tryCatch({
    .pandoc_dir <- "/home/quant/.local/share/r-pandoc/3.9/pandoc-3.9/bin"; if (dir.exists(.pandoc_dir)) Sys.setenv(RSTUDIO_PANDOC = .pandoc_dir)  # 조건부 (2026-06-10 fix: 죽은 WSL 경로 무조건 setenv 제거)
    rmarkdown::render(
      out_rmd, output_file = basename(out_html),
      params = list(
        strategy_id = strategy_id, strat_dir = strat_dir,
        output_dir = output_dir, lang = lang, viz_list = viz_list,
        narrative_json = toJSON(narrative, auto_unbox = TRUE),
        classification_json = toJSON(cls, auto_unbox = TRUE)
      ), quiet = TRUE)
    TRUE
  }, error = function(e) { cat(sprintf("[render] Error: %s\n", e$message)); FALSE })

  if (render_ok && file.exists(out_html)) {
    # Copy to production if exists
    prod_base <- file.path(PROJECT_ROOT, "05_Production", "2.Factor_Model")
    if (dir.exists(prod_base)) {
      prod_dirs <- list.dirs(prod_base, recursive = FALSE, full.names = TRUE)
      prod_match <- prod_dirs[grepl(strategy_id, basename(prod_dirs))]
      for (pd in prod_match) {
        file.copy(out_html, file.path(pd, basename(out_html)), overwrite = TRUE)
        file.copy(out_html, file.path(pd, "output", basename(out_html)), overwrite = TRUE)
      }
    }
    cat(sprintf("[render] SUCCESS: %s (%s)\n", basename(out_html),
                format(file.size(out_html), big.mark = ",")))
  }
  invisible(out_html)
}

cat("[report_agent_llm] Functions: prepare_report_bundle(), cleanup_old_reports(), render_report()\n")
cat("[report_agent_llm] Reporter Agent는 Q-Lead가 Agent tool로 스폰합니다.\n")
