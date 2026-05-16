#==============================================================================
# brinson_decomp.R -- Brinson-Fachler Performance Attribution (Sector-level)
#
# 7 QEPM Modern Trends Phase 2.D
# Constitutional SOT: qvest_research_philosophy.md Principle 7 — Attribution & Feedback Loop
#
# brinson_decomp(portfolio_panel, benchmark_panel, returns_panel)
#   portfolio_panel: data.table(Date, Ticker, weight)         (sums to 1 per Date)
#   benchmark_panel: data.table(Date, Ticker, weight)         (sums to 1 per Date)
#   returns_panel:   data.table(Date, Ticker, Sector, Ret_1m_fwd)
#
# Returns: list(
#   per_period:  data.table per Date with allocation/selection/interaction effects
#   per_sector:  cumulative sector-level decomposition
#   summary:     total {allocation, selection, interaction, total_active}
# )
#
# Brinson-Fachler formulas:
#   Allocation_k = (w_p_k - w_b_k) × (r_b_k - r_b_total)
#   Selection_k  = w_b_k × (r_p_k - r_b_k)
#   Interaction_k = (w_p_k - w_b_k) × (r_p_k - r_b_k)
#
# References:
#   Brinson, Hood & Beebower (1986) "Determinants of Portfolio Performance" FAJ
#   Brinson & Fachler (1985) "Measuring Non-US Equity Portfolio Performance" JoPM
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

brinson_decomp <- function(portfolio_panel, benchmark_panel, returns_panel,
                            date_col = "Date", ticker_col = "Ticker",
                            sector_col = "Sector", ret_col = "Ret_1m_fwd") {

  port <- as.data.table(portfolio_panel)
  bench <- as.data.table(benchmark_panel)
  rets <- as.data.table(returns_panel)

  setnames(port,  c(date_col, ticker_col, "weight"), c("Date", "Ticker", "w_p"), skip_absent = TRUE)
  setnames(bench, c(date_col, ticker_col, "weight"), c("Date", "Ticker", "w_b"), skip_absent = TRUE)
  setnames(rets,  c(date_col, ticker_col, sector_col, ret_col),
                  c("Date", "Ticker", "Sector", "ret"), skip_absent = TRUE)

  port[, Date := as.Date(Date)]
  bench[, Date := as.Date(Date)]
  rets[, Date := as.Date(Date)]

  # Merge into combined panel per (Date, Ticker)
  merged <- merge(port, bench, by = c("Date", "Ticker"), all = TRUE)
  merged[is.na(w_p), w_p := 0]
  merged[is.na(w_b), w_b := 0]
  merged <- merge(merged, rets[, .(Date, Ticker, Sector, ret)],
                   by = c("Date", "Ticker"), all.x = TRUE)
  merged <- merged[!is.na(ret) & !is.na(Sector)]
  if (nrow(merged) == 0L) {
    return(list(per_period = data.table(), per_sector = data.table(),
                 summary = list()))
  }

  # ---- Per (Date, Sector) aggregates ----
  per_ds <- merged[, .(
    w_p_k = sum(w_p, na.rm = TRUE),
    w_b_k = sum(w_b, na.rm = TRUE),
    r_p_k = sum(w_p * ret, na.rm = TRUE) / pmax(sum(w_p, na.rm = TRUE), 1e-12),
    r_b_k = sum(w_b * ret, na.rm = TRUE) / pmax(sum(w_b, na.rm = TRUE), 1e-12)
  ), by = .(Date, Sector)]

  # Replace NaN/Inf with 0 for empty sectors
  per_ds[is.nan(r_p_k) | is.infinite(r_p_k), r_p_k := 0]
  per_ds[is.nan(r_b_k) | is.infinite(r_b_k), r_b_k := 0]

  # ---- Total benchmark return per Date ----
  bench_total <- per_ds[, .(r_b_total = sum(w_b_k * r_b_k, na.rm = TRUE)), by = Date]
  per_ds <- merge(per_ds, bench_total, by = "Date")

  # ---- Brinson-Fachler ----
  per_ds[, allocation := (w_p_k - w_b_k) * (r_b_k - r_b_total)]
  per_ds[, selection  := w_b_k * (r_p_k - r_b_k)]
  per_ds[, interaction := (w_p_k - w_b_k) * (r_p_k - r_b_k)]

  # ---- Per-period aggregation ----
  per_period <- per_ds[, .(
    allocation = sum(allocation, na.rm = TRUE),
    selection = sum(selection, na.rm = TRUE),
    interaction = sum(interaction, na.rm = TRUE),
    r_p_total = sum(w_p_k * r_p_k, na.rm = TRUE),
    r_b_total = first(r_b_total)
  ), by = Date]
  per_period[, total_active := r_p_total - r_b_total]
  per_period[, residual := total_active - allocation - selection - interaction]

  # ---- Per-sector cumulative ----
  per_sector <- per_ds[, .(
    cum_allocation = sum(allocation, na.rm = TRUE),
    cum_selection = sum(selection, na.rm = TRUE),
    cum_interaction = sum(interaction, na.rm = TRUE),
    cum_total_effect = sum(allocation + selection + interaction, na.rm = TRUE),
    n_months = .N
  ), by = Sector][order(-cum_total_effect)]

  # ---- Total summary ----
  total_active_sum <- sum(per_period$total_active, na.rm = TRUE)
  summary <- list(
    cum_allocation = sum(per_period$allocation, na.rm = TRUE),
    cum_selection = sum(per_period$selection, na.rm = TRUE),
    cum_interaction = sum(per_period$interaction, na.rm = TRUE),
    cum_total_active = total_active_sum,
    cum_portfolio_return = sum(per_period$r_p_total, na.rm = TRUE),
    cum_benchmark_return = sum(per_period$r_b_total, na.rm = TRUE),
    n_periods = nrow(per_period),
    sum_check_residual = total_active_sum - sum(per_period$allocation + per_period$selection +
                                                 per_period$interaction, na.rm = TRUE)
  )

  list(per_period = per_period, per_sector = per_sector, summary = summary)
}

