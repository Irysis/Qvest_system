#==============================================================================
# Quant Module — Report Charts Library
# report_charts.R
#
# Independent chart rendering functions for agent-driven reports.
# Each function returns a plotly object or writes an HTML table via cat().
#
# Usage: source("02_Infrastructure/report_charts.R")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(xts)
  library(plotly)
  library(arrow)
})

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.na(a)) return(b)
  a
}

# ── Shared theme ──
.rc_ib_colors <- list(

  primary   = "#003366",
  secondary = "#004d99",
  accent    = "#0066cc",
  red       = "#8B0000",
  green     = "#28a745",
  orange    = "#FF9800",
  gray      = "gray70",
  bg        = "white"
)

.rc_layout_base <- function(p, title_text = "", yaxis_title = "", xaxis_title = "",
                            show_legend = TRUE) {
  legend_cfg <- if (show_legend) list(orientation = "h", y = -0.12) else list(visible = FALSE)
  p %>% layout(
    title = list(text = title_text,
                 font = list(color = .rc_ib_colors$primary, size = 16)),
    yaxis = list(title = yaxis_title, gridcolor = "#eee"),
    xaxis = list(title = xaxis_title, gridcolor = "#eee"),
    legend = legend_cfg,
    hovermode = "x unified",
    plot_bgcolor = .rc_ib_colors$bg,
    paper_bgcolor = .rc_ib_colors$bg
  )
}

