# v53 Sprint 2 S2.8: grid_runner — 조합 탐색 opt-in 래퍼
# 목적: Forge가 grid search를 수행할 때 iteration을 투명하게 기록.
# 기존 전략 코드에는 영향 없음 (opt-in). 신규 S5 mutation 설계 시 사용 권장.
#
# 기록 위치: .cache/grid_runs/{STR_ID}_{timestamp}.parquet (arrow 필요)
# iteration 50+ 시 hurdle_gate에서 combinatorial_penalty=-10 부여 (S2.9 연계).
#
# Usage:
#   source("02_Infrastructure/portfolio/grid_runner.R")
#   results <- run_grid(
#     param_grid = expand.grid(lookback = c(21, 63, 126), quantile = c(0.1, 0.2)),
#     eval_fn = function(params) { ... 백테스트 ... ; list(sharpe=..., cagr=...) },
#     strategy_id = "STR_TEST",
#     seed = 42
#   )

suppressPackageStartupMessages({
  library(data.table)
})

.grid_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

run_grid <- function(param_grid, eval_fn, strategy_id,
                     seed = NULL, verbose = TRUE, max_iter = 100L) {
  stopifnot(is.data.frame(param_grid), is.function(eval_fn),
            is.character(strategy_id), length(strategy_id) == 1L)
  root <- .grid_root()
  cache_dir <- file.path(root, ".cache/grid_runs")
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

  if (is.null(seed)) {
    stop("[grid_runner] seed 필수 (재현성 보장). set seed = 42 등.")
  }
  set.seed(seed)

  n_iter <- nrow(param_grid)
  if (n_iter > max_iter) {
    warning(sprintf("[grid_runner] n_iter=%d exceeds max_iter=%d, truncating",
                     n_iter, max_iter))
    param_grid <- param_grid[seq_len(max_iter), , drop = FALSE]
    n_iter <- max_iter
  }

  t0 <- Sys.time()
  log <- vector("list", n_iter)

  for (i in seq_len(n_iter)) {
    params <- as.list(param_grid[i, , drop = FALSE])
    if (verbose) cat(sprintf("[grid_runner] iter %d/%d: %s\n", i, n_iter,
                              paste(names(params), unlist(params), sep="=", collapse=", ")))
    res <- tryCatch(eval_fn(params),
                    error = function(e) list(error = conditionMessage(e)))
    log[[i]] <- c(list(iter = i, timestamp = as.character(Sys.time())),
                  params, res)
  }

  dt <- rbindlist(lapply(log, function(x) {
    out <- list()
    for (k in names(x)) out[[k]] <- if (is.null(x[[k]])) NA else x[[k]]
    out
  }), fill = TRUE)
  attr(dt, "seed") <- seed
  attr(dt, "strategy_id") <- strategy_id
  attr(dt, "started_at") <- as.character(t0)
  attr(dt, "ended_at") <- as.character(Sys.time())
  attr(dt, "n_combinations") <- n_iter

  # 기록 (parquet 우선, 불가 시 csv)
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  path_prefix <- file.path(cache_dir, sprintf("%s_%s", strategy_id, ts))
  saved_path <- NULL
  if (requireNamespace("arrow", quietly = TRUE)) {
    path <- paste0(path_prefix, ".parquet")
    tryCatch({
      arrow::write_parquet(dt, path)
      saved_path <- path
    }, error = function(e) NULL)
  }
  if (is.null(saved_path)) {
    path <- paste0(path_prefix, ".csv")
    fwrite(dt, path)
    saved_path <- path
  }

  if (verbose) cat(sprintf("[grid_runner] saved %d iterations → %s\n",
                            n_iter, saved_path))

  list(
    results = dt,
    strategy_id = strategy_id,
    n_combinations = n_iter,
    seed = seed,
    log_path = saved_path,
    started_at = as.character(t0),
    ended_at = as.character(Sys.time())
  )
}

cat("[grid_runner] Loaded. Function: run_grid(param_grid, eval_fn, strategy_id, seed)\n")
