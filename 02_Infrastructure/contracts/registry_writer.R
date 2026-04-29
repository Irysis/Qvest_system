## ============================================================================
## registry_writer.R — qepm/registry/backtest_registry.csv master registry
## Lawbook §22
## ============================================================================

suppressMessages({library(data.table)})

REGISTRY_PATH <- file.path(
  ifelse(exists("PROJECT_ROOT"), PROJECT_ROOT,
         "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"),
  "qepm/registry/backtest_registry.csv"
)

REGISTRY_COLS <- c(
  "run_id", "strategy_id", "strategy_name", "strategy_version",
  "start_date", "end_date", "frequency",
  "universe_id", "benchmark_primary", "return_type",
  "cagr", "vol", "sharpe", "mdd", "calmar",
  "information_ratio", "hit_ratio_vs_bm", "turnover",
  "cvar_99", "integrity_status", "created_at"
)

#' Initialize registry CSV (skeleton with header only)
init_registry <- function(path = REGISTRY_PATH) {
  if (!dir.exists(dirname(path))) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  }
  if (!file.exists(path)) {
    fwrite(data.table(matrix(nrow = 0, ncol = length(REGISTRY_COLS),
                              dimnames = list(NULL, REGISTRY_COLS))),
           path)
    cat(sprintf("[registry_writer] Initialized: %s\n", path))
  }
  invisible(path)
}

#' Append bt_result summary to master registry
#' @param bt_result list (validated, audited)
#' @param block_on_fail audit FAIL 시 등재 차단 boolean (L3 hard block)
register_bt_result <- function(bt_result, path = REGISTRY_PATH,
                                 block_on_fail = TRUE) {
  init_registry(path)

  # L3 hard block: critical FAIL 또는 integrity_status FAIL 시 차단
  integrity <- bt_result$manifest$integrity_status[1]
  if (block_on_fail && integrity == "FAIL") {
    msg <- sprintf("[registry_writer L3 BLOCK] %s integrity=FAIL — registry 등재 차단",
                   bt_result$manifest$strategy_id[1])
    cat(msg, "\n")
    return(invisible(list(blocked = TRUE, reason = msg)))
  }

  m <- bt_result$metrics
  get_metric <- function(name) {
    if (is.null(m) || nrow(m) == 0) return(NA_real_)
    val <- m[metric_name == name & is_official == TRUE & metric_type == "backtested",
              metric_value]
    if (length(val) == 0) NA_real_ else as.numeric(val[1])
  }

  bc <- bt_result$benchmark_compare
  get_bm_metric <- function(name) {
    if (is.null(bc) || nrow(bc) == 0) return(NA_real_)
    val <- bc[metric_name == name, active_value]
    if (length(val) == 0) NA_real_ else as.numeric(val[1])
  }

  row <- data.table(
    run_id = bt_result$manifest$run_id[1],
    strategy_id = bt_result$manifest$strategy_id[1],
    strategy_name = bt_result$strategy_spec$strategy_name[1] %||% bt_result$manifest$strategy_id[1],
    strategy_version = bt_result$manifest$strategy_version[1],
    start_date = bt_result$manifest$start_date[1],
    end_date = bt_result$manifest$end_date[1],
    frequency = bt_result$manifest$frequency[1],
    universe_id = bt_result$manifest$universe_id[1],
    benchmark_primary = bt_result$manifest$benchmark_ids[1],
    return_type = "net",
    cagr = get_metric("CAGR"),
    vol = get_metric("Annualized_Volatility"),
    sharpe = get_metric("Sharpe"),
    mdd = get_metric("MDD"),
    calmar = get_metric("Calmar"),
    information_ratio = get_bm_metric("Information_Ratio"),
    hit_ratio_vs_bm = get_bm_metric("Hit_Ratio_vs_BM"),
    turnover = get_metric("Average_Turnover"),
    cvar_99 = get_metric("CVaR_99"),
    integrity_status = integrity,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )

  # Read existing + append (run_id 중복 방지: 같은 run_id 이미 있으면 update)
  existing <- if (file.exists(path) && file.size(path) > 0) {
    tryCatch(fread(path), error = function(e) NULL)
  } else NULL

  if (!is.null(existing) && nrow(existing) > 0) {
    existing <- existing[run_id != row$run_id]
    out <- rbind(existing, row, fill = TRUE)
  } else {
    out <- row
  }

  fwrite(out, path)
  cat(sprintf("[registry_writer] Registered: %s (CAGR=%.2f%% / SR=%.4f / MDD=%.2f%% / integrity=%s)\n",
              row$run_id,
              row$cagr * 100, row$sharpe, row$mdd * 100, integrity))

  invisible(list(blocked = FALSE, row = row, total_entries = nrow(out)))
}

#' Read registry summary (sorted by sharpe desc)
read_registry_summary <- function(path = REGISTRY_PATH, top_n = NULL) {
  if (!file.exists(path)) {
    cat("[registry_writer] Empty registry\n")
    return(data.table())
  }
  dt <- fread(path)
  if (nrow(dt) == 0) return(dt)
  setorder(dt, -sharpe)
  if (!is.null(top_n)) dt <- head(dt, top_n)
  dt
}

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a) && a != "") a else b

cat("[registry_writer.R] Loaded — register_bt_result() / read_registry_summary()\n")
cat(sprintf("  Registry path: %s\n", REGISTRY_PATH))
