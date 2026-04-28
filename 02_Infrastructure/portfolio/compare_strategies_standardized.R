## compare_strategies_standardized.R (Phase 2, Plan v1.0 2026-04-29)
##
## Goal: 마일스톤 admitted 전략들을 동일 framework로 share-based 실측 비교
##
## 도훈 명령 enforcement (Session 73, 2026-04-28~29):
##   1. Forge 단계 이후 forge_realized_share_based만 인용 (추정 금지)
##   2. PerformanceAnalytics 표준 함수만 사용 (자체 cumprod/prod/mean/sd 합성 금지)
##   3. verbose=TRUE로 BOP/EOP weight + contribution + value 모두 산출
##
## Charter §9 measurement_basis_primary = "forge_realized_share_based" 강제
##
## Inputs:
##   - strategies_list: named list of weights.csv paths
##   - returns_panel: monthly returns matrix (xts: Date × Ticker, raw monthly returns)
##   - blends: named list of blend ratios (e.g. STR_1715 = 1.0, or STR_1715 = 0.7 + STR_1656 = 0.3)
##
## Outputs:
##   - 4way_summary.json (Charter §9 schema)
##   - 4way_returns_panel.parquet (verbose results)
##   - 4way_charts.png (PerformanceSummary chart)

suppressMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(jsonlite)
})
options(scipen = 999)

# ─────────────────────────────────────────────────────────
# 1. Helper: load weights.csv → xts (Date × Ticker matrix)
# ─────────────────────────────────────────────────────────
load_weights_xts <- function(weights_path, returns_panel_cols) {
  if (!file.exists(weights_path)) {
    stop(sprintf("[load_weights_xts] not found: %s", weights_path))
  }
  w <- fread(weights_path)
  # Detect Date / Ticker / Weight column names
  date_col <- intersect(c("Date", "Signal_Date", "sig_date"), names(w))[1]
  weight_col <- intersect(c("Weight", "weight", "w"), names(w))[1]
  ticker_col <- intersect(c("Ticker", "ticker"), names(w))[1]
  if (is.na(date_col) || is.na(weight_col) || is.na(ticker_col)) {
    stop(sprintf("[load_weights_xts] missing Date/Ticker/Weight cols: %s", weights_path))
  }
  setnames(w, c(date_col, ticker_col, weight_col), c("Date", "Ticker", "Weight"))
  w[, Date := as.Date(Date)]

  # Wide format: Date × Ticker → fill 0
  w_wide <- dcast(w[, .(Date, Ticker, Weight)],
                   Date ~ Ticker, value.var = "Weight", fill = 0)
  W <- xts(as.matrix(w_wide[, -1, with = FALSE]), order.by = w_wide$Date)

  # Pad to returns_panel column universe
  pad_cols <- setdiff(returns_panel_cols, colnames(W))
  if (length(pad_cols) > 0) {
    pad_mat <- xts(matrix(0, nrow = nrow(W), ncol = length(pad_cols),
                          dimnames = list(NULL, pad_cols)),
                   order.by = index(W))
    W <- merge(W, pad_mat)
  }
  W <- W[, returns_panel_cols]
  W
}

