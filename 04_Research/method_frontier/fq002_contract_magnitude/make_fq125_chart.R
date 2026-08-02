# make_fq125_chart.R — FQ-125 확정 라운드 보고 차트 (WT-D20260802_023)
#   패널1: 섭동 120 draws t_NW 분포 히스토그램 + q05 + 0선 (판정 시각화)
#   패널2: 월별 rank-IC (A_size primary) + 부기간 평균선
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
J <- fromJSON(file.path(OUTD, "fq125_confirm_results.json"), simplifyVector = TRUE)

DR <- as.data.table(J$perturbation$draws)
icA <- as.data.table(J$ic_series$A_size); icA[, Date := as.Date(Date)]

png(file.path(OUTD, "fq125_confirm_chart.png"), width = 1100, height = 780, res = 110)
par(mfrow = c(2, 1), mar = c(3.4, 4, 2.8, 1), family = "sans")

hist(DR$t_nw, breaks = 24, col = "#3b7dd8", border = "white",
     main = sprintf("FQ-125 섭동 판정 — %d draws t_NW 분포 (멤버십 drop 10%% 60시드 + 스코어 노이즈 60시드)  q05=%+.3f > 0 → 확정",
                    nrow(DR), J$perturbation$q05_t_nw_pooled),
     cex.main = 0.8, xlab = "t_NW(lag3) of monthly rank-IC", ylab = "draws",
     xlim = range(c(0, DR$t_nw)) + c(-0.1, 0.1))
abline(v = 0, lwd = 2)
abline(v = J$perturbation$q05_t_nw_pooled, lty = 2, lwd = 2, col = "#d8663b")
abline(v = J$ic$A_size$t_nw, lty = 3, lwd = 2, col = "#333333")
legend("topleft", legend = c(sprintf("q05 = %+.3f", J$perturbation$q05_t_nw_pooled),
                             sprintf("무섭동 t_NW = %+.3f", J$ic$A_size$t_nw), "0 (판정선)"),
       lty = c(2, 3, 1), lwd = 2, col = c("#d8663b", "#333333", "black"), bty = "n", cex = 0.78)

bp <- barplot(icA$ic, names.arg = format(icA$Date, "%y-%m"), las = 2, cex.names = 0.7,
              col = ifelse(icA$ic >= 0, "#3b7dd8", "#d8663b"),
              main = sprintf("월별 rank-IC (계약금액 12M 누적/시가총액)  meanIC=%+.3f t=%+.2f (NW %+.2f) | 전반12 %+.3f vs 후반12 %+.3f",
                             J$ic$A_size$mean_ic, J$ic$A_size$t_plain, J$ic$A_size$t_nw,
                             J$subperiod_halves$first12$mean_ic, J$subperiod_halves$last12$mean_ic),
              cex.main = 0.78, ylab = "Spearman rank-IC")
abline(h = 0)
abline(h = J$ic$A_size$mean_ic, lty = 2, col = "#3b7dd8")
dev.off()
cat("[chart] →", file.path(OUTD, "fq125_confirm_chart.png"), "\n")
