## R29 chart pack (telegram principle 9 — 실측 그래프 첨부 의무)
suppressPackageStartupMessages({library(arrow); library(data.table)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_005"); CH <- file.path(WT,"charts"); dir.create(CH,showWarnings=FALSE)
GD <- as.data.table(read_parquet(file.path(WT,"z6_vintage_grid.parquet")))
col_dirty<-"#c0392b"; col_clean<-"#2980b9"; col_gate<-"#7f8c8d"

png(file.path(CH,"r29_panel.png"), width=1500, height=1050, res=130)
par(mfrow=c(2,2), mar=c(6.5,4.6,3.4,1.2), family="sans")

## Panel 1: paired NW-t — dirty(look-ahead base) vs clean(PIT base)
labs <- c("R27 stored\n(LA base+val)","recon off+1\n(LA base)","recon off0\n(CLEAN base)*","clean base\n+prod-ic")
vals <- c(3.738, 2.226, 1.023, 1.328)
cols <- c(col_dirty,col_dirty,col_clean,col_clean)
bp<-barplot(vals, names.arg=labs, col=cols, border=NA, ylim=c(0,4.2), las=1,
  main="Z6 paired NW-t: look-ahead base vs PIT-clean base", ylab="paired NW-t (lag3)", cex.names=0.78)
abline(h=2.0, col=col_gate, lty=2, lwd=2); text(bp[1],2.12,"gate 2.0",col=col_gate,cex=0.8,adj=0)
text(bp, vals+0.13, sprintf("%.2f",vals), cex=0.92, font=2)
text(mean(bp[3:4]), 3.9, "* PRIMARY (production convention)", col=col_clean, cex=0.72)

## Panel 2: base PORT_t by vintage (the seam, 2.08x)
b2<-c(3.058, 6.376, 3.247, 6.922)
l2<-c("off0 clean\nstored-th","off+1 LA\nstored-th","off0 clean\nic-th","off+1 LA\nic-th")
c2<-c(col_clean,col_dirty,col_clean,col_dirty)
bp2<-barplot(b2,names.arg=l2,col=c2,border=NA,ylim=c(0,8),las=1,
  main="Base panel PORT_t: T-1 clean vs same-month (2.08x seam)",ylab="cap-w top-25 PORT_t",cex.names=0.8)
text(bp2,b2+0.25,sprintf("%.2f",b2),cex=0.92,font=2)
text(mean(bp2[1:2]),7.4,"2.08x",col=col_dirty,font=2,cex=1.0)

## Panel 3: IS vs HO paired — primary clean vs R27 reference
grp<-c("IS","HO")
clean_v<-c(GD[cell=="PRIMARY_clean_base_clean_val",paired_is], GD[cell=="PRIMARY_clean_base_clean_val",paired_ho])
r27_v<-c(3.107, 4.357)  # from verify (A) stored base + pfs
mat<-rbind(clean=clean_v, R27_LA=r27_v)
bp3<-barplot(mat, beside=TRUE, names.arg=grp, col=c(col_clean,col_dirty), border=NA, ylim=c(0,4.8), las=1,
  main="paired NW-t: IS vs Holdout", ylab="paired NW-t")
abline(h=2.0,col=col_gate,lty=2,lwd=2)
legend("topleft",c("clean base (PIT)","R27 LA base"),fill=c(col_clean,col_dirty),border=NA,bty="n",cex=0.85)
text(as.vector(bp3), as.vector(mat)+0.14, sprintf("%.2f",as.vector(mat)), cex=0.82, font=2)

## Panel 4: value vintage parity + dual-basis
vv<-readRDS(file.path(WT,"value_vintage_parity.rds"))
l4<-c("value vs\nfactor_db T-1","value vs\nsame-month","EW-uni pt\n(clean Z6)","cap-w pt\n(clean Z6)")
b4<-c(vv$par_off0, vv$par_off1, GD[cell=="PRIMARY_clean_base_clean_val",ewuni_port_t]/8, GD[cell=="PRIMARY_clean_base_clean_val",variant_port_t]/8)
# first two are correlations (0-1), last two are PORT_t scaled /8 for co-display; annotate raw
c4<-c("#27ae60","#27ae60","#8e44ad","#8e44ad")
bp4<-barplot(b4,names.arg=l4,col=c4,border=NA,ylim=c(0,1.15),las=1,
  main="Value=clean(cor 1.0) | dual-basis EW-uni strong",ylab="cor  /  (PORT_t /8)",cex.names=0.74)
ann<-c(sprintf("%.3f",vv$par_off0),sprintf("%.3f",vv$par_off1),
  sprintf("%.2f",GD[cell=="PRIMARY_clean_base_clean_val",ewuni_port_t]),
  sprintf("%.2f",GD[cell=="PRIMARY_clean_base_clean_val",variant_port_t]))
text(bp4,b4+0.04,ann,cex=0.9,font=2)
dev.off()
cat("CHART_DONE:", file.path(CH,"r29_panel.png"), "\n")
