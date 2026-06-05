#!/usr/bin/env Rscript
#==============================================================================
# 612_p3_kmeans_cluster.R — P3 5D K-means 9-cluster 데이터-driven cell 분석
#
# 도훈 mandate 2026-05-27:
# 사전 정의 9 grid (σ × λ 3x3) 대안으로 K-means K=9 데이터-driven cluster.
# 5D feature space: z_σ + z_λ + z_μ + z_inv_ν + z_var05.
# 각 cluster centroid + n + fwd22 통계 (mean/std/MDD/Sharpe/위반율) + 시각화.
#
# Output:
#   - p3_kmeans_clusters.png (σ × λ projection, cluster color)
#   - p3_kmeans_summary.csv (cluster 통계)
#   - stdout: cluster 해석 (centroid 정렬 + 의미 라벨 후보)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(dplyr)
  library(ggplot2)
  library(scales)
  library(stats)  # kmeans
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))

args <- commandArgs(trailingOnly = TRUE)
src_path <- if (length(args) >= 1) args[1] else file.path(
  PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet"
)
K <- if (length(args) >= 2) as.integer(args[2]) else 9L
seed <- 42L

# ── 1. Load P3 ───────────────────────────────────────────────────────────────
dat <- as.data.table(read_parquet(src_path))
dat[, Date := as.Date(Date)]
setorder(dat, Date)

# Merge live P3 daily predictions
daily_path <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet")
if (file.exists(daily_path)) {
  daily <- as.data.table(read_parquet(daily_path))
  daily[, Date := as.Date(Date)]
  new_rows <- daily[!Date %in% dat$Date]
  if (nrow(new_rows) > 0) {
    common_cols <- intersect(names(dat), names(daily))
    dat <- rbindlist(list(dat[, ..common_cols], new_rows[, ..common_cols]),
                     use.names = TRUE)
    setorder(dat, Date)
  }
}

cat(sprintf("[kmeans] data: %d rows (%s ~ %s)\n",
            nrow(dat), as.character(dat$Date[1]), as.character(dat$Date[nrow(dat)])))

# ── 2. 5D feature engineering (PIT-safe expanding z) ─────────────────────────
expanding_z <- function(x, min_obs = 60L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    v <- x[1:i]
    m <- mean(v, na.rm = TRUE)
    s <- sd(v, na.rm = TRUE)
    if (is.na(s) || s == 0) next
    out[i] <- (x[i] - m) / s
  }
  out
}
clip_z <- function(z, cap = 3) pmin(pmax(z, -cap), cap)

dat[, z_sigma   := clip_z(expanding_z(sigma))]
dat[, z_lam     := clip_z(expanding_z(lam))]
dat[, z_mu      := clip_z(expanding_z(mu))]
dat[, z_inv_nu  := clip_z(expanding_z(1 / pmax(nu, 1)))]
dat[, z_var05   := clip_z(expanding_z(var_05))]

# fwd 22d cumulative log return for backtest stats
dat[, y_cum := cumsum(ifelse(is.na(y_actual), 0, y_actual))]
dat[, fwd22 := shift(y_cum, n = -22, type = "lag") - y_cum]
dat[Date > (max(Date) - 22), fwd22 := NA_real_]

# ── 3. K-means (drop rows with any NA z) ─────────────────────────────────────
feat_cols <- c("z_sigma", "z_lam", "z_mu", "z_inv_nu", "z_var05")
dat_kmeans <- dat[complete.cases(dat[, ..feat_cols])]
cat(sprintf("[kmeans] usable rows for clustering: %d\n", nrow(dat_kmeans)))

X <- as.matrix(dat_kmeans[, ..feat_cols])
set.seed(seed)
km <- kmeans(X, centers = K, nstart = 50, iter.max = 100)
dat_kmeans[, cluster := km$cluster]

cat(sprintf("[kmeans] K=%d clusters fit. tot.withinss=%.1f  betweenss=%.1f  ratio=%.3f\n",
            K, km$tot.withinss, km$betweenss, km$betweenss / km$totss))

# ── 4. Cluster statistics (n, centroid, fwd22 stats) ─────────────────────────
centroid_df <- as.data.table(km$centers)
centroid_df[, cluster := seq_len(.N)]
setcolorder(centroid_df, "cluster")

cluster_stats <- dat_kmeans[, .(
  n = .N,
  sigma_med = median(sigma, na.rm = TRUE),
  lam_med   = median(lam, na.rm = TRUE),
  mu_med    = median(mu, na.rm = TRUE),
  nu_med    = median(nu, na.rm = TRUE),
  var05_med = median(var_05, na.rm = TRUE),
  fwd22_mean = mean(fwd22, na.rm = TRUE),
  fwd22_med  = median(fwd22, na.rm = TRUE),
  fwd22_std  = sd(fwd22, na.rm = TRUE),
  fwd22_min  = min(fwd22, na.rm = TRUE),
  fwd22_max  = max(fwd22, na.rm = TRUE),
  breach_5pct = mean(fwd22 < -5, na.rm = TRUE),
  breach_10pct = mean(fwd22 < -10, na.rm = TRUE)
), by = cluster][order(cluster)]

# Sharpe-like (22d return / 22d std) — rough
cluster_stats[, fwd22_sharpe := fwd22_mean / fwd22_std]

