## 14_jump_figure.R — 점프 모형 시험 구간(그날 기준 온라인 국면 · 6개월마다 재선택된 (λ, κ)) 그림: 요인 누적 수익 + 강세/약세 띠
suppressMessages({ library(data.table) })
a <- commandArgs(trailingOnly = TRUE); TP <- readRDS(a[1]); OUTP <- a[2]
nm <- c(SMB = "규모(SMB)", HML = "가치(HML)", RMW = "수익성(RMW)", CMA = "투자(CMA)", WML = "모멘텀(WML)")
png(OUTP, width = 1300, height = 1250)
par(mfrow = c(5, 1), mar = c(2.2, 5, 2.6, 1), cex.main = 1.3, cex.axis = 1.05)
for (f in names(TP)) {
  te <- as.data.table(TP[[f]]$test); cum <- cumprod(1 + te$r)
  plot(te$Date, cum, type = "n", log = "y", xlab = "", ylab = "누적(로그)",
       main = sprintf("%s — 점프 모형 그날 기준 국면(초록 = 강세 · 빨강 = 약세) · 전환 %.1f회/년", nm[[f]],
                      sum(diff(te$state) != 0) / (as.numeric(diff(range(te$Date))) / 365.25)))
  rl <- rle(te$state); ends <- cumsum(rl$lengths); starts <- c(1, head(ends, -1) + 1)
  usr <- par("usr")
  for (i in seq_along(rl$values))
    rect(te$Date[starts[i]], 10^usr[3], te$Date[ends[i]], 10^usr[4], border = NA,
         col = if (rl$values[i] == 1) adjustcolor("forestgreen", 0.15) else adjustcolor("firebrick", 0.15))
  lines(te$Date, cum, lwd = 1.8)
}
dev.off(); cat("written", OUTP, "\n")
