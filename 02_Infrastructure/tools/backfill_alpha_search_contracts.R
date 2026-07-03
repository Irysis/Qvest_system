#!/usr/bin/env Rscript
# Backfill standardized Backtest Result Contract artifacts for AlphaSearch runs.
# Telegram is intentionally not used here.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

find_root <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  root_arg <- grep("^--root=", args, value = TRUE)
  if (length(root_arg)) {
    p <- sub("^--root=", "", root_arg[[1]])
    if (file.exists(file.path(p, "02_Infrastructure", "config.R"))) {
      return(normalizePath(p, winslash = "/", mustWork = TRUE))
    }
  }
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure", "config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[backfill_alpha_search_contracts] project root not found")
}

args <- commandArgs(trailingOnly = TRUE)
ROOT <- find_root()
setwd(ROOT)
force_all <- "--all" %in% args
limit_arg <- grep("^--limit=", args, value = TRUE)
limit_n <- if (length(limit_arg)) suppressWarnings(as.integer(sub("^--limit=", "", limit_arg[[1]]))) else NA_integer_
if (!is.finite(limit_n)) limit_n <- NA_integer_

source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "contracts", "backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure", "contracts", "audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure", "contracts", "save_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure", "validation", "lookahead_detector.R"))

rel_path <- function(path) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  pref <- paste0(normalizePath(ROOT, winslash = "/", mustWork = FALSE), "/")
  if (startsWith(p, pref)) substring(p, nchar(pref) + 1L) else p
}

as_chr1 <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) return(default)
  x <- as.character(x[[1]])
  if (!nzchar(x) || is.na(x)) default else x
}

as_num1 <- function(x, default = NA_real_) {
  if (is.null(x) || length(x) == 0L) return(default)
  out <- suppressWarnings(as.numeric(x[[1]]))
  if (is.finite(out)) out else default
}

resolve_factor_engine <- function(path) {
  p <- as_chr1(path, "")
  if (!nzchar(p)) return("")
  if (file.exists(p)) return(normalizePath(p, winslash = "/", mustWork = FALSE))
  p2 <- file.path(ROOT, p)
  if (file.exists(p2)) return(normalizePath(p2, winslash = "/", mustWork = FALSE))
  p
}

alpha_spec <- function(manifest, factor_engine_path) {
  exec <- manifest$execution %||% list()
  list(
    strategy_id = as_chr1(manifest$strategy_id),
    strategy_name = as_chr1(manifest$strategy_name),
    strategy_family = "alpha_search",
    signal_description = substr(as_chr1(manifest$strategy_idea, ""), 1, 300),
    universe_rule = sprintf("%s + 20d avg trading value >= 2e8 KRW (t-1 PIT)",
                            as_chr1(exec$universe, "ALL")),
    rebalance_frequency = "monthly",
    signal_date_rule = "month_end_signal",
    execution_date_rule = "t_plus_1_first_trading_day",
    weighting_method = as_chr1(exec$weight_method, "unknown"),
    max_position_weight = 0.20,
    max_leverage = 1.0,
    cash_rule = "fully_invested_after_floor_shares",
    cost_model = "v2.4_delta_15bps",
    missing_data_rule = "exclude_na_scores",
    risk_controls = "none (alpha-search S1 — overlay 금지)",
    lookahead_prevention = "detect_lookahead static scan CLEAN (PIT C1-C15)",
    survivorship_bias_control = "RAWDATA PIT membership / time-varying universe filters",
    factor_engine_path = rel_path(factor_engine_path)
  )
}

