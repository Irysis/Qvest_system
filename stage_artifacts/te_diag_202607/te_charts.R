## TE 진단 차트 2종 (텔레그램 원칙 9). 시각화 전용 — 수치는 계약/실측 산출값.
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({library(data.table)}))
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/te_diag_202607")
d <- fread(file.path(OUT, "merged_series.csv")); d[, date := as.Date(date)]
setorder(d, date)
a <- d$active_rds; N <- nrow(d)
PRED <- 0.18984  # full-sample 상수 예측 (contract TE, book_state incumbent)
ALERT <- 1.5 * PRED
col_str <- "#1f77b4"; col_bm <- "#888888"; col_neg <- "#d62728"; col_ewma <- "#ff7f0e"; col_pos <- "#2ca02c"

## rolling-12m 실현 TE + EWMA97 예측 시계열
rte <- rep(NA_real_, N)
for (t in 12:N) rte[t] <- sd(a[(t-11):t]) * sqrt(12)
ew <- rep(NA_real_, N); v <- var(a[1:12]); lam <- 0.97
for (t in 13:N) { v <- lam*v + (1-lam)*a[t-1]^2; ew[t] <- sqrt(v)*sqrt(12) }

## --- Chart 1: 롤링 실현 TE vs 예측 ---
png(file.path(OUT, "chart1_te_rolling.png"), width = 1040, height = 560, res = 110)
par(mar = c(4, 4.6, 3.4, 1))
sub <- d$date >= as.Date("2016-01-01")  # 최근 10년 가독
yl <- c(0, max(rte[sub], na.rm=TRUE)*1.05)
plot(d$date[sub], rte[sub], type="l", lwd=2.4, col=col_str, ylim=yl, xlab="", ylab="연율 추적오차 (TE)",
     main="라이브 북 TE: 롤링12M 실현 vs 예측(full-sample 상수)")
lines(d$date[sub], ew[sub], lwd=1.8, col=col_ewma, lty=1)
abline(h=PRED, col=col_bm, lwd=2, lty=2)
abline(h=ALERT, col=col_neg, lwd=1.6, lty=3)
## trailing-21m 실현 강조점
tr21 <- sd(tail(a,21))*sqrt(12)
points(max(d$date), tr21, pch=19, col=col_neg, cex=1.3)
text(max(d$date), tr21, sprintf(" 실현21M %.3f", tr21), pos=2, col=col_neg, cex=0.85)
legend("topleft", bty="n", cex=0.85, lwd=c(2.4,1.8,2,1.6), lty=c(1,1,2,3),
       col=c(col_str,col_ewma,col_bm,col_neg),
       legend=c("롤링12M 실현 TE","EWMA(λ0.97) 예측","예측=full-sample 0.190","1.5x 경보선 0.285"))
dev.off()

## --- Chart 2: trailing-21m active 분산 성분분해 (구조축, 가법 정확) ---
dec <- fread(file.path(OUT, "decomp_sel_vs_overlay.csv"))
r21 <- dec[window=="trail21"]
shares <- c(Selection = r21$var_share_sel, `Overlay 자체분산` = r21$var_share_ovl,
            `Sel×Overlay 공분산(2cov)` = r21$var_share_2cov)
shares <- shares * 100
png(file.path(OUT, "chart2_variance_decomp.png"), width = 1040, height = 540, res = 110)
par(mar = c(5.4, 12.5, 3.4, 3))
cols <- c(col_str, col_ewma, col_neg)
bp <- barplot(rev(shares), horiz=TRUE, las=1, col=rev(cols), border=NA, xlim=c(0, 82),
              xlab="", main="TE 급등 성분분해 — 구조축 (trailing-21M active 분산 기여, 가법·정확)")
text(rev(shares)+2, bp, sprintf("%.0f%%", rev(shares)), xpd=NA, cex=0.95, pos=4)
mtext("active 분산 기여 (%)", side=1, line=2.4, cex=0.85)
mtext("전체 대비 변동성 3.07x · Selection(base가 melt-up BM 못따라감) 70% + Overlay 노출스위칭 계열 30%",
      side=1, line=3.9, cex=0.72, col="#555555")
dev.off()

cat("charts done:\n")
cat(file.path(OUT, "chart1_te_rolling.png"), "\n")
cat(file.path(OUT, "chart2_variance_decomp.png"), "\n")
