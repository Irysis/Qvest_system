## ============================================================================
## registry_writer.R — qepm/registry/backtest_registry.csv master registry
## Lawbook §22
## ============================================================================

suppressMessages({library(data.table)})

.qvest_registry_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) return(get("PROJECT_ROOT", inherits = TRUE))
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[registry_writer] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

REGISTRY_PATH <- file.path(
  .qvest_registry_root(),
  "qepm/registry/backtest_registry.csv"
)

REGISTRY_COLS <- c(
  "run_id", "strategy_id", "strategy_name", "strategy_version",
  "start_date", "end_date", "frequency",
  "universe_id", "benchmark_primary", "return_type",
  "cagr", "vol", "sharpe", "mdd", "calmar",
  "information_ratio", "portfolio_alpha_t", "hit_ratio_vs_bm", "turnover",
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

  # L3 hard block: integrity_status가 audit-완료 상태가 아니면 차단
  #   FAIL          — audit critical FAIL
  #   PENDING       — build_manifest 초기값 = audit_bt_result() 미실행 (감사 GOV-05)
  #   NA/결측/빈값  — manifest 손상 또는 미기록
  # (audit_bt_result가 부여하는 상태는 PASS/WARNING/FAIL — PENDING 등재는 audit 우회)
  integrity <- bt_result$manifest$integrity_status[1]
  integrity_missing <- is.null(integrity) || length(integrity) == 0 ||
    is.na(integrity) || !nzchar(as.character(integrity))
  if (block_on_fail && (integrity_missing || integrity %in% c("FAIL", "PENDING"))) {
    label <- if (integrity_missing) "MISSING/NA" else as.character(integrity)
    msg <- sprintf("[registry_writer L3 BLOCK] %s integrity=%s — registry 등재 차단 (audit_bt_result() 실행 후 PASS/WARNING만 등재 가능)",
                   bt_result$manifest$strategy_id[1], label)
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
    portfolio_alpha_t = get_bm_metric("Portfolio_Alpha_t_NW_lag3"),
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

# vector-safe %||% (override 시 build_bt_result vector input 보호)
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1) {
    if (is.na(a)) return(b)
    if (is.character(a) && a == "") return(b)
  } else {
    if (all(is.na(a))) return(b)
  }
  a
}

cat("[registry_writer.R] Loaded — register_bt_result() / read_registry_summary()\n")
cat(sprintf("  Registry path: %s\n", REGISTRY_PATH))
