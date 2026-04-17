library(data.table); library(arrow); library(ggplot2)
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== Regime Engine Visualization & Telegram Briefing ===\n\n")

output_dir <- file.path(RESEARCH_OUTPUT, "regime_comparison/output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ================================================================
# Load data
# ================================================================
regime <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
regime[, Date := as.Date(Date)]
setorder(regime, Date)

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
bm[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm[, .(BM_Ret_M = prod(1 + BM_Ret) - 1), by = YM]
regime <- merge(regime, bm_monthly, by = "YM", all.x = TRUE)
setorder(regime, Date)
regime[, CumRet := cumprod(1 + fifelse(is.na(BM_Ret_M), 0, BM_Ret_M))]

# BCS
bcs_path <- file.path(output_dir, "bcs_daily_signal.parquet")
has_bcs <- file.exists(bcs_path)
if (has_bcs) {
  bcs <- as.data.table(read_parquet(bcs_path))
  bcs[, Date := as.Date(Date)]
  bcs[, YM := format(Date, "%Y-%m")]
  bcs_monthly <- bcs[, .(BCS_avg = mean(BCS, na.rm = TRUE),
                           BCS_Q5_pct = mean(BCS_Q == "Q5", na.rm = TRUE) * 100),
                       by = YM]
}

# ================================================================
# Chart 1: Regime Score Time Series + Category Overlay
# ================================================================
cat("[viz] Chart 1: Regime Score time series...\n")

regime[, Category_f := factor(Category,
                                levels = c("RISK_OFF","CAUTION","NEUTRAL","RISK_ON"))]

p1 <- ggplot(regime, aes(x = Date)) +
  geom_rect(aes(xmin = Date - 15, xmax = Date + 15,
                ymin = 0, ymax = 100,
                fill = Category_f), alpha = 0.3) +
  geom_line(aes(y = Regime_Score), linewidth = 0.8, color = "black") +
  geom_hline(yintercept = c(25, 45, 70), linetype = "dashed", color = "grey50", linewidth = 0.3) +
  scale_fill_manual(values = c(RISK_OFF = "#d32f2f", CAUTION = "#ff9800",
                                NEUTRAL = "#90caf9", RISK_ON = "#4caf50"),
                     name = "Category") +
  annotate("text", x = as.Date("1992-01-01"), y = c(12, 35, 57, 85),
           label = c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF"),
           hjust = 0, size = 3, color = "grey40") +
  labs(title = "Unified Regime Signal: 3-Layer Cascade Score",
       subtitle = "MSM(40pt) + FRED MRS(35pt) + KTRI/VEA(15pt) | 1990-09 ~ 2026-03",
       x = NULL, y = "Regime Score (0-100)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(output_dir, "regime_score_timeseries.png"), p1,
       width = 14, height = 6, dpi = 150)

# ================================================================
# Chart 2: Regime Score vs Benchmark Cumulative Return
# ================================================================
cat("[viz] Chart 2: Score vs cumulative return...\n")

p2 <- ggplot(regime, aes(x = Date)) +
  geom_rect(aes(xmin = Date - 15, xmax = Date + 15,
                ymin = 0, ymax = Inf,
                fill = Category_f), alpha = 0.15) +
  geom_line(aes(y = CumRet), color = "#1565c0", linewidth = 0.7) +
  geom_line(aes(y = Regime_Score / 15), color = "red", linewidth = 0.5, alpha = 0.7) +
  scale_y_continuous(
    name = "KOSPI 200 Cumulative Return",
    sec.axis = sec_axis(~ . * 15, name = "Regime Score")
  ) +
  scale_fill_manual(values = c(RISK_OFF = "#d32f2f", CAUTION = "#ff9800",
                                NEUTRAL = "#90caf9", RISK_ON = "#4caf50"),
                     name = "") +
  labs(title = "Regime Score (red) vs KOSPI200 Cumulative Return (blue)",
       subtitle = "RISK_OFF/CAUTION periods shaded | Score overlaid on right axis",
       x = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(output_dir, "regime_vs_cumret.png"), p2,
       width = 14, height = 6, dpi = 150)

# ================================================================
# Chart 3: Crisis Detection Timeline (zoomed)
# ================================================================
cat("[viz] Chart 3: Crisis detection zoom...\n")

crises <- list(
  list(name = "GFC", start = "2007-01-01", end = "2009-06-30",
       crash_start = "2008-01-01", peak_ym = "2008-09"),
  list(name = "COVID", start = "2019-07-01", end = "2020-09-30",
       crash_start = "2020-02-20", peak_ym = "2020-03"),
  list(name = "Rate Shock", start = "2021-06-01", end = "2023-01-31",
       crash_start = "2022-01-05", peak_ym = "2022-09")
)

crisis_plots <- list()
for (cr in crises) {
  sub_dt <- regime[Date >= cr$start & Date <= cr$end]
  if (nrow(sub_dt) == 0) next

  pp <- ggplot(sub_dt, aes(x = Date)) +
    geom_col(aes(y = Regime_Score, fill = Category_f), width = 25, alpha = 0.8) +
    geom_hline(yintercept = c(45, 70), linetype = "dashed", color = "grey40") +
    geom_vline(xintercept = as.Date(cr$crash_start), color = "red",
               linetype = "solid", linewidth = 0.8) +
    annotate("text", x = as.Date(cr$crash_start), y = 85,
             label = "Crash Start", hjust = -0.1, color = "red", size = 3) +
    scale_fill_manual(values = c(RISK_OFF = "#d32f2f", CAUTION = "#ff9800",
                                  NEUTRAL = "#90caf9", RISK_ON = "#4caf50")) +
    labs(title = sprintf("%s Crisis: Regime Score Timeline", cr$name),
         x = NULL, y = "Score") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "none")

  fname <- sprintf("crisis_zoom_%s.png", tolower(cr$name))
  ggsave(file.path(output_dir, fname), pp, width = 10, height = 4, dpi = 150)
  crisis_plots[[cr$name]] <- fname
}

# ================================================================
# Chart 4: BCS Components During Crises (if available)
# ================================================================
if (has_bcs) {
  cat("[viz] Chart 4: BCS daily signal...\n")

  bcs[, BCS_smooth := frollmean(BCS, n = 20, align = "right")]
  q80 <- quantile(bcs$BCS, 0.8, na.rm = TRUE)

  p4 <- ggplot(bcs, aes(x = Date)) +
    geom_line(aes(y = BCS), color = "grey70", linewidth = 0.3) +
    geom_line(aes(y = BCS_smooth), color = "#e65100", linewidth = 0.7) +
    geom_hline(yintercept = q80, linetype = "dashed", color = "red") +
    annotate("text", x = min(bcs$Date) + 100, y = q80 + 0.02,
             label = "Q5 (Danger) Threshold", color = "red", size = 3) +
    labs(title = "BCS Daily Signal (20d smoothed)",
         subtitle = sprintf("BCS v2: VIX_Chg3(40%%) + Complacency(25%%) + MultiDanger(15%%) + PutOI(20%%) | r=-0.143"),
         x = NULL, y = "BCS Score") +
    theme_minimal(base_size = 11)

  ggsave(file.path(output_dir, "bcs_daily_signal.png"), p4,
         width = 14, height = 5, dpi = 150)
}

# ================================================================
# Chart 5: Cash Allocation Over Time (Cascade + BCS)
# ================================================================
cat("[viz] Chart 5: Cash allocation...\n")

regime[, Cash_Pct_100 := Cash_Pct * 100]
if (has_bcs) {
  regime <- merge(regime, bcs_monthly, by = "YM", all.x = TRUE)
  regime[, BCS_Overlay := fifelse(!is.na(BCS_Q5_pct) & BCS_Q5_pct > 50, 15,
                            fifelse(!is.na(BCS_Q5_pct) & BCS_Q5_pct > 25, 5, 0))]
  regime[, Total_Cash := pmin(100, Cash_Pct_100 + BCS_Overlay)]
} else {
  regime[, Total_Cash := Cash_Pct_100]
}

p5 <- ggplot(regime[!is.na(Cash_Pct)], aes(x = Date)) +
  geom_area(aes(y = Total_Cash), fill = "#ef5350", alpha = 0.4) +
  geom_area(aes(y = Cash_Pct_100), fill = "#ef5350", alpha = 0.6) +
  labs(title = "Cash Allocation: Cascade (dark) + BCS Overlay (light)",
       subtitle = "Graduated: Score>=70 → 50-100%, Score 45-69 → 15-35%, BCS Q5 → +15%",
       x = NULL, y = "Cash %") +
  scale_y_continuous(limits = c(0, 100)) +
  theme_minimal(base_size = 11)

ggsave(file.path(output_dir, "cash_allocation.png"), p5,
       width = 14, height = 4, dpi = 150)

# ================================================================
# Chart 6: Layer Contribution Stacked Area
# ================================================================
cat("[viz] Chart 6: Layer contributions...\n")

regime[, L1_contrib := 40 * pmin(1, fifelse(is.na(MSM_Crisis_Prob), 0, MSM_Crisis_Prob) / 0.8)]
regime[, L2_contrib := 0.35 * fifelse(is.na(FRED_MRS), 0, FRED_MRS)]
regime[, L3_contrib := fifelse(
  !is.na(KTRI_Score) & KTRI_Score <= 35 & !is.na(VEA_Score) & VEA_Score >= 70, 15,
  fifelse(!is.na(KTRI_Score) & KTRI_Score <= 35 | (!is.na(VEA_Score) & VEA_Score >= 70), 8, 0))]

layer_long <- melt(regime[, .(Date, MSM = L1_contrib, FRED = L2_contrib, KTRI = L3_contrib)],
                    id.vars = "Date", variable.name = "Layer", value.name = "Contribution")

p6 <- ggplot(layer_long, aes(x = Date, y = Contribution, fill = Layer)) +
  geom_area(alpha = 0.7) +
  scale_fill_manual(values = c(MSM = "#42a5f5", FRED = "#66bb6a", KTRI = "#ffa726")) +
  geom_hline(yintercept = c(45, 70), linetype = "dashed", color = "grey40") +
  labs(title = "3-Layer Cascade: Contribution Breakdown",
       subtitle = "MSM(max 40pt) + FRED(max 35pt) + KTRI(max 15pt)",
       x = NULL, y = "Score Points") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(output_dir, "layer_contributions.png"), p6,
       width = 14, height = 5, dpi = 150)