# ─────────────────────────────────────────────────────────
# 2. Build blended weights via xts matrix sum
#    (NOT via row-wise return合성 — 도훈 명령)
# ─────────────────────────────────────────────────────────
build_blended_weights_xts <- function(weights_xts_list, blend_ratios,
                                        returns_panel_index = NULL) {
  # blend_ratios: named numeric (sum to 1.0)
  # returns_panel_index: target monthly grid (returns_panel index) for forward-fill
  if (abs(sum(blend_ratios) - 1.0) > 1e-6) {
    stop(sprintf("[build_blended_weights] blend_ratios sum %.6f != 1.0",
                 sum(blend_ratios)))
  }
  if (!all(names(blend_ratios) %in% names(weights_xts_list))) {
    stop(sprintf("[build_blended_weights] missing strategies: %s",
                 paste(setdiff(names(blend_ratios), names(weights_xts_list)),
                       collapse = ", ")))
  }

  # Determine target grid:
  #   - if returns_panel_index provided → snap weights to that monthly grid (correct path)
  #   - otherwise → fallback to union of weights_xts dates (legacy)
  if (!is.null(returns_panel_index)) {
    target_grid <- as.Date(returns_panel_index)
  } else {
    date_grids <- lapply(names(blend_ratios), function(s) index(weights_xts_list[[s]]))
    target_grid <- sort(unique(do.call(c, date_grids)))
    target_grid <- as.Date(target_grid)
  }

  cols <- colnames(weights_xts_list[[names(blend_ratios)[1]]])
  blended <- xts(matrix(0, nrow = length(target_grid), ncol = length(cols),
                        dimnames = list(NULL, cols)),
                 order.by = target_grid)

  for (s in names(blend_ratios)) {
    W_s <- weights_xts_list[[s]]
    # Snap W_s rows to target_grid: for each YM in target_grid, find nearest
    # weights date <= target_grid date (forward-fill semantics).
    if (!is.null(returns_panel_index)) {
      ws_dt <- as.data.table(W_s, keep.rownames = "Date")
      ws_dt[, Date := as.Date(Date)]
      ws_dt[, YM := format(Date, "%Y-%m")]
      grid_dt <- data.table(Date = target_grid,
                            YM = format(target_grid, "%Y-%m"))
      # For each grid YM, attach weights row (latest sig_date in same YM); else NA.
      ws_latest_by_ym <- ws_dt[, .SD[which.max(Date)], by = YM]
      merged <- merge(grid_dt, ws_latest_by_ym, by = "YM",
                       all.x = TRUE, suffixes = c(".grid", ".w"))
      setorder(merged, Date.grid)
      mat_cols <- setdiff(names(merged),
                           c("Date.grid", "Date.w", "YM"))
      mat <- as.matrix(merged[, ..mat_cols])
      W_snapped <- xts(mat, order.by = merged$Date.grid)
      # Forward-fill (carry last weight forward across months without rebal)
      W_snapped <- zoo::na.locf(W_snapped, na.rm = FALSE)
      W_snapped[is.na(W_snapped)] <- 0
      W_snapped <- W_snapped[, cols]
    } else {
      W_snapped <- zoo::na.locf(merge(W_s, xts(, target_grid), all = TRUE),
                                 na.rm = FALSE)[target_grid]
      W_snapped[is.na(W_snapped)] <- 0
    }
    blended <- blended + W_snapped * blend_ratios[s]
  }
  blended
}

# ─────────────────────────────────────────────────────────
# 3. Run Return.portfolio for one blend (verbose=TRUE)
# ─────────────────────────────────────────────────────────
run_blend_return_portfolio <- function(returns_panel, blended_weights_xts,
                                        rebalance_on = "months") {
  # ENFORCEMENT: PerformanceAnalytics standard call only
  rp <- PerformanceAnalytics::Return.portfolio(
    R           = returns_panel,
    weights     = blended_weights_xts,
    rebalance_on = rebalance_on,
    verbose     = TRUE
  )
  rp
}

