## R31 charts — paired per sub-axis (gate) + pre/post-2024 recency + incumbent corr. metric_type=weighted_screen.
suppressPackageStartupMessages({library(arrow); library(data.table)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_007"); CH<-file.path(WT,"charts")
source(file.path(QM,"02_Infrastructure/telegram/tg_chart_pack.R"))
RG <- as.data.table(read_parquet(file.path(WT,"subaxis_b2_grid.parquet")))
lab <- sprintf("%s", RG$subaxis)

## 1) paired NW-t vs base per sub-axis (gate 2.0)
tg_chart_sweep(lab, RG$paired_full, CH,
  "R31 밸류 정의 스펙트럼 — cap-w paired NW-t (vs clean base)",
  value_label="paired NW-t (실측)", hline=2.0, hline_label="AND-gate",
  highlight="EBIT_EV", filename="01_paired_by_subaxis.png")

## 2) recency: pre-2024 vs 2024+ grouped bar
o <- order(RG$paired_full)
mat <- rbind(pre2024=RG$paired_pre2024[o], post2024=RG$paired_post2024[o]); colnames(mat)<-RG$subaxis[o]
grDevices::png(file.path(CH,"02_recency_pre_post_2024.png"), width=1050, height=580, res=110)
graphics::par(mar=c(4.2,4.4,3.4,1.2))
bp<-barplot(mat, beside=TRUE, col=c("#4c78a8","#e45756"), border=NA, las=1,
  ylab="paired NW-t", main="R31 recency — pre-2024 vs 2024+ (정의별 감쇠 여부)",
  cex.names=0.82, ylim=range(c(mat,0))*1.2)
abline(h=0,col="#333333"); legend("topleft",legend=c("pre-2024","2024+"),fill=c("#4c78a8","#e45756"),bty="n",cex=0.8)
mtext("EBIT_EV·FCF는 2024+ 감쇠 / SP·EP·CFP는 2024+ 개선 = 감쇠는 정의-특이(value-보편 아님)", side=3,line=0.2,cex=0.68,col="#555555")
dev.off()

## 3) incumbent redundancy (cor_active) per sub-axis (frontier threshold 0.5)
tg_chart_sweep(lab, RG$cor_active, CH,
  "R31 incumbent 잉여 — variant active corr vs base (구성-바운드)",
  value_label="active corr (screening proxy)", hline=0.5, hline_label="frontier",
  highlight="EBIT_EV", filename="03_incumbent_cor.png")

cat("CHARTS_DONE\n"); cat(list.files(CH),sep="\n")
