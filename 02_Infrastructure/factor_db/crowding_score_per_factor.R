#==============================================================================
# crowding_score_per_factor.R -- Per-factor Crowding Score (Acadian 2026 정통)
#
# 7 QEPM Modern Trends Phase 2.C
# Constitutional SOT: 02_Infrastructure/docs/qvest_research_philosophy.md Principle 5
#
# crowding_score_per_factor(factor_exposures, sig_date, RAWDATA, top_n = 20)
#   factor_exposures: data.table(Ticker, factor_name, exposure)
#   sig_date:         signal date (PIT)
#   RAWDATA:          for Vol / Size / institutional flow inputs
#   top_n:            decile/top-N portfolio size for concentration measure
#
# Returns: data.table(factor_name, crowding_score [0~1], hhi_top, vol_concentration,
#                     passive_overlap_proxy, demand_elasticity_proxy)
#
# 4 sub-components (weighted average):
#   1. HHI_top — Herfindahl-Hirschman Index of top-N factor portfolio weights
#                (proxies position concentration)
#   2. Vol_concentration — share of top-N portfolio volume in total market volume
#                          (proxies trading volume crowding)
#   3. Passive_overlap_proxy — overlap with KOSPI200/KOSDAQ150 benchmark
#                              (proxies passive ownership crowding)
#   4. Demand_elasticity_proxy — Size-weighted average rank reversal cost
#                                (Behmaram 2024, smaller = more elastic = less crowded)
#
# PIT: Date <= sig_date strict. C1-C15 정합.
#
# References:
#   - Acadian (2026) "Systematic Crowding Monitoring"
#   - Behmaram (2024) "Demand Elasticity in Equity Markets"
#   - Lou-Polk (2013) DTC factor
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

crowding_score_per_factor <- function(factor_exposures,
                                       sig_date,
                                       RAWDATA,
                                       benchmark_tickers = NULL,
                                       top_n = 20L,
                                       weights = list(hhi = 0.30,
                                                       vol = 0.25,
                                                       passive = 0.25,
                                                       elasticity = 0.20)) {

  stopifnot(is.data.table(factor_exposures) || is.data.frame(factor_exposures))
  if (!is.data.table(factor_exposures)) factor_exposures <- as.data.table(factor_exposures)
  required_cols <- c("Ticker", "factor_name", "exposure")
  if (!all(required_cols %in% names(factor_exposures))) {
    stop(sprintf("factor_exposures missing columns: %s",
                  paste(setdiff(required_cols, names(factor_exposures)), collapse = ", ")))
  }

  sig_d <- as.Date(sig_date)

  # ---- PIT-strict daily snapshot (most recent <= sig_date) ----
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  rd <- rd[Date <= sig_d]
  if (nrow(rd) == 0L) {
    return(data.table(factor_name = unique(factor_exposures$factor_name),
                       crowding_score = NA_real_))
  }
  setorder(rd, Ticker, Date)
  rd_last <- rd[, .SD[.N], by = Ticker, .SDcols = c("Date", "Close", "Vol", "Size")]

  total_market_vol <- sum(rd_last$Vol, na.rm = TRUE)
  total_market_size <- sum(rd_last$Size, na.rm = TRUE)

  out <- list()
  for (fname in unique(factor_exposures$factor_name)) {
    fe <- factor_exposures[factor_name == fname & !is.na(exposure)]
    if (nrow(fe) < top_n) {
      out[[fname]] <- data.table(factor_name = fname, crowding_score = NA_real_,
                                  hhi_top = NA_real_, vol_concentration = NA_real_,
                                  passive_overlap_proxy = NA_real_,
                                  demand_elasticity_proxy = NA_real_,
                                  n_universe = nrow(fe))
      next
    }

    setorder(fe, -exposure)
    top <- fe[1:top_n]
    top_merged <- merge(top, rd_last, by = "Ticker", all.x = TRUE)
    top_merged <- top_merged[!is.na(Size) & Size > 0]
    if (nrow(top_merged) < 5L) {
      out[[fname]] <- data.table(factor_name = fname, crowding_score = NA_real_,
                                  hhi_top = NA_real_, vol_concentration = NA_real_,
                                  passive_overlap_proxy = NA_real_,
                                  demand_elasticity_proxy = NA_real_,
                                  n_universe = nrow(fe))
      next
    }

    # (1) HHI — Cap-weighted concentration
    w <- top_merged$Size / sum(top_merged$Size, na.rm = TRUE)
    hhi <- sum(w^2)  # 1/N (perfectly diverse) ~ 1 (single name)
    # Normalize: hhi_score = (hhi - 1/N) / (1 - 1/N), in [0, 1]
    hhi_norm <- (hhi - 1/top_n) / max(1 - 1/top_n, 1e-12)

    # (2) Volume concentration — top-N share of total market trading volume
    vol_share <- if (total_market_vol > 0) sum(top_merged$Vol, na.rm = TRUE) / total_market_vol else NA_real_
    # Compare to neutral (top_n / N_universe). Higher = more concentrated.
    n_universe <- nrow(rd_last)
    neutral_share <- top_n / max(n_universe, 1L)
    vol_score <- if (!is.na(vol_share)) pmin(1, pmax(0, (vol_share - neutral_share) / (1 - neutral_share))) else NA_real_

    # (3) Passive overlap — share of top-N in benchmark constituents
    if (!is.null(benchmark_tickers) && length(benchmark_tickers) > 0) {
      overlap <- sum(top_merged$Ticker %in% benchmark_tickers) / top_n
      passive_score <- overlap  # 0 ~ 1 direct
    } else {
      # Fallback: top-N by Size (proxy for index inclusion)
      large_caps <- rd_last[order(-Size)][1:min(200L, .N), Ticker]
      overlap <- sum(top_merged$Ticker %in% large_caps) / top_n
      passive_score <- overlap
    }

    # (4) Demand elasticity proxy — inverse Size-weighted (smaller cap = less elastic = more cost)
    # Use ADV proxy if available, else use Size directly
    median_size_market <- median(rd_last$Size, na.rm = TRUE)
    median_size_top <- median(top_merged$Size, na.rm = TRUE)
    # If top is smaller than market median → more cost / less elastic → higher crowding when scaled
    size_ratio <- median_size_top / max(median_size_market, 1e-12)
    elasticity_score <- 1 - pmin(1, size_ratio)  # 0 (top very large = elastic) ~ 1 (top tiny)

    # Composite crowding score
    composite <- (
      (if (!is.na(hhi_norm)) weights$hhi * hhi_norm else 0) +
      (if (!is.na(vol_score)) weights$vol * vol_score else 0) +
      (if (!is.na(passive_score)) weights$passive * passive_score else 0) +
      (if (!is.na(elasticity_score)) weights$elasticity * elasticity_score else 0)
    )
    total_w <- (
      (if (!is.na(hhi_norm)) weights$hhi else 0) +
      (if (!is.na(vol_score)) weights$vol else 0) +
      (if (!is.na(passive_score)) weights$passive else 0) +
      (if (!is.na(elasticity_score)) weights$elasticity else 0)
    )
    composite_score <- if (total_w > 0) composite / total_w else NA_real_

    out[[fname]] <- data.table(
      factor_name = fname,
      crowding_score = composite_score,
      hhi_top = hhi_norm,
      vol_concentration = vol_score,
      passive_overlap_proxy = passive_score,
      demand_elasticity_proxy = elasticity_score,
      n_universe = n_universe,
      n_top = nrow(top_merged)
    )
  }

  rbindlist(out, fill = TRUE)
}

