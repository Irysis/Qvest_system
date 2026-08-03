# =============================================================================
# finalize_parity_charts.R — WT-D20260803_006
#   (1) WT-005 창별 양수비율 parity (교차 라운드 정합 — 내 era 정의가 같은 대상인가)
#   (2) 차트 3종
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006F] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean

R6 <- readRDS(file.path(OUT, "era_results.rds"))
CP <- readRDS(file.path(SRC, "canonical_pool.rds")); RES <- CP$res
DATES <- R6$DATES; POOL <- R6$POOL
A <- matrix(NA_real_, nrow = length(DATES), ncol = length(RES),
            dimnames = list(as.character(DATES), names(RES)))
for (f in names(RES)) { r <- RES[[f]]; A[as.character(r$date), f] <- r$active }
A <- A[, POOL, drop = FALSE]; NM <- nrow(A)

# ── (1) WT-005 primary 격자(W=60, 비중첩, 표본 끝 정렬) 재현 ────────────────
make_bounds <- function(n, W) { b <- list(); e <- n
  while (e - W + 1L >= 1L) { b[[length(b)+1L]] <- c(e - W + 1L, e); e <- e - W }; rev(b) }
bnd <- make_bounds(NM, 60L)
par_tab <- rbindlist(lapply(bnd, function(ix) {
  sub <- A[ix[1]:ix[2], , drop = FALSE]
  nf <- colSums(is.finite(sub)); ok <- nf >= 24L & nf/nrow(sub) >= 0.90
  tt <- vapply(colnames(sub)[ok], function(f) {
          x <- sub[, f]; .nw_t_mean(x[is.finite(x)], lag = 3L) }, numeric(1))
  mu <- colMeans(sub[, ok, drop = FALSE], na.rm = TRUE)
  data.table(from = DATES[ix[1]], to = DATES[ix[2]], n_factor = sum(ok),
             pos_ratio_PORTt = mean(tt > 0), pos_ratio_meanactive = mean(mu > 0),
             sign_agree = mean((tt > 0) == (mu > 0)))
}))
say("=== WT-005 창별 양수비율 parity (W=60 primary 격자) ===")
print(par_tab)
say("Q-Lead 사전 확인값 0.754 / 0.908 / 0.216 / 0.021 대비 PORT_t 기준: %s",
    paste(sprintf("%.3f", par_tab$pos_ratio_PORTt), collapse = " / "))
say("본 라운드 era 정의(mean-active 부호)와 WT-005 정의(PORT_t 부호) 부호 일치율: %s",
    paste(sprintf("%.3f", par_tab$sign_agree), collapse = " / "))
PARITY_OK <- max(abs(par_tab$pos_ratio_PORTt - par_tab$pos_ratio_meanactive)) < 0.06
say("PARITY: %s (최대 격차 %.4f)", ifelse(PARITY_OK, "PASS", "REVIEW"),
    max(abs(par_tab$pos_ratio_PORTt - par_tab$pos_ratio_meanactive)))

# ── (2) 차트 ────────────────────────────────────────────────────────────────
CH <- file.path(OUT, "charts"); dir.create(CH, showWarnings = FALSE)
P <- R6$Sp$P
E_all <- rep(NA_real_, NM); E_all[match(P$t, seq_len(NM))] <- P$E
Bm <- R6$Bm

png(file.path(CH, "era_timeline.png"), width = 1500, height = 950, res = 130)
par(mfrow = c(2,1), mar = c(3.4, 4.4, 2.6, 1.2))
plot(DATES, Bm, type = "h", col = ifelse(Bm > .5, "#2e7d32", "#c62828"),
     xlab = "", ylab = "월간 breadth B_t", main = "era 공통성분: 월간 breadth 와 forward era 지수 (h=24)")
abline(h = 0.5, lty = 2)
lines(P$Date, P$E, col = "#1565c0", lwd = 2.4)
legend("topright", c("월간 breadth (양수=녹)", "forward 24M era 지수 E"),
       col = c("grey40", "#1565c0"), lwd = c(1, 2.4), bty = "n", cex = .78)