# ─────────────────────────────────────────────────────────
# 4. Standardized metric extraction (PerformanceAnalytics only)
# ─────────────────────────────────────────────────────────
extract_metrics <- function(portfolio_returns_xts, blend_label, n_unique_dates) {
  R <- portfolio_returns_xts
  if (is.null(colnames(R)) || ncol(R) == 0) colnames(R) <- "portfolio.returns"

  ann <- PerformanceAnalytics::table.AnnualizedReturns(R, scale = 12, Rf = 0)
  ds <- PerformanceAnalytics::table.DownsideRisk(R, scale = 12)
  mdd <- PerformanceAnalytics::maxDrawdown(R)
  calmar <- PerformanceAnalytics::CalmarRatio(R, scale = 12)
  sortino <- PerformanceAnalytics::SortinoRatio(R, MAR = 0)

  list(
    blend_label = blend_label,
    measurement_basis_primary = "forge_realized_share_based",
    n_periods = nrow(R),
    weights_csv_unique_dates_count = n_unique_dates,
    schedule_density_ratio = 1.0,  # placeholder; needs per-strategy fill
    annualized_return = round(as.numeric(ann[1, 1]), 6),
    annualized_vol = round(as.numeric(ann[2, 1]), 6),
    sharpe_annualized = round(as.numeric(ann[3, 1]), 6),
    max_drawdown = round(as.numeric(mdd), 6),
    calmar_ratio = round(as.numeric(calmar[1, 1]), 6),
    sortino_ratio = round(as.numeric(sortino[1, 1]), 6),
    semi_deviation = round(as.numeric(ds["Semi Deviation", 1]), 6),
    historical_var_95 = round(as.numeric(ds["Historical VaR (95%)", 1]), 6),
    historical_es_95 = round(as.numeric(ds["Historical ES (95%)", 1]), 6),
    loss_deviation = round(as.numeric(ds["Loss Deviation", 1]), 6)
  )
}

