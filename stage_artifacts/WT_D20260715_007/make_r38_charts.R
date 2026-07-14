## make_r38_charts.R — R38 텔레그램 차트 (원칙 9 실측 그래프 의무)
## (A) 진입 vs 청산 forward 위험 (MID tercile, state별 raw수익·excess·downside·tail)
## (B) hold-duration 감쇠 (MID, dur 버킷별 forward 수익/excess + vs-OFF NW-t)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260715_007"
res <- fromJSON(file.path(OUT,"r38_results.json"))
o   <- readRDS(file.path(OUT,"_r38_objects.rds"))
SS  <- as.data.table(o$SS_mid)     # state summary MID
DS  <- as.data.table(o$DS_mid)     # duration summary MID
SS[, ord := match(state, c("OFF","ENTRY","SUSTAIN","EXIT"))]; setorder(SS, ord)
DS[, ord := match(dur_bkt, c("d1","d2_3","d4plus"))]; setorder(DS, ord)

col_off<-"#9aa0a6"; col_entry<-"#1a73e8"; col_sust<-"#188038"; col_exit<-"#d93025"
scols <- c(OFF=col_off, ENTRY=col_entry, SUSTAIN=col_sust, EXIT=col_exit)

## ── Chart A: 진입 vs 청산 forward 위험 (2 패널) ─────────────────────────────────
png(file.path(OUT,"chart_A_entry_vs_exit.png"), width=1000, height=460, res=110)
par(mfrow=c(1,2), mar=c(4,4.2,3.2,1), family="sans")
## 좌: forward 수익 (raw + excess)
b <- rbind(SS$mean_fwd, SS$mean_exc)*100
bp <- barplot(b, beside=TRUE, names.arg=SS$state, col=rep(scols[SS$state], each=2),
   density=c(-1,25), border=NA, ylim=c(min(b,0)-0.3, max(b)+0.9),
   main="A1. 상태별 익월 수익 (MID tercile)", ylab="월수익 %", cex.names=0.95)
abline(h=0, col="gray50")
legend("topright", legend=c("raw 총수익","excess(vs cap-w BM)"), fill="gray40", density=c(-1,25), border=NA, bty="n", cex=0.8)
text(colMeans(bp), b+ifelse(b>=0,0.12,-0.2), sprintf("%+.2f", b), cex=0.72, col="gray20")
## 우: 하방위험 (downside 평균손실 + tail<-15% 빈도)
par(new=FALSE)
ds <- SS$downside*100; th <- SS$tail_hit*100
bp2 <- barplot(-ds, names.arg=SS$state, col=scols[SS$state], border=NA,
   ylim=c(0, max(-ds)*1.25), main="A2. 하방위험 (MID) — 낮을수록 안전", ylab="음월 평균손실 % (절대값)", cex.names=0.95)
text(bp2, -ds+0.25, sprintf("dn %.1f", -ds), cex=0.74, col="white")
text(bp2, -ds*0.45, sprintf("tail %.1f%%", th), cex=0.72, col="white", font=2)
mtext("SUSTAIN/EXIT 하방·tail이 OFF보다 낮음 = 청산 후에도 위험 protection 점착", side=1, line=2.6, cex=0.68, col="gray30")
dev.off()

## ── Chart B: hold-duration 감쇠 (2 패널) ───────────────────────────────────────
mv <- res$P2_duration$mid_vs_off   # list d1/d2_3/d4plus {gap_ann, gap_t, n_months}
dur_lab <- c(d1="dur=1 (진입)", d2_3="dur=2-3", d4plus="dur=4+ (지속)")
png(file.path(OUT,"chart_B_duration.png"), width=1000, height=460, res=110)
par(mfrow=c(1,2), mar=c(4.5,4.2,3.2,1), family="sans")
## 좌: dur별 raw수익 vs excess
b2 <- rbind(DS$mean_fwd, DS$mean_exc)*100
bp3 <- barplot(b2, beside=TRUE, names.arg=dur_lab[DS$dur_bkt], col=c("#5f6368","#188038"),
   ylim=c(min(b2,0)-0.2, max(b2)+0.8), main="B1. hold-duration별 익월 수익 (MID)", ylab="월수익 %", cex.names=0.82)
abline(h=0,col="gray50")
legend("topright", legend=c("raw 총수익","excess"), fill=c("#5f6368","#188038"), border=NA, bty="n", cex=0.8)
text(colMeans(bp3), b2+0.12, sprintf("%+.2f", b2), cex=0.72, col="gray20")
mtext("raw는 신선할수록↑(약한 감쇠), excess는 지속할수록↑", side=1, line=3.1, cex=0.68, col="gray30")
## 우: dur별 vs-OFF NW-t (안전 신호 신뢰도)
tt <- sapply(c("d1","d2_3","d4plus"), function(k) mv[[k]]$gap_t)
bp4 <- barplot(tt, names.arg=dur_lab[c("d1","d2_3","d4plus")], col=ifelse(tt>=2,"#188038","#c5a900"), border=NA,
   ylim=c(0, max(tt)*1.25+0.3), main="B2. SAFE 신뢰도 vs OFF (NW-t)", ylab="NW lag-3 t", cex.names=0.82)
abline(h=2, col="#d93025", lty=2); text(par("usr")[1]+0.3, 2.1, "t=2", col="#d93025", cex=0.7, adj=0)
text(bp4, tt+0.1, sprintf("t=%.2f", tt), cex=0.78, col="gray20", font=2)
mtext("지속 flag이 더 신뢰(표본↑·안정) — 신선도 절벽 없음", side=1, line=3.1, cex=0.68, col="gray30")
dev.off()

cat("[charts] saved:\n  ", file.path(OUT,"chart_A_entry_vs_exit.png"), "\n  ", file.path(OUT,"chart_B_duration.png"), "\n")
