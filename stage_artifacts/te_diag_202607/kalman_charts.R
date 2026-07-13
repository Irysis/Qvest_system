## Kalman head-to-head 차트 2종 (텔레그램 원칙 9). 시각화 전용 — 수치는 실측 산출값.
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({library(data.table)}))
setDTthreads(1)
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/te_diag_202607/kalman_ext"
ht <- fread(file.path(OUT,"kalman_headtohead_eval.csv"))
cv <- fread(file.path(OUT,"kalman_rolling_curves.csv")); cv[,date:=as.Date(date)]; setorder(cv,date)

## 색: Kalman 강조(파랑/보라), 대조군 회색, ewma97 주황
labmap <- c(kalman_SV="Kalman-SV", kalman_TVbeta="Kalman-TVβ", ewma97="EWMA λ0.97",
            ewma94="EWMA λ0.94", expand_const="상수(현행)", roll36="롤링36", regime_cond="국면조건부")
ht[, lab := labmap[estimator]]
colf <- function(e) ifelse(e=="kalman_SV","#1f77b4", ifelse(e=="kalman_TVbeta","#9467bd",
        ifelse(e=="ewma97","#ff7f0e","#9aa0a6")))

## ---- Chart K1: 추정기 서열 (오경보율 + 분산비 2패널) ----
png(file.path(OUT,"chartK1_estimator_ranking.png"), width=1120, height=640, res=112)
par(mfrow=c(1,2), mar=c(7.5,4.4,3.2,1))
o1 <- order(ht$alert_1p5_rate)
bp1 <- barplot(ht$alert_1p5_rate[o1]*100, col=colf(ht$estimator[o1]), border=NA,
        names.arg=ht$lab[o1], las=2, cex.names=0.82, ylab="1.5x 오경보율 (%)",
        main="① 오경보율 (낮을수록 우수)")
text(bp1, ht$alert_1p5_rate[o1]*100, sprintf("%.1f",ht$alert_1p5_rate[o1]*100), pos=3, cex=0.72, xpd=NA)
o2 <- order(abs(ht$realized_over_pred-1))
bp2 <- barplot(ht$realized_over_pred[o2], col=colf(ht$estimator[o2]), border=NA,
        names.arg=ht$lab[o2], las=2, cex.names=0.82, ylab="실현/예측 분산비 (1=이상)",
        ylim=c(0,max(ht$realized_over_pred)*1.12), main="② 분산비 (1에 근접할수록 우수)")
abline(h=1, col="#d62728", lwd=1.6, lty=2)
text(bp2, ht$realized_over_pred[o2], sprintf("%.3f",ht$realized_over_pred[o2]), pos=3, cex=0.72, xpd=NA)
dev.off()

## ---- Chart K2: 롤링 예측 vs 실현 TE 곡선 (최근 10년) ----
png(file.path(OUT,"chartK2_rolling_pred_vs_realized.png"), width=1120, height=580, res=112)
par(mar=c(4,4.6,3.4,1))
sub <- cv$date >= as.Date("2016-01-01")
yl <- c(0, max(cv$realized_fwd12_TE[sub], cv$pred_ewma97[sub], cv$pred_kSV[sub], na.rm=TRUE)*1.05)
plot(cv$date[sub], cv$realized_fwd12_TE[sub], type="l", lwd=2.6, col="#333333", ylim=yl,
     xlab="", ylab="연율 추적오차 (TE)", main="롤링 예측 TE vs 전향12M 실현 TE (최근 10년)")
lines(cv$date[sub], cv$pred_ewma97[sub],   lwd=1.9, col="#ff7f0e")
lines(cv$date[sub], cv$pred_kSV[sub],      lwd=2.1, col="#1f77b4")
lines(cv$date[sub], cv$pred_kTVbeta[sub],  lwd=1.7, col="#9467bd", lty=1)
abline(h=0.18984, col="#888888", lwd=1.6, lty=2)
legend("topleft", bty="n", cex=0.82, lwd=c(2.6,1.9,2.1,1.7,1.6), lty=c(1,1,1,1,2),
       col=c("#333333","#ff7f0e","#1f77b4","#9467bd","#888888"),
       legend=c("전향12M 실현 TE","EWMA λ0.97 예측","Kalman-SV 예측","Kalman-TVβ 예측","현행 상수 0.190"))
dev.off()
cat("[charts] chartK1_estimator_ranking.png · chartK2_rolling_pred_vs_realized.png →", OUT, "\n")
