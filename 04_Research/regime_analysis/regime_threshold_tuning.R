suppressPackageStartupMessages({
  library(data.table); library(arrow); library(ggplot2); library(patchwork)
})
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== Regime v2 Threshold Tuning ===\n")

regime <- as.data.table(read_parquet(FRED_REGIME_CACHE))
setorder(regime, Date)

res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_Ret = prod(1 + BM_Ret, na.rm=TRUE) - 1), by = YM]
bm_m[, Date := as.Date(cut(as.Date(paste0(YM,"-01")) + 31, "month")) - 1]
setorder(bm_m, Date)

# v1 & v2 scores
regime[, v1 := 0L]
if ("VIX_Regime" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(VIX_Regime) & VIX_Regime=="crisis", 30L,
    fifelse(!is.na(VIX_Regime) & VIX_Regime=="elevated", 15L, 0L))]
if ("YC_Inversion" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(YC_Inversion) & YC_Inversion, 25L, 0L)]
if ("Credit_Stress" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(Credit_Stress) & Credit_Stress, 25L, 0L)]
if ("KRW_Stress" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(KRW_Stress) & KRW_Stress, 20L, 0L)]
regime[, v2 := Macro_Risk_Score]

dt <- merge(regime[, .(Date, v1, v2)], bm_m[, .(Date, BM_Ret)], by="Date")
dt <- dt[!is.na(BM_Ret)]
setorder(dt, Date)

# ── Grid search: HALF threshold × SKIP threshold ──
dd_fn <- function(x) x / cummax(x) - 1

results <- list()
idx <- 0

# v1 baseline (fixed)
r_v1 <- dt$BM_Ret * fifelse(dt$v1 >= 30, 0, fifelse(dt$v1 >= 15, 0.5, 1.0))
c_v1 <- cumprod(1 + r_v1)
n <- length(r_v1)
results[[idx <- idx + 1]] <- data.table(
  Version = "v1(4축)", Half = 15, Skip = 30, HalfExp = 0.5,
  CAGR = prod(1+r_v1)^(12/n)-1, Vol = sd(r_v1)*sqrt(12),
  SR = (prod(1+r_v1)^(12/n)-1) / (sd(r_v1)*sqrt(12)),
  MDD = min(dd_fn(c_v1)),
  SkipMonths = sum(dt$v1 >= 30),
  HalfMonths = sum(dt$v1 >= 15 & dt$v1 < 30)
)

# v2 grid: half_thresh × skip_thresh × half_exposure
half_thresholds <- c(10, 12, 15, 18, 20, 25)
skip_thresholds <- c(20, 25, 28, 30, 35, 40)
half_exposures  <- c(0.3, 0.5, 0.7)

for (ht in half_thresholds) {
  for (st in skip_thresholds) {
    if (ht >= st) next  # half must be < skip
    for (he in half_exposures) {
      exp <- fifelse(dt$v2 >= st, 0, fifelse(dt$v2 >= ht, he, 1.0))
      r <- dt$BM_Ret * exp
      cum <- cumprod(1 + r)
      cagr <- prod(1+r)^(12/n) - 1
      vol <- sd(r) * sqrt(12)
      results[[idx <- idx + 1]] <- data.table(
        Version = "v2", Half = ht, Skip = st, HalfExp = he,
        CAGR = cagr, Vol = vol, SR = cagr / vol,
        MDD = min(dd_fn(cum)),
        SkipMonths = sum(dt$v2 >= st),
        HalfMonths = sum(dt$v2 >= ht & dt$v2 < st)
      )
    }
  }
}

grid <- rbindlist(results)
cat(sprintf("\nGrid: %d combinations tested\n", nrow(grid)))

# ── Filter: better than v1 on at least one metric ──
v1_row <- grid[Version == "v1(4축)"]
cat(sprintf("\nv1 baseline: CAGR=%.1f%% SR=%.3f MDD=%.1f%%\n",
    v1_row$CAGR*100, v1_row$SR, v1_row$MDD*100))

