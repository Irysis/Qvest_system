suppressMessages({library(data.table)})
OUT <- "stage_artifacts/WT_D20260713_006"; CH <- file.path(OUT,"charts"); dir.create(CH,showWarnings=FALSE)
TR <- readRDS(file.path(OUT,"test_results.rds"))$RES
labs <- c("Benford\nFSD","m1\n문장길이","제출\n지연(F3)","스택\n(>=2)")
keys <- c("F1","F2","F3","ST")
lift <- sapply(keys,function(k) TR[[k]]$lift)
lo <- sapply(keys,function(k) TR[[k]]$lift_boot[1]); hi <- sapply(keys,function(k) TR[[k]]$lift_boot[2])
orr <- sapply(keys,function(k) TR[[k]]$or_raw); orc <- sapply(keys,function(k) TR[[k]]$or_ctrl)
pc <- sapply(keys,function(k) TR[[k]]$or_ctrl_p)

# Chart 1: lift bars with ticker-bootstrap CI + base-rate=1 line
png(file.path(CH,"01_lift_bars.png"), width=1000, height=560, res=110)
par(mar=c(4,4.5,3.5,1))
cols <- c("#9aa5b1","#9aa5b1","#c0392b","#e08e0b")
bp <- barplot(lift, names.arg=labs, col=cols, border=NA, ylim=c(0,max(hi,2.7)*1.05),
  ylab="Lift  =  P(사건|최악10%) / 기저율", main="포렌식 feature 최악 10분위의 12개월 악재사건 Lift (기저율=1.0)")
arrows(bp, lo, bp, hi, angle=90, code=3, length=0.06, lwd=2, col="#2c3e50")
abline(h=1, lty=2, lwd=2, col="#2c3e50")
text(bp, hi+0.08, sprintf("%.2fx", lift), font=2, cex=0.95)
text(bp, 0.12, sprintf("사건율\n%.1f%%", sapply(keys,function(k)TR[[k]]$evr1)*100), cex=0.7, col="white")
legend("topleft", legend=c("점추정 lift","티커-클러스터 부트스트랩 95% CI","기저율(1.0)"),
  pch=c(15,NA,NA), lty=c(NA,1,2), col=c("#c0392b","#2c3e50","#2c3e50"), bty="n", cex=0.85)
mtext("CI 하단이 1.0 아래로 내려가면 유의 아님. delay만 점추정 2.07배이나 클러스터 CI가 1을 포함(검정력 한계)", side=1, line=2.6, cex=0.72, col="#555")
dev.off()

# Chart 2: control before/after (raw OR vs controlled OR) — size-disguise test
png(file.path(CH,"02_control_before_after.png"), width=1000, height=560, res=110)
par(mar=c(4,4.5,3.5,1))
M <- rbind(orr, orc)
bp2 <- barplot(M, beside=TRUE, names.arg=labs, col=c("#95a5a6","#2980b9"), border=NA,
  ylim=c(0,max(M)*1.15), ylab="Odds Ratio (사건 승산비)",
  main="Size/tier/유동성 통제 전 vs 후 OR — '크기 위장' 검정")
abline(h=1, lty=2, lwd=2, col="#2c3e50")
for(j in 1:4){ text(bp2[1,j], orr[j]+0.06, sprintf("%.2f",orr[j]), cex=0.8)
  text(bp2[2,j], orc[j]+0.06, sprintf("%.2f",orc[j]), cex=0.8, font=2) }
text(bp2[2,3], orc[3]-0.25, sprintf("p=%.3f",pc[3]), cex=0.8, col="white", font=2)
legend("topright", legend=c("통제 전 (raw OR)","통제 후 (controlled OR)","OR=1"),
  pch=c(15,15,NA), lty=c(NA,NA,2), col=c("#95a5a6","#2980b9","#2c3e50"), bty="n", cex=0.85)
mtext("delay: 2.18->2.06 (거의 안 줄어듦) = 소형주 위장 아님. 통제 후에도 승산 2배 유지, 단 p=0.075로 사전등록 문턱 미달", side=1, line=2.6, cex=0.72, col="#555")
dev.off()

# Chart 3: delay event-type decomposition (why union dilutes)
png(file.path(CH,"03_delay_eventtype.png"), width=1000, height=560, res=110)
par(mar=c(4,4.5,3.5,1))
et <- c("상폐\nDelisting","관리종목\nAdminStock","불성실공시\nUnfaithful","거래정지(단기)\nLongHalt","합집합\nUNION")
etl <- c(6.38,4.24,3.82,1.80,2.07)
etc <- c("#c0392b","#c0392b","#c0392b","#95a5a6","#e08e0b")
bp3 <- barplot(etl, names.arg=et, col=etc, border=NA, ylim=c(0,7),
  ylab="delay 최악10% Lift", main="제출지연 신호의 사건유형별 Lift — 합집합이 진짜 신호를 희석")
abline(h=1, lty=2, lwd=2, col="#2c3e50")
text(bp3, etl+0.2, sprintf("%.1fx",etl), font=2, cex=0.95)
mtext("심각사건(상폐6.4x·관리4.2x·불성실3.8x)엔 강함. 기저 큰 단기 거래정지(1.8x)가 합집합을 2.07로 끌어내림 -> 다음 라운드=심각사건 한정 재과녁", side=1, line=2.6, cex=0.72, col="#555")
dev.off()
cat(normalizePath(file.path(CH,c("01_lift_bars.png","02_control_before_after.png","03_delay_eventtype.png"))), sep="\n")
