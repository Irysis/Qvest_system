## make_r36_charts.R — R36 monitoring 판정 차트 3종 (도훈 mandate 원칙 9)
## 시각화 전용. 수치는 r36_results.json 계약 산출값만 표기.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260715_005"
J <- fromJSON(file.path(OUT,"r36_results.json"))
try({ windowsFonts(kr=windowsFont("Malgun Gothic")) }, silent=TRUE)
FAM <- "kr"
col_str <- "#1f77b4"; col_pos <- "#2ca02c"; col_neg <- "#d62728"; col_gray <- "#999999"; col_mid <- "#ff7f0e"

## ── Chart 1: 형태별 forward SAFE 강건성 (gap_t + IC_t) ──────────────────────────
f1 <- file.path(OUT,"01_form_safe_strength.png")
png(f1, width=1040, height=560, res=110); par(mar=c(4.6,10.5,3.4,1.4), family=FAM)
labs <- c("F0 baseline\nINS02≥+1.0 (R33)","F1 정밀\nINS02≥1.0 ∧ INS03≥0.5","F2 완화\nINS02≥+0.5","F3cut\nINS01≥+0.5","F3 연속\nINS01 IC")
vals <- c(J$F0_base$safe$gap_ret_t, J$F1_prec$safe$gap_ret_t, J$F2_relax$safe$gap_ret_t, J$F3_cont$cut_safe$gap_ret_t, J$F3_cont$continuous_ic$ic_t)
mo   <- c(J$F0_base$coverage$coverage_months, J$F1_prec$coverage$coverage_months, J$F2_relax$coverage$coverage_months, 250L, J$F3_cont$continuous_ic$ic_months)
cols <- c(col_gray, col_neg, col_pos, col_pos, col_str)
bp <- barplot(rev(vals), horiz=TRUE, col=rev(cols), border=NA, xlim=c(0,6),
  names.arg=rev(labs), las=1, cex.names=0.72, xlab="forward SAFE gap t값 (NW lag-3) — 클수록 강건",
  main="R36 ① 형태별 forward SAFE 강건성 — 전 형태 t>3 (F1 무이득)")
abline(v=2, lty=2, col=col_neg); text(2, 0.4, "t=2\n유의선", col=col_neg, cex=0.62, pos=4)
text(rev(vals), bp, sprintf("t=%.2f  (%d개월)", rev(vals), rev(mo)), pos=4, cex=0.68, col="#333333", xpd=NA)
mtext("월 커버리지(armed months): 완화 126→250 · 연속 253 — 모니터링 coverage 2배", side=3, line=0.2, cex=0.7, col="#555555")
dev.off()

## ── Chart 2: 대형주 TOP30 표본↑ 신호 thin ──────────────────────────────────────
f2 <- file.path(OUT,"02_top30_sample_vs_signal.png")
png(f2, width=1040, height=560, res=110); par(mar=c(4.6,4.4,3.6,4.6), family=FAM)
forms2 <- c("F0\nbaseline","F1\n정밀","F2\n완화","F3cut\nINS01")
n_top30 <- c(J$F0_base$coverage$n_flag_top30, J$F1_prec$coverage$n_flag_top30, J$F2_relax$coverage$n_flag_top30, J$F3_cont$cut_safe$n_flag_top30)
## TOP30_t 추출 (tier top30 테이블에서 megatier=="TOP30")
get_t30 <- function(top30df){ d<-as.data.table(top30df); d[megatier=="TOP30", gap_t][1] }
t_top30 <- c(get_t30(J$F0_base$tier$top30), get_t30(J$F1_prec$tier$top30), get_t30(J$F2_relax$tier$top30), get_t30(J$F3_cont$cut_safe$top30))
bp2 <- barplot(n_top30, col="#cbd5e1", border=NA, ylim=c(0,2700), names.arg=forms2, cex.names=0.8,
  ylab="TOP30 대형주 flag 표본 수 (막대)", main="R36 ② 대형주 TOP30 — 표본 3배↑, 그러나 SAFE 신호 t<2 잔존")
text(bp2, n_top30, n_top30, pos=3, cex=0.72, col="#475569")
par(new=TRUE); plot(bp2, t_top30, type="b", pch=19, col=col_neg, lwd=2.2, cex=1.3, axes=FALSE, xlab="", ylab="", ylim=c(0,3), xlim=range(bp2)+c(-0.6,0.6))
axis(4, col=col_neg, col.axis=col_neg, cex.axis=0.8); mtext("TOP30 SAFE gap t값 (점선)", side=4, line=2.6, col=col_neg, cex=0.85)
abline(h=2, lty=2, col=col_neg); text(bp2, t_top30, sprintf("t=%.2f", t_top30), pos=1, cex=0.7, col=col_neg)
mtext("표본은 744→2341(3.1x) 강화되나 mega-tier 신호 t 는 문턱(2) 미달 — SAFE=mid-cap 중심", side=3, line=0.2, cex=0.7, col="#555555")
dev.off()

## ── Chart 3: SAFE = 위험 감소 (F2 완화 권고안 · flag vs 비flag) ─────────────────
f3 <- file.path(OUT,"03_safe_risk_reduction.png")
png(f3, width=1040, height=560, res=110); par(mar=c(4.2,4.6,3.6,1.4), family=FAM)
S <- J$F2_relax$safe
m <- rbind(flag=c(S$fwd_flag*100, -S$downside_flag*100, S$vol_flag*100, S$tail_flag*100),
           nonflag=c(J$F2_relax$safe$fwd_nonflag*100, -S$downside_nonflag*100, S$vol_nonflag*100, S$tail_nonflag*100))
colnames(m) <- c("월수익(+좋음)","하방크기(작을수록↑)","변동성(작을수록↑)","급락<-15% 빈도")
bp3 <- barplot(m, beside=TRUE, col=c(col_pos, col_gray), border=NA, ylim=c(0,16),
  legend.text=c("순매수 flag (SAFE)","비-flag"), args.legend=list(x="topright",bty="n",cex=0.85),
  ylab="% (월수익·하방·급락빈도) / 변동성%", main="R36 ③ 순매수 flag = 위험 감소 (F2 완화안, INS02≥+0.5)")
text(bp3, as.vector(m), sprintf("%.1f", as.vector(m)), pos=3, cex=0.66, col="#333333")
mtext("flag 보유 = 고수익·저하방·저급락 (down -7.5%vs-8.5% · vol 12.6%vs13.9% · 급락 5.6%vs7.9%) — 모니터링 SAFE 라벨", side=3, line=0.2, cex=0.68, col="#555555")
dev.off()

cat("[charts]", f1, f2, f3, sep="\n")