# Centroid sort by "risk severity" (z_sigma + (-z_lam) + (-z_mu) + z_inv_nu + (-z_var05))
centroid_df[, risk_proxy := z_sigma + (-z_lam) + (-z_mu) + z_inv_nu + (-z_var05)]
setorder(centroid_df, risk_proxy)
centroid_df[, risk_rank := seq_len(.N)]

# Merge ranks back
cluster_stats <- merge(cluster_stats, centroid_df[, .(cluster, risk_rank, risk_proxy)],
                       by = "cluster")
setorder(cluster_stats, risk_rank)

cat("\n[kmeans] Cluster summary (sorted by risk_rank, lowest → highest risk):\n")
print(cluster_stats[, .(cluster, risk_rank, n,
                         sigma_med, lam_med, mu_med, nu_med, var05_med,
                         fwd22_mean, fwd22_std, fwd22_sharpe, breach_5pct, breach_10pct)])

# Today's assignment
latest_row <- tail(dat_kmeans, 1)
latest_cluster <- latest_row$cluster
latest_rank <- cluster_stats[cluster == latest_cluster, risk_rank]
cat(sprintf("\n[kmeans] TODAY (%s): cluster #%d  (risk_rank %d / %d)\n",
            as.character(latest_row$Date), latest_cluster, latest_rank, K))

# Save CSV
out_dir <- file.path(
  PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief",
  as.character(latest_row$Date)
)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(cluster_stats, file.path(out_dir, "p3_kmeans_summary.csv"))
fwrite(centroid_df, file.path(out_dir, "p3_kmeans_centroids.csv"))

# ── 5. Visualization: σ × λ projection + cluster color ──────────────────────
# Color palette by risk rank (gradient red→green)
palette9 <- c("#1B5E20", "#388E3C", "#7CB342", "#FBC02D",
              "#FB8C00", "#F4511E", "#E53935", "#C62828", "#8E0000")

rank_map <- centroid_df[, .(cluster, risk_rank)]
dat_kmeans <- merge(dat_kmeans, rank_map, by = "cluster", all.x = TRUE,
                     sort = FALSE)
dat_kmeans[, cluster_label := factor(risk_rank, levels = 1:K,
                                      labels = paste0("C", 1:K, " (rank ", 1:K, ")"))]

# Sort clusters by risk_rank for legend
cluster_label_order <- centroid_df[order(risk_rank), paste0("C", cluster, " (rank ", risk_rank, ")")]

# 60d trail
trail_all <- tail(dat_kmeans[!is.na(sigma) & !is.na(lam)], 252)
trail <- tail(trail_all, 60)
trail[, t_idx := seq_len(.N)]
latest <- tail(trail, 1)

# Plot σ vs λ with cluster color (data points) + centroid markers
p <- ggplot() +
  # All historical points colored by cluster (risk_rank)
  geom_point(data = dat_kmeans, aes(x = pmin(pmax(sigma, 0), 5),
                                      y = pmin(pmax(lam, -0.5), 0.5),
                                      color = factor(risk_rank)),
             alpha = 0.25, size = 0.7) +
  scale_color_manual(values = palette9,
                     labels = sprintf("rank %d (n=%d)", 1:K,
                                       cluster_stats[order(risk_rank), n]),
                     name = "Risk Rank") +
  # 60d trail (red gradient)
  geom_path(data = trail, aes(x = sigma, y = lam),
            color = "#B71C1C", linewidth = 0.7, alpha = 0.4) +
  geom_point(data = trail, aes(x = sigma, y = lam),
             color = "black", size = 1.8, alpha = 0.6) +
  # Latest point (yellow star)
  geom_point(data = latest, aes(x = sigma, y = lam),
             shape = 21, fill = "#FDD835", color = "#424242", size = 5, stroke = 1.2) +
  # NOW badge
  annotate("label", x = 0.1, y = 0.49,
           label = sprintf("NOW (%s): cluster #%d (risk_rank %d/%d)\nσ=%.2f%%  λ=%+.3f  μ=%+.2f%%  ν=%.1f  VaR05=%.2f%%",
                            as.character(latest$Date), latest$cluster, latest_rank, K,
                            latest$sigma, latest$lam, latest$mu, latest$nu, latest$var_05),
           hjust = 0, vjust = 1, size = 3.8, fontface = "bold",
           color = "#B71C1C", fill = scales::alpha("white", 0.9), linewidth = 0.3) +
  coord_cartesian(xlim = c(0, 5), ylim = c(-0.5, 0.5)) +
  labs(title = sprintf("P3 K-means 9-Cluster (5D: σ + λ + μ + 1/ν + VaR05) — data: %s",
                       as.character(latest$Date)),
       subtitle = sprintf("K=%d, n=%d  |  Centroid risk_proxy 정렬 (rank 1 = safest, rank %d = riskiest)",
                          K, nrow(dat_kmeans), K),
       x = expression(bold("σ (변동성, %)")),
       y = expression(bold("λ (비대칭)"))) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 13),
        plot.subtitle = element_text(size = 10, color = "gray30"),
        legend.position = "right",
        legend.text = element_text(size = 9))

out_png <- file.path(out_dir, "p3_kmeans_clusters.png")
ggsave(out_png, p, width = 11, height = 7.5, dpi = 140)
cat(sprintf("\n[kmeans] saved → %s\n", out_png))
cat(sprintf("[kmeans] CSV  → %s\n", file.path(out_dir, "p3_kmeans_summary.csv")))
