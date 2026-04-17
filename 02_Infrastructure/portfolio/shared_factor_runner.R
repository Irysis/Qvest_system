#==============================================================================
# shared_factor_runner.R — 팩터 1회 계산 + 가중 N건 비교 러너 (정본)
#
# 동일 팩터/종목 선정에서 비중 결정 방법론만 비교할 때 사용.
# 전체 파이프라인(RAWDATA 로드 → 팩터 계산 → HRP → overlay)을
# N번 반복하지 않고, 팩터 1회 + 가중 N건 루프로 최적화.
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source(file.path(INFRA_DIR, "backtest_harness.R"))
#   source(file.path(PORTFOLIO_DIR, "shared_factor_runner.R"))
#
#   results <- run_weight_comparison(
#     FACTORS  = FACTORS,
#     RAWDATA  = RAWDATA,
#     BM_DT    = BM_DT,
#     regime_dt = build_daily_regime(use_cache = TRUE)
#   )
#   print(results$comparison)  # 비교 테이블
#
# Dependencies: backtest_harness.R, regime/apply_regime_overlay.R (optional)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
})

# ─── Default weight methods ──────────────────────────────────────────────────
.DEFAULT_WEIGHT_METHODS <- list(
  list(name = "EW",         method = "equal",      cov_method = "sample"),
  list(name = "IVOL",       method = "ivol",       cov_method = "sample"),
  list(name = "HRP",        method = "hrp",        cov_method = "gerber_rmt"),
  list(name = "HRP_LW",     method = "hrp",        cov_method = "ledoit_wolf"),
  list(name = "MinVar",     method = "minvar",      cov_method = "ledoit_wolf"),
  list(name = "RiskParity", method = "riskparity",  cov_method = "sample"),
  list(name = "ScoreTilt",  method = "score_tilt",  cov_method = "gerber_rmt")
)


