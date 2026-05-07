suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

# ─── 1. 데이터 로드 (cd로 진입한 상태, 상대 경로) ─────────────
str1715 <- fread(file = "qepm/mailbox/worktask/WT-D20260427_016/backtest_result/v31_monthly_returns.csv")
str1715[, Date := as.Date(Date)]
str1715[, NAV := cum]

pg2blend <- fread(file = "qepm/mailbox/worktask/WT-D20260427_016/backtest_result_v2/pg2_blend_monthly_fullperiod.csv")
pg2blend[, Date := as.Date(paste0(YM, "-15"))]

# 12개월 rolling
str1715_12m <- str1715[Date >= as.Date("2025-05-01")]
pg2_12m <- pg2blend[Date >= as.Date("2025-05-01")]

# 정규화 (5월 = 100)
str1715_12m[, NAV_idx := 100 * NAV / NAV[1]]
pg2_12m[, NAV_idx := 100 * cum_blend / cum_blend[1]]

cat(sprintf("[data] STR_1715 12m: %d rows / Last NAV %.1f\n",
            nrow(str1715_12m), tail(str1715_12m$NAV_idx, 1)))

# ─── 2. Chart 1: STR_1715 12m NAV ────────────────────────────
p1 <- ggplot() +
  geom_line(data = str1715_12m, aes(x = Date, y = NAV_idx),
             color = "#0066CC", size = 1.2) +
  geom_point(data = str1715_12m, aes(x = Date, y = NAV_idx),
              color = "#0066CC", size = 2) +
  labs(title = "STR_1715 단독 — 최근 12개월 NAV (정규화 100)",
       subtitle = sprintf("5월 1일 = 100 -> 4월 = %.1f (12개월 누적)",
                          tail(str1715_12m$NAV_idx, 1)),
       x = NULL, y = "정규화 NAV") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "gray40"))

ggsave(filename = "/tmp/qvest_morning_equity.png", plot = p1, width = 10, height = 5, dpi = 100)
cat("[plot 1] /tmp/qvest_morning_equity.png\n")

# ─── 3. Chart 2: 24개월 월별 수익률 ─────────────────────────
pg2_24m <- pg2blend[Date >= as.Date("2024-05-01")]
pg2_24m[, color_grp := ifelse(blend_ret >= 0, "양", "음")]

p2 <- ggplot(pg2_24m, aes(x = Date, y = blend_ret * 100, fill = color_grp)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = c("양" = "#00A86B", "음" = "#CC3333")) +
  labs(title = "PG2 블렌드 — 최근 24개월 월별 수익률",
       subtitle = sprintf("%d개월 / 평균 %.2f%% / 표준편차 %.2f%% / 적중률 %.0f%%",
                          nrow(pg2_24m),
                          mean(pg2_24m$blend_ret) * 100,
                          sd(pg2_24m$blend_ret) * 100,
                          mean(pg2_24m$blend_ret > 0) * 100),
       x = NULL, y = "월별 수익률 (%)",
       fill = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 11, color = "gray40"),
        legend.position = "top")

ggsave(filename = "/tmp/qvest_morning_monthly.png", plot = p2, width = 10, height = 5, dpi = 100)
cat("[plot 2] /tmp/qvest_morning_monthly.png\n")

# ─── 4. Chart 3: 6/1 발효 sleeve pie ───────────────────────
sleeve <- data.table(
  sleeve = factor(c("STR_1715 AR 임계값", "Cross-Asset TSMOM", "KR 국채 10년"),
                   levels = c("STR_1715 AR 임계값", "Cross-Asset TSMOM", "KR 국채 10년")),
  weight = c(70, 15, 15)
)
sleeve[, label := sprintf("%s\n%d%%", sleeve, weight)]

p3 <- ggplot(sleeve, aes(x = "", y = weight, fill = sleeve)) +
  geom_bar(stat = "identity", width = 1, color = "white", size = 2) +
  coord_polar("y", start = 0) +
  scale_fill_manual(values = c("STR_1715 AR 임계값" = "#1F4E79",
                                "Cross-Asset TSMOM"  = "#FFB74D",
                                "KR 국채 10년"       = "#66BB6A")) +
  geom_text(aes(label = label), position = position_stack(vjust = 0.5),
             color = "white", fontface = "bold", size = 4.5) +
  labs(title = "PG2 운용 — 6월 1일 발효 슬리브 배분",
       subtitle = "Hybrid 70/15/15 (Path C 승인 5월 5일)") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
        plot.subtitle = element_text(size = 11, color = "gray40", hjust = 0.5),
        legend.position = "none")

ggsave(filename = "/tmp/qvest_morning_sleeve.png", plot = p3, width = 8, height = 6, dpi = 100)
cat("[plot 3] /tmp/qvest_morning_sleeve.png\n")

cat("[done] 3 PNGs saved\n")
