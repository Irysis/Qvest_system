## make_r37_charts.R — R37 텔레그램 차트팩 (원칙 9: 실측 보고 = 그래프 첨부 의무)
##   ① power curve (TOP30 F2 표본이 효과크기별 검출 검정력) ② 형태·복합 TOP30 t 막대(hline=2)
##   ③ pooled 순열 null 히스토그램. 시각화 전용(수치는 계약값). base R + tg_chart_sweep.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260715_006"; CH <- file.path(OUT,"charts"); dir.create(CH, showWarnings=FALSE, recursive=TRUE)
o <- readRDS(file.path(OUT,"_r37_objects.rds")); P1<-o$P1; P2<-o$P2; PB<-o$PB_pool; res<-o$out

## ── ① power curve: TOP30 F2 표본 SE 고정, 효과크기 0~22%/yr 에 대한 two-sided 5% 검정력 ──
se_mo <- P1$F2_relax$top30$se_mo   # monthly SE
grid_ann <- seq(0, 0.22, by=0.002); zc <- qnorm(0.975)
pow <- sapply(grid_ann, function(a){ ncp<-(a/12)/se_mo; pnorm(ncp-zc)+pnorm(-ncp-zc) })
png(file.path(CH,"r37_power_curve.png"), width=1000, height=560, res=110)
par(mar=c(4.4,4.6,3.4,1.4), family="")
plot(grid_ann*100, pow, type="l", lwd=2.4, col="#1f77b4", ylim=c(0,1),
     xlab="가정한 진짜 효과크기 (연 %/yr)", ylab="검출 검정력 (two-sided 5%)",
     main="TOP30 표본 검정력 곡선 — 효과크기 얼마면 잡히나 (F2, n=250개월·flag 2341)")
abline(h=0.8, col="#888888", lty=3)
marks <- list(
  c(P1$F2_relax$top30$gap_ann*100, "#d62728", "TOP30 관측 3.8%"),
  c(res$P1_power_vs_death$bootstrap_top30_f2_ci$hi*100, "#ff7f0e", "관측 CI상단 9.7%"),
  c(P1$F2_relax$large$gap_ann*100, "#9467bd", "large-tercile 5.6%"),
  c(P1$F2_relax$mid$gap_ann*100, "#2ca02c", "mid 19.1%"))
mde <- 2.802*se_mo*12*100
abline(v=mde, col="#333333", lty=2, lwd=1.6); text(mde, 0.05, sprintf("MDE(80%%)\n%.1f%%", mde), col="#333333", cex=0.72, pos=4)
for(m in marks){ x<-as.numeric(m[1]); py<-pnorm((x/100/12)/se_mo-zc)+pnorm(-(x/100/12)/se_mo-zc)
  abline(v=x, col=m[2], lty=1, lwd=1.4); points(x, py, pch=19, col=m[2], cex=1.1)
  text(x, min(py+0.06,0.97), m[3], col=m[2], cex=0.68, pos=4, offset=0.2) }
legend("right", legend="검정력 0.8 기준선", lty=3, col="#888888", bty="n", cex=0.72)
dev.off()

## ── ② 형태·복합 TOP30 t 막대 (hline=2) ──
labs <- c("F0 baseline","F2 완화","F3 강도연속","복합 union","복합 inter","복합 addz","pooled(F0∪F2∪F3)")
vals <- c(P1$F0_base$top30$gap_t, P1$F2_relax$top30$gap_t, P1$F3_cut$top30$gap_t,
          P2$C_union$top30$gap_t, P2$C_inter$top30$gap_t, P2$C_addz$top30$gap_t, o$gt_pool$fit$t)
p2 <- tg_chart_sweep(labels=labs, values=round(vals,2), out_dir=CH,
  title="TOP30(대형주) SAFE gap NW-t — 7형태 전부 <2 (문턱 미달)",
  value_label="NW-lag3 t (TOP30 forward gap)", hline=2, hline_label="유의 문턱 t=",
  filename="r37_top30_t_bars.png")

## ── ③ pooled 순열 null 히스토그램 ──
png(file.path(CH,"r37_pooled_perm.png"), width=1000, height=560, res=110)
par(mar=c(4.4,4.4,3.4,1.4), family="")
obs <- res$P3_pooled_perm$top30_pooled$gap_ann
hist(PB$perm_ann*100, breaks=40, col="#c6dbef", border="white",
     xlab="pooled TOP30 gap (연 %/yr) — 월내 flag 셔플 귀무분포",
     main=sprintf("pooled cross-form TOP30 순열검정 (nperm=%d, p=%.3f)", PB$nperm, res$P3_pooled_perm$perm$p_value))
abline(v=obs*100, col="#d62728", lwd=2.6); text(obs*100, par("usr")[4]*0.85, sprintf("관측 %+.2f%%", obs*100), col="#d62728", pos=2, cex=0.8)
abline(v=res$P3_pooled_perm$perm$q95*100, col="#ff7f0e", lty=2); text(res$P3_pooled_perm$perm$q95*100, par("usr")[4]*0.6, "null q95", col="#ff7f0e", pos=4, cex=0.7)
dev.off()

cat("charts:\n", normalizePath(file.path(CH,"r37_power_curve.png"),winslash="/"), "\n",
    p2, "\n", normalizePath(file.path(CH,"r37_pooled_perm.png"),winslash="/"), "\n")