#==============================================================================
# Convenience: per-factor monitoring across sig_dates (decay detection)
#==============================================================================
crowding_timeseries <- function(factor_exposures_panel,
                                  sig_dates,
                                  RAWDATA,
                                  benchmark_tickers = NULL,
                                  top_n = 20L) {
  results <- list()
  for (sd in as.list(as.Date(sig_dates))) {
    fe_sd <- factor_exposures_panel[Date == sd]
    if (nrow(fe_sd) == 0L) next
    res <- crowding_score_per_factor(fe_sd, sd, RAWDATA,
                                       benchmark_tickers, top_n)
    res[, sig_date := sd]
    results[[as.character(sd)]] <- res
  }
  rbindlist(results, fill = TRUE)
}

#==============================================================================
# Crowding alert: factor-level threshold breach detection
#==============================================================================
crowding_alert <- function(crowding_ts,
                            threshold_high = 0.75,
                            threshold_increase_3m = 0.15) {
  setorder(crowding_ts, factor_name, sig_date)
  crowding_ts[, crowding_3m_ago := shift(crowding_score, 3L), by = factor_name]
  crowding_ts[, crowding_delta_3m := crowding_score - crowding_3m_ago]
  alerts <- crowding_ts[
    (crowding_score >= threshold_high) |
    (crowding_delta_3m >= threshold_increase_3m & !is.na(crowding_delta_3m))
  ]
  alerts[, alert_reason := fifelse(
    crowding_score >= threshold_high & crowding_delta_3m >= threshold_increase_3m,
    "BOTH_HIGH_AND_RISING",
    fifelse(crowding_score >= threshold_high, "HIGH_LEVEL", "RAPID_INCREASE"))]
  alerts[, .(factor_name, sig_date, crowding_score, crowding_3m_ago,
              crowding_delta_3m, alert_reason)]
}
