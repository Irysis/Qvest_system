# R24 Step 04 — size-tier decomposition (small-cap confound) + mandated charts
suppressMessages({library(data.table)})
setDTthreads(1L)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
OUT <- "stage_artifacts/WT_D20260713_008"; CH <- file.path(OUT,"charts"); dir.create(CH,showWarnings=FALSE)
S  <- readRDS(file.path(OUT,"episode_panel.rds")); TR <- readRDS(file.path(OUT,"test_results.rds"))
ep <- S$Ehard
rf <- TR$RES$hardened; rs <- TR$RES$diag_wd_strict; loo <- TR$loo_summary

# ---- size-tier decomposition (per-fy tercile of log_size): is the extreme tail just micro-caps? ----
ep[, size_tier := cut(frank(log_size)/.N, breaks=c(0,1/3,2/3,1), labels=c("small","mid","large")), by=fy]
tab_all    <- ep[, .N, by=size_tier][order(size_tier)]
tab_strict <- ep[wd_strict==1, .N, by=size_tier][order(size_tier)]
tab_late   <- ep[worst_decile_late==1, .N, by=size_tier][order(size_tier)]
# OR of wd_strict conditional on size within each tier (does effect survive within a tier?)
tier_or <- lapply(c("small","mid","large"), function(t){
  sub <- ep[size_tier==t]; n1<-sub[wd_strict==1,.N]; x1<-sub[wd_strict==1,sum(E)]; base<-mean(sub$E)
  list(tier=t, n=nrow(sub), wd_n=n1, wd_ev=x1, base=base, evr=if(n1>0)x1/n1 else NA,
       lift=if(n1>0 && base>0) (x1/n1)/base else NA)
})
diag <- list(tab_all=tab_all, tab_strict=tab_strict, tab_late=tab_late, tier_or=tier_or)
saveRDS(diag, file.path(OUT,"size_tier_diag.rds"))
cat("[04] size-tier of extreme-tail (wd_strict) episodes:\n"); print(tab_strict)
cat("[04] extreme-tail lift within size tiers:\n")
for(z in tier_or) cat(sprintf("   %-6s n=%d wd_n=%d wd_ev=%d base=%.4f lift=%.2f\n", z$tier,z$n,z$wd_n,z$wd_ev,z$base, z$lift %||% NA))

# ===================== CHART 1: independent event-firm count R23 vs R24 =====================
png(file.path(CH,"01_independent_firms.png"), width=1000, height=560, res=110)
par(mar=c(4.6,4.8,3.8,1))
vals <- c(6, 27, 528)
labs <- c("R23 최악10%\n(K200∪KQ150 월패널)","R24 극단꼬리\n(에피소드·677유니버스)","R24 동결정의\n(임의지각=희석)")
cols <- c("#95a5a6","#c0392b","#d9a441")
bp <- barplot(vals, names.arg=labs, col=cols, border=NA, ylim=c(0,600),
  ylab="독립 late-filer 회사 수", main="독립 에피소드 검정력: 6개(취약) → 27개(LOO-강건, 극단꼬리)")
text(bp, vals+18, c("6개\n(LOO 3/6 치명)","27개\n(LOO 全생존)","528개\n(신호 희석)"), font=2, cex=0.8)
mtext("R23 벽=6개 회사 의존(부트CI 1포함). R24 극단꼬리=27개 독립회사, 부트CI 1배제, LOO 강건", side=1, line=3.0, cex=0.72, col="#555")
dev.off()

# ===================== CHART 2: lift by treatment definition (dilution story) =====================
png(file.path(CH,"02_lift_by_definition.png"), width=1040, height=580, res=110)
par(mar=c(5.0,4.8,3.8,1))
lv <- c(rf$lift, rs$lift, 1.10)
lo <- c(rf$lift_boot[1], rs$lift_boot[1], NA); hi <- c(rf$lift_boot[2], rs$lift_boot[2], NA)
labs <- c("동결 PRIMARY\n(임의지각, 1105ep)","극단꼬리 진단\n(top-decile, 29ep)","연속 지연일수\n(delisting hazard)")
cols <- c("#d9a441","#c0392b","#7f8c8d")
bp <- barplot(lv, names.arg=labs, col=cols, border=NA, ylim=c(0,20),
  ylab="심각사건 Lift (기저율=1.0)", main="신호는 극단꼬리에만: 임의지각 1.23x(CI∋1) vs 극단꼬리 10.0x(CI∌1)")