par(mar = c(3.4, 4.4, 2.6, 1.2))
plot(P$Date, P$y, type = "s", col = "#1565c0", lwd = 2.2, ylim = c(-1.6, 1.6),
     yaxt = "n", xlab = "", ylab = "", main = "실제 era 부호 vs 실시간 추정 (RT_CUSUM)")
axis(2, at = c(-1,1), labels = c("팩터 안통함", "팩터 통함"), cex.axis = .8)
lines(P$Date, P$p_rt_cusum * 0.86, type = "s", col = "#ef6c00", lwd = 2.2)
mism <- P$p_rt_cusum != P$y
points(P$Date[mism], rep(-1.42, sum(mism)), pch = 15, col = "#c62828", cex = .5)
legend("bottomleft", c("실제 era", "RT_CUSUM 실시간 추정", "오예측 월"),
       col = c("#1565c0", "#ef6c00", "#c62828"), lwd = c(2.2,2.2,NA),
       pch = c(NA,NA,15), bty = "n", cex = .74)
dev.off()

acc <- R6$Sp$acc; act <- R6$Sp$acc_trans
ord <- c("br_rt","trail12","trail24","trail36","trail60","rt_cusum","peek6","fullcusum","oracle")
lbl <- c("BR_rt(기준선)","trail12","trail24*","trail36","trail60","RT_CUSUM(primary)",
         "INJ_PEEK6(누출)","INJ_FULLCUSUM(누출)","INJ_ORACLE(예지)")
png(file.path(CH, "accuracy_by_arm.png"), width = 1500, height = 880, res = 130)
par(mar = c(7.6, 4.4, 3.0, 1.2))
M <- rbind(acc[ord], act[ord])
cols <- c("#1565c0", "#ef6c00")
bp <- barplot(M, beside = TRUE, names.arg = lbl, las = 2, ylim = c(0, 1.08),
        col = cols, border = NA, ylab = "적중률",
        main = "era 방향 적중률 — 전체 vs era 전환 월 (h=24, n=203 / 전환 81)")
abline(h = 0.5, lty = 2, col = "grey30")
abline(h = R6$Sp$acc[["br_rt"]], lty = 3, col = "#1565c0")
text(colMeans(bp), pmax(M[1,],M[2,]) + 0.05, sprintf("%.2f", acc[ord]), cex = .62, col = "#1565c0")
legend("topleft", c("전체 월", "era 전환 월"), fill = cols, bty = "n", cex = 0.78)
mtext("* trail24 의 전환 적중률 0 은 정의상 항등 — 증거 아님", side = 1, line = 6.2, cex = .62, adj = 0)
dev.off()

png(file.path(CH, "detection_lag.png"), width = 1400, height = 780, res = 130)
LS <- R6$lag_sus
par(mar = c(4.6, 8.6, 3.0, 1.2))
v <- LS$lag_rt_cusum_m; v[is.na(v)] <- 40
bp <- barplot(v, horiz = TRUE, col = ifelse(is.na(LS$lag_rt_cusum_m), "#c62828",
        ifelse(v >= 24, "#ef6c00", "#2e7d32")), border = NA,
        names.arg = format(LS$change_date, "%Y-%m"), las = 1, xlim = c(0, 44),
        xlab = "탐지 지연 (개월)", main = "지속 era 전환 8회 — RT_CUSUM 탐지 지연")
abline(v = 24, lty = 2, col = "grey20")
text(v + 1.2, bp, ifelse(is.na(LS$lag_rt_cusum_m), "미탐지", paste0(v, "m")), cex = .7, adj = 0)
mtext("점선 = 예측 지평 h=24개월 (초과 = 실무상 사전 추정 불가)", side = 3, cex = .66)
dev.off()
say("charts 3종 저장")

saveRDS(list(par_tab = par_tab, parity_ok = PARITY_OK), file.path(OUT, "parity.rds"))
say("DONE")