#==============================================================================
# Helper: format Brinson summary for telegram/report
#==============================================================================
brinson_summary_text <- function(brinson_result, lang = "ko") {
  s <- brinson_result$summary
  if (lang == "ko") {
    sprintf(paste0(
      "Brinson 분해 (%d개월)\n",
      "── 총 active: %+.2fpp\n",
      "── 섹터배분 (allocation): %+.2fpp\n",
      "── 종목선택 (selection): %+.2fpp\n",
      "── 상호작용 (interaction): %+.2fpp\n",
      "── 잔차: %+.4fpp (sum-check)\n",
      "── port: %+.2f%% / bench: %+.2f%%"
    ), s$n_periods,
       s$cum_total_active * 100,
       s$cum_allocation * 100,
       s$cum_selection * 100,
       s$cum_interaction * 100,
       s$sum_check_residual * 100,
       s$cum_portfolio_return * 100,
       s$cum_benchmark_return * 100)
  } else {
    sprintf(paste0(
      "Brinson Decomposition (%d months)\n",
      "── Total active: %+.2fpp\n",
      "── Allocation: %+.2fpp\n",
      "── Selection: %+.2fpp\n",
      "── Interaction: %+.2fpp\n",
      "── Residual: %+.4fpp\n",
      "── Portfolio: %+.2f%% / Benchmark: %+.2f%%"
    ), s$n_periods,
       s$cum_total_active * 100,
       s$cum_allocation * 100,
       s$cum_selection * 100,
       s$cum_interaction * 100,
       s$sum_check_residual * 100,
       s$cum_portfolio_return * 100,
       s$cum_benchmark_return * 100)
  }
}
