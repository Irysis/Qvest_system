#!/usr/bin/env Rscript
# Build an execution plan from the prioritized strategy pool.
# The inbox_hold JSON files are mostly Forge contracts, not directly runnable code.
# This script separates already-runnable candidates from specs that need build work.

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

args <- commandArgs(trailingOnly = TRUE)
pool_csv <- if (length(args) >= 1L) args[[1]] else {
  Sys.glob("stage_artifacts/reports/prioritized_strategy_pool_*.csv") |>
    sort(decreasing = TRUE) |>
    head(1L)
}
if (!length(pool_csv) || !file.exists(pool_csv)) {
  stop("prioritized strategy pool CSV not found")
}

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
date_tag <- Sys.getenv("QVEST_BATCH_TAG", format(Sys.Date(), "%Y%m%d"))
date_tag <- gsub("[^A-Za-z0-9_.-]", "_", date_tag)
out_dir <- file.path(root, "stage_artifacts", "batch_434", date_tag)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pool <- read.csv(pool_csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
loose_status <- c(
  "KEEP", "KEEP_RESCOPED", "KEEP_ARCH_OVERLAY", "KEEP_DATA_FIRST",
  "KEEP_ML", "KEEP_RERUN", "KEEP_DIAGNOSTIC", "LOW_KNOWN_WEAK"
)
if (isTRUE(tolower(Sys.getenv("QVEST_INCLUDE_DONE_OR_CONSUMED", "false")) %in% c("1", "true", "yes"))) {
  loose_status <- c(loose_status, "DONE_OR_CONSUMED")
}
pool <- pool[pool$status %in% loose_status, , drop = FALSE]

read_json <- function(file) {
  path <- file.path(root, "qepm", "mailbox", "forge", "inbox_hold", file)
  if (!file.exists(path)) return(list())
  tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) list(.error = e$message))
}

find_strategy_run_all <- function(item_id) {
  if (!grepl("^STR_[0-9]+", item_id %||% "")) return(NA_character_)
  hits <- Sys.glob(file.path(root, "04_Research", "strategies", paste0(item_id, "*"), "run_all.R"))
  if (length(hits)) normalizePath(hits[[1]], winslash = "/", mustWork = FALSE) else NA_character_
}

alpha_exact_fe_map <- c(
  ALPHA_12 = "02_Infrastructure/alpha_search/fe_52whigh.R"
)

alpha_proxy_fe_map <- c(
  ALPHA_07 = "02_Infrastructure/alpha_search/fe_leadlag_network.R",
  ALPHA_22 = "02_Infrastructure/alpha_search/fe_amihud.R"
)

alpha_name_map <- c(
  ALPHA_07 = "Analyst Co-Coverage Lead-Lag Momentum",
  ALPHA_12 = "52-Week High Anchor Momentum",
  ALPHA_22 = "Modified Amihud Liquidity"
)

alpha_single_map <- c(
  ALPHA_04 = "M05_Trended_Mom",
  ALPHA_05 = "R05_Tail_Risk",
  ALPHA_06 = "AC07_Operating_Accruals",
  ALPHA_08 = "INV01_Foreign_NetBuy_20d",
  ALPHA_09 = "V24_Residual_Income",
  ALPHA_10 = "Q01_GPA",
  ALPHA_11 = "GR03_Asset_Growth",
  ALPHA_13 = "V03_CFP",
  ALPHA_14 = "Q04_Piotroski_F",
  ALPHA_16 = "Q12_Asset_Turnover",
  ALPHA_17 = "V11_Shareholder_Yield"
)

alpha_single_name_map <- c(
  ALPHA_04 = "Trended Momentum",
  ALPHA_05 = "Tail Quantile Risk",
  ALPHA_06 = "Accruals Quality",
  ALPHA_08 = "Investor Flow Foreign NetBuy",
  ALPHA_09 = "Residual Income V/P",
  ALPHA_10 = "Gross Profitability",
  ALPHA_11 = "Asset Growth",
  ALPHA_13 = "Cash Flow Yield",
  ALPHA_14 = "Piotroski F-Score",
  ALPHA_16 = "Efficiency Asset Turnover",
  ALPHA_17 = "Shareholder Yield"
)

