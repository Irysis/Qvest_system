# =============================================================================
# s2_common.R — shared loader/executor for Track V base runners (s2_run_b*.R)
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(arrow); library(jsonlite)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ)
TV   <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV")
INP  <- file.path(TV, "inputs")
RESD <- file.path(TV, "results")
dir.create(RESD, recursive = TRUE, showWarnings = FALSE)
source(file.path(PROJ, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(TV, "trackv_engine.R"))

START_DATE <- as.Date("2005-01-01")

# ---- shared inputs ----
ADV <- as.data.table(read_parquet(file.path(INP, "adv_panel.parquet")))
ADV[, Date := as.Date(Date)]
MEP <- as.data.table(read_parquet(file.path(INP, "me_panel.parquet")))
MEP[, Date := as.Date(Date)]; MEP[, ret_date := as.Date(ret_date)]
BMM <- fread(file.path(INP, "bm_monthly.csv"))
BMM[, Date := as.Date(Date)]; BMM[, ym := format(Date, "%Y-%m")]

# RET for me_panel-mode bases (B2/B3/B4): forward 1M of month after Date
RET_ME <- MEP[, .(Date, Ticker, ret_fwd, r_idx = ret_date)]
RET_ME_K <- copy(RET_ME); setkey(RET_ME_K, Ticker, Date)

# ret_ok lookup (driver drop rule: selected name must have finite fwd return)
RETOK <- RET_ME[, .(Date, Ticker, ret_ok = is.finite(ret_fwd) & !is.na(r_idx))]

month_end_cal <- function(d) as.Date(format(seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L))

# ---- executor: run preregistered list, save json + series rds ----
tv_execute <- function(base_id, runs, S_map, RET, repro = NULL) {
  res <- list(); series_store <- list()
  for (rn in names(runs)) {
    cfg <- runs[[rn]]
    S <- S_map[[cfg$score_set %||% "default"]]
    cat(sprintf("[%s] run %s ...\n", base_id, rn))
    r <- tryCatch(tv_run_variant(rn, S, RET, BMM, cfg),
                  error = function(e) list(run_id = rn, error = conditionMessage(e)))
    if (!is.null(r$error)) {
      cat(sprintf("  ERROR: %s\n", r$error))
      res[[rn]] <- list(run_id = rn, error = r$error)
    } else {
      res[[rn]] <- list(run_id = rn, metric_type = "canonical_screen",
                        cfg = cfg[setdiff(names(cfg), "score_set")],
                        windows = r$windows, diag = r$diag)
      series_store[[rn]] <- r$series
      f <- r$windows$FULL
      cat(sprintf("  FULL: n=%d SRnet=%.3f CAGR=%.2f%% MDD=%.1f%% TO1w=%.2fx cost=%.2f%%/yr | IS SR=%.3f OOS SR=%.3f | PORT_t=%.2f | avgN=%.1f naFill=%.4f\n",
                  f$n_months, f$sr_net, f$cagr_net*100, f$mdd_net*100, f$to_oneway_ann,
                  f$cost_ann_pct, r$windows$IS$sr_net, r$windows$OOS$sr_net, f$port_t_nw,
                  r$diag$avg_n, r$diag$na_fill_share))
    }
  }
  out <- list(base_id = base_id, generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
              cost_model = "v2.4_kr_retail_15bps delta (cost_t = 0.0015 x sum|dW| both legs, drift-aware BOP/EOP)",
              metric_type = "canonical_screen", repro_check = repro, runs = res)
  write_json(out, file.path(RESD, paste0(tolower(base_id), "_results.json")),
             auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  saveRDS(series_store, file.path(RESD, paste0(tolower(base_id), "_series.rds")))
  cat(sprintf("[%s] saved %d runs -> results/\n", base_id, length(res)))
  invisible(out)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
cat("[s2_common] loaded\n")
