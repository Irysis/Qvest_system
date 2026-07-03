# pg2_w2_charts.R — PG2 강화 P1: 최우수 후보(S3_consensus + 보유밴드) 2차트
#   equity_curve.png (누적 vs BM) + annual_returns.png (연간 vs BM). alpha-search 2차트 규약.
suppressMessages(library(data.table))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(ROOT, "stage_artifacts/pg2_w2_earnings3m")
prs <- readRDS(file.path(OUTDIR, "period_returns_store.rds"))

BEST <- "S3_consensus_band"    # 최우수: 보유밴드 결합 3-신호 합의 (paired-t +2.03, PORT_t 2.20)
pr <- as.data.table(prs[[BEST]])
setorder(pr, date)
pr[, nav_str := cumprod(1 + ret_net)]
pr[, nav_bm := cumprod(1 + benchmark_ret)]

# --- Chart 1: equity curve vs BM ---
png(file.path(OUTDIR, "equity_curve.png"), width = 1000, height = 560, res = 110)
par(mar = c(4, 4.2, 3.2, 1))
yl <- range(c(pr$nav_str, pr$nav_bm))
plot(pr$date, pr$nav_str, type = "l", lwd = 2.4, col = "#1f77b4", log = "y",
     ylim = yl, xlab = "", ylab = "누적수익 (log, 초기=1)",
     main = "PG2 강화 P1: 3-신호합의+보유밴드 vs KOSPI200 (net 15bps)")
lines(pr$date, pr$nav_bm, lwd = 2, col = "#888888", lty = 2)
legend("topleft", legend = c("전략(S3 합의+밴드)", "KOSPI200"),
       col = c("#1f77b4", "#888888"), lwd = c(2.4, 2), lty = c(1, 2), bty = "n")
fs <- pr$nav_str[nrow(pr)]; fb <- pr$nav_bm[nrow(pr)]
mtext(sprintf("최종 누적: 전략 %.1fx / BM %.1fx  (%s~%s, %d개월)",
              fs, fb, format(min(pr$date), "%Y-%m"), format(max(pr$date), "%Y-%m"), nrow(pr)),
      side = 3, line = 0.2, cex = 0.8, col = "#555555")
dev.off()

# --- Chart 2: annual returns vs BM ---
pr[, yr := format(date, "%Y")]
ann <- pr[, .(str = prod(1 + ret_net) - 1, bm = prod(1 + benchmark_ret) - 1), by = yr]
png(file.path(OUTDIR, "annual_returns.png"), width = 1000, height = 560, res = 110)
par(mar = c(4, 4.2, 3.2, 1))
mat <- rbind(ann$str, ann$bm) * 100
bp <- barplot(mat, beside = TRUE, names.arg = ann$yr, col = c("#1f77b4", "#bbbbbb"),
              border = NA, las = 2, cex.names = 0.7, ylab = "연간수익률 (%)",
              main = "연간수익률: 3-신호합의+보유밴드 vs KOSPI200")
abline(h = 0, col = "#333333")
legend("topright", legend = c("전략", "KOSPI200"), fill = c("#1f77b4", "#bbbbbb"), border = NA, bty = "n")
dev.off()
cat("[charts] equity_curve.png + annual_returns.png saved to", OUTDIR, "\n")