update_manifest_contract <- function(manifest_path, manifest, status, pit_status, pit_violations) {
  exec <- manifest$execution %||% list()
  exec$bt_result_path <- rel_path(status$bt_result_path %||% file.path(dirname(manifest_path), "bt_result.rds"))
  manifest$execution <- exec
  manifest$pit <- list(
    code_scan = "detect_lookahead",
    status = pit_status,
    factor_engine_path = rel_path(status$factor_engine_path %||% ""),
    violations = as.list(pit_violations %||% character(0)),
    note = "Backfill re-ran code-level PIT scan on the current factor_engine_path."
  )
  manifest$backtest_contract <- list(
    status = status$status %||% NA_character_,
    run_id = status$run_id %||% NA_character_,
    metric_type = status$metric_type %||% NA_character_,
    bt_result_path = rel_path(status$bt_result_path %||% file.path(dirname(manifest_path), "bt_result.rds")),
    output_dir = rel_path(dirname(manifest_path)),
    integrity_status = status$integrity_status %||% NA_character_,
    audit_pass = status$audit_pass %||% NA_integer_,
    audit_fail = status$audit_fail %||% NA_integer_,
    audit_warn = status$audit_warn %||% NA_integer_,
    validation_errors = as.list(status$validation_errors %||% character(0)),
    note = status$note %||% NA_character_
  )
  write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null")
}

