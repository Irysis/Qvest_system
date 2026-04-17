#==============================================================================
# Experiment Contract — Lawbook v1.4.2 Ch.14
#
# Immutable record of what an experiment intends to test.
# Created BEFORE running any backtest. Prevents post-hoc rationalization.
#
# Fields:
#   - strategy_name, hypothesis, family, prior_evidence
#   - config (all backtest parameters)
#   - expected_outcome (predicted direction & magnitude)
#   - fingerprint, data_snapshot_id
#   - timestamp (creation)
#
# Usage:
#   source("experiment_contract.R")
#   contract <- create_contract("STR_999", hypothesis = "...", config = list(...))
#   save_contract(contract)
#   result <- attach_result(contract, hurdle_result)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

cat("[experiment_contract] Loaded.\n")

CONTRACT_DIR <- file.path(
  ifelse(exists("RESEARCH_REG"), RESEARCH_REG,
         "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/06_Registry"),
  "contracts"
)

#' Compute data snapshot ID from cache file modification times
compute_data_snapshot_id <- function() {
  cache_dir <- ifelse(exists("CACHE_DIR"), CACHE_DIR,
                      "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache")
  key_files <- c("RAWDATA.parquet", "benchmark.parquet", "fundamental_dart.parquet")
  mtimes <- sapply(file.path(cache_dir, key_files), function(f) {
    if (file.exists(f)) format(file.mtime(f), "%Y%m%d_%H%M") else "missing"
  })
  substr(digest(paste(mtimes, collapse = "|"), algo = "md5"), 1, 8)
}

#' Create an experiment contract
create_contract <- function(strategy_name,
                             hypothesis,
                             family = "unknown",
                             prior_evidence = list(),
                             config = list(),
                             expected_outcome = list(
                               direction = "positive",
                               cagr_range = c(10, 25),
                               sharpe_range = c(0.5, 1.5)
                             ),
                             notes = "") {

  fp <- if (exists("compute_fingerprint") && is.function(compute_fingerprint)) {
    compute_fingerprint(config)
  } else {
    substr(digest(config, algo = "md5"), 1, 8)
  }

  contract <- list(
    contract_version = "1.0",
    strategy_name    = strategy_name,
    hypothesis       = hypothesis,
    family           = family,
    prior_evidence   = prior_evidence,
    config           = config,
    expected_outcome = expected_outcome,
    fingerprint      = fp,
    data_snapshot_id = compute_data_snapshot_id(),
    notes            = notes,
    created_at       = format(Sys.time(), "%Y-%m-%d %H:%M:%S KST"),
    status           = "PENDING",
    result           = NULL
  )

  cat(sprintf("[contract] Created for %s (fp=%s, data=%s)\n",
              strategy_name, fp, contract$data_snapshot_id))
  contract
}

#' Save contract to disk
save_contract <- function(contract, dir = CONTRACT_DIR) {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  path <- file.path(dir, paste0(contract$strategy_name, "_contract.json"))
  write_json(contract, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[contract] Saved: %s\n", path))
  invisible(path)
}

#' Load contract from disk
load_contract <- function(strategy_name, dir = CONTRACT_DIR) {
  path <- file.path(dir, paste0(strategy_name, "_contract.json"))
  if (!file.exists(path)) {
    cat(sprintf("[contract] Not found: %s\n", path))
    return(NULL)
  }
  fromJSON(path, simplifyDataFrame = FALSE)
}

#' Attach backtest result to existing contract
attach_result <- function(contract, hurdle_result) {
  contract$status <- "COMPLETED"
  contract$completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S KST")
  contract$result <- list(
    grade      = hurdle_result$grade,
    score      = hurdle_result$score,
    pass       = hurdle_result$pass,
    cagr       = hurdle_result$verdict$metrics$CAGR,
    sharpe     = hurdle_result$verdict$metrics$Sharpe,
    sharpe_m   = hurdle_result$verdict$metrics$Sharpe_m,
    mdd        = hurdle_result$verdict$metrics$MDD,
    es99_d     = hurdle_result$verdict$metrics$ES99_d
  )

  # Check if outcome matched expectations
  if (!is.null(contract$expected_outcome) && !is.null(contract$result$cagr)) {
    expected_range <- contract$expected_outcome$cagr_range
    if (length(expected_range) == 2) {
      in_range <- contract$result$cagr >= expected_range[1] &&
                  contract$result$cagr <= expected_range[2]
      contract$outcome_match <- in_range
    }
  }

  cat(sprintf("[contract] Result attached: %s Grade %s (score %.1f)\n",
              contract$strategy_name, contract$result$grade, contract$result$score))
  contract
}

#' List all contracts
list_contracts <- function(dir = CONTRACT_DIR) {
  if (!dir.exists(dir)) return(data.table())
  files <- list.files(dir, pattern = "_contract\\.json$", full.names = TRUE)
  if (length(files) == 0) return(data.table())

  rbindlist(lapply(files, function(f) {
    c <- tryCatch(fromJSON(f, simplifyDataFrame = FALSE), error = function(e) NULL)
    if (is.null(c)) return(NULL)
    data.table(
      strategy = c$strategy_name,
      family   = c$family %||% NA,
      status   = c$status,
      grade    = c$result$grade %||% NA,
      score    = c$result$score %||% NA,
      fp       = c$fingerprint,
      data_snap = c$data_snapshot_id,
      created  = c$created_at
    )
  }), fill = TRUE)
}

cat("[experiment_contract] Functions: create_contract(), save_contract(), load_contract(), attach_result(), list_contracts(), compute_data_snapshot_id()\n")
