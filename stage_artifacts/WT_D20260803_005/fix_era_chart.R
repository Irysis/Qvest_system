suppressPackageStartupMessages({library(data.table)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/WT_D20260803_005"; CH <- file.path(OUT,"charts")
DBR <- readRDS(file.path(OUT,"dualbasis_results.rds")); P1R <- readRDS(file.path(OUT,"persistence_results.rds"))
E <- DBR$era2; GRIDS <- P1R$grids
png(file.path(CH,"wt005_era_dualbasis.png"), width=1200, height=680)
par(mfrow=c(1,2), mar=c(7,4.5,4.5,1), oma=c(0,0,4,0))
for (g in c("primary","rob36")) {
  Eg <- E[grid==g]; W <- GRIDS[[g]]$W
  bp <- barplot(rbind(Eg$pos_cap, Eg$pos_ew), beside=TRUE,
    names.arg=format(Eg$to, "~%y.%m"), col=c("#cf222e","#1f6feb"), ylim=c(0,1.05),
    ylab="PORT_t > 0 인 factor 비율", las=2, cex.names=0.9,
    main=sprintf("창 %d개월 (창당 285 factor)", W))
  abline(h=0.5, lty=2)
  text(bp, rbind(Eg$pos_cap, Eg$pos_ew), sprintf("%.2f", rbind(Eg$pos_cap, Eg$pos_ew)), pos=3, cex=0.8)
}
mtext("WT-005 era 공통성분 — 판정 부호의 정체", outer=TRUE, line=1.8, cex=1.25, font=2)
mtext(sprintf("빨강 = cap-w 벤치(현 판정 기준): era 라벨 일치율 %.2f  |  파랑 = EW-유니버스 벤치: %.2f — era 진폭이 벤치 구성에서 나온다",
      mean(DBR$era_share$agree_cap), mean(DBR$era_share$agree_ew)), outer=TRUE, line=0.2, cex=0.95)
dev.off()
cat("era chart rewritten\n")
