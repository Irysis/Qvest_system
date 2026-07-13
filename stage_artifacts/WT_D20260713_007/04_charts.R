suppressMessages({library(data.table)})
OUT <- "stage_artifacts/WT_D20260713_007"; CH <- file.path(OUT,"charts"); dir.create(CH,showWarnings=FALSE)
TR <- readRDS(file.path(OUT,"test_results.rds"))
S  <- readRDS(file.path(OUT,"target.rds"))
rh <- TR$RES$hardened; sp <- TR$SPL$hardened; hz <- TR$HZ

# Chart 1: severity vs union lift + per-type + ticker-cluster CI (the concentration story)
png(file.path(CH,"01_severity_lift.png"), width=1040, height=580, res=110)
par(mar=c(4.2,4.6,3.6,1))
labs <- c("R22 합집합\n(단기정지 포함)","R23 심각사건\n합집합","상폐\nDelisting","관리종목\nAdminStock","불성실공시\nUnfaithful")
vals <- c(2.07, rh$lift, 6.38, 4.24, 3.82)
cols <- c("#95a5a6","#c0392b","#e67e22","#e67e22","#e67e22")
bp <- barplot(vals, names.arg=labs, col=cols, border=NA, ylim=c(0,7.2),
  ylab="제출지연 최악10% Lift (기저율=1.0)",
  main="심각사건 한정 재과녁: 합집합 Lift 2.07 -> 3.74 (단기정지 희석 제거)")
# ticker-bootstrap CI on R23 union bar
arrows(bp[2], rh$lift_boot[1], bp[2], rh$lift_boot[2], angle=90, code=3, length=0.07, lwd=2.5, col="#2c3e50")
abline(h=1, lty=2, lwd=2, col="#2c3e50")
text(bp, vals+0.22, sprintf("%.2fx", vals), font=2, cex=0.95)
text(bp[2], rh$lift_boot[2]+0.25, sprintf("티커-부트 95%% CI\n[%.2f, %.2f]", rh$lift_boot[1], rh$lift_boot[2]), cex=0.72, col="#c0392b")
mtext("점추정 3.74배는 예측대로 집중. 그러나 티커-클러스터 부트 CI 하단 0.95<1 -> 소수 종목 의존(검정력 벽 잔존)", side=1, line=2.7, cex=0.72, col="#555")
dev.off()

# Chart 2: controlled OR forest — raw vs controlled vs post-2016, + concentration annotation
png(file.path(CH,"02_controlled_or.png"), width=1040, height=580, res=110)
par(mar=c(4.2,10,3.6,2))
rows <- c("통제 후 OR\n(full-sample, PRIMARY)","통제 전 OR (raw)","통제 후 OR\n(post-2016)")
est <- c(rh$or_ctrl, rh$or_raw, sp$post2016$or_ctrl)
lo  <- c(rh$or_ctrl_ci[1], NA, NA); hi <- c(rh$or_ctrl_ci[2], NA, NA)
pv  <- c(rh$or_ctrl_p, NA, sp$post2016$p)
y <- rev(seq_along(rows))
plot(NA, xlim=c(0.5, 10), ylim=c(0.5, length(rows)+0.5), xlab="Odds Ratio (사건 승산비, 로그축)", ylab="", yaxt="n", log="x",
  main="심각사건 예측: 통제 후 승산비 (사건-보유 클러스터 6개 = 추론 취약)")
axis(2, at=y, labels=rows, las=1, cex.axis=0.82)
abline(v=1, lty=2, lwd=2, col="#2c3e50")
points(est, y, pch=19, cex=1.6, col=c("#c0392b","#95a5a6","#2980b9"))
for(i in 1) arrows(lo[i], y[i], hi[i], y[i], angle=90, code=3, length=0.06, lwd=2.5, col="#c0392b")
for(i in seq_along(rows)){
  lbl <- sprintf("OR=%.2f", est[i]); if(!is.na(pv[i])) lbl <- sprintf("%s  p=%.3f", lbl, pv[i])
  text(est[i], y[i]+0.28, lbl, cex=0.8, font=2) }
mtext("통제 전 4.08 -> 후 3.43 (거의 안 줄어듦=크기위장 아님). 명목 p=0.011<0.05 통과하나, 47건 사건이 단 6개 종목", side=1, line=2.7, cex=0.72, col="#555")
dev.off()

# Chart 3: fragility — event concentration by ticker + leave-one-out kill
png(file.path(CH,"03_fragility.png"), width=1040, height=580, res=110)
par(mar=c(4.2,4.6,3.6,1))
tks <- c("A016790","A001570","A290510","A036490","A084990","A001440")
ev  <- c(12,11,11,7,5,1)
killed <- c(TRUE,TRUE,TRUE,FALSE,FALSE,FALSE)  # LOO pushes p>=0.05
colv <- ifelse(killed, "#c0392b", "#e67e22")
bp <- barplot(ev, names.arg=tks, col=colv, border=NA, ylim=c(0,14), las=2, cex.names=0.8,
  ylab="worst-decile 사건 관측수 (월단위)", main="47건 '사건'의 실체: 단 6개 late-filer 회사-에피소드 (12개월 중복계상)")
text(bp, ev+0.4, ev, font=2, cex=0.9)
legend("topright", legend=c("이 종목 제거 시 p>=0.05 (유의 붕괴)","제거해도 유의 유지"),
  pch=15, col=c("#c0392b","#e67e22"), bty="n", cex=0.82)
mtext("12개월 hold로 한 늦은-제출 에피소드가 최대 12개월 반복 -> 실질 독립 에피소드 ~6개. 3개 종목 각각이 유의성을 좌우", side=1, line=2.6, cex=0.72, col="#555")
dev.off()

# Chart 4: label-hardening — flag onset vs actual designation date gap
png(file.path(CH,"04_label_hardening.png"), width=1040, height=580, res=110)
par(mar=c(4.2,4.6,3.6,1))
au <- S$au; gm <- au[match_type=="hardened", gap_m]
h <- hist(gm, breaks=seq(min(gm)-0.5, max(gm)+0.5, by=1), plot=FALSE)
bp <- barplot(h$counts, names.arg=h$mids, col=ifelse(h$mids<0,"#c0392b",ifelse(h$mids==0,"#2ca02c","#95a5a6")),
  border=NA, ylab="교차매칭 사건 수", xlab="플래그 onset - 실제 지정 공시월 (개월)",
  main="라벨 PIT 경화: RAWDATA 플래그 onset vs 실제 지정 공시일 괴리")
mtext(sprintf("동월 정확 매칭 %.0f%%  |  플래그 선행(look-ahead 위험) %.1f%%  |  중앙값 %.0f개월 -> 백데이팅 미래참조 없음 (교차 %d/%d)",
  mean(gm==0)*100, mean(gm<0)*100, median(gm), sum(au$match_type=="hardened"), sum(au$covered)),
  side=1, line=2.7, cex=0.7, col="#555")
dev.off()

cat(normalizePath(file.path(CH,c("01_severity_lift.png","02_controlled_or.png","03_fragility.png","04_label_hardening.png"))), sep="\n")
