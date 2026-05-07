suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(scales)
})

# ─── 1. 데이터 로드 ───────────────────────────────────────────
r7 <- as.data.table(read_parquet(".cache/regime_v7.parquet"))
us <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))

# 24개월 window (최근)
r7_24m <- r7[apply_start >= as.Date("2024-05-01")]
setorder(r7_24m, apply_start)

us_24m <- us[Date >= as.Date("2024-05-01")]
setorder(us_24m, Date)

# 4월 최신 status
mrs_now <- tail(r7_24m$MRS, 1)
slow_crisis_now <- tail(r7_24m$slow_crisis, 1)
cat_now <- tail(us_24m$Category, 1)
score_now <- tail(us_24m$Regime_Score, 1)
cash_now <- tail(us_24m$Cash_Pct, 1)
ktri_now <- tail(us_24m$KTRI_Score, 1)
fred_now <- tail(us_24m$FRED_MRS, 1)

cat(sprintf("[현황 4월] MRS v7 = %.1f / slow_crisis %.2f\n", mrs_now, slow_crisis_now))
cat(sprintf("[unified]  Score %.1f / Category %s / Cash %.1f%%\n",
            score_now, cat_now, cash_now * 100))
cat(sprintf("[layers]   FRED %.1f / KTRI %.1f\n", fred_now, ktri_now))

# Regime classification 4-bin (MRS thresholds)
classify_mrs <- function(x) {
  fcase(
    is.na(x), NA_character_,
    x < 25,    "BULL",
    x < 40,    "NORMAL",
    x < 55,    "CAUTION",
    default = "CRISIS"
  )
}
r7_24m[, regime := classify_mrs(MRS)]
r7_24m[, regime := factor(regime, levels = c("BULL", "NORMAL", "CAUTION", "CRISIS"))]

# ─── 2. Chart 1: MRS v7 24개월 ───────────────────────────────
regime_colors <- c("BULL" = "#4CAF50", "NORMAL" = "#2196F3",
                    "CAUTION" = "#FF9800", "CRISIS" = "#E53935")

p1 <- ggplot(r7_24m, aes(x = apply_start, y = MRS, fill = regime)) +
  geom_bar(stat = "identity", width = 25) +
  geom_hline(yintercept = c(25, 40, 55), color = "gray60",
              linetype = "dashed", linewidth = 0.5) +
  annotate("text", x = min(r7_24m$apply_start), y = 28, label = "BULL/NORMAL",
            hjust = 0, size = 3, color = "gray40") +
  annotate("text", x = min(r7_24m$apply_start), y = 43, label = "NORMAL/CAUTION",
            hjust = 0, size = 3, color = "gray40") +
  annotate("text", x = min(r7_24m$apply_start), y = 58, label = "CAUTION/CRISIS",
            hjust = 0, size = 3, color = "gray40") +
  scale_fill_manual(values = regime_colors, drop = FALSE) +
  labs(title = "시장 국면 점수 (MRS v7) — 최근 24개월",
       subtitle = sprintf("4월 = %.1f (%s) / 임계: 25 / 40 / 55",
                          mrs_now, classify_mrs(mrs_now)),
       x = NULL, y = "MRS v7 점수", fill = "국면") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "gray40"),
        legend.position = "top")

ggsave(filename = "/tmp/qvest_morning_mrs.png", plot = p1,
        width = 11, height = 5, dpi = 100)
cat("[plot 1] /tmp/qvest_morning_mrs.png\n")

# ─── 3. Chart 2: 4-Layer Signal 24개월 ──────────────────────
us_long <- melt(us_24m[, .(Date, MSM = MSM_Crisis_Prob * 100,
                           FRED = FRED_MRS,
                           KTRI = KTRI_Score,
                           VEA = VEA_Score)],
                id.vars = "Date",
                variable.name = "Layer", value.name = "Score")

p2 <- ggplot(us_long, aes(x = Date, y = Score, color = Layer)) +
  geom_line(linewidth = 1.0, na.rm = TRUE) +
  geom_point(size = 1.5, na.rm = TRUE) +
  scale_color_manual(values = c("MSM" = "#E53935", "FRED" = "#1976D2",
                                 "KTRI" = "#43A047", "VEA" = "#FB8C00")) +
  labs(title = "통합 국면 신호 4계층 — 최근 24개월",
       subtitle = sprintf("4월: 시장상태(MSM) NA / FRED %.1f / KTRI %.1f / VEA %.1f",
                          fred_now, ktri_now,
                          tail(us_24m$VEA_Score, 1)),
       x = NULL, y = "점수 (0~100)", color = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "gray40"),
        legend.position = "top")

ggsave(filename = "/tmp/qvest_morning_layers.png", plot = p2,
        width = 11, height = 5, dpi = 100)
cat("[plot 2] /tmp/qvest_morning_layers.png\n")

# ─── 4. Chart 3: Regime Score + Cash 24개월 ────────────────
us_24m[, RegimeScoreScaled := Regime_Score]
us_24m[, CashScaled := Cash_Pct * 100]

p3 <- ggplot(us_24m, aes(x = Date)) +
  geom_bar(aes(y = CashScaled, fill = "현금 비중"),
            stat = "identity", alpha = 0.5, width = 25) +
  geom_line(aes(y = RegimeScoreScaled, color = "국면 점수"),
             linewidth = 1.2) +
  geom_point(aes(y = RegimeScoreScaled, color = "국면 점수"), size = 2) +
  scale_fill_manual(values = c("현금 비중" = "#9E9E9E"), name = NULL) +
  scale_color_manual(values = c("국면 점수" = "#1F4E79"), name = NULL) +
  labs(title = "통합 국면 점수 + 현금 비중 권고 — 최근 24개월",
       subtitle = sprintf("4월: 점수 %.1f (%s) / 권고 현금 %.1f%% / 5월 운용 = 70 위험 + 30 현금",
                          score_now, cat_now, cash_now * 100),
       x = NULL, y = "값 (점수 / 현금 %)") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "gray40"),
        legend.position = "top")

ggsave(filename = "/tmp/qvest_morning_score_cash.png", plot = p3,
        width = 11, height = 5, dpi = 100)
cat("[plot 3] /tmp/qvest_morning_score_cash.png\n")

# Save summary for telegram
saveRDS(list(mrs = mrs_now, slow_crisis = slow_crisis_now,
              category = cat_now, score = score_now, cash = cash_now,
              fred = fred_now, ktri = ktri_now,
              regime_24m_dist = table(r7_24m$regime)),
        "/tmp/qvest_regime_summary.rds")

cat("[done] 3 PNGs + summary saved\n")