process_one <- function(manifest_path) {
  alpha_dir <- dirname(manifest_path)
  bt_path <- file.path(alpha_dir, "bt_result.rds")
  status_path <- file.path(alpha_dir, "bt_contract_status.json")
  manifest <- tryCatch(fromJSON(manifest_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(manifest)) {
    return(data.table(alpha_dir = rel_path(alpha_dir), strategy_id = NA_character_,
                      status = "FAIL_MANIFEST_READ", bt_result_path = rel_path(bt_path),
                      detail = "strategy_manifest.json read failed"))
  }
  sid <- as_chr1(manifest$strategy_id)
  if (!force_all && file.exists(bt_path)) {
    return(data.table(alpha_dir = rel_path(alpha_dir), strategy_id = sid,
                      status = "SKIP_EXISTS", bt_result_path = rel_path(bt_path),
                      detail = "bt_result.rds already exists"))
  }

  fe_path <- resolve_factor_engine(manifest$factor_engine_path)
  pit <- if (nzchar(fe_path) && file.exists(fe_path)) {
    tryCatch(detect_lookahead(fe_path, verbose = FALSE),
             error = function(e) list(clean = NA, violations = list(list(msg = conditionMessage(e)))))
  } else {
    list(clean = NA, violations = list(list(msg = "factor_engine_path missing or not found")))
  }
  pit_status <- if (isTRUE(pit$clean)) "CLEAN" else if (identical(pit$clean, FALSE)) "FAIL" else "UNKNOWN"
  pit_violations <- vapply(pit$violations %||% list(), function(v) {
    paste(na.omit(c(v$check, v$line, v$msg)), collapse = " | ")
  }, character(1))
  if (identical(pit_status, "FAIL")) {
    status <- list(status = "SKIP_PIT_FAIL", strategy_id = sid, run_id = NA_character_,
                   metric_type = "unavailable", bt_result_path = bt_path,
                   output_dir = alpha_dir, integrity_status = "FAIL",
                   audit_pass = NA_integer_, audit_fail = NA_integer_, audit_warn = NA_integer_,
                   validation_errors = pit_violations,
                   factor_engine_path = fe_path,
                   note = "code-level PIT scan failed during backfill; contract not built")
    write_json(status, status_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null")
    update_manifest_contract(manifest_path, manifest, status, pit_status, pit_violations)
    return(data.table(alpha_dir = rel_path(alpha_dir), strategy_id = sid,
                      status = status$status, bt_result_path = rel_path(bt_path),
                      detail = paste(pit_violations, collapse = "; ")))
  }

  sim_path <- file.path(ROOT, "stage_artifacts", "module_quarantine", sid, "sim_result.rds")
  if (!file.exists(sim_path)) {
    status <- list(status = "FAIL_MISSING_SIM", strategy_id = sid, run_id = NA_character_,
                   metric_type = "unavailable", bt_result_path = bt_path,
                   output_dir = alpha_dir, integrity_status = "FAIL",
                   audit_pass = NA_integer_, audit_fail = NA_integer_, audit_warn = NA_integer_,
                   validation_errors = character(0),
                   factor_engine_path = fe_path,
                   note = sprintf("sim_result.rds not found at %s", rel_path(sim_path)))
    write_json(status, status_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null")
    update_manifest_contract(manifest_path, manifest, status, pit_status, pit_violations)
    return(data.table(alpha_dir = rel_path(alpha_dir), strategy_id = sid,
                      status = status$status, bt_result_path = rel_path(bt_path),
                      detail = status$note))
  }

  tryCatch({
    sim <- readRDS(sim_path)
    exec <- manifest$execution %||% list()
    spec <- alpha_spec(manifest, fe_path)
    run_id <- sprintf("ASBT_%s", basename(alpha_dir))
    bt <- build_bt_result(
      sim, spec, run_id = run_id, strategy_id = sid,
      strategy_version = "alpha_search_v1",
      benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
      transaction_cost_bps = round(as_num1(exec$commission, 0.0015) * 1e4, 1),
      slippage_bps = 0,
      risk_free_rate = 0, frequency = "daily", annualization_factor = 252,
      universe_id = as_chr1(exec$universe, "ALL"),
      code_version = "backfill_alpha_search_contracts_v1",
      created_by_agent = "AlphaSearchBackfill"
    )
    bt <- audit_bt_result(bt)
    validation <- validate_bt_result(bt)
    save_bt_result(bt, alpha_dir, save_xlsx = FALSE)
    AU <- as.data.table(bt$audit)
    status <- list(
      status = if (isTRUE(validation$valid)) "OK" else "INVALID",
      strategy_id = sid,
      strategy_name = as_chr1(manifest$strategy_name),
      run_id = run_id,
      metric_type = "backtested",
      bt_result_path = bt_path,
      output_dir = alpha_dir,
      integrity_status = bt$manifest$integrity_status[1] %||% "UNKNOWN",
      audit_pass = nrow(AU[status == "PASS"]),
      audit_fail = nrow(AU[status == "FAIL"]),
      audit_warn = nrow(AU[status == "WARN"]),
      validation_errors = validation$errors %||% character(0),
      factor_engine_path = fe_path,
      note = "standard Backtest Result Contract backfilled without Telegram"
    )
    write_json(status, status_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null")
    update_manifest_contract(manifest_path, manifest, status, pit_status, pit_violations)
    data.table(alpha_dir = rel_path(alpha_dir), strategy_id = sid,
               status = status$status, bt_result_path = rel_path(bt_path),
               detail = sprintf("integrity=%s pass=%s fail=%s warn=%s",
                                status$integrity_status, status$audit_pass,
                                status$audit_fail, status$audit_warn))
  }, error = function(e) {
    status <- list(status = "FAIL_BUILD", strategy_id = sid, run_id = NA_character_,
                   metric_type = "unavailable", bt_result_path = bt_path,
                   output_dir = alpha_dir, integrity_status = "FAIL",
                   audit_pass = NA_integer_, audit_fail = NA_integer_, audit_warn = NA_integer_,
                   validation_errors = character(0),
                   factor_engine_path = fe_path,
                   error = conditionMessage(e),
                   note = "contract backfill failed")
    write_json(status, status_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null")
    update_manifest_contract(manifest_path, manifest, status, pit_status, pit_violations)
    data.table(alpha_dir = rel_path(alpha_dir), strategy_id = sid,
               status = status$status, bt_result_path = rel_path(bt_path),
               detail = conditionMessage(e))
  })
}

manifests <- Sys.glob(file.path(ROOT, "stage_artifacts", "alpha_search", "*", "strategy_manifest.json"))
manifests <- sort(unique(manifests))
if (!force_all) {
  manifests <- manifests[!file.exists(file.path(dirname(manifests), "bt_result.rds"))]
}
if (is.finite(limit_n) && length(manifests) > limit_n) manifests <- manifests[seq_len(limit_n)]

out_root <- file.path(ROOT, "stage_artifacts", "alpha_search_contract_backfill")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
run_tag <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_csv <- file.path(out_root, sprintf("backfill_%s.csv", run_tag))

cat(sprintf("[backfill] root=%s\n", ROOT))
cat(sprintf("[backfill] candidates=%d force_all=%s\n", length(manifests), force_all))

rows <- if (length(manifests)) {
  rbindlist(lapply(manifests, process_one), fill = TRUE)
} else {
  data.table(alpha_dir = character(), strategy_id = character(), status = character(),
             bt_result_path = character(), detail = character())
}
fwrite(rows, log_csv)
print(rows[, .N, by = status][order(status)])
cat(sprintf("[backfill] report=%s\n", rel_path(log_csv)))