# Best by Sharpe
best_sr <- grid[Version=="v2"][which.max(SR)]
cat(sprintf("\nBest Sharpe:  Half=%d Skip=%d Exp=%.1f → CAGR=%.1f%% SR=%.3f MDD=%.1f%% (Skip=%d Half=%d)\n",
    best_sr$Half, best_sr$Skip, best_sr$HalfExp,
    best_sr$CAGR*100, best_sr$SR, best_sr$MDD*100, best_sr$SkipMonths, best_sr$HalfMonths))

# Best by MDD
best_mdd <- grid[Version=="v2"][which.max(MDD)]  # MDD is negative, max = least bad
cat(sprintf("Best MDD:     Half=%d Skip=%d Exp=%.1f → CAGR=%.1f%% SR=%.3f MDD=%.1f%% (Skip=%d Half=%d)\n",
    best_mdd$Half, best_mdd$Skip, best_mdd$HalfExp,
    best_mdd$CAGR*100, best_mdd$SR, best_mdd$MDD*100, best_mdd$SkipMonths, best_mdd$HalfMonths))

# Best CAGR with MDD <= v1 MDD
safe <- grid[Version=="v2" & MDD >= v1_row$MDD]
if (nrow(safe) > 0) {
  best_safe <- safe[which.max(CAGR)]
  cat(sprintf("Best CAGR (MDD<=v1): Half=%d Skip=%d Exp=%.1f → CAGR=%.1f%% SR=%.3f MDD=%.1f%%\n",
      best_safe$Half, best_safe$Skip, best_safe$HalfExp,
      best_safe$CAGR*100, best_safe$SR, best_safe$MDD*100))
} else {
  cat("No v2 config beats v1 MDD\n")
  best_safe <- best_mdd
}

# Pareto front: not dominated on both SR and MDD
v2g <- grid[Version=="v2"]
v2g[, dominated := FALSE]
for (i in 1:nrow(v2g)) {
  if (any(v2g$SR[-i] >= v2g$SR[i] & v2g$MDD[-i] >= v2g$MDD[i] &
          (v2g$SR[-i] > v2g$SR[i] | v2g$MDD[-i] > v2g$MDD[i])))
    v2g[i, dominated := TRUE]
}
pareto <- v2g[dominated == FALSE][order(-SR)]
cat(sprintf("\nPareto front: %d configs\n", nrow(pareto)))
print(pareto[1:min(10, nrow(pareto)), .(Half, Skip, HalfExp,
  CAGR=sprintf("%.1f%%", CAGR*100), SR=sprintf("%.3f", SR),
  MDD=sprintf("%.1f%%", MDD*100), SkipM=SkipMonths, HalfM=HalfMonths)])

# ── Top 5 comparison chart ──
common_cols <- intersect(names(v1_row), names(pareto))
top5 <- rbind(v1_row[, ..common_cols], pareto[1:min(4, nrow(pareto)), ..common_cols])
top5[, label := fifelse(Version=="v1(4축)", "v1(4축) H15/S30",
  sprintf("v2 H%d/S%d/E%.0f%%", Half, Skip, HalfExp*100))]

# Simulate each for equity curves
curves <- list()
for (i in 1:nrow(top5)) {
  row <- top5[i]
  if (row$Version == "v1(4축)") {
    exp <- fifelse(dt$v1 >= 30, 0, fifelse(dt$v1 >= 15, 0.5, 1.0))
  } else {
    exp <- fifelse(dt$v2 >= row$Skip, 0, fifelse(dt$v2 >= row$Half, row$HalfExp, 1.0))
  }
  r <- dt$BM_Ret * exp
  curves[[i]] <- data.table(Date = dt$Date, Config = row$label,
                             Cum = cumprod(1+r), DD = dd_fn(cumprod(1+r)) * 100)
}
curve_dt <- rbindlist(curves)

# Add benchmark
bm_curve <- data.table(Date = dt$Date, Config = "KOSPI200",
  Cum = cumprod(1 + dt$BM_Ret), DD = dd_fn(cumprod(1 + dt$BM_Ret)) * 100)
curve_dt <- rbind(bm_curve, curve_dt)

