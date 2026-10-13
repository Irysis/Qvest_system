## P0R01 도판 — ① 보는 창 프런티어(상승 포착 × 위기 누적 포착 · CAGR 문턱 색) ② 엔진별 기준(C0) · 보는 창 S 최고 칸 누적 곡선(로그 · τ_D 선)
## 수치 = evaluation.json(R 계약 산출) · 곡선 = 각 칸 산출물 02_nav.csv · 05_benchmark_returns.csv(그린다 · 계산하지 않는다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
OUT <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/charts"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = TRUE)
T <- as.data.table(ev$table)[status %in% c("evaluated", "axis_violation")]
UCF <- ev$thresholds$uc_floor; DCS <- suppressWarnings(as.numeric(ev$thresholds$dc_strong[1])); CM <- ev$thresholds$cagr_min
font <- if (.Platform$OS.type == "windows") { windowsFonts(K = windowsFont("Malgun Gothic")); "K" } else "sans"
eng_col <- c(E1 = "#1f77b4", E2 = "#d62728", E3 = "#2ca02c")
png(file.path(OUT, "frontier_visible.png"), width = 1400, height = 1000, res = 150, family = font)
par(mar = c(5, 5, 4, 2))
xr <- range(c(T$dc, DCS), na.rm = TRUE); yr <- range(c(T$uc, UCF), na.rm = TRUE)
plot(T$dc, T$uc, type = "n", xlim = xr + c(-0.05, 0.05), ylim = yr + c(-0.05, 0.05),
     xlab = "위기 누적 포착(보는 창 중앙값 · 낮을수록 방어)", ylab = "강세 상승 포착(보는 창 중앙값)",
     main = "P0 실현 가능성 지도 — 보는 창(2000~2022)")
rect(xr[1] - 1, UCF, DCS, yr[2] + 1, col = adjustcolor("#2ca02c", 0.08), border = NA)
abline(h = UCF, lty = 2, col = "grey40"); abline(v = DCS, lty = 2, col = "grey40")
points(T$dc, T$uc, pch = ifelse(T$cagr >= CM, 19, 1), col = eng_col[T$engine], cex = 1.6)
text(T$dc, T$uc, labels = T$component, pos = 3, cex = 0.75, col = eng_col[T$engine])
legend("bottomright", bty = "n", cex = 0.85,
       legend = c("E1 모멘텀 12-1", "E2 2002.06975 원형", "E3 B6_36", "● CAGR ≥ 16%  ○ 미만", "녹색 = 목표 영역(상승 · 위기)"),
       col = c(eng_col, "black", "#2ca02c"), pch = c(19, 19, 19, NA, 15), pt.cex = c(1.2, 1.2, 1.2, NA, 1.5))
mtext(sprintf("부품: C0 없음 · C1 추세 현금 · C2 변동성 타기팅 · C3 낙폭 제어 · C4 저변동 · C5 퀄리티 · C6 추세+저변동 | 문턱 상승 %.2f · 위기 %.3f",
              UCF, DCS), side = 1, line = 4, cex = 0.7)
dev.off()
## 누적 곡선 — 엔진별 C0 와 보는 창 S 최고 칸
pick <- unique(c(T[component == "C0"]$code, T[, .SD[which.max(S_vis)], by = engine]$code))
nav <- function(code) {
  e <- fromJSON(file.path(RD, "results", code, "eval.json"), simplifyVector = TRUE)
  n <- fread(file.path(e$artifacts, "02_nav.csv"))[, .(date = as.Date(date), nav = nav_net / nav_net[1])]
  n[, code := code]; n
}
N <- rbindlist(lapply(pick, nav))
b <- fread(file.path(fromJSON(file.path(RD, "results", pick[1], "eval.json"))$artifacts, "05_benchmark_returns.csv"))[, .(date = as.Date(date), nav = benchmark_nav / benchmark_nav[1])]
png(file.path(OUT, "nav_engines.png"), width = 1600, height = 900, res = 150, family = font)
par(mar = c(4, 5, 4, 2))
plot(b$date, b$nav, type = "l", log = "y", col = "grey30", lwd = 2, ylim = range(c(N$nav, b$nav), na.rm = TRUE),
     xlab = "", ylab = "누적(로그)", main = "엔진별 기준(C0) · 보는 창 S 최고 칸 vs KOSPI200")
abline(v = as.Date("2022-12-31"), lty = 3); text(as.Date("2022-12-31"), max(N$nav, na.rm = TRUE), "τ_D", pos = 4, cex = 0.8)
for (cd in pick) { x <- N[code == cd]; en <- T[code == cd]$engine; lines(x$date, x$nav, col = eng_col[en], lty = if (T[code == cd]$component == "C0") 2 else 1, lwd = 1.6) }
legend("topleft", bty = "n", cex = 0.8, legend = c("KOSPI200", paste0(T[code %in% pick]$engine, " ", T[code %in% pick]$component)),
       col = c("grey30", eng_col[T[code %in% pick]$engine]), lty = c(1, ifelse(T[code %in% pick]$component == "C0", 2, 1)), lwd = 1.6)
dev.off()
cat("도판:", file.path(OUT, c("frontier_visible.png", "nav_engines.png")), "\n")