#==============================================================================
# 1. Equity Curve (with regime overlay)
#==============================================================================
rc_equity_curve <- function(sim, strat_id, regime_cache_path = NULL) {

  strat_xts <- sim$strategy_xts
  daily_ret <- as.numeric(strat_xts)
  cum_s <- cumprod(1 + daily_ret)
  dates <- as.Date(index(strat_xts))

  cum_bm <- if (!is.null(sim$bm_xts)) cumprod(1 + as.numeric(sim$bm_xts)) else rep(1, length(cum_s))

  eq_dt <- data.table(Date = dates, Strategy = cum_s, BM = cum_bm)

  # Regime overlay
  regime_shapes <- list()
  regime_annotations <- list()

  if (!is.null(regime_cache_path) && file.exists(regime_cache_path)) {
    regime_dt <- as.data.table(read_parquet(regime_cache_path))
    regime_dt[, YM := format(Date, "%Y-%m")]
    eq_dt[, YM := format(Date, "%Y-%m")]
    eq_dt <- merge(eq_dt, regime_dt[, .(YM, VIX_Regime)], by = "YM", all.x = TRUE)
    eq_dt[is.na(VIX_Regime), VIX_Regime := "normal"]
    setorder(eq_dt, Date)

    eq_dt[, grp := cumsum(c(1, diff(as.numeric(factor(VIX_Regime))) != 0))]
    rects <- eq_dt[, .(x0 = min(Date), x1 = max(Date), regime = VIX_Regime[1]), by = grp]

    regime_shapes <- lapply(1:nrow(rects), function(i) {
      color <- switch(rects$regime[i],
                      "crisis" = "rgba(229,57,53,0.30)",
                      "elevated" = "rgba(255,152,0,0.25)",
                      "rgba(129,199,132,0.15)")
      list(type = "rect", x0 = rects$x0[i], x1 = rects$x1[i],
           y0 = 0, y1 = 1, yref = "paper", fillcolor = color,
           line = list(width = 0), layer = "below")
    })

    regime_annotations <- list(
      list(x = "2008-09-15", y = 1, yref = "paper", text = "GFC", showarrow = FALSE,
           font = list(size = 9, color = "#c62828"), bgcolor = "rgba(255,255,255,0.7)"),
      list(x = "2020-03-15", y = 1, yref = "paper", text = "COVID", showarrow = FALSE,
           font = list(size = 9, color = "#c62828"), bgcolor = "rgba(255,255,255,0.7)"),
      list(x = "2022-06-15", y = 1, yref = "paper", text = "Rate Hike", showarrow = FALSE,
           font = list(size = 9, color = "#e65100"), bgcolor = "rgba(255,255,255,0.7)"),
      list(x = "2018-09-15", y = 1, yref = "paper", text = "Trade War", showarrow = FALSE,
           font = list(size = 9, color = "#e65100"), bgcolor = "rgba(255,255,255,0.7)"))
  }

  p <- plot_ly() %>%
    add_lines(x = eq_dt$Date, y = eq_dt$Strategy, name = strat_id,
              line = list(color = .rc_ib_colors$primary, width = 2),
              hovertemplate = paste0("Date: %{x|%Y-%m-%d}<br>Growth: %{y:.2f}x<extra>",
                                    strat_id, "</extra>")) %>%
    add_lines(x = eq_dt$Date, y = eq_dt$BM, name = "KOSPI200",
              line = list(color = "#FF6B6B", width = 1.5),
              hovertemplate = "Date: %{x|%Y-%m-%d}<br>Growth: %{y:.2f}x<extra>KOSPI200</extra>") %>%
    layout(
      title = list(text = "Equity Curve (Log Scale) with Regime Overlay",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(type = "log", title = "Growth of 1", gridcolor = "#eee"),
      xaxis = list(title = "", gridcolor = "#eee"),
      shapes = regime_shapes,
      annotations = regime_annotations,
      hovermode = "x unified",
      legend = list(orientation = "h", y = -0.1),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
  p
}

#==============================================================================
# 2. Drawdown Chart
#==============================================================================
rc_drawdown <- function(sim, mdd_value = NULL) {

  daily_ret <- as.numeric(sim$strategy_xts)
  cum_s <- cumprod(1 + daily_ret)
  dates <- as.Date(index(sim$strategy_xts))
  dd <- cum_s / cummax(cum_s) - 1

  mdd_label <- if (!is.null(mdd_value)) sprintf(" | MDD = -%.2f%%", mdd_value) else ""


  plot_ly(x = dates, y = dd * 100, type = "scatter", mode = "lines",
          fill = "tozeroy", fillcolor = "rgba(139,0,0,0.15)",
          line = list(color = .rc_ib_colors$red, width = 1),
          hovertemplate = "Date: %{x}<br>Drawdown: %{y:.2f}%<extra></extra>") %>%
    layout(
      title = list(text = paste0("Maximum Drawdown", mdd_label),
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(title = "Drawdown (%)", gridcolor = "#eee"),
      xaxis = list(title = "", gridcolor = "#eee"),
      shapes = list(
        list(type = "line", x0 = min(dates), x1 = max(dates), y0 = -5, y1 = -5,
             line = list(color = "gray70", dash = "dot", width = 0.5)),
        list(type = "line", x0 = min(dates), x1 = max(dates), y0 = -10, y1 = -10,
             line = list(color = "gray70", dash = "dot", width = 0.5)),
        list(type = "line", x0 = min(dates), x1 = max(dates), y0 = -15, y1 = -15,
             line = list(color = "gray70", dash = "dot", width = 0.5))
      ),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 3. Annual Returns (vs benchmark)
#==============================================================================
rc_annual_returns <- function(sim, strat_id) {

  daily_ret_s <- as.numeric(sim$strategy_xts)
  dates <- as.Date(index(sim$strategy_xts))
  bm_ret <- if (!is.null(sim$bm_xts)) as.numeric(sim$bm_xts) else rep(0, length(daily_ret_s))

  ann_dt <- data.table(Date = dates, Strat = daily_ret_s, BM = bm_ret)
  ann_dt[, Year := format(Date, "%Y")]
  annual <- ann_dt[, .(
    Strategy = (prod(1 + Strat) - 1) * 100,
    KOSPI200 = (prod(1 + BM) - 1) * 100
  ), by = Year]

  plot_ly(annual, x = ~Year) %>%
    add_bars(y = ~Strategy, name = strat_id, marker = list(color = .rc_ib_colors$primary),
             hovertemplate = paste0("%{y:.1f}%<extra>", strat_id, "</extra>")) %>%
    add_bars(y = ~KOSPI200, name = "KOSPI200", marker = list(color = "lightgray"),
             hovertemplate = "%{y:.1f}%<extra>KOSPI200</extra>") %>%
    layout(barmode = "group",
           title = list(text = "Annual Returns",
                        font = list(color = .rc_ib_colors$primary, size = 16)),
           yaxis = list(title = "Return (%)", zeroline = TRUE),
           xaxis = list(title = ""),
           hovermode = "x unified",
           legend = list(orientation = "h", y = -0.15),
           plot_bgcolor = "white", paper_bgcolor = "white")
}

#==============================================================================
# 4. Rolling Sharpe (6M + 12M)
#==============================================================================
rc_rolling_sharpe <- function(sim, windows = c(126, 252),
                              hit6m = NULL, hit12m = NULL) {

  daily_ret <- as.numeric(sim$strategy_xts)
  dates <- as.Date(index(sim$strategy_xts))

  roll_6m <- data.table::frollapply(daily_ret, windows[1],
                                     function(x) mean(x) / sd(x) * sqrt(252))
  roll_12m <- data.table::frollapply(daily_ret, windows[2],
                                      function(x) mean(x) / sd(x) * sqrt(252))

  hit6_label <- if (!is.null(hit6m)) sprintf("%.1f%%", hit6m) else "--"
  hit12_label <- if (!is.null(hit12m)) sprintf("%.1f%%", hit12m) else "--"
  roll_title <- sprintf("Rolling Sharpe Ratio | 6M hit rate: %s | 12M hit rate: %s",
                         hit6_label, hit12_label)

  zero_line <- function(d) list(type = "line", x0 = min(d), x1 = max(d),
                                y0 = 0, y1 = 0, line = list(color = "#333", width = 0.8))
  ref_line <- function(d, yval) list(type = "line", x0 = min(d), x1 = max(d),
                                      y0 = yval, y1 = yval,
                                      line = list(color = "gray80", dash = "dot"))

  subplot(
    plot_ly() %>%
      add_lines(x = dates[!is.na(roll_6m)], y = roll_6m[!is.na(roll_6m)],
                name = "6M Rolling", line = list(color = .rc_ib_colors$primary, width = 1.2),
                hovertemplate = "Date: %{x}<br>Sharpe: %{y:.2f}<extra>6M</extra>") %>%
      layout(yaxis = list(title = "Sharpe", gridcolor = "#eee"),
             shapes = list(zero_line(dates), ref_line(dates, 1), ref_line(dates, 2)),
             annotations = list(list(text = "6-Month Rolling Sharpe", x = 0.01, y = 1,
                                     xref = "paper", yref = "paper", showarrow = FALSE,
                                     font = list(size = 13, color = .rc_ib_colors$primary,
                                                 weight = "bold")))),
    plot_ly() %>%
      add_lines(x = dates[!is.na(roll_12m)], y = roll_12m[!is.na(roll_12m)],
                name = "12M Rolling", line = list(color = .rc_ib_colors$secondary, width = 1.2),
                hovertemplate = "Date: %{x}<br>Sharpe: %{y:.2f}<extra>12M</extra>") %>%
      layout(yaxis = list(title = "Sharpe", gridcolor = "#eee"),
             shapes = list(zero_line(dates), ref_line(dates, 1), ref_line(dates, 2)),
             annotations = list(list(text = "12-Month Rolling Sharpe", x = 0.01, y = 1,
                                     xref = "paper", yref = "paper", showarrow = FALSE,
                                     font = list(size = 13, color = .rc_ib_colors$primary,
                                                 weight = "bold")))),
    nrows = 2, shareX = TRUE, titleY = TRUE
  ) %>%
    layout(
      title = list(text = roll_title,
                   font = list(color = .rc_ib_colors$primary, size = 14)),
      xaxis = list(title = "", gridcolor = "#eee"),
      legend = list(orientation = "h", y = -0.08),
      plot_bgcolor = "white", paper_bgcolor = "white",
      hovermode = "x unified"
    )
}

#==============================================================================
# 5. Sleeve Contribution (stacked bar — annual)
#==============================================================================
rc_sleeve_contribution <- function(sleeve_csv_path) {

  if (!file.exists(sleeve_csv_path)) return(NULL)

  sc <- fread(sleeve_csv_path)
  sleeve_cols <- setdiff(names(sc), "Year")
  sleeve_colors <- c("#E74C3C", "#2E86C1", "#27AE60", "#F39C12", "#8E44AD", "#1ABC9C")

  p <- plot_ly(sc, x = ~Year)
  for (i in seq_along(sleeve_cols)) {
    col_name <- sleeve_cols[i]
    p <- p %>%
      add_bars(y = sc[[col_name]] * 100, name = col_name,
               marker = list(color = sleeve_colors[min(i, length(sleeve_colors))]))
  }
  p %>%
    layout(barmode = "stack",
           title = list(text = "Annual Sleeve Contribution (%)",
                        font = list(color = .rc_ib_colors$primary, size = 16)),
           yaxis = list(title = "Return (%)"),
           xaxis = list(title = ""),
           hovermode = "x unified",
           legend = list(orientation = "h", y = -0.15),
           plot_bgcolor = "white", paper_bgcolor = "white")
}

#==============================================================================
# 6. Sleeve Correlation Heatmap
#==============================================================================
rc_sleeve_correlation <- function(sleeve_sims) {

  if (length(sleeve_sims) < 2) return(NULL)

  # Align dates
  common_dates <- Reduce(intersect, lapply(sleeve_sims, function(s) as.Date(index(s$strategy_xts))))
  common_dates <- sort(as.Date(common_dates))
  if (length(common_dates) < 60) return(NULL)

  mat <- do.call(cbind, lapply(sleeve_sims, function(s) as.numeric(s$strategy_xts[common_dates])))
  colnames(mat) <- names(sleeve_sims)
  corr <- cor(mat, use = "pairwise.complete.obs")

  plot_ly(x = colnames(corr), y = rownames(corr), z = corr,
          type = "heatmap",
          colorscale = list(c(0, "#003366"), c(0.5, "white"), c(1, "#cc0000")),
          zmin = -1, zmax = 1,
          hovertemplate = "%{x} vs %{y}: %{z:.3f}<extra></extra>") %>%
    layout(
      title = list(text = "Sleeve Return Correlation",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 7. Sleeve Weights Timeline (Factor Momentum weights over time)
#==============================================================================
rc_sleeve_weights <- function(fm_weights_dt) {

  if (is.null(fm_weights_dt) || nrow(fm_weights_dt) == 0) return(NULL)

  # Expect columns: Date, plus one column per sleeve weight
  date_col <- names(fm_weights_dt)[1]
  weight_cols <- setdiff(names(fm_weights_dt), date_col)
  sleeve_colors <- c("#E74C3C", "#2E86C1", "#27AE60", "#F39C12", "#8E44AD", "#1ABC9C")

  p <- plot_ly()
  for (i in seq_along(weight_cols)) {
    p <- p %>%
      add_lines(x = fm_weights_dt[[date_col]], y = fm_weights_dt[[weight_cols[i]]] * 100,
                name = weight_cols[i], fill = "tonexty",
                line = list(color = sleeve_colors[min(i, length(sleeve_colors))], width = 0.5))
  }
  p %>%
    layout(
      title = list(text = "Factor Momentum Weight Allocation Over Time",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(title = "Weight (%)", range = c(0, 100)),
      xaxis = list(title = ""),
      hovermode = "x unified",
      legend = list(orientation = "h", y = -0.12),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 8. Overlay Attribution (cumulative comparison: base vs +VT vs +VT+DD etc.)
#==============================================================================
rc_overlay_attribution <- function(overlay_sims) {

  if (length(overlay_sims) < 2) return(NULL)

  overlay_colors <- c("#999999", "#2196F3", "#FF9800", "#4CAF50", "#9C27B0")
  overlay_names <- names(overlay_sims)

  p <- plot_ly()
  for (i in seq_along(overlay_sims)) {
    ret <- as.numeric(overlay_sims[[i]]$strategy_xts)
    cum <- cumprod(1 + ret)
    dates <- as.Date(index(overlay_sims[[i]]$strategy_xts))
    p <- p %>%
      add_lines(x = dates, y = cum, name = overlay_names[i],
                line = list(color = overlay_colors[min(i, length(overlay_colors))],
                            width = if (i == length(overlay_sims)) 2.5 else 1.2),
                hovertemplate = paste0("Date: %{x}<br>Growth: %{y:.2f}x<extra>",
                                      overlay_names[i], "</extra>"))
  }
  p %>%
    layout(
      title = list(text = "Overlay Attribution: Cumulative Impact",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(type = "log", title = "Growth of 1", gridcolor = "#eee"),
      xaxis = list(title = "", gridcolor = "#eee"),
      hovermode = "x unified",
      legend = list(orientation = "h", y = -0.12),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 9. Exposure Timeline (VT / DD Brake / MRS exposure over time)
#==============================================================================
rc_exposure_timeline <- function(exposure_dt) {

  if (is.null(exposure_dt) || nrow(exposure_dt) == 0) return(NULL)

  # Expect columns: Date, plus exposure columns (vt_scale, dd_exp, mrs_exp, combined)
  date_col <- "Date"
  exp_cols <- setdiff(names(exposure_dt), date_col)
  exp_colors <- c("VT" = "#2196F3", "DD_Brake" = "#FF9800",
                  "Soft_MRS" = "#9C27B0", "Combined" = "#333333",
                  "vt_scale" = "#2196F3", "dd_exp" = "#FF9800",
                  "mrs_exp" = "#9C27B0", "combined" = "#333333")

  p <- plot_ly()
  for (col in exp_cols) {
    color <- if (col %in% names(exp_colors)) exp_colors[[col]] else "#666"
    p <- p %>%
      add_lines(x = exposure_dt[[date_col]], y = exposure_dt[[col]] * 100,
                name = col,
                line = list(color = color, width = if (col %in% c("Combined", "combined")) 2 else 1),
                hovertemplate = paste0("%{x}<br>", col, ": %{y:.1f}%<extra></extra>"))
  }
  p %>%
    layout(
      title = list(text = "Daily Exposure Timeline",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(title = "Exposure (%)", range = c(0, 105), gridcolor = "#eee"),
      xaxis = list(title = "", gridcolor = "#eee"),
      hovermode = "x unified",
      legend = list(orientation = "h", y = -0.12),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 10. DD Brake Activation (time series of brake intensity)
#==============================================================================
rc_dd_brake_activation <- function(dates, dd_exp_med, dd_exp_short = NULL) {

  p <- plot_ly()
  p <- p %>%
    add_lines(x = dates, y = (1 - dd_exp_med) * 100,
              name = "Medium-term Brake", fill = "tozeroy",
              fillcolor = "rgba(255,152,0,0.2)",
              line = list(color = "#FF9800", width = 1),
              hovertemplate = "Date: %{x}<br>Reduction: %{y:.1f}%<extra>Medium</extra>")

  if (!is.null(dd_exp_short)) {
    p <- p %>%
      add_lines(x = dates, y = (1 - dd_exp_short) * 100,
                name = "Short-term Brake",
                line = list(color = "#E74C3C", width = 1, dash = "dot"),
                hovertemplate = "Date: %{x}<br>Reduction: %{y:.1f}%<extra>Short</extra>")
  }
  p %>%
    layout(
      title = list(text = "DD Brake Activation Intensity",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(title = "Exposure Reduction (%)", gridcolor = "#eee"),
      xaxis = list(title = "", gridcolor = "#eee"),
      hovermode = "x unified",
      legend = list(orientation = "h", y = -0.12),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 11. IC Time Series (+ rolling ICIR)
#==============================================================================
rc_ic_timeseries <- function(ic_csv_path) {

  if (!file.exists(ic_csv_path)) return(NULL)

  ic <- fread(ic_csv_path)
  if (!"IC" %in% names(ic)) return(NULL)

  date_col <- intersect(c("Date", "YM", "date"), names(ic))[1]
  if (is.na(date_col)) return(NULL)

  ic_vals <- ic$IC
  ic_dates <- ic[[date_col]]

  # Rolling ICIR (12-month)
  rolling_icir <- data.table::frollapply(ic_vals, 12, function(x) mean(x, na.rm = TRUE) / sd(x, na.rm = TRUE))

  subplot(
    plot_ly() %>%
      add_bars(x = ic_dates, y = ic_vals, name = "Monthly IC",
               marker = list(color = ifelse(ic_vals >= 0, "#003366", "#cc3333")),
               hovertemplate = "%{x}<br>IC: %{y:.4f}<extra></extra>") %>%
      layout(yaxis = list(title = "IC")),
    plot_ly() %>%
      add_lines(x = ic_dates[!is.na(rolling_icir)], y = rolling_icir[!is.na(rolling_icir)],
                name = "12M Rolling ICIR",
                line = list(color = .rc_ib_colors$secondary, width = 1.5)) %>%
      layout(yaxis = list(title = "ICIR")),
    nrows = 2, shareX = TRUE, titleY = TRUE
  ) %>%
    layout(
      title = list(text = "Information Coefficient Time Series",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      legend = list(orientation = "h", y = -0.12),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

#==============================================================================
# 12. Sector Exposure Heatmap
#==============================================================================
rc_sector_exposure <- function(holdings_csv_path) {

  if (!file.exists(holdings_csv_path)) return(NULL)

  hld <- fread(holdings_csv_path)
  if (!"Sector" %in% names(hld)) return(NULL)

  date_col <- intersect(c("Signal_Date", "Date", "YM"), names(hld))[1]
  if (is.na(date_col)) return(NULL)

  # Count sector exposure per period
  sector_exp <- hld[, .N, by = c(date_col, "Sector")]
  sector_total <- hld[, .N, by = date_col]
  setnames(sector_total, "N", "Total")
  sector_exp <- merge(sector_exp, sector_total, by = date_col)
  sector_exp[, Pct := N / Total]

  # Pivot for heatmap
  sector_wide <- dcast(sector_exp, get(date_col) ~ Sector, value.var = "Pct", fill = 0)
  mat <- as.matrix(sector_wide[, -1])
  rownames(mat) <- as.character(sector_wide[[1]])

  plot_ly(x = colnames(mat), y = rownames(mat), z = mat * 100,
          type = "heatmap",
          colorscale = list(c(0, "white"), c(1, "#003366")),
          hovertemplate = "%{y}<br>%{x}: %{z:.1f}%<extra></extra>") %>%
    layout(
      title = list(text = "Sector Exposure Over Time",
                   font = list(color = .rc_ib_colors$primary, size = 16)),
      yaxis = list(title = "", autorange = "reversed"),
      xaxis = list(title = "", tickangle = -45),
      plot_bgcolor = "white", paper_bgcolor = "white"
    )
}

cat("[report_charts] Loaded: 12 chart functions (rc_*)\n")