for(i in 1:2) arrows(bp[i], lo[i], bp[i], hi[i], angle=90, code=3, length=0.07, lwd=2.5, col="#2c3e50")
abline(h=1, lty=2, lwd=2, col="#2c3e50")
text(bp, pmax(lv,c(hi[1],hi[2],1.1))+0.9, c(sprintf("%.2fx\nfirmBoot[%.2f,%.2f]",rf$lift,rf$lift_boot[1],rf$lift_boot[2]),
  sprintf("%.1fx\nfirmBoot[%.1f,%.1f]",rs$lift,rs$lift_boot[1],rs$lift_boot[2]),"1.10x\np=0.19(flat)"), font=2, cex=0.72)
mtext("연속 지연 flat = 비단조·극단꼬리 집중(R22 D2/R23 재현). 동결 p90이 '임의지각'으로 넓혀져 희석됨", side=1, line=3.3, cex=0.72, col="#555")
dev.off()

# ===================== CHART 3: controlled OR forest =====================
png(file.path(CH,"03_controlled_or.png"), width=1040, height=560, res=110)
par(mar=c(4.6,11,3.8,2))
rows <- c("동결 PRIMARY OR\n(임의지각, year-FE)","극단꼬리 OR\n(top-decile, year-FE)","극단꼬리 OR\n(통제, no-FE)")
est <- c(rf$or_fe, rs$or_fe, rs$or_no)
loci<- c(rf$ci_fe[1], rs$ci_fe[1], rs$ci_no[1]); hici<- c(rf$ci_fe[2], rs$ci_fe[2], rs$ci_no[2])
pv  <- c(rf$p_fe, rs$p_fe, rs$p_no)
y <- rev(seq_along(rows))
plot(NA, xlim=c(0.7, 25), ylim=c(0.5,length(rows)+0.5), xlab="Odds Ratio (승산비, 로그축)", ylab="", yaxt="n", log="x",
  main="심각사건 통제후 승산비: 동결 2.34(p=0.051) vs 극단꼬리 6.2(p<0.001)")
axis(2, at=y, labels=rows, las=1, cex.axis=0.8)
abline(v=1, lty=2, lwd=2, col="#2c3e50")
cols <- c("#d9a441","#c0392b","#e67e22")
points(est, y, pch=19, cex=1.7, col=cols)
for(i in seq_along(rows)) arrows(loci[i], y[i], hici[i], y[i], angle=90, code=3, length=0.06, lwd=2.5, col=cols[i])
for(i in seq_along(rows)) text(est[i], y[i]+0.30, sprintf("OR=%.2f p=%.4g",est[i],pv[i]), cex=0.78, font=2)
mtext("동결 PRIMARY CI 하단 0.996≈1 -> 미달. 극단꼬리는 크게 1 배제. year-FE로 시대 기저율 통제", side=1, line=2.9, cex=0.72, col="#555")
dev.off()

# ===================== CHART 4: size-tier decomposition =====================
png(file.path(CH,"04_size_tier.png"), width=1000, height=560, res=110)
par(mar=c(4.6,4.8,3.8,1))
g <- c("small","mid","large")
m <- rbind(
  all=sapply(g, function(t){ v<-tab_all[size_tier==t,N]; if(length(v))v else 0}),
  strict=sapply(g, function(t){ v<-tab_strict[size_tier==t,N]; if(length(v))v else 0}))
mp <- prop.table(m, 1)*100
bp <- barplot(mp, beside=TRUE, col=c("#95a5a6","#c0392b"), border=NA, ylim=c(0,80),
  names.arg=c("소형(하위1/3)","중형","대형(상위1/3)"), ylab="구성비 (%)",
  main="극단꼬리 지각제출의 규모 분포 (소형주 재발견 여부 점검)")
legend("topright", c("전체 에피소드","극단꼬리 지각(wd_strict)"), fill=c("#95a5a6","#c0392b"), border=NA, bty="n", cex=0.85)
text(bp, mp+3, sprintf("%.0f%%",mp), cex=0.78, font=2)
lt <- tier_or[[1]]  # small tier lift
mtext(sprintf("극단꼬리는 소형주 편중하나, size_z/year-FE 통제 후에도 OR=6.2 생존(순수 규모 아님). 소형내 lift=%.1fx", lt$lift %||% NA),
  side=1, line=2.9, cex=0.7, col="#555")
dev.off()

cat("[04] DONE — 4 charts + size_tier_diag.rds saved\n")
cat("   charts:", paste(list.files(CH,pattern="png$"),collapse=", "),"\n")
