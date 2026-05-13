#==============================================================================
# Benchmark Comparison Charts — STR_1715_AR_on_M4_R05_overlay_PG2 (V2 admit)
# vs KOSPI200 Total Return
#
# 도훈 mandate 2026-05-13: 전략 상세 브리핑 + 초과수익률 시각화
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(scales)
  library(PerformanceAnalytics)
})

suppressPackageStartupMessages({library(xts)})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "qepm/mailbox/worktask/WT-H20260513_001/output")

# 1. Strategy returns (V2 admit, monthly) — YM key merge (도훈 audit 9 정합)
pr <- fread(file.path(OUT, "period_returns_layer5.csv"))
pr[, YM := substr(anchor_date, 1, 7)]

# 2. Benchmark monthly returns (KOSPI200) — month-end close → return
bm_daily <- as.data.table(read_parquet(file.path(PROJ, ".cache/benchmark.parquet")))
bm_daily[, Date := as.Date(Date)]
bm_daily[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(BM_Close_eom = last(BM_Close)), by = YM]
bm_monthly[, BM_Ret_M := BM_Close_eom / shift(BM_Close_eom) - 1]

# Merge — YM key (date format mismatch 회피)
dt <- merge(pr[, .(YM, ret_strategy = ret_L5_V2, regime)],
            bm_monthly[, .(YM, ret_bm = BM_Ret_M)], by = "YM", all.x = TRUE)
dt <- dt[!is.na(ret_strategy) & !is.na(ret_bm)]

# Restrict to admit-comparable 255m (2005-02 ~ 2026-04)
dt <- dt[YM >= "2005-02" & YM <= "2026-04"]
dt[, Date := as.Date(paste0(YM, "-01"))]
dt[, active_ret := ret_strategy - ret_bm]

cat(sprintf("n_months merged (admit-comparable 255m): %d | first: %s | last: %s\n",
            nrow(dt), min(dt$YM), max(dt$YM)))

# 3. Cumulative NAV
dt[, nav_strategy := cumprod(1 + ret_strategy)]
dt[, nav_bm       := cumprod(1 + ret_bm)]
dt[, nav_active   := cumprod(1 + active_ret)]

# 4. Summary metrics — PerformanceAnalytics standard (도훈 audit 9)
strat_xts <- xts(dt$ret_strategy, order.by = dt$Date)
bm_xts    <- xts(dt$ret_bm,       order.by = dt$Date)
active_xts <- xts(dt$active_ret,   order.by = dt$Date)

t_strat <- table.AnnualizedReturns(strat_xts)
t_bm    <- table.AnnualizedReturns(bm_xts)
t_active <- table.AnnualizedReturns(active_xts)

metrics <- list(
  Strategy = list(
    CAGR = as.numeric(t_strat[1, 1]),
    Vol  = as.numeric(t_strat[2, 1]),
    SR   = as.numeric(t_strat[3, 1]),
    MDD  = as.numeric(maxDrawdown(strat_xts))
  ),
  Benchmark = list(
    CAGR = as.numeric(t_bm[1, 1]),
    Vol  = as.numeric(t_bm[2, 1]),
    SR   = as.numeric(t_bm[3, 1]),
    MDD  = as.numeric(maxDrawdown(bm_xts))
  ),
  Active = list(
    CAGR    = as.numeric(t_active[1, 1]),
    TE      = as.numeric(TrackingError(strat_xts, bm_xts, scale = 12)),
    IR      = as.numeric(InformationRatio(strat_xts, bm_xts, scale = 12)),
    HitRate = mean(dt$ret_strategy > dt$ret_bm),
    MDD_active = as.numeric(maxDrawdown(active_xts))
  )
)
n <- nrow(dt)
total_years <- n / 12
summary_df <- data.table(
  Metric = c("CAGR", "Vol", "Sharpe / IR", "MDD"),
  Strategy = c(sprintf("%.2f%%", metrics$Strategy$CAGR * 100),
               sprintf("%.2f%%", metrics$Strategy$Vol * 100),
               sprintf("%.4f", metrics$Strategy$SR),
               sprintf("%.2f%%", metrics$Strategy$MDD * 100)),
  Benchmark = c(sprintf("%.2f%%", metrics$Benchmark$CAGR * 100),
                sprintf("%.2f%%", metrics$Benchmark$Vol * 100),
                sprintf("%.4f", metrics$Benchmark$SR),
                sprintf("%.2f%%", metrics$Benchmark$MDD * 100)),
  Active = c(sprintf("%.2f%%", metrics$Active$CAGR * 100),
             sprintf("%.2f%% (TE)", metrics$Active$TE * 100),
             sprintf("%.4f (IR)", metrics$Active$IR),
             sprintf("%.2f%%", metrics$Active$MDD_active * 100))
)
print(summary_df)
fwrite(summary_df, file.path(OUT, "benchmark_comparison_summary.csv"))

# Save metric JSON
jsonlite::write_json(metrics, file.path(OUT, "benchmark_comparison_metrics.json"),
                     pretty = TRUE, auto_unbox = TRUE)