#' Run weight comparison: same factors, multiple weighting methods
#'
#' @param FACTORS       data.table(Date, Ticker, Score) — 월별 시그널
#' @param RAWDATA       data.table from load_rawdata()
#' @param BM_DT         benchmark data.table (Date, BM_Ret)
#' @param weight_methods list of list(name, method, cov_method). NULL = 7가지 기본
#' @param regime_dt     data.table from build_daily_regime() (optional)
#'                      NULL이면 overlay 미적용 (S1 순수 팩터 비교)
#' @param inv_dt        inverse ETF data.table (optional, overlay용)
#' @param n_holdings    종목 수 (default 20)
#' @param commission    수수료율 (default 0.0015)
#' @param buffer_zone   list(keep_n, entry_n) (default 35/20)
#' @param output_dir    결과 저장 디렉토리 (NULL이면 저장 안 함)
#' @param run_hurdle    hurdle gate 실행 여부 (default FALSE)
#' @param strategy_name 전략명 (hurdle/chart용)
#'
#' @return list(
#'   comparison = data.table (Name, SR, CAGR, MDD, TO, ...),
#'   sims       = list(name = sim_result, ...),
#'   best       = list(name, sr, method)
#' )
run_weight_comparison <- function(
  FACTORS,
  RAWDATA,
  BM_DT,
  weight_methods = NULL,
  regime_dt      = NULL,
  inv_dt         = NULL,
  ic_history     = NULL,    # named numeric vector (name=Date string, value=IC) for V2 ic_tilt
  n_holdings     = 20L,
  commission     = 0.0015,
  buffer_zone    = list(keep_n = 35L, entry_n = 20L),
  output_dir     = NULL,
  run_hurdle     = FALSE,
  strategy_name  = "WeightComparison",
  parallel       = TRUE
) {

  if (is.null(weight_methods)) weight_methods <- .DEFAULT_WEIGHT_METHODS

  cat(sprintf("\n══════ Weight Comparison: %d methods ══════\n", length(weight_methods)))
  cat(sprintf("  FACTORS: %d signals | N=%d | commission=%.2f%%\n",
              uniqueN(FACTORS$Date), n_holdings, commission * 100))
  if (!is.null(regime_dt)) cat("  Regime overlay: ENABLED\n")
  cat("\n")

  # ── Load overlay function if regime_dt provided ───────────────────
  overlay_fn <- NULL
  if (!is.null(regime_dt)) {
    overlay_path <- file.path(
      if (exists("REGIME_DIR")) REGIME_DIR
      else file.path(if (exists("INFRA_DIR")) INFRA_DIR else "02_Infrastructure", "regime"),
      "apply_regime_overlay.R"
    )
    if (file.exists(overlay_path)) {
      source(overlay_path, local = TRUE)
      overlay_fn <- apply_regime_overlay
    } else {
      warning("[shared_factor_runner] apply_regime_overlay.R not found. Overlay disabled.")
    }
  }

  # ── Run each weight method (sequential or parallel) ──────────────
  sims <- list()
  perfs <- list()
  t0 <- proc.time()

  .run_single_method <- function(wm, RAWDATA, BM_DT, FACTORS, n_holdings,
                                  commission, buffer_zone, overlay_fn,
                                  regime_dt, inv_dt, ic_history = NULL) {
    # Score Tilt Variant methods that need regime_dt passed into the simulation
    needs_regime_in_sim <- wm$method %in% c("regime_tilt", "regime_softmax")
    # ic_tilt needs ic_history
    needs_ic <- wm$method == "ic_tilt"

    sim <- tryCatch(
      run_monthly_simulation(
        RAWDATA       = RAWDATA,
        BM_DT         = BM_DT,
        FACTORS       = FACTORS,
        n_holdings    = n_holdings,
        weight_method = wm$method,
        commission    = commission,
        buffer_zone   = buffer_zone,
        cov_method    = wm$cov_method %||% "sample",
        regime_dt     = if (needs_regime_in_sim) regime_dt else NULL,
        ic_history    = if (needs_ic) ic_history else NULL
      ),
      error = function(e) {
        message(sprintf("[.run_single_method] %s FAILED: %s", wm$name, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(sim)) return(NULL)

    if (!is.null(overlay_fn) && !is.null(regime_dt)) {
      sim <- tryCatch(
        overlay_fn(sim, regime_dt, BM_DT, inv_dt = inv_dt),
        error = function(e) sim
      )
    }

    perf <- summarise_perf(sim$strategy_xts, wm$name)
    to <- tryCatch(calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT), error = function(e) NA)
    list(sim = sim, perf = cbind(perf, data.table(TO = to, Method = wm$method,
                                                   Cov = wm$cov_method %||% "sample")))
  }

  if (parallel && length(weight_methods) > 1L) {
    # ── Parallel execution ──────────────────────────────────────────
    n_workers <- min(length(weight_methods), parallel::detectCores() - 1L, 4L)
    cat(sprintf("[PARALLEL] %d methods × %d workers\n", length(weight_methods), n_workers))

    library(future.apply)
    old_plan <- plan(multisession, workers = n_workers)
    on.exit(plan(old_plan), add = TRUE)

    par_results <- future_lapply(weight_methods, function(wm) {
      # 각 worker에서 backtest_harness 함수들이 필요
      .run_single_method(wm, RAWDATA, BM_DT, FACTORS, n_holdings,
                         commission, buffer_zone, overlay_fn,
                         regime_dt, inv_dt, ic_history)
    }, future.seed = TRUE)

    plan(sequential)

    for (i in seq_along(weight_methods)) {
      wm <- weight_methods[[i]]
      r <- par_results[[i]]
      if (!is.null(r)) {
        sims[[wm$name]] <- r$sim
        perfs[[wm$name]] <- r$perf
        cat(sprintf("[%d/%d] %s: SR=%.3f CAGR=%.1f%% MDD=%.1f%%\n",
                    i, length(weight_methods), wm$name,
                    r$perf$Sharpe, r$perf$CAGR, r$perf$MDD))
      } else {
        cat(sprintf("[%d/%d] %s: FAILED\n", i, length(weight_methods), wm$name))
      }
    }

  } else {
    # ── Sequential execution ──────────────────────────────────────
    for (i in seq_along(weight_methods)) {
      wm <- weight_methods[[i]]
      cat(sprintf("[%d/%d] %s (method=%s, cov=%s)...",
                  i, length(weight_methods), wm$name, wm$method,
                  wm$cov_method %||% "sample"))
      t1 <- proc.time()

      r <- .run_single_method(wm, RAWDATA, BM_DT, FACTORS, n_holdings,
                               commission, buffer_zone, overlay_fn,
                               regime_dt, inv_dt, ic_history)

      if (is.null(r)) { cat(" FAILED\n"); next }

      elapsed <- (proc.time() - t1)["elapsed"]
      cat(sprintf(" SR=%.3f CAGR=%.1f%% MDD=%.1f%% TO=%.0f%% (%.0fs)\n",
                  r$perf$Sharpe, r$perf$CAGR, r$perf$MDD, r$perf$TO, elapsed))

      sims[[wm$name]] <- r$sim
      perfs[[wm$name]] <- r$perf
    }
  }

  total_elapsed <- (proc.time() - t0)["elapsed"]
  cat(sprintf("\n══════ Done in %.0fs ══════\n", total_elapsed))

  # ── Comparison table ──────────────────────────────────────────────
  comparison <- rbindlist(perfs, fill = TRUE)
  setorder(comparison, -Sharpe)

  cat("\n=== Weight Method Comparison ===\n")
  print(comparison[, .(Label, Sharpe, CAGR, MDD, TO, Method)])

  # ── Best method ───────────────────────────────────────────────────
  best_row <- comparison[1]
  best <- list(
    name   = best_row$Label,
    sr     = best_row$Sharpe,
    method = best_row$Method
  )
  cat(sprintf("\nBest: %s (SR=%.3f)\n", best$name, best$sr))

  # ── Save results if output_dir provided ───────────────────────────
  if (!is.null(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    fwrite(comparison, file.path(output_dir, "weight_comparison.csv"))

    # Charts for best method
    if (!is.null(sims[[best$name]])) {
      tryCatch(
        generate_charts(sims[[best$name]], output_dir = output_dir,
                        strategy_name = paste0(strategy_name, "_", best$name)),
        error = function(e) cat("[chart error]", e$message, "\n")
      )
    }

    # Hurdle for each if requested
    if (run_hurdle && exists("run_hurdle_gate")) {
      for (nm in names(sims)) {
        sub_dir <- file.path(output_dir, nm)
        dir.create(sub_dir, showWarnings = FALSE)
        tryCatch({
          hr <- run_hurdle_gate(
            sim_result = sims[[nm]], FACTORS = FACTORS,
            strategy_name = paste0(strategy_name, "_", nm),
            output_dir = sub_dir
          )
          jsonlite::write_json(hr, file.path(sub_dir, "hurdle_result.json"),
                               auto_unbox = TRUE, pretty = TRUE)
        }, error = function(e) cat(sprintf("[hurdle %s] %s\n", nm, e$message)))
      }
    }
  }

  # ── Return ────────────────────────────────────────────────────────
  list(
    comparison = comparison,
    sims       = sims,
    best       = best,
    elapsed    = total_elapsed
  )
}

# ─── Null coalesce (if not already defined) ──────────────────────────────────
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[shared_factor_runner] Loaded. run_weight_comparison(FACTORS, RAWDATA, BM_DT)\n")
