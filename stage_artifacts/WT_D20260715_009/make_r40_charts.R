## make_r40_charts.R — R40 텔레그램 차트 (원칙 9 실측 그래프 의무)
## (A) 검열 census: ON→off outcome 분해 + CENSORED 소분류 (검열 극소 + terminal-truncation 분리)
## (B) 다중월 forward 위험궤적 (h=0..3): tail + paired-t (protection 단기·지연 재악화 directional)
## (C) worst-case 대입: EXIT tail 시나리오별 vs OFF baseline (검열편향 immaterial)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260715_009"
res <- fromJSON(file.path(OUT,"r40_results.json"))
o   <- readRDS(file.path(OUT,"_r40_objects.rds"))

col_off<-"#9aa0a6"; col_ok<-"#188038"; col_warn<-"#c5a900"; col_bad<-"#d93025"; col_blue<-"#1a73e8"

## ── Chart A: 검열 census (MID) ──────────────────────────────────────────────────
cen <- res$P2_census$mid
oc  <- unlist(cen$outcome); oc <- oc[c("SUSTAIN","EXIT_obs","cov_lost","CENSORED")]; oc[is.na(oc)]<-0
trunc_mid <- res$right_truncated$mid
png(file.path(OUT,"chart_A_censoring_census.png"), width=1040, height=470, res=110)
par(mfrow=c(1,2), mar=c(5,4.4,3.4,1), family="sans")
## 좌: ON→off outcome 분해
cols_oc <- c(SUSTAIN=col_ok, EXIT_obs=col_blue, cov_lost=col_warn, CENSORED=col_bad)
bp <- barplot(oc, col=cols_oc[names(oc)], border=NA, ylim=c(0,max(oc)*1.18),
   main="A1. flag-ON 다음달 outcome (MID, n=959)", ylab="name-months", cex.names=0.86,
   names.arg=c("SUSTAIN\n(유지)","EXIT_obs\n(잔존청산)","cov_lost\n(커버상실)","CENSORED\n(패널이탈)"))
text(bp, oc+max(oc)*0.03, sprintf("%d\n(%.1f%%)", oc, 100*oc/sum(oc)), cex=0.72, col="gray20")
mtext(sprintf("검열(CENSORED)=%d건(0.2%%) · terminal-truncation %d건 분리제외", oc["CENSORED"], trunc_mid), side=1, line=3.4, cex=0.66, col="gray30")
## 우: CENSORED 소분류 + 진성폐지 0
ct <- unlist(cen$cens_type); if(is.null(ct)||length(ct)==0) ct <- c(none=0)
bp2 <- barplot(ct, col=col_bad, border=NA, ylim=c(0,max(ct,1)*1.4),
   main="A2. 검열 사유 분해 (MID)", ylab="건수", cex.names=0.82,
   names.arg=names(ct))
text(bp2, ct+max(ct,1)*0.06, sprintf("%d", ct), cex=0.8, col="gray20", font=2)
mtext("★진성폐지(delisted_hard)=0 · 21년 패널 전체 delisting 0건", side=1, line=2.6, cex=0.68, col=col_ok)
dev.off()

## ── Chart B: 다중월 forward 위험궤적 (MID EXIT cohort) ──────────────────────────
tj <- res$P1_multimonth
hs <- c("h0","h1","h2","h3")
tail_v <- sapply(hs, function(k) tj[[k]]$tail)*100
pt_v   <- sapply(hs, function(k) tj[[k]]$paired_vs_off_t)
off_tail <- res$P2_worstcase$off_baseline$tail*100
png(file.path(OUT,"chart_B_multimonth_trajectory.png"), width=1040, height=470, res=110)
par(mfrow=c(1,2), mar=c(4.6,4.4,3.4,1), family="sans")
## 좌: tail(<-15%) 궤적 vs OFF
bp <- barplot(tail_v, names.arg=c("h=0\n(청산월)","h=1","h=2","h=3"), col=ifelse(tail_v<=off_tail,col_ok,col_bad), border=NA,
   ylim=c(0,max(tail_v,off_tail)*1.2), main="B1. 청산후 tail위험 궤적 (MID, <-15% 빈도)", ylab="tail hit %", cex.names=0.86)
abline(h=off_tail, col=col_off, lty=2, lwd=2); text(par("usr")[2], off_tail+0.4, sprintf("OFF=%.1f%%",off_tail), col="gray30", cex=0.72, adj=1)
text(bp, tail_v+0.4, sprintf("%.1f", tail_v), cex=0.78, col="gray20", font=2)
mtext("h=0-1 protection(OFF↓), h2-3 baseline 복귀 = protection 단기(1개월)", side=1, line=2.7, cex=0.66, col="gray30")
## 우: paired vs OFF NW-t 궤적
bp2 <- barplot(pt_v, names.arg=c("h=0","h=1","h=2","h=3"), col=ifelse(pt_v>=0,col_ok,col_warn), border=NA,
   ylim=c(min(pt_v)-0.4, max(pt_v)+0.5), main="B2. 수익 premium 궤적 vs OFF (NW-t)", ylab="NW lag-3 t", cex.names=0.86)
abline(h=0,col="gray50"); abline(h=c(-2,2), col=col_bad, lty=3)
text(bp2, pt_v+ifelse(pt_v>=0,0.12,-0.16), sprintf("%+.2f",pt_v), cex=0.78, col="gray20", font=2)
mtext("+1.89→-1.65 감쇠 but |t|<2 전구간 = 지연 재악화 directional(비유의)", side=1, line=2.7, cex=0.66, col="gray30")
dev.off()

## ── Chart C: worst-case 대입 (MID EXIT tail vs OFF) ─────────────────────────────
sc <- res$P2_worstcase$scenarios
sc_names <- c("actual_only","wc_m20","wc_m30","wc_m50","wc_m80","wipeout")
tail_sc <- sapply(sc_names, function(k) sc[[k]]$tail)*100
r38_tail <- res$P2_worstcase$r38_exit_obs$tail*100
png(file.path(OUT,"chart_C_worstcase.png"), width=1000, height=470, res=110)
par(mar=c(5.5,4.6,3.6,1), family="sans")
bp <- barplot(tail_sc, names.arg=c("실측만","WC -20%","WC -30%","WC -50%","WC -80%","wipeout\n-100%"),
   col=ifelse(tail_sc<=off_tail,col_ok,col_bad), border=NA, ylim=c(0,max(tail_sc,off_tail)*1.25),
   main="C. 검열종목 worst-case 대입 후 EXIT tail (MID)", ylab="EXIT tail hit % (<-15%)", cex.names=0.8)
abline(h=off_tail, col=col_off, lty=2, lwd=2); text(par("usr")[2], off_tail+0.35, sprintf("OFF baseline=%.1f%%",off_tail), col="gray30", cex=0.74, adj=1)
abline(h=r38_tail, col=col_blue, lty=3, lwd=2); text(par("usr")[1]+0.2, r38_tail-0.5, sprintf("R38 관측EXIT=%.1f%%",r38_tail), col=col_blue, cex=0.72, adj=0)
text(bp, tail_sc+0.35, sprintf("%.1f", tail_sc), cex=0.82, col="gray20", font=2)
mtext("검열종목 2건뿐 → wipeout(-100%)까지 대입해도 EXIT tail < OFF = 검열편향 immaterial", side=1, line=3.8, cex=0.72, col=col_ok, font=2)
dev.off()

cat("[charts] saved: chart_A_censoring_census.png, chart_B_multimonth_trajectory.png, chart_C_worstcase.png\n")