#─── Chart 1: Strategy vs Benchmark NAV (log scale) ──────────
plot_dt <- melt(dt[, .(Date, Strategy = nav_strategy, Benchmark = nav_bm)],
                id.vars = "Date", variable.name = "Series", value.name = "NAV")

p1 <- ggplot(plot_dt, aes(x = Date, y = NAV, color = Series, linewidth = Series)) +
  geom_line() +
  scale_y_continuous(trans = "log10", labels = label_number(accuracy = 0.1)) +
  scale_color_manual(values = c("Strategy" = "#1f77b4", "Benchmark" = "#999999")) +
  scale_linewidth_manual(values = c("Strategy" = 1.2, "Benchmark" = 0.8)) +
  labs(title = sprintf("STR_1715_AR_on_M4_R05 (V2 admit) vs KOSPI200 (log NAV, %d months)", n),
       subtitle = sprintf("Strategy CAGR %.1f%% / Benchmark CAGR %.1f%% / Active CAGR +%.1fpp",
                           metrics$Strategy$CAGR * 100, metrics$Benchmark$CAGR * 100,
                           (metrics$Strategy$CAGR - metrics$Benchmark$CAGR) * 100),
       x = NULL, y = "NAV (log scale, base=1.0)",
       caption = sprintf("V2 admit | %s ~ %s | PerformanceAnalytics geometric",
                          format(min(dt$Date), "%Y-%m"),
                          format(max(dt$Date), "%Y-%m"))) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.minor = element_blank())
ggsave(file.path(OUT, "vs_benchmark_nav.png"), p1, width = 10, height = 5.5, dpi = 110)

#─── Chart 2: Cumulative excess return (Active NAV) ──────────
p2 <- ggplot(dt, aes(x = Date, y = nav_active)) +
  geom_line(color = "#d62728", linewidth = 1.0) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
  scale_y_continuous(labels = label_number(accuracy = 0.1)) +
  labs(title = "Cumulative Excess Return (Strategy − KOSPI200)",
       subtitle = sprintf("IR %.4f | TE %.2f%% | Annual active %.2fpp | Hit Rate %.1f%%",
                           metrics$Active$IR, metrics$Active$TE * 100,
                           metrics$Active$CAGR * 100,
                           metrics$Active$HitRate * 100),
       x = NULL, y = "Cumulative Active NAV") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT, "vs_benchmark_excess_return.png"), p2, width = 10, height = 5.0, dpi = 110)

#─── Chart 3: Annual excess return bar ───────────────────────
dt[, year := format(Date, "%Y")]
annual_dt <- dt[, .(strategy = prod(1 + ret_strategy) - 1,
                    benchmark = prod(1 + ret_bm) - 1,
                    active = prod(1 + ret_strategy) / prod(1 + ret_bm) - 1),
                by = year]
annual_dt[, year_int := as.integer(year)]

annual_plot <- melt(annual_dt[, .(year_int, Strategy = strategy, Benchmark = benchmark,
                                    Active = active)],
                     id.vars = "year_int", variable.name = "Series",
                     value.name = "Return")

p3 <- ggplot(annual_plot, aes(x = year_int, y = Return, fill = Series)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  geom_hline(yintercept = 0, linewidth = 0.3) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  scale_fill_manual(values = c("Strategy" = "#1f77b4", "Benchmark" = "#999999",
                                 "Active" = "#d62728")) +
  scale_x_continuous(breaks = seq(min(annual_dt$year_int), max(annual_dt$year_int), 2)) +
  labs(title = "Annual Returns: Strategy vs Benchmark vs Active",
       subtitle = sprintf("Strategy outperformed benchmark in %d/%d years (%.0f%%)",
                           sum(annual_dt$active > 0), nrow(annual_dt),
                           mean(annual_dt$active > 0) * 100),
       x = NULL, y = "Annual Return", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
ggsave(file.path(OUT, "vs_benchmark_annual.png"), p3, width = 12, height = 5.5, dpi = 110)

cat("\n=== Charts generated ===\n")
cat("1. vs_benchmark_nav.png\n")
cat("2. vs_benchmark_excess_return.png\n")
cat("3. vs_benchmark_annual.png\n")
cat("\n=== Metrics ===\n")
cat(sprintf("Strategy CAGR: %.2f%% / Vol: %.2f%% / Sharpe: %.4f / MDD: %.2f%%\n",
            metrics$Strategy$CAGR * 100, metrics$Strategy$Vol * 100,
            metrics$Strategy$SR, metrics$Strategy$MDD * 100))
cat(sprintf("Benchmark CAGR: %.2f%% / Vol: %.2f%% / Sharpe: %.4f / MDD: %.2f%%\n",
            metrics$Benchmark$CAGR * 100, metrics$Benchmark$Vol * 100,
            metrics$Benchmark$SR, metrics$Benchmark$MDD * 100))
cat(sprintf("Active CAGR: +%.2fpp / TE: %.2f%% / IR: %.4f / Hit Rate: %.1f%%\n",
            (metrics$Strategy$CAGR - metrics$Benchmark$CAGR) * 100,
            metrics$Active$TE * 100, metrics$Active$IR,
            metrics$Active$HitRate * 100))