pool_single_map <- c(
  SF_02_cfyield_overlay = "V03_CFP",
  SF_28_value_only_brk = "V03_CFP",
  SF_39_value_mrs1225 = "V03_CFP",
  SF_06_sue_pure_overlay = "C01_SUE",
  SF_43_sue_mrs1225 = "C01_SUE",
  SF_32_indmom_brk = "M07_IndMom",
  SF_38_indmom_mrs1225 = "M07_IndMom",
  SF_54_es_factor = "D47_CVaR_5pct",
  SF_58_rev_breadth = "C04_ESBR",
  MF_KKK1_VOL_OF_VOL = "D41_Vol_of_Vol"
)

pool_fe_map <- c(
  SF_35_rev_brk = "02_Infrastructure/alpha_search/fe_streversal.R",
  SF_42_rev_mrs1225 = "02_Infrastructure/alpha_search/fe_streversal.R",
  SF_53_resid_mom = "02_Infrastructure/alpha_search/fe_residmom.R"
)

pool_fe_name_map <- c(
  SF_35_rev_brk = "Short-Term Reversal Base Signal",
  SF_42_rev_mrs1225 = "Short-Term Reversal Base Signal",
  SF_53_resid_mom = "Residual Momentum Base Signal"
)

classify_one <- function(i) {
  r <- pool[i, , drop = FALSE]
  item_id <- r$item_id
  status <- r$status
  file <- r$file
  js <- read_json(file)
  cmd <- js$cmd %||% r$bucket %||% ""

  execution_class <- "BUILD_THEN_RUN"
  runnable_command <- NA_character_
  run_dir <- root
  reason <- "Forge contract/spec requires code generation before backtest"
  mapping_quality <- "BUILD_REQUIRED"
  mapping_notes <- reason

  if (identical(status, "KEEP_DATA_FIRST")) {
    execution_class <- "DATA_FIRST"
    reason <- "requires external/cache data collection or validation before backtest"
    mapping_quality <- "DATA_REQUIRED"
  } else if (identical(status, "KEEP_DIAGNOSTIC")) {
    execution_class <- "DIAGNOSTIC_BUILD_THEN_RUN"
    reason <- "diagnostic/sweep spec; code or target artifacts must be prepared"
    mapping_quality <- "DIAGNOSTIC_SPEC"
  } else if (identical(status, "KEEP_ML")) {
    execution_class <- "ML_BUILD_THEN_RUN"
    reason <- "ML spec; requires model pipeline setup and heavier validation"
    mapping_quality <- "ML_SPEC"
  } else if (identical(status, "LOW_KNOWN_WEAK")) {
    execution_class <- "LOW_PRIORITY_RUN"
    reason <- r$reason %||% "known weak evidence; run only after high-priority queue"
    mapping_quality <- "LOW_PRIORITY_SPEC"
  }
  mapping_notes <- reason

  # Expanded msg_005 rerun items: only run if the target directory exists.
  if (identical(r$prefix, "MSG_RERUN")) {
    target <- switch(item_id,
      STR_1035 = "04_Research/strategies/STR_1035_oas_minvar/run_all.R",
      STR_1033 = "04_Research/strategies/STR_1033_nco/run_all.R",
      STR_1030 = "04_Research/strategies/STR_1030_gerber_bl_hybrid/run_all.R",
      NA_character_
    )
    if (!is.na(target) && file.exists(file.path(root, target))) {
      execution_class <- "RUN_EXISTING_R"
      run_dir <- dirname(file.path(root, target))
      runnable_command <- "Rscript -e 'source(\"run_all.R\")'"
      reason <- "existing strategy run_all.R found"
      mapping_quality <- "EXISTING_STRATEGY_RUNNER"
    } else {
      execution_class <- "MISSING_BASE_CODE"
      reason <- "rerun requested but target strategy directory/run_all.R is missing"
      mapping_quality <- "MISSING_BASE_CODE"
    }
    mapping_notes <- reason
  }

  # Generic existing STR_* strategy directory detection.
  existing_run_all <- find_strategy_run_all(item_id)
  if (is.na(runnable_command) && !is.na(existing_run_all)) {
    execution_class <- "RUN_EXISTING_R"
    run_dir <- dirname(existing_run_all)
    runnable_command <- "Rscript -e 'source(\"run_all.R\")'"
    reason <- "existing strategy run_all.R found by STR id"
    mapping_quality <- "EXISTING_STRATEGY_RUNNER"
    mapping_notes <- reason
  }

  # A few alpha specs have existing alpha_search factor engines.
  if (is.na(runnable_command) && item_id %in% names(alpha_exact_fe_map)) {
    fe <- alpha_exact_fe_map[[item_id]]
    if (file.exists(file.path(root, fe))) {
      sname <- alpha_name_map[[item_id]]
      idea <- gsub("'", "", r$title %||% sname)
      execution_class <- "RUN_ALPHA_SEARCH_FE"
      runnable_command <- sprintf(
        paste0(
          "Rscript -e 'source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
          "res <- run_alpha_search(strategy_name=\"%s\", strategy_idea=\"%s\", ",
          "factor_engine_path=\"%s\", weight_method=\"equal\", universe=\"ALL\", ",
          "send_telegram=TRUE, tg_dry_run=FALSE, factor_analysis=TRUE); ",
          "saveRDS(res, file.path(\"stage_artifacts\", \"batch_434\", \"%s\", \"%s_result.rds\"))'"
        ),
        sname, idea, fe, date_tag, item_id
      )
      reason <- "existing alpha_search factor engine mapped"
      mapping_quality <- "EXACT_FACTOR_ENGINE"
      mapping_notes <- reason
    }
  }

  if (is.na(runnable_command) && item_id %in% names(alpha_proxy_fe_map)) {
    fe <- alpha_proxy_fe_map[[item_id]]
    if (file.exists(file.path(root, fe))) {
      sname <- alpha_name_map[[item_id]]
      idea <- gsub("'", "", r$title %||% sname)
      execution_class <- "RUN_ALPHA_SEARCH_FE"
      runnable_command <- sprintf(
        paste0(
          "Rscript -e 'source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
          "res <- run_alpha_search(strategy_name=\"%s\", strategy_idea=\"%s\", ",
          "factor_engine_path=\"%s\", weight_method=\"equal\", universe=\"ALL\", ",
          "send_telegram=TRUE, tg_dry_run=FALSE, factor_analysis=TRUE); ",
          "saveRDS(res, file.path(\"stage_artifacts\", \"batch_434\", \"%s\", \"%s_result.rds\"))'"
        ),
        sname, idea, fe, date_tag, item_id
      )
      reason <- "proxy factor engine mapped; not exact source spec"
      mapping_quality <- "PROXY_SPEC_MISMATCH"
      mapping_notes <- if (identical(item_id, "ALPHA_07")) {
        "proxy: existing engine is price lead-lag network, while source spec asks analyst co-coverage lead-lag"
      } else {
        "proxy: existing engine is standard Amihud, while source spec asks modified AdjILLIQ"
      }
    }
  }

  if (is.na(runnable_command) && item_id %in% names(alpha_single_map)) {
    factor_name <- alpha_single_map[[item_id]]
    sname <- alpha_single_name_map[[item_id]]
    idea <- gsub("'", "", r$title %||% sname)
    execution_class <- "RUN_ALPHA_SINGLE_FACTOR"
    runnable_command <- sprintf(
      paste0(
        "FACTOR_NAME=%s Rscript -e 'source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
        "res <- run_alpha_search(strategy_name=\"%s\", strategy_idea=\"%s\", ",
        "factor_engine_path=\"02_Infrastructure/alpha_search/fe_single.R\", ",
        "weight_method=\"equal\", universe=\"ALL\", send_telegram=TRUE, tg_dry_run=FALSE, ",
        "factor_analysis=TRUE); ",
        "saveRDS(res, file.path(\"stage_artifacts\", \"batch_434\", \"%s\", \"%s_result.rds\"))'"
      ),
      shQuote(factor_name), sname, idea, date_tag, item_id
    )
    reason <- sprintf("factor DB single factor mapped via fe_single.R (%s)", factor_name)
    mapping_quality <- "EXACT_SINGLE_FACTOR"
    mapping_notes <- reason
  }

  if (is.na(runnable_command) && item_id %in% names(pool_single_map)) {
    factor_name <- pool_single_map[[item_id]]
    sname <- gsub("'", "", r$title %||% item_id)
    idea <- sname
    execution_class <- "RUN_ALPHA_SINGLE_FACTOR"
    runnable_command <- sprintf(
      paste0(
        "FACTOR_NAME=%s Rscript -e 'source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
        "res <- run_alpha_search(strategy_name=\"%s\", strategy_idea=\"%s\", ",
        "factor_engine_path=\"02_Infrastructure/alpha_search/fe_single.R\", ",
        "weight_method=\"equal\", universe=\"ALL\", send_telegram=TRUE, tg_dry_run=FALSE, ",
        "factor_analysis=TRUE); ",
        "saveRDS(res, file.path(\"stage_artifacts\", \"batch_434\", \"%s\", \"%s_result.rds\"))'"
      ),
      shQuote(factor_name), sname, idea, date_tag, item_id
    )
    reason <- sprintf("base signal mapped via fe_single.R (%s); overlays/portfolio wrappers excluded", factor_name)
    mapping_quality <- "BASE_SIGNAL_ONLY"
    mapping_notes <- reason
  }

  if (is.na(runnable_command) && item_id %in% names(pool_fe_map)) {
    fe <- pool_fe_map[[item_id]]
    if (file.exists(file.path(root, fe))) {
      sname <- pool_fe_name_map[[item_id]] %||% gsub("'", "", r$title %||% item_id)
      idea <- gsub("'", "", r$title %||% sname)
      execution_class <- "RUN_ALPHA_SEARCH_FE"
      runnable_command <- sprintf(
        paste0(
          "Rscript -e 'source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
          "res <- run_alpha_search(strategy_name=\"%s\", strategy_idea=\"%s\", ",
          "factor_engine_path=\"%s\", weight_method=\"equal\", universe=\"ALL\", ",
          "send_telegram=TRUE, tg_dry_run=FALSE, factor_analysis=TRUE); ",
          "saveRDS(res, file.path(\"stage_artifacts\", \"batch_434\", \"%s\", \"%s_result.rds\"))'"
        ),
        sname, idea, fe, date_tag, item_id
      )
      reason <- "base factor engine mapped; overlays/portfolio wrappers excluded"
      mapping_quality <- "BASE_SIGNAL_ONLY"
      mapping_notes <- reason
    }
  }

  data.frame(
    status = status,
    item_id = item_id,
    priority_score = r$priority_score,
    bucket = r$bucket,
    prefix = r$prefix,
    family = r$family,
    execution_class = execution_class,
    run_dir = run_dir,
    runnable_command = runnable_command,
    title = r$title,
    file = file,
    reason = reason,
    mapping_quality = mapping_quality,
    mapping_notes = mapping_notes,
    stringsAsFactors = FALSE
  )
}

