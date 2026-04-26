#==============================================================================
# WT-D20260426_007 Alpha — Charts (ICIR / regime IC / confidence dist / λ×κ heatmap)
#==============================================================================

t0 <- Sys.time()

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
OUT_STAGE <- file.path(PROJECT_ROOT, "qepm/stage_artifacts/WT_D20260426_007")
OUT_CHART <- file.path(OUT_STAGE, "charts")
dir.create(OUT_CHART, showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(ggplot2)
})

# Load data
scores <- as.data.table(read_parquet(file.path(OUT_STAGE, "alpha_scores.parquet")))
sweep <- as.data.table(read_parquet(file.path(OUT_STAGE, "lambda_kappa_grid.parquet")))

# Chart 1: ICIR time-series — IC per month (rolling)
ic_ts <- scores[!is.na(alpha_v2) & !is.na(fwd_1m),
                .(ic = cor(alpha_v2, fwd_1m, method = "spearman", use="complete.obs"),
                  n = .N), by = Date]
setkey(ic_ts, Date)
ic_ts[, ic_roll12 := frollmean(ic, 12L, align = "right")]

p1 <- ggplot(ic_ts, aes(x = Date)) +
  geom_col(aes(y = ic), fill = "#5DADE2", alpha = 0.5) +
  geom_line(aes(y = ic_roll12), color = "#E74C3C", size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  geom_hline(yintercept = 0.04, linetype = "dotted", color = "darkgreen") +
  geom_hline(yintercept = -0.04, linetype = "dotted", color = "darkred") +
  labs(title = "WT-D20260426_007 — Monthly Rank IC (alpha_v2 vs fwd_1m)",
       subtitle = sprintf("Mean IC=%.4f / ICIR=%.3f / 12M rolling overlay",
                          mean(ic_ts$ic, na.rm=TRUE),
                          mean(ic_ts$ic, na.rm=TRUE)/sd(ic_ts$ic, na.rm=TRUE)),
       x = NULL, y = "Rank IC") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))
ggsave(file.path(OUT_CHART, "ic_timeseries.png"), p1,
       width = 9, height = 5, dpi = 100)
cat("[chart] ic_timeseries.png saved\n")

# Chart 2: λ×κ grid heatmap
sweep_long <- sweep
p2 <- ggplot(sweep_long, aes(x = factor(lambda), y = factor(kappa),
                              fill = composite_score)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.4f", composite_score)),
            color = "white", size = 4) +
  scale_fill_gradient(low = "#34495E", high = "#27AE60") +
  labs(title = "WT-D20260426_007 — λ × κ Grid Sweep (composite = ICIR × sub_stab)",
       subtitle = "Optimal: λ=0.5 κ=1.5 (composite=0.2005)",
       x = "λ (rank exponent)", y = "κ (confidence exponent)",
       fill = "Composite") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "right")
ggsave(file.path(OUT_CHART, "lambda_kappa_heatmap.png"), p2,
       width = 8, height = 6, dpi = 100)
cat("[chart] lambda_kappa_heatmap.png saved\n")

# Chart 3: Confidence distribution
p3 <- ggplot(scores, aes(x = confidence)) +
  geom_histogram(fill = "#3498DB", alpha = 0.7, bins = 50) +
  geom_vline(xintercept = mean(scores$confidence, na.rm=TRUE),
             linetype = "dashed", color = "#E74C3C", size = 1) +
  labs(title = "WT-D20260426_007 — Confidence Vector Distribution",
       subtitle = sprintf("3-component composite: 0.4*sub_stab + 0.3*resid + 0.3*coverage. Mean=%.3f / SD=%.3f",
                          mean(scores$confidence, na.rm=TRUE),
                          sd(scores$confidence, na.rm=TRUE)),
       x = "Confidence c_i", y = "Frequency") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))
ggsave(file.path(OUT_CHART, "confidence_distribution.png"), p3,
       width = 8, height = 5, dpi = 100)
cat("[chart] confidence_distribution.png saved\n")

# Chart 4: Sub-period IC bars (3 periods)
sub_periods <- list(
  P1 = list(start = as.Date("2008-01-01"), end = as.Date("2014-12-31")),
  P2 = list(start = as.Date("2015-01-01"), end = as.Date("2019-12-31")),
  P3 = list(start = as.Date("2020-01-01"), end = as.Date("2024-01-22"))
)
sub_dt <- rbindlist(lapply(names(sub_periods), function(p) {
  prng <- sub_periods[[p]]
  sub <- ic_ts[Date >= prng$start & Date <= prng$end]
  data.table(period = p, mean_ic = mean(sub$ic, na.rm = TRUE),
             icir = mean(sub$ic, na.rm = TRUE) / sd(sub$ic, na.rm = TRUE),
             n = nrow(sub))
}))

p4 <- ggplot(sub_dt, aes(x = period)) +
  geom_col(aes(y = mean_ic), fill = "#9B59B6", alpha = 0.7) +
  geom_text(aes(y = mean_ic, label = sprintf("IC=%.4f\nICIR=%.2f\nn=%d",
                                              mean_ic, icir, n)),
            vjust = -0.5, size = 3.5) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_hline(yintercept = 0.04, linetype = "dotted", color = "darkgreen") +
  labs(title = "WT-D20260426_007 — Sub-period IC (Stability Check)",
       subtitle = "Sub-stab gate: 3 sub-periods × sign consistency × CV normalization. Target sub_stab >= 0.50.",
       x = NULL, y = "Mean Rank IC") +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold")) +
  scale_y_continuous(limits = c(-0.01, max(sub_dt$mean_ic) * 1.5))
ggsave(file.path(OUT_CHART, "subperiod_ic.png"), p4,
       width = 8, height = 5, dpi = 100)
cat("[chart] subperiod_ic.png saved\n")

cat(sprintf("\n[generate_charts] complete (%.1fs) — 4 charts saved in %s\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")), OUT_CHART))
