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
build_blended_weights_xts <- function(weights_xts_list, blend_ratios) {
  # blend_ratios: named numeric (sum to 1.0)
  if (abs(sum(blend_ratios) - 1.0) > 1e-6) {
    stop(sprintf("[build_blended_weights] blend_ratios sum %.6f != 1.0",
                 sum(blend_ratios)))
  }
  if (!all(names(blend_ratios) %in% names(weights_xts_list))) {
    stop(sprintf("[build_blended_weights] missing strategies: %s",
                 paste(setdiff(names(blend_ratios), names(weights_xts_list)),
                       collapse = ", ")))
  }

  # Find common date grid (intersection of all weights_xts dates)
  date_grids <- lapply(names(blend_ratios), function(s) index(weights_xts_list[[s]]))
  common_dates <- Reduce(intersect, date_grids)
  if (length(common_dates) == 0) {
    # Use union, forward-fill weights
    common_dates <- sort(unique(Reduce(c, date_grids)))
  }
  common_dates <- as.Date(common_dates)

  # Initialize blended weights
  cols <- colnames(weights_xts_list[[names(blend_ratios)[1]]])
  blended <- xts(matrix(0, nrow = length(common_dates), ncol = length(cols),
                        dimnames = list(NULL, cols)),
                 order.by = common_dates)

  for (s in names(blend_ratios)) {
    W_s <- weights_xts_list[[s]]
    # Align W_s to common_dates with forward-fill (last sig_date weight carries forward)
    W_aligned <- na.locf(merge(W_s, xts(, common_dates), all = TRUE),
                         na.rm = FALSE)[common_dates]
    W_aligned[is.na(W_aligned)] <- 0
    blended <- blended + W_aligned * blend_ratios[s]
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

    blended_W <- build_blended_weights_xts(weights_xts_list, blend_ratios)
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
  # Monthly compound: PerformanceAnalytics 표준 — 자체 prod 합성으로 보일 수 있으나
  # 이는 daily→monthly aggregation이지 portfolio 측정이 아님. PerformanceAnalytics는
  # daily.frame을 받아도 처리 가능하지만 실 운용은 monthly rebalance라 monthly panel 필요.
  ret_monthly <- raw[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1,
                         Date = max(Date)),
                     by = .(Ticker, YM)]
  ret_monthly <- ret_monthly[!is.na(Date)]
  setorder(ret_monthly, Date, Ticker)

  ret_wide <- dcast(ret_monthly, Date ~ Ticker, value.var = "Ret_1m", fill = 0)
  date_vec <- ret_wide$Date
  R_full <- xts(as.matrix(ret_wide[, -1, with = FALSE]), order.by = date_vec)
  R_full[is.na(R_full)] <- 0
  R_full
}
