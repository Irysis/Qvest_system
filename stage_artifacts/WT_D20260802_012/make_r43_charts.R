## make_r43_charts.R — R43 실측 시각화 (텔레그램 원칙 9)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
R  <- fromJSON(file.path(OUT,"r43_results.json"))
FU <- fromJSON(file.path(OUT,"r43_followup.json"))
DC <- fromJSON(file.path(OUT,"r43_decomposition.json"))
MC <- fromJSON(file.path(OUT,"r43_mechanism.json"))
I2 <- as.data.table(read_parquet(file.path(OUT,"r43_live_monthly_maxz.parquet")))
MO <- as.data.table(read_parquet(file.path(OUT,"r43_monthly_names.parquet")))
GS <- as.data.table(read_parquet(file.path(OUT,"r43_group_summary_mid.parquet")))
CV <- as.data.table(read_parquet(file.path(OUT,"r43_coverage.parquet")))
CVA <- CV[slice == "ALL"]
KO <- function(n) { f <- c("맑은 고딕","Malgun Gothic","NanumGothic"); for (x in f) if (x %in% names(grDevices::windowsFonts()) || TRUE) return(x); "sans" }
try(grDevices::windowsFonts(kr = grDevices::windowsFont("Malgun Gothic")), silent = TRUE)
FAM <- tryCatch({ if ("kr" %in% names(grDevices::windowsFonts())) "kr" else "" }, error=function(e) "")

## ── A: 주축 침묵 구조 + 커버리지 변화 ────────────────────────────────────────
png(file.path(OUT,"chart_A_silence_coverage.png"), width=1400, height=900, res=110)
par(mfrow=c(2,1), mar=c(3.4,4.6,3.0,1.2), family=FAM)
I2[, d := as.Date(signal_date)]
plot(I2$d, I2$max_z, type="h", col=ifelse(I2$n_ge1==0,"#d94040","#7fb3d5"), lwd=1.4,
     xlab="", ylab="월별 최대 z", ylim=c(0, max(I2$max_z)*1.05),
     main=sprintf("① 현행 tripwire 는 %d/%d 개월(%.1f%%) 구조적으로 침묵 — 최대 z 가 문턱에 닿지 않는다",
                  FU$F1$live_silent_months, FU$F1$live_months, FU$F1$live_silent_pct))
abline(h=1.0, col="#111111", lwd=2, lty=2)
text(min(I2$d), 1.06, " 문턱 z=1.0 (R33 frozen)", adj=0, cex=0.85)
legend("topright", c("발화월(최대 z ≥ 1.0)","침묵월(최대 z < 1.0)","문턱"),
       col=c("#7fb3d5","#d94040","#111111"), lwd=c(2,2,2), lty=c(1,1,2), bty="n", cex=0.85)
MO[, d := as.Date(paste0(substr(hold_ym,1,4),"-",substr(hold_ym,5,6),"-01"))]
plot(MO$d, MO$nAp, type="h", col="#f0a860", lwd=1.3, xlab="", ylab="월별 SAFE 종목수",
     main=sprintf("② 보조축 추가 시 감시 가능월 %d → %d (전체 %d개월) · SAFE 종목-월 %d → %d (+%.1f%%)",
                  FU$F1$uni_A_active_months, FU$F1$uni_Ap_active_months, FU$F1$uni_months,
                  CVA$safe_A, CVA$safe_Ap, CVA$safe_delta_pct))
lines(MO$d, MO$nA, type="h", col="#3a6ea5", lwd=1.3)
legend("topleft", c("현행 A (INS02 breadth)","보조축이 추가한 몫 (INS_MAGQ3)"),
       col=c("#3a6ea5","#f0a860"), lwd=3, bty="n", cex=0.85)
dev.off()

## ── B: 4분할 그룹 안전 특성 (MID habitat) ────────────────────────────────────
png(file.path(OUT,"chart_B_group_safety.png"), width=1400, height=760, res=110)
par(mfrow=c(1,3), mar=c(4.4,4.9,3.6,1.0), family=FAM)
ord <- c("NEITHER","A_ONLY","BOTH","MAG_ONLY")
lab <- c("무신호","현행만","둘 다","보조축만")
G <- GS[match(ord, grp4)]
pt <- R$D3_group_summary$paired_vs_NEITHER
tv <- c(NA, pt$A_ONLY$mid_ret$gap_t, pt$BOTH$mid_ret$gap_t, pt$MAG_ONLY$mid_ret$gap_t)
cols <- c("#b8b8b8","#3a6ea5","#2e8b57","#f0a860")
b <- barplot(G$mean_fwd*100, names.arg=lab, col=cols, las=1, ylab="월평균 수익 (%)",
             main="익월 평균수익", cex.names=1.0, ylim=c(0, max(G$mean_fwd*100)*1.18))