thm <- theme_minimal(base_size=11) + theme(legend.position="bottom",
  plot.title=element_text(face="bold", size=13))
colors <- c("gray50", "#E74C3C", "#2E86C1", "#27AE60", "#8E44AD", "#F39C12")

p1 <- ggplot(curve_dt, aes(Date, Cum, color=Config)) +
  geom_line(linewidth=0.7) +
  scale_color_manual(values=colors[1:length(unique(curve_dt$Config))]) +
  scale_y_log10(labels=scales::comma) +
  labs(title="Cumulative Growth (Top Pareto Configs)", y="Growth of 1", x=NULL) + thm

p2 <- ggplot(curve_dt, aes(Date, DD, color=Config)) +
  geom_line(linewidth=0.5) +
  scale_color_manual(values=colors[1:length(unique(curve_dt$Config))]) +
  geom_hline(yintercept=-25, linetype="dashed", alpha=0.3) +
  labs(title="Drawdown (%)", y="DD%", x=NULL) + thm

# Scatter: SR vs MDD for all grid
p3 <- ggplot(v2g, aes(x=MDD*100, y=SR)) +
  geom_point(alpha=0.3, size=1.5, color="gray60") +
  geom_point(data=pareto, aes(MDD*100, SR), color="#2E86C1", size=2.5) +
  geom_point(data=v1_row, aes(MDD*100, SR), color="#E74C3C", size=4, shape=17) +
  annotate("text", x=v1_row$MDD*100+1, y=v1_row$SR+0.02, label="v1", color="#E74C3C", fontface="bold") +
  geom_line(data=pareto[order(MDD)], aes(MDD*100, SR), color="#2E86C1", linewidth=0.8, alpha=0.5) +
  labs(title="Sharpe vs MDD — Pareto Front", x="MDD (%)", y="Sharpe Ratio") + thm

combined <- (p1 | p3) / p2 +
  plot_annotation(
    title = "Regime v2 Threshold Tuning — Pareto Optimization",
    subtitle = sprintf("Grid: %d configs | Pareto: %d | v1: SR=%.3f MDD=%.1f%%",
      nrow(grid)-1, nrow(pareto), v1_row$SR, v1_row$MDD*100),
    theme = theme(plot.title=element_text(face="bold", size=14))
  )

out <- file.path(PROJECT_ROOT, "research_output", "regime_analysis")
chart_path <- file.path(out, "regime_v2_threshold_tuning.png")
ggsave(chart_path, combined, width=14, height=10, dpi=150, bg="white")
cat(sprintf("\nChart: %s\n", chart_path))

# ── Telegram ──
tryCatch({
  best <- pareto[1]
  tg_send_photo(chart_path, caption=paste0(
    "\xF0\x9F\x94\xA7 v2 Threshold Tuning Results\n\n",
    sprintf("Grid: %d configs tested\n", nrow(grid)-1),
    sprintf("Pareto front: %d optimal configs\n\n", nrow(pareto)),
    "v1 baseline: ", sprintf("SR %.3f MDD %.1f%%\n", v1_row$SR, v1_row$MDD*100),
    sprintf("Best SR:  H%d/S%d/E%.0f%% SR=%.3f MDD=%.1f%%\n",
      best_sr$Half, best_sr$Skip, best_sr$HalfExp*100, best_sr$SR, best_sr$MDD*100),
    sprintf("Best MDD: H%d/S%d/E%.0f%% SR=%.3f MDD=%.1f%%\n",
      best_mdd$Half, best_mdd$Skip, best_mdd$HalfExp*100, best_mdd$SR, best_mdd$MDD*100),
    sprintf("Best balanced: H%d/S%d/E%.0f%% SR=%.3f MDD=%.1f%%\n",
      best$Half, best$Skip, best$HalfExp*100, best$SR, best$MDD*100),
    sprintf("\nRecommend: HALF=%d SKIP=%d EXP=%.0f%%", best$Half, best$Skip, best$HalfExp*100)
  ))
  cat("TG sent!\n")
}, error=function(e) cat("TG error:", e$message, "\n"))

cat("\n=== Done ===\n")