# ================================================================
# Telegram Briefing
# ================================================================
cat("\n[tg] Sending regime engine briefing...\n")

# Current regime
curr <- regime[.N]
curr_bcs <- if (has_bcs) sprintf("BCS avg=%.3f", tail(bcs$BCS, 1)) else "N/A"

briefing_msg <- sprintf(
'<b>🔬 국면 엔진 v1.1 — 3-Layer Cascade + BCS</b>

<b>▸ 현재 국면 (%s)</b>
  Score: %.1f → <b>%s</b> | Cash: %.0f%%
  MSM: %.2f | FRED: %.0f | KTRI: %.0f | VEA: %.0f
  %s

<b>▸ Architecture</b>
  L1 (MSM): 조기탐지 (Recall 86.5%%, max 40pt)
  L2 (FRED): 거시확인 (Precision 40%%, max 35pt)
  L3 (KTRI+VEA): 미시구조 (Precision 60.8%%, max 15pt)
  L4 (BCS): 행태 오버레이 (r=-0.143, Q5→+15%% cash)

<b>▸ BCS (Behavioral Composite Score)</b>
  VIX 3d변화(40%%) + Complacency(25%%) + Multi-Danger(15%%) + Put OI(20%%)
  Q1-Q5 spread: +2.52%%/mo | Cascade 직교(r=0.07)
  위기 선행: COVID +80d, Rate +181d, 2015China +83d

<b>▸ Crisis Detection</b>
  GFC 2008: Peak 81.2 (RISK_OFF, Cash 69%%)
  COVID 2020: Peak 74.2 (RISK_OFF, Cash 57%%)
  Rate 2022: Peak 64.4 (CAUTION, Cash 30%%)

<b>▸ Backtest (BM overlay)</b>
  Benchmark: CAGR 5.9%%, Sharpe 0.338
  Cascade: CAGR 8.0%%, Sharpe 0.425
  Cascade+BCS: CAGR 8.2%%, Sharpe 0.433

<b>▸ 신규 교훈 (L-44~L-48)</b>
  L-44: BCS r=-0.143, 최강 행태 신호
  L-45: Complacency=유일한 사전위기 신호
  L-46: VIX 3일 변화가 최적 룩백
  L-47: BCS↔Cascade 직교(r=0.07), NEUTRAL +353bps VA
  L-48: BCS 위기 선행 20-181일

📁 regime_signal.R v1.1 | bcs_daily_signal.parquet',
  curr$YM, curr$Regime_Score, curr$Category, curr$Cash_Pct * 100,
  curr$MSM_Crisis_Prob, curr$FRED_MRS, curr$KTRI_Score, curr$VEA_Score,
  curr_bcs)

tg_send(briefing_msg)
cat("[tg] Briefing sent.\n")

# Send charts
charts <- c("regime_score_timeseries.png", "regime_vs_cumret.png",
             "layer_contributions.png", "cash_allocation.png")
if (has_bcs) charts <- c(charts, "bcs_daily_signal.png")
charts <- c(charts, paste0("crisis_zoom_", c("gfc","covid","rate shock"), ".png"))

for (chart_file in charts) {
  full_path <- file.path(output_dir, chart_file)
  if (file.exists(full_path)) {
    tg_send_photo(full_path, caption = tools::file_path_sans_ext(chart_file))
    Sys.sleep(0.5)
    cat(sprintf("[tg] Sent: %s\n", chart_file))
  }
}

cat("\n=== Visualization & Briefing Complete ===\n")
