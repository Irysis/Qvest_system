#!/usr/bin/env Rscript
#==============================================================================
# 611_p3_9quad_ktri_style.R — P3 9-Quadrant chart with KTRI-style 점 규칙
#
# 도훈 mandate 2026-05-27:
# KTRI 9사분면 (telegram_notify.R line 2208~2271) 점 규칙 그대로 적용:
#   - 옛 192d: gray60 + alpha gradient (0.15~0.45) + size 1.3
#   - 최근 60d: gradient #FFCCBC → #C62828 + size 1.8 + alpha 0.8
#   - 60d trail line: #B71C1C + linewidth 0.7 + alpha 0.4
#   - 시작/최신점: shape 21, fill #FDD835, color #424242, size 5, stroke 1.2
#   - 시작/끝 라벨: 흰 박스 + nudge_x +2.5 nudge_y -2.5
#   - NOW badge 좌상단
#   - 5D direction subtitle
#   - 9-cell background color + dashed boundary
#
# Axes:
#   x = σ (변동성, %)        — 0 ~ 5%
#   y = λ (비대칭 skewness)  — -0.5 ~ +0.5
#
# 9 cells (σ low/med/high × λ bear/neutral/bull):
#   (low,bear)    잠재폭발     (low,neutral)  평온        (low,bull)    안정강세
#   (med,bear)    약세진행     (med,neutral)  보통        (med,bull)    강세진행
#   (high,bear)   위기         (high,neutral) 혼란        (high,bull)   급등
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(dplyr)
  library(ggplot2)
  library(scales)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))

# Args
args <- commandArgs(trailingOnly = TRUE)
src_path <- if (length(args) >= 1) args[1] else file.path(
  PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet"
)
out_dir <- if (length(args) >= 2) args[2] else NULL

# Axis cut points
SIGMA_LOW  <- 1.0
SIGMA_HIGH <- 1.8
LAM_BEAR   <-  -0.10
LAM_BULL   <-  +0.10

XLIM <- c(0, 5)
YLIM <- c(-0.5, 0.5)

# ── 1. Load P3 predictions ───────────────────────────────────────────────────
dat <- as.data.table(read_parquet(src_path))
dat[, Date := as.Date(Date)]
setorder(dat, Date)

# Merge live P3 daily predictions (if available)
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

# ── 2. Bin σ / λ ─────────────────────────────────────────────────────────────
dat[, sigma_bin := cut(sigma, breaks = c(-Inf, SIGMA_LOW, SIGMA_HIGH, Inf),
                       labels = c("S_Low", "S_Mid", "S_High"), right = FALSE)]
dat[, lam_bin   := cut(lam, breaks = c(-Inf, LAM_BEAR, LAM_BULL, Inf),
                       labels = c("L_Bear", "L_Neutral", "L_Bull"), right = FALSE)]
dat[, sigma_plot := pmin(pmax(sigma, XLIM[1]), XLIM[2])]
dat[, lam_plot   := pmin(pmax(lam, YLIM[1]), YLIM[2])]

# ── 3. Zone summary table (9 cells × forward 22d cumulative return) ─────────
# forward 22d cumulative log return (y_actual is log return * 100, sum is additive)
dat[, y_cum := cumsum(ifelse(is.na(y_actual), 0, y_actual))]
dat[, fwd22 := shift(y_cum, n = -22, type = "lag") - y_cum]
dat[Date > (max(Date) - 22), fwd22 := NA_real_]  # last 22d ungrounded → NA
zone_map <- list(
  S_Low_L_Bear     = list(zone = "잠재 폭발",      fill = "#FFE0B2"),
  S_Low_L_Neutral  = list(zone = "평온",          fill = "#E3F2FD"),
  S_Low_L_Bull     = list(zone = "안정 강세",      fill = "#E8F5E9"),
  S_Mid_L_Bear     = list(zone = "약세 진행",      fill = "#FBE9E7"),
  S_Mid_L_Neutral  = list(zone = "보통",          fill = "#FAFAFA"),
  S_Mid_L_Bull     = list(zone = "강세 진행",      fill = "#F1F8E9"),
  S_High_L_Bear    = list(zone = "위기",          fill = "#FFCDD2"),
  S_High_L_Neutral = list(zone = "혼란",          fill = "#FFE0B2"),
  S_High_L_Bull    = list(zone = "급등 (Vol Risk)", fill = "#DCEDC8")
)

# Continuous Risk Score (1-5) — expanding z-score 정합 (PIT)
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
dat[, z_sigma  := clip_z(expanding_z(sigma))]
dat[, z_lam    := clip_z(expanding_z(lam))]
dat[, z_mu     := clip_z(expanding_z(mu))]
dat[, z_inv_nu := clip_z(expanding_z(1 / pmax(nu, 1)))]   # higher fat-tail (low nu) → higher z
dat[, z_var05  := clip_z(expanding_z(var_05))]            # VaR_05 is negative; more negative → z negative → -z positive (risk ↑)