text(b, G$mean_fwd*100, sprintf("%+.2f%%", G$mean_fwd*100), pos=3, cex=0.95, xpd=NA)
text(b, 0, sprintf("n=%d", G$n_obs), pos=3, cex=0.82, xpd=NA, col="#444444")
b <- barplot(-G$downside*100, names.arg=lab, col=cols, las=1, ylab="하방손실 (%, 작을수록 안전)",
             main="하방손실(음수달 평균)", cex.names=1.0, ylim=c(0, max(-G$downside*100)*1.18))
text(b, -G$downside*100, sprintf("%.2f%%", -G$downside*100), pos=3, cex=0.95, xpd=NA)
b <- barplot(G$tail_hit*100, names.arg=lab, col=cols, las=1, ylab="급락 빈도 (%)",
             main="급락(-15% 이하) 빈도", cex.names=1.0, ylim=c(0, max(G$tail_hit*100)*1.18))
text(b, G$tail_hit*100, sprintf("%.1f%%", G$tail_hit*100), pos=3, cex=0.95, xpd=NA)
mtext(sprintf("MID 시총층 · 무신호 대비 월별-paired NW-t: 현행만 %+.2f / 둘다 %+.2f / ★보조축만 %+.2f (기준 2.0 미달)",
              tv[2], tv[3], tv[4]), side=1, line=-1.2, outer=TRUE, cex=0.92)
dev.off()

## ── C: 창-정합 통제 + 기전 귀속 ──────────────────────────────────────────────
png(file.path(OUT,"chart_C_window_matched.png"), width=1500, height=760, res=110)
par(mfrow=c(1,2), mar=c(5.2,4.8,4.4,1.0), family=FAM)
sl <- "REST"; d <- DC$decomposition[[sl]]
vals <- c(d$A_full$gap_t, d$Ap_full$gap_t, d$A_matched$gap_t, d$Ap_matched$gap_t, d$Ap_newmonths$gap_t)
nms  <- c("A\n전체월","A′\n전체월","A\n발화월","A′\n발화월\n(창정합)","A′\n침묵월\n단독")
cl   <- c("#3a6ea5","#f0a860","#3a6ea5","#f0a860","#d94040")
b <- barplot(vals, names.arg=nms, col=cl, las=1, ylab="유지 vs 무신호 NW-t", ylim=c(-0.4, max(vals)*1.25),
             main=sprintf("③ 겉보기 희석 %.2f→%.2f 의 정체\n같은 월로 맞추면 사라진다 (REST tier)", d$A_full$gap_t, d$Ap_full$gap_t),
             cex.names=0.9, cex.main=1.0)
abline(h=2.0, col="#111111", lty=2, lwd=2); text(0.25, 2.14, " t=2.0", adj=0, cex=0.85)
text(b, vals, sprintf("%+.2f", vals), pos=3, cex=1.0, xpd=NA)
text(b, 0.08, sprintf("%d개월", c(d$A_full$n_months, d$Ap_full$n_months, d$A_matched$n_months, d$Ap_matched$n_months, d$Ap_newmonths$n_months)),
     pos=3, cex=0.8, col="#333333", xpd=NA)
sc <- MC$sustain_composition
cells <- MC$cell_metrics
cn <- names(cells); cv <- sapply(cells, function(x) x$paired_t); cnn <- sapply(cells, function(x) x$n)
o <- order(-cv)
b <- barplot(cv[o], names.arg=gsub("→","\n→ ",cn[o]), col=ifelse(cv[o]>0,"#2e8b57","#d94040"), las=1,
             ylab="무신호(A-OFF) 대비 NW-t", ylim=c(min(cv)-0.5, max(cv)*1.45),
             main="④ 창-정합 개선을 만든 이행 셀\n전부 표본 얇고 t<2 (유의 아님)", cex.names=0.82, cex.main=1.0)
abline(h=2.0, col="#111111", lty=2, lwd=2); abline(h=0, col="#888888")
text(b, cv[o], sprintf("%+.2f", cv[o]), pos=ifelse(cv[o]>0,3,1), cex=0.95, xpd=NA)
text(b, 0, sprintf("n=%d", cnn[o]), pos=ifelse(cv[o]>0,1,3), cex=0.8, col="#333333", xpd=NA)
mtext(sprintf("A′ 유지 %d개 = 기존 %d + 신규편입 %d — 신규편입은 하방 %.2f%% · 급락 %.1f%% 로 기존 유지(%.2f%% · %.1f%%)보다 나쁘다",
              sc$total, sc$existing, sc$added, -sc$added_metrics$downside*100, sc$added_metrics$tail*100,
              -sc$existing_metrics$downside*100, sc$existing_metrics$tail*100),
      side=1, line=-1.1, outer=TRUE, cex=0.9)
dev.off()
cat("[charts] 3 saved\n")