plan <- do.call(rbind, lapply(seq_len(nrow(pool)), classify_one))
class_rank <- c(
  RUN_EXISTING_R = 1, RUN_ALPHA_SEARCH_FE = 2, BUILD_THEN_RUN = 3,
  RUN_ALPHA_SINGLE_FACTOR = 2, DIAGNOSTIC_BUILD_THEN_RUN = 4, DATA_FIRST = 5,
  ML_BUILD_THEN_RUN = 6, LOW_PRIORITY_RUN = 7, MISSING_BASE_CODE = 8
)
plan$class_rank <- class_rank[plan$execution_class]
plan$class_rank[is.na(plan$class_rank)] <- 99
plan$priority_sort <- suppressWarnings(as.numeric(plan$priority_score))
plan$priority_sort[is.na(plan$priority_sort)] <- -Inf
plan <- plan[order(plan$class_rank, -plan$priority_sort, plan$item_id), ]
plan$class_rank <- NULL
plan$priority_sort <- NULL

plan_csv <- file.path(out_dir, "execution_plan.csv")
ready_csv <- file.path(out_dir, "ready_commands.csv")
summary_csv <- file.path(out_dir, "execution_plan_summary.csv")
write.csv(plan, plan_csv, row.names = FALSE, fileEncoding = "UTF-8")
ready <- plan[!is.na(plan$runnable_command), , drop = FALSE]
write.csv(ready, ready_csv, row.names = FALSE, fileEncoding = "UTF-8")
summary <- as.data.frame(sort(table(plan$execution_class), decreasing = TRUE))
names(summary) <- c("execution_class", "n")
write.csv(summary, summary_csv, row.names = FALSE, fileEncoding = "UTF-8")

cat(sprintf("plan=%s\n", plan_csv))
cat(sprintf("ready=%s\n", ready_csv))
cat(sprintf("summary=%s\n", summary_csv))
print(summary, row.names = FALSE)
