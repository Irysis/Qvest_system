suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts) })
PROJ <- "G:/Quant_Module_Moltbot"
s  <- readRDS(file.path(PROJ, "04_Research/strategies/STR_valearn_70_top25/sim_result.rds"))
d  <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]; setorder(d, Date)
bm <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
d <- merge(d, bm, by="Date", all.x=TRUE)
RG <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]; setorder(RG, Date)
q <- data.table(Date=d$Date); res <- RG[q, on=.(Date), roll=TRUE]; d[, cat_me := res$Category]
d[, reg := shift(cat_me, 1L)]; d[is.na(reg), reg:="NEUTRAL"]
nM <- nrow(d); is_cut <- floor(nM*0.60)
# overlay: CAUTION off (e=0.0)
apply_ov <- function(e_d){ prev<-1; rn<-numeric(nM)
  for(i in 1:nM){ e<-if(d$reg[i]=="CAUTION") e_d else 1; r<-e*d$r[i]; if(abs(e-prev)>1e-9) r<-r-abs(e-prev)*(15/1e4); prev<-e; rn[i]<-r }; rn }
d[, r_ov := apply_ov(0.0)]
d[, nav_base := cumprod(1+r)]; d[, nav_ov := cumprod(1+r_ov)]; d[, nav_bm := cumprod(1+ifelse(is.finite(bm),bm,0))]
outdir <- file.path(PROJ, "04_Research/factor_rotation/output"); dir.create(outdir, showWarnings=FALSE, recursive=TRUE)
png(file.path(outdir, "valearn_overlay_equity.png"), width=1100, height=620, res=110)
par(mar=c(4,4,3,1))
yl <- range(c(d$nav_base, d$nav_ov, d$nav_bm), na.rm=TRUE)
plot(d$Date, d$nav_base, type="l", log="y", col="#888888", lwd=1.8, ylim=yl,
     xlab="", ylab="누적가치 (log, 1=2005-03)", main="valearn: 기준(frozen) vs CAUTION 디리스크 오버레이 vs KOSPI200")
lines(d$Date, d$nav_ov, col="#1f77b4", lwd=2.2)
lines(d$Date, d$nav_bm, col="#d62728", lwd=1.4, lty=2)
abline(v=d$Date[is_cut], col="#999999", lty=3)
text(d$Date[is_cut], yl[2]*0.9, "IS|OOS", pos=4, cex=0.8, col="#666666")
legend("topleft", c("기준 valearn (SR0.71 MDD45.6% F)","CAUTION off (SR0.88 MDD34.4% C)","KOSPI200"),
       col=c("#888888","#1f77b4","#d62728"), lwd=c(1.8,2.2,1.4), lty=c(1,1,2), bty="n", cex=0.85)
dev.off()
cat("saved equity:", file.path(outdir, "valearn_overlay_equity.png"), "\n")
# drawdown comparison
png(file.path(outdir, "valearn_overlay_drawdown.png"), width=1100, height=440, res=110)
par(mar=c(4,4,3,1))
dd_base <- d$nav_base/cummax(d$nav_base)-1; dd_ov <- d$nav_ov/cummax(d$nav_ov)-1
plot(d$Date, dd_base*100, type="l", col="#888888", lwd=1.8, ylim=c(min(dd_base*100),2),
     xlab="", ylab="낙폭 %", main="낙폭: 기준 vs CAUTION 디리스크 오버레이")
lines(d$Date, dd_ov*100, col="#1f77b4", lwd=2)
abline(h=0, col="#cccccc"); abline(v=d$Date[is_cut], col="#999999", lty=3)
legend("bottomleft", c("기준 (MDD 45.6%)","CAUTION off (MDD 34.4%)"), col=c("#888888","#1f77b4"), lwd=c(1.8,2), bty="n", cex=0.85)
dev.off()
cat("saved drawdown:", file.path(outdir, "valearn_overlay_drawdown.png"), "\n")
