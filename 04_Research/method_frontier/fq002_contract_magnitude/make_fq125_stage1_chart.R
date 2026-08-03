# make_fq125_stage1_chart.R — WT-D20260803_008 보고 차트
#  패널1: 월별 rank-IC 79개월 (신규 55 / 파일럿 24 구분) + 합산 평균
#  패널2: 사전관측(t-1) mega-cap 주도 국면별 IC 분포 + 순열 귀무분포
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
J  <- fromJSON(file.path(OUTD, "fq125_stage1_results.json"), simplifyVector = TRUE)
RR <- fromJSON(file.path(OUTD, "fq125_stage1_regime_robust.json"), simplifyVector = TRUE)

ic <- as.data.table(J$ic_series); ic[, Date := as.Date(Date)]
Rg <- as.data.table(read_parquet(file.path(OUTD, "gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "gridx_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
ms <- local({
  X <- merge(Rg, MEM[, .(Date, Ticker, Size)], by = c("Date", "Ticker"))
  X <- X[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
  X[, rk := frank(-Size, ties.method = "first"), by = Date]
  Y <- X[, .(mega_spread = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by = Date][order(Date)]
  Y[, ms_lag1 := shift(mega_spread, 1)]; Y
})
ic <- merge(ic, ms, by = "Date")
ic[, era := fifelse(Date >= as.Date("2024-07-01"), "pilot", "new")]

png(file.path(OUTD, "fq125_stage1_chart.png"), width = 1180, height = 820, res = 110)
par(mfrow = c(2, 1), mar = c(3.6, 4.2, 3.0, 1), family = "sans")

cols <- ifelse(ic$ic >= 0, "#3b7dd8", "#d8663b")
bp <- barplot(ic$ic, names.arg = ifelse(seq_len(nrow(ic)) %% 3 == 1, format(ic$Date, "%y-%m"), ""),
              las = 2, cex.names = 0.62, col = cols, border = NA,
              main = sprintf("월별 rank-IC 79개월 (계약금액 12M 누적 / 시가총액)  평균 %+.4f  t_NW(lag3) %+.3f  |  신규 55M 평균 %+.4f  파일럿 24M %+.4f",
                             J$gate$combined$mean_ic, J$gate$combined$t_nw,
                             J$gate$new_segment$mean_ic, J$gate$pilot_segment$mean_ic),
              cex.main = 0.72, ylab = "Spearman rank-IC")
abline(h = 0); abline(h = J$gate$combined$mean_ic, lty = 2, col = "#3b7dd8")
xsplit <- bp[which(ic$era == "pilot")[1]] - 0.5
abline(v = xsplit, lty = 3, lwd = 2, col = "#666666")
text(xsplit, par("usr")[4] * 0.92, " 파일럿 승계구간 →", cex = 0.7, adj = 0, col = "#444444")
legend("bottomleft", legend = "게이트: t_NW>=1.5 & 신규 평균IC>0 → PASS", bty = "n", cex = 0.72)

# 패널2: 국면별 IC (사전관측 t-1 상태) + 순열 귀무분포
par(mar = c(3.8, 9.5, 3.0, 1))
brd <- ic[is.finite(ms_lag1) & ms_lag1 <= 0, ic]; mgd <- ic[is.finite(ms_lag1) & ms_lag1 > 0, ic]
bx <- boxplot(list(`대형주 주도 (t-1)` = mgd, `저변 주도 (t-1)` = brd), col = c("#c9c9c9", "#3b7dd8"),
              horizontal = TRUE, las = 1, cex.axis = 0.8,
              main = sprintf("사전관측(t-1) 국면별 rank-IC — 저변주도 %+.4f (n=%d) vs 대형주주도 %+.4f (n=%d) | 격차 %+.4f, 라벨 순열 p=%.4f",
                             mean(brd), length(brd), mean(mgd), length(mgd),
                             RR$observed$gap, RR$R1_permutation$p_one_sided),
              cex.main = 0.72, xlab = "Spearman rank-IC")
abline(v = 0, lty = 2)
points(c(mean(mgd), mean(brd)), c(1, 2), pch = 18, cex = 1.6, col = "#d8663b")
legend("topright", legend = c("◆ 구간 평균",
                              sprintf("조건부 canonical PORT_t = %+.2f (n=%d, 사후선택)",
                                      RR$R4_consumption$broad_led_only$portfolio_alpha_t_nw_lag3,
                                      RR$R4_consumption$broad_led_only$n_months),
                              sprintf("무조건 canonical PORT_t = %+.2f (전이 벽)",
                                      RR$R4_consumption$unconditional$portfolio_alpha_t_nw_lag3)),
       bty = "n", cex = 0.72)
dev.off()
cat("[chart] →", file.path(OUTD, "fq125_stage1_chart.png"), "\n")
