## P2R01 보고 차트 2장 — 계약 산출물(02_nav · 05_benchmark · 전기간 행동 카드)의 시각화만(성과 수치 자체 계산 없음 · 원칙 9)
## 실행: Rscript charts.R   (evaluate.R 뒤 — results/<코드>/full/behavior_card.json 이 있어야 한다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
RD <- "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot"
OUT <- "stage_artifacts/programs/P2_DEFENSE/P2R01_s2_pilot/charts"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
TAU <- as.Date("2022-12-31")
LAB <- c(RX0 = "기저(같은 판본 재측정)", RX1 = "처방 1 · 하방 비대칭 팩터", RX2 = "처방 2 · 회전 상한", RX3 = "처방 3 · 추세 상태 베타 오버레이")
COL <- c("KOSPI200" = "grey55", "기저(같은 판본 재측정)" = "black", "처방 1 · 하방 비대칭 팩터" = "#d1495b",
         "처방 2 · 회전 상한" = "#00798c", "처방 3 · 추세 상태 베타 오버레이" = "#edae49")

navs <- list(); cards <- list(); bench <- NULL
for (id in names(LAB)) {
  rj <- file.path(RD, "results", sprintf("P2R01_%s.json", id)); if (!file.exists(rj)) next
  r <- fromJSON(rj); if (!isTRUE(r$ok)) next
  nv <- fread(file.path(r$artifacts, "02_nav.csv"), select = c("date", "nav_net"))
  navs[[id]] <- nv[, .(date = as.Date(date), nav = nav_net, series = LAB[[id]])]
  if (is.null(bench)) { b <- fread(file.path(r$artifacts, "05_benchmark_returns.csv"), select = c("date", "benchmark_nav"))
                        bench <- b[, .(date = as.Date(date), nav = benchmark_nav, series = "KOSPI200")] }
  cf <- file.path(RD, "results", sprintf("P2R01_%s", id), "full", "behavior_card.json")
  if (file.exists(cf)) cards[[id]] <- fromJSON(cf, simplifyVector = TRUE)
}
stopifnot(length(navs) >= 1L, !is.null(bench), "RX0" %in% names(cards))
D <- rbindlist(c(list(bench), navs))
D[, series := factor(series, levels = names(COL)[names(COL) %in% unique(series)])]
cr <- as.data.table(cards$RX0$crises)[, .(peak = as.Date(peak_date), trough = as.Date(trough_date))]
## 로그 축에서는 ±Inf 음영이 NaN 으로 떨어진다 — 자료 범위로 유한하게 잡는다
cr[, `:=`(ylo = min(D$nav, na.rm = TRUE) * 0.92, yhi = max(D$nav, na.rm = TRUE) * 1.08)]

g1 <- ggplot(D, aes(date, nav, colour = series)) +
  geom_rect(data = cr, aes(xmin = peak, xmax = trough, ymin = ylo, ymax = yhi), inherit.aes = FALSE, fill = "#e63946", alpha = 0.12) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "grey30") +
  annotate("text", x = TAU, y = Inf, label = "τ_D 2022-12-31 · 오른쪽 = 시험 창", hjust = 1.02, vjust = 1.5, size = 3) +
  geom_line(linewidth = 0.45) + scale_y_log10() + scale_colour_manual(values = COL, name = NULL) +
  labs(title = "P2R01 — 누적 순자산(15bps 순 · 로그) · 붉은 음영 = 위기(Lunde-Timmermann 20/20)",
       x = NULL, y = "순자산(시작 = 1)") +
  theme_minimal(base_size = 10) + theme(legend.position = "bottom", legend.text = element_text(size = 8)) +
  guides(colour = guide_legend(nrow = 2))
ggsave(file.path(OUT, "cum_nav_crisis.png"), g1, width = 9, height = 5.4, dpi = 130)

C <- rbindlist(lapply(names(cards), function(id) {
  x <- as.data.table(cards[[id]]$crises)
  if (!nrow(x)) return(NULL)
  x[, .(crisis = sprintf("%s~%s", format(as.Date(peak_date), "%y.%m"), format(as.Date(trough_date), "%y.%m")),
        window = window, dd_capture = as.numeric(dd_capture), series = LAB[[id]])]
}), fill = TRUE)
C[, crisis := factor(crisis, levels = unique(crisis[order(as.Date(paste0("20", substr(crisis, 1, 5), ".01"), "%Y.%m.%d"))]))]
C[, series := factor(series, levels = names(COL)[names(COL) %in% unique(series)])]
g2 <- ggplot(C, aes(crisis, dd_capture, colour = series)) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "grey40") +
  geom_point(size = 2.4, position = position_dodge(width = 0.55)) +
  scale_colour_manual(values = COL, name = NULL) +
  labs(title = "위기별 하락 포착률(전략 낙폭 ÷ 시장 낙폭 · 1 미만 = 시장보다 덜 빠짐)",
       subtitle = "전기간 행동 카드 · 위기 = Lunde-Timmermann 20/20 · 2023년 이후 위기는 시험 창", x = NULL, y = "하락 포착률") +
  theme_minimal(base_size = 10) + theme(legend.position = "bottom", legend.text = element_text(size = 8),
                                        axis.text.x = element_text(angle = 30, hjust = 1)) +
  guides(colour = guide_legend(nrow = 2))
ggsave(file.path(OUT, "crisis_dd_capture.png"), g2, width = 9, height = 5.0, dpi = 130)
cat("charts:", file.path(OUT, c("cum_nav_crisis.png", "crisis_dd_capture.png")), sep = "\n")