# Composite risk score (higher = more risk). Outliers clipped to ±3 σ.
# weights: σ=0.7 (변동성 최우선), λ=0.5 (좌편향 위험), μ=0.3 (negative drift),
#          ν=0.3 (fat-tail bonus), VaR_05=0.4 (tail loss magnitude)
dat[, risk_raw := 0.7 * z_sigma
                + 0.5 * (-z_lam)
                + 0.3 * (-z_mu)
                + 0.3 * z_inv_nu
                + 0.4 * (-z_var05)]
dat[, risk_score := pmin(pmax(3.0 + risk_raw, 1.0), 5.0)]

# Zone summary (avg fwd22 + risk_score per cell — backtest-driven calibration)
tbl <- dat[!is.na(sigma_bin) & !is.na(lam_bin),
           .(n = .N,
             avg_fwd22 = mean(fwd22, na.rm = TRUE),
             med_fwd22 = median(fwd22, na.rm = TRUE),
             avg_risk = mean(risk_score, na.rm = TRUE)),
           by = .(sigma_bin, lam_bin)]
all_grid <- as.data.table(expand.grid(
  sigma_bin = factor(c("S_Low","S_Mid","S_High"), levels = c("S_Low","S_Mid","S_High")),
  lam_bin   = factor(c("L_Bear","L_Neutral","L_Bull"), levels = c("L_Bear","L_Neutral","L_Bull"))
))
tbl2 <- merge(all_grid, tbl, by = c("sigma_bin","lam_bin"), all.x = TRUE)
tbl2[, key := paste(as.character(sigma_bin), as.character(lam_bin), sep = "_")]
tbl2[, zone := sapply(key, function(k) zone_map[[k]]$zone)]
tbl2[, fill := sapply(key, function(k) zone_map[[k]]$fill)]

# Cell centers (label positions)
sigma_centers <- c(S_Low = (0 + SIGMA_LOW)/2,
                   S_Mid = (SIGMA_LOW + SIGMA_HIGH)/2,
                   S_High = (SIGMA_HIGH + 5)/2)
lam_centers   <- c(L_Bear = (-0.5 + LAM_BEAR)/2,
                   L_Neutral = (LAM_BEAR + LAM_BULL)/2,
                   L_Bull = (LAM_BULL + 0.5)/2)
tbl2[, x := sigma_centers[as.character(sigma_bin)]]
tbl2[, y := lam_centers[as.character(lam_bin)]]
tbl2[, lbl := zone]

# ── 4. Trail: 252d (old 192d gray + recent 60d red gradient) ─────────────────
trail_all <- tail(dat[!is.na(sigma) & !is.na(lam)], 252)
trail_old <- head(trail_all, max(0, nrow(trail_all) - 60))
trail_old[, t_idx := seq_len(.N)]
trail <- tail(trail_all, 60)
trail[, t_idx := seq_len(.N)]
latest <- tail(trail, 1)

# 5d direction
recent5 <- tail(trail, min(5, nrow(trail)))
ds5 <- if (nrow(recent5) >= 2) recent5$sigma[nrow(recent5)] - recent5$sigma[1] else 0
dl5 <- if (nrow(recent5) >= 2) recent5$lam[nrow(recent5)]   - recent5$lam[1]   else 0
dir5 <- if (ds5 >= 0 & dl5 <= 0) {
  "Risk-Off tilt (sigma up, lam down)"
} else if (ds5 <= 0 & dl5 >= 0) {
  "Risk-On tilt (sigma down, lam up)"
} else {
  "Mixed"
}

# Start / End date labels
date_labels <- trail[c(1, nrow(trail))]
date_labels[, anchor_lbl := format(Date, "%y/%m/%d")]

# Latest zone
latest_key <- sprintf("%s_%s", as.character(latest$sigma_bin), as.character(latest$lam_bin))
now_zone <- zone_map[[latest_key]]$zone

ref_date <- as.character(latest$Date)

