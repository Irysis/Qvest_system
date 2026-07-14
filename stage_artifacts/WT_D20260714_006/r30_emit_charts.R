## R30 — emit alpha_scores.parquet (B2 conditional / Z6 blend / pure value) + charts
suppressPackageStartupMessages({library(arrow); library(data.table)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_006")
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
W_BLEND<-0.30
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SIZE <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))$SIZE
DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`,`0_ic_S7`)], VP[,.(Date,Ticker,vz_off0)], by=c("Date","Ticker"), all.x=TRUE)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,cap_rank,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]
DT[, b_z := zc(`0_stored_S7`), by=Date]
DT[, v_z := zc(vz_off0), by=Date]; DT[is.na(v_z), v_z := 0]
DT[, score_pureval := vz_off0]
DT[, score_z6_blend := (1-W_BLEND)*b_z + W_BLEND*v_z]                                  # R29 primary (all-tier)
DT[, v_boost_nonmega := fifelse(tier %in% c("MID","OTHER"), v_z, 0)]
DT[, score_B2_nonmega := (1-W_BLEND)*b_z + W_BLEND*v_boost_nonmega]                    # B2 (gate-crossing)
DT[, v_boost_mid := fifelse(tier=="MID", v_z, 0)]
DT[, score_B1_midonly := (1-W_BLEND)*b_z + W_BLEND*v_boost_mid]
AS <- DT[is.finite(`0_stored_S7`), .(Date,Ticker,cap_rank,tier,base_z=b_z,value_z=v_z,
  score_pureval, score_z6_blend, score_B1_midonly, score_B2_nonmega)]
save_safe(AS, file.path(WT,"alpha_scores.parquet"), function(o,p) write_parquet(o,p))
cat(sprintf("alpha_scores.parquet: %d rows, %d months, cols=%s\n", nrow(AS), uniqueN(AS$Date), paste(names(AS),collapse=",")))

## ---- charts (telegram v7 mandate) ----
BG <- as.data.table(read_parquet(file.path(WT,"branchB_grid.parquet")))
AD <- readRDS(file.path(WT,"r30_branchA_diag.rds"))
As <- as.data.table(AD$A_summary)
png(file.path(WT,"charts/r30_panel.png"), width=1500, height=1000, res=130)
par(mfrow=c(2,2), mar=c(4.5,4.5,3,1.5), cex.main=1.05, cex.lab=0.95)
COL<-c("#2c6fbb","#e07b39","#3a9d3a","#b03a5b")
## (1) Branch B paired vs gate
bb <- rbind(data.table(cell="R29\nuncond",paired=1.243,dIR=0.153,pass=FALSE),
            BG[,.(cell=gsub("_","\n",cell),paired=paired_full,dIR=dIR_full,pass=AND_gate)])
bp<-barplot(bb$paired, names.arg=bb$cell, col=ifelse(bb$pass,COL[3],"#9aa4ad"), border=NA,
  main="Branch B: cap-w paired NW-t (AND-gate 2.0)", ylab="paired NW-t (lag3)", ylim=c(0,2.8))
abline(h=2.0, lty=2, col="#b03a5b", lwd=2); text(bp, bb$paired+0.08, sprintf("%.2f",bb$paired), cex=0.85)
text(bp, 0.12, sprintf("dIR %.2f",bb$dIR), cex=0.7, col="white")
## (2) Branch B B2 IS/HO/post17/lag1/placebo robustness
b2 <- BG[cell=="B2_MID_OTHER"]
rv <- c(full=b2$paired_full, IS=b2$paired_is, HO=b2$paired_ho, post17=b2$post2017_t, lag1=b2$paired_lag1)
rp<-barplot(rv, col=c(COL[1],"#7aa8d8","#d88",COL[2],COL[3]), border=NA, ylim=c(0,2.8),
  main="B2 (non-mega) robustness decomposition", ylab="NW-t")
abline(h=2.0,lty=2,col="#b03a5b"); text(rp, rv+0.08, sprintf("%.2f",rv), cex=0.82)
mtext(sprintf("placebo p=%.3f (null max %.2f) | paired-diff oos_v2=%.2f", AD$B2_placebo$p, AD$B2_placebo$null_max, AD$B2_oos_paireddiff), side=1, line=2.6, cex=0.72)
## (3) Branch A EW deployability (EWuni_t + oos_v2 x10; TE in text)
ea <- matrix(c(As$ewuni_port_t, As$ewuni_oos_v2*10), nrow=2, byrow=TRUE)
colnames(ea)<-c("Z6_blend","pure_value")
eb<-barplot(ea, beside=TRUE, col=c(COL[1],COL[2]), border=NA, ylim=c(0,7.5),
  main="Branch A: EW-relative track (배포성)", ylab="value")
legend("topright", c("EWuni PORT_t","oos_v2 x10"), fill=c(COL[1],COL[2]), bty="n", cex=0.78)
abline(h=2.95,lty=3,col="#b03a5b")
text(eb[1,1], As$ewuni_port_t[1]+0.25, sprintf("t %.2f",As$ewuni_port_t[1]),cex=0.75)
text(eb[1,2], As$ewuni_port_t[2]+0.25, sprintf("t %.2f",As$ewuni_port_t[2]),cex=0.75)
text(eb[2,1], As$ewuni_oos_v2[1]*10+0.25, sprintf("oos %.2f",As$ewuni_oos_v2[1]),cex=0.72)
text(eb[2,2], As$ewuni_oos_v2[2]*10+0.25, sprintf("oos %.2f",As$ewuni_oos_v2[2]),cex=0.72)
mtext(sprintf("TE ann: Z6 %.1f%% / pureVal %.1f%% | overlap(P-pure) 12.5/19.5%% · active-corr 0.19/0.50",
  As$te_ew_ann[1]*100, As$te_ew_ann[2]*100), side=1, line=2.7, cex=0.66)
## (4) pure-value trailing 3-split stability + spread context
ts<-AD$trailing_V; tz<-AD$trailing_Z6
tp<-barplot(rbind(tz,ts), beside=TRUE, col=c(COL[1],COL[2]), border=NA, ylim=c(0,5.5),
  names.arg=c("early","mid","recent"), main="EW-active trailing 3-split NW-t (감쇠 점검)", ylab="NW-t")
legend("topright", c("Z6 blend","pure value"), fill=c(COL[1],COL[2]), bty="n", cex=0.8)
mtext("value_quality_spread 백분위=0.175 (06-24 '사상최대'에서 압축 — 늦은-사이클 리스크)", side=1, line=2.6, cex=0.7, col="#b03a5b")
dev.off()
cat("charts/r30_panel.png written\n")
cat("EMIT_DONE\n")
