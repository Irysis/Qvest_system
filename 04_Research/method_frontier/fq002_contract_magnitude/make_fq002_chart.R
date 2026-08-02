# make_fq002_chart.R — FQ-002 파일럿 보고 차트 (WT-D20260802_018)
#   패널1: 월별 rank-IC (A_revenue primary) + lag1 대비
#   패널2: 커버리지(신호보유 종목수) + 정정 A/B mean IC 주석
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
J <- fromJSON(file.path(OUTD, "pilot_results.json"), simplifyVector = TRUE)

icA <- as.data.table(J$ic_series$A_revenue);  icA[, Date := as.Date(Date)]
icL <- as.data.table(J$ic_series$A_revenue_lag1); icL[, Date := as.Date(Date)]
cov <- as.data.table(J$coverage$monthly); cov[, Date := as.Date(Date)]

png(file.path(OUTD, "fq002_pilot_chart.png"), width = 1100, height = 780, res = 110)
par(mfrow = c(2, 1), mar = c(3.2, 4, 2.6, 1), family = "sans")

bp <- barplot(icA$ic, names.arg = format(icA$Date, "%y-%m"), las = 2, cex.names = 0.7,
              col = ifelse(icA$ic >= 0, "#3b7dd8", "#d8663b"),
              main = sprintf("FQ-002 계약수주 magnitude 파일럿 — 월별 rank-IC (계약금액/최근매출액, 12M 누적)  meanIC=%+.3f t=%+.2f (NW %+.2f)",
                             J$ic$A_revenue$mean_ic, J$ic$A_revenue$t_plain, J$ic$A_revenue$t_nw),
              cex.main = 0.83, ylab = "Spearman rank-IC")
abline(h = 0)
abline(h = J$ic$A_revenue$mean_ic, lty = 2, col = "#3b7dd8")
lines(bp, icL$ic[match(icA$Date, icL$Date)], type = "p", pch = 4, col = "#555555")
legend("topleft", legend = c("월별 IC", "평균 IC", "lag1 스트레스 IC(×)"),
       fill = c("#3b7dd8", NA, NA), border = NA, lty = c(NA, 2, NA), pch = c(NA, NA, 4),
       col = c(NA, "#3b7dd8", "#555555"), bty = "n", cex = 0.75)

plot(cov$Date, cov$n_cov, type = "h", lwd = 5, col = "#7aa87a", ylim = c(0, max(cov$n_cov) * 1.25),
     main = sprintf("월별 신호보유 종목수 (평균 %.0f종, ≥20종 월비율 %.0f%%) | 정정 A/B: mean(B−A)=%+.4f paired_t=%+.2f",
                    J$coverage$mean_names, 100 * J$coverage$months_ge20,
                    J$correction_ab$mean_diff_B_minus_A, J$correction_ab$t_paired),
     cex.main = 0.83, ylab = "신호보유 종목수", xlab = "")
abline(h = 20, lty = 3)
dev.off()
cat("[chart] →", file.path(OUTD, "fq002_pilot_chart.png"), "\n")