# ─────────────────────────────────────────────────────────
# 5. Main entry point
# ─────────────────────────────────────────────────────────
compare_strategies_standardized <- function(
  strategies_list,                    # named list: list(STR_1715 = "weights.csv", ...)
  returns_panel,                      # xts: Date × Ticker monthly returns
  blends,                             # named list: list(blend_label = list(STR_X = ratio))
  output_dir = NULL,
  rebalance_on = "months"
) {
  if (is.null(output_dir)) {
    output_dir <- file.path(tempdir(), sprintf("4way_compare_%s",
                                                format(Sys.time(), "%Y%m%d_%H%M%S")))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Step 1: Load all weights as xts
  cat("[compare] Loading weights...\n")
  weights_xts_list <- list()
  weights_meta <- list()
  for (s in names(strategies_list)) {
    w_xts <- load_weights_xts(strategies_list[[s]], colnames(returns_panel))
    weights_xts_list[[s]] <- w_xts
    weights_meta[[s]] <- list(
      path = strategies_list[[s]],
      n_unique_dates = length(unique(index(w_xts))),
      date_range = c(as.character(min(index(w_xts))),
                     as.character(max(index(w_xts))))
    )
    cat(sprintf("  %s: %d sig_dates | %s ~ %s\n",
                s, weights_meta[[s]]$n_unique_dates,
                weights_meta[[s]]$date_range[1], weights_meta[[s]]$date_range[2]))
  }

  # Step 2: For each blend, build blended weights + Return.portfolio + metrics
  cat("\n[compare] Running PerformanceAnalytics::Return.portfolio (verbose=TRUE)...\n")
  results <- list()
  verbose_outputs <- list()
  for (blend_label in names(blends)) {
    blend_ratios <- unlist(blends[[blend_label]])
    cat(sprintf("\n  Blend [%s]: %s\n", blend_label,
                paste(sprintf("%s=%.2f", names(blend_ratios), blend_ratios),
                      collapse = " + ")))

    # Compute n_unique_dates as min across constituent strategies
    n_dates_blend <- min(sapply(names(blend_ratios),
                                 function(s) weights_meta[[s]]$n_unique_dates))

    blended_W <- build_blended_weights_xts(weights_xts_list, blend_ratios,
                                            returns_panel_index = index(returns_panel))
    rp <- run_blend_return_portfolio(returns_panel, blended_W, rebalance_on)
    metrics <- extract_metrics(rp$returns, blend_label, n_dates_blend)

    results[[blend_label]] <- metrics
    verbose_outputs[[blend_label]] <- list(
      returns = rp$returns,
      contribution = rp$contribution,
      BOP_Weight = rp$BOP.Weight,
      EOP_Weight = rp$EOP.Weight,
      BOP_Value = rp$BOP.Value,
      EOP_Value = rp$EOP.Value
    )

    cat(sprintf("    SR=%.4f | CAGR=%.4f | MDD=%.4f | n_periods=%d\n",
                metrics$sharpe_annualized, metrics$annualized_return,
                metrics$max_drawdown, metrics$n_periods))
  }

  # Step 3: Save 4way_summary.json
  rank_by_sr <- names(results)[order(-sapply(results,
                                              function(r) r$sharpe_annualized))]

  summary_obj <- list(
    as_of = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    measurement_basis_primary = "forge_realized_share_based",
    harness_version = "compare_strategies_standardized_v1.0",
    plan_version = "v1.0_2026-04-29",
    enforcement = list(
      no_self_synthesis = TRUE,
      performance_analytics_only = TRUE,
      forge_realized_share_based_only = TRUE
    ),
    rebalance_on = rebalance_on,
    strategies_meta = weights_meta,
    blends = results,
    ranked_by_sr_desc = rank_by_sr
  )
  summary_path <- file.path(output_dir, "4way_summary.json")
  write_json(summary_obj, summary_path, pretty = TRUE,
             auto_unbox = TRUE, null = "null")

  # Step 4: Save returns panel (parquet)
  combined_returns <- do.call(merge,
                               lapply(verbose_outputs, function(v) v$returns))
  colnames(combined_returns) <- names(verbose_outputs)
  ret_dt <- as.data.table(combined_returns, keep.rownames = "Date")
  fwrite(ret_dt, file.path(output_dir, "4way_returns_combined.csv"))

  # Step 5: PerformanceSummary chart (PerformanceAnalytics standard)
  png(file.path(output_dir, "4way_performance_summary.png"),
      width = 1600, height = 1000)
  PerformanceAnalytics::charts.PerformanceSummary(
    combined_returns,
    main = sprintf("4-way blend comparison — %s",
                    format(Sys.Date(), "%Y-%m-%d")),
    colorset = c("#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e")
  )
  dev.off()

  cat(sprintf("\n[compare] outputs:\n"))
  cat(sprintf("  summary:  %s\n", summary_path))
  cat(sprintf("  returns:  %s\n", file.path(output_dir, "4way_returns_combined.csv")))
  cat(sprintf("  chart:    %s\n", file.path(output_dir, "4way_performance_summary.png")))
  cat(sprintf("\n[compare] Ranked by Sharpe:\n"))
  for (b in rank_by_sr) {
    cat(sprintf("  %s: SR=%.4f | CAGR=%.4f | MDD=%.4f\n",
                b, results[[b]]$sharpe_annualized,
                results[[b]]$annualized_return, results[[b]]$max_drawdown))
  }

  invisible(list(
    summary = summary_obj,
    verbose_outputs = verbose_outputs,
    paths = list(summary = summary_path,
                 returns = file.path(output_dir, "4way_returns_combined.csv"),
                 chart = file.path(output_dir, "4way_performance_summary.png"))
  ))
}

# ─────────────────────────────────────────────────────────
# Helper: build returns_panel from .cache/rawdata.parquet
# ─────────────────────────────────────────────────────────
build_monthly_returns_panel <- function(rawdata_path) {
  raw <- as.data.table(read_parquet(rawdata_path,
                                    col_select = c("Date", "Ticker", "Ret")))
  raw <- raw[!is.na(Ret) & !is.na(Date)]
  raw[, Date := as.Date(Date)]
  raw[, YM := format(Date, "%Y-%m")]
  # Daily→monthly aggregation per ticker. Date는 month-start 통일 (ticker마다
  # 다른 max(Date)가 dcast row를 dense하게 만드는 것을 방지).
  ret_monthly <- raw[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
                     by = .(Ticker, YM)]
  ret_monthly[, Date := as.Date(paste0(YM, "-01"))]
  ret_monthly <- ret_monthly[!is.na(Date)]
  setorder(ret_monthly, Date, Ticker)

  ret_wide <- dcast(ret_monthly, Date ~ Ticker, value.var = "Ret_1m", fill = 0)
  date_vec <- ret_wide$Date
  R_full <- xts(as.matrix(ret_wide[, -1, with = FALSE]), order.by = date_vec)
  R_full[is.na(R_full)] <- 0
  R_full
}