# ── 5. ggplot (KTRI style) ───────────────────────────────────────────────────
p <- ggplot() +
  # 9-cell background
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_Low_L_Bear$fill,    alpha=0.7) +
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_Low_L_Neutral$fill, alpha=0.7) +
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_Low_L_Bull$fill,    alpha=0.7) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_Mid_L_Bear$fill,    alpha=0.6) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_Mid_L_Neutral$fill, alpha=0.6) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_Mid_L_Bull$fill,    alpha=0.6) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_High_L_Bear$fill,    alpha=0.55) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_High_L_Neutral$fill, alpha=0.5) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_High_L_Bull$fill,    alpha=0.5) +
  # Boundaries
  geom_vline(xintercept = c(SIGMA_LOW, SIGMA_HIGH), linetype = "dashed", color = "gray45", linewidth = 0.6) +
  geom_hline(yintercept = c(LAM_BEAR, LAM_BULL), linetype = "dashed", color = "gray45", linewidth = 0.6) +
  # Old 192d gray points
  geom_point(data = trail_old, aes(sigma_plot, lam_plot, alpha = t_idx),
             color = "gray60", size = 1.3) +
  scale_alpha_continuous(range = c(0.15, 0.45), guide = "none") +
  # 60d trail line
  geom_path(data = trail, aes(sigma_plot, lam_plot), color = "#B71C1C", linewidth = 0.7, alpha = 0.4) +
  # 60d trail points (gradient)
  geom_point(data = trail, aes(sigma_plot, lam_plot, color = t_idx), size = 1.8, alpha = 0.8) +
  scale_color_gradient(low = "#FFCCBC", high = "#C62828", guide = "none") +
  # Start dot
  geom_point(data = head(trail, 1), aes(sigma_plot, lam_plot),
             shape = 21, fill = "#FDD835", color = "#424242", size = 5, stroke = 1.2) +
  # Latest dot
  geom_point(data = latest, aes(sigma_plot, lam_plot),
             shape = 21, fill = "#FDD835", color = "#424242", size = 5, stroke = 1.2) +
  # Zone labels
  geom_text(data = tbl2, aes(x, y, label = lbl),
            size = 3.2, fontface = "bold", color = "gray30", alpha = 0.7) +
  # Connector lines: dot → label
  geom_segment(data = date_labels,
               aes(x = sigma_plot, y = lam_plot,
                   xend = sigma_plot + 0.12, yend = lam_plot - 0.025),
               color = "gray30", linewidth = 0.4) +
  # Start/End date label boxes
  geom_label(data = date_labels, aes(sigma_plot, lam_plot, label = anchor_lbl),
             size = 2.4, fontface = "bold", color = "black",
             fill = scales::alpha("white", 0.85), linewidth = 0.2,
             label.padding = unit(0.12, "lines"),
             nudge_x = 0.12, nudge_y = -0.025, hjust = 0) +
  # NOW badge (top-left) — continuous risk score 포함
  annotate("label", x = XLIM[1] + 0.1, y = YLIM[2] - 0.01,
           label = sprintf("NOW: %s\nσ=%.2f%%  λ=%+.3f  μ=%+.2f%%  ν=%.1f  VaR05=%.2f%%\nRisk Score: %.2f / 5.0",
                            now_zone, latest$sigma, latest$lam, latest$mu, latest$nu,
                            latest$var_05, latest$risk_score),
           hjust = 0, vjust = 1, size = 4, fontface = "bold",
           color = "#B71C1C", fill = scales::alpha("white", 0.9), linewidth = 0.3) +
  coord_cartesian(xlim = XLIM, ylim = YLIM, clip = "off") +
  labs(title = sprintf("P3 σ × λ 9-Quadrant (252d, data: %s)", ref_date),
       subtitle = sprintf("5D Change: σ %+.2f%% | λ %+.3f | %s", ds5, dl5, dir5),
       x = expression(bold("σ (변동성, %)") * "  (calm" %<-% "" %->% "stress)"),
       y = expression(bold("λ (비대칭)") * "  (bear" %<-% "" %->% "bull)")) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, face = "bold", color = "gray30"),
        axis.title = element_text(size = 11),
        panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
        panel.grid.minor = element_blank())

# ── 6. Save ──────────────────────────────────────────────────────────────────
if (is.null(out_dir)) {
  out_dir <- file.path(
    PROJECT_ROOT,
    "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief",
    ref_date
  )
}
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "p3_9quad_ktri_style.png")
ggsave(out_path, p, width = 9, height = 6.8, dpi = 140)
cat(sprintf("[p3_9quad] saved → %s\n", out_path))
cat(sprintf("[p3_9quad] NOW: %s (σ=%.2f%% λ=%+.3f μ=%+.2f%% ν=%.1f)\n",
            now_zone, latest$sigma, latest$lam, latest$mu, latest$nu))
cat(sprintf("[p3_9quad] Risk Score: %.2f / 5.0\n", latest$risk_score))
cat(sprintf("[p3_9quad] 5D: σ %+.2f%% λ %+.3f → %s\n", ds5, dl5, dir5))
cat("\n[p3_9quad] Cell stats (backtest-driven, fwd22 avg):\n")
print(tbl2[, .(sigma_bin, lam_bin, zone, n, avg_fwd22, avg_risk)])
