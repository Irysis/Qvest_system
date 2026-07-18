## ae_crisis_tripwire_chart.R — AE crisis tripwire 타임라인 차트 (텔레그램 시각화 전용)
## 시각화 전용 — 게이트/판정 수치 아님. 소비: ae_crisis_tripwire_timeline.csv
suppressWarnings(suppressMessages({library(data.table)}))
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
tl <- fread(file.path(ROOT, "qepm/observability/ae_crisis_tripwire_timeline.csv"))
tl[, decision_date := as.Date(decision_date)]
tl[, exceed_max := pmax(exceed_seq, exceed_pt)]
OUT <- file.path(ROOT, "qepm/observability/ae_crisis_tripwire_timeline.png")

col_state <- c(AE_ACUTE_ALERT="#d62728", BOTH_CONFIRM="#ff7f0e", M4_ONLY="#1f77b4", CALM="#cccccc")
crisis <- list(list("2008 GFC","2008-08-01","2009-04-30"),
               list("COVID","2020-02-01","2020-04-30"),
               list("2022","2022-01-01","2022-10-31"))

grDevices::png(OUT, width = 1180, height = 560, res = 110)
graphics::par(mar = c(3.6, 4.4, 3.4, 1.2), family = "")
YCAP <- 6                                            # y 상한 캡 (2008 GFC 피크 ~18은 off-scale 주석)
tl[, y_disp := pmin(exceed_max, YCAP)]
peak_i <- which.max(tl$exceed_max); peak_v <- tl$exceed_max[peak_i]
plot(tl$decision_date, tl$y_disp, type = "n", ylim = c(0, YCAP),
     xlab = "", ylab = "AE 이탈 초과배율  (recon-error / tau, y캡 6)",
     main = "AE 비지도 이상탐지 crisis tripwire — 이탈 초과배율 vs M4 발화 (2008-2026)")
## crisis window 음영
for (cw in crisis) {
  rect(as.Date(cw[[2]]), 0, as.Date(cw[[3]]), YCAP, col = "#fdece0", border = NA)
  text(mean(c(as.Date(cw[[2]]), as.Date(cw[[3]]))), YCAP*0.90, cw[[1]], cex = 0.72, col = "#a0522d")
}
abline(h = 1.0, lty = 2, col = "#555555")            # AE fire threshold
text(as.Date("2013-01-01"), 1.12, "tau (발화 임계 = 1.0)", pos = 4, cex = 0.66, col = "#555555")
## AE 이탈 초과배율 선 (캡)
lines(tl$decision_date, tl$y_disp, col = "#888888", lwd = 1)
## M4 발화 = 하단 파랑 tick
m4 <- tl[m4_fire == 1L]
points(m4$decision_date, rep(0.06, nrow(m4)), pch = 17, col = "#1f77b4", cex = 0.8)
## AE 발화월 = 상태색 점 (캡)
fp <- tl[ae_fire == 1L]
points(fp$decision_date, pmin(fp$exceed_max, YCAP), pch = 19,
       col = col_state[fp$state], cex = 1.05)
## 2008 GFC off-scale 피크 주석
text(tl$decision_date[peak_i], YCAP*0.985, sprintf("2008 GFC 피크 %.0f×↑ (캡)", peak_v),
     cex = 0.66, col = "#d62728", pos = 4)
legend("topright", bty = "n", cex = 0.72,
       legend = c("AE_ACUTE_ALERT (M4 미발화 급성 OOD)", "BOTH_CONFIRM (AE∧M4)",
                  "M4 발화(하단 ▲)", "AE 이탈 초과배율"),
       col = c(col_state["AE_ACUTE_ALERT"], col_state["BOTH_CONFIRM"], "#1f77b4", "#888888"),
       pch = c(19, 19, 17, NA), lwd = c(NA, NA, NA, 1))
mtext("2008 GFC: AE 9/9 방어 · M4 6/9 (AE_ACUTE 3=M4 미포착)   |   monitoring 배관 · 자본 아님",
      side = 1, line = 2.2, cex = 0.7, col = "#666666")
grDevices::dev.off()
cat("[chart] →", OUT, "\n")
