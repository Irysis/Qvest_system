suppressPackageStartupMessages({library(arrow);library(data.table)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; WT<-file.path(QM,"stage_artifacts/WT_D20260715_001")
CH<-file.path(WT,"charts"); dir.create(CH,showWarnings=FALSE)
nav<-as.data.table(read_parquet(file.path(WT,"nav_series.parquet"))); nav[,date:=as.Date(date)]
TAB<-as.data.table(read_parquet(file.path(WT,"comparison_table.parquet")))[overlay=="applied"]
ERA<-as.data.table(read_parquet(file.path(WT,"era_active.parquet")))
VM<-as.data.table(read_parquet(file.path(WT,"value_marginal_era.parquet")))
cols<-c(arm0="#555555",arm1="#1f77b4",arm2="#d62728",bench="#999999")
png_safe<-function(p,w,h,fn){tmp<-file.path(tempdir(),paste0("c_",Sys.getpid(),"_",basename(p)))
  png(tmp,width=w,height=h,res=120);fn();dev.off()
  if(file.exists(p))file.remove(p);file.copy(tmp,p);file.remove(tmp)}

## 1. equity curve (full, log) — 3 arm overlay + bench
png_safe(file.path(CH,"equity_curve.png"),1100,620,function(){
  par(mar=c(4,4,3,1))
  ymax<-max(nav$arm1_ovl,nav$arm2_ovl,nav$arm0_ovl); ymin<-min(nav$bench)
  plot(nav$date,nav$arm0_ovl,type="l",log="y",col=cols["arm0"],lwd=2,ylim=c(ymin,ymax),
    xlab="",ylab="NAV (log, x)",main="R32: PG2 book (M4xR05 overlay) — baseline vs +value  [clean recon basis]")
  lines(nav$date,nav$arm1_ovl,col=cols["arm1"],lwd=2)
  lines(nav$date,nav$arm2_ovl,col=cols["arm2"],lwd=2)
  lines(nav$date,nav$bench,col=cols["bench"],lwd=1.5,lty=2)
  abline(v=as.Date("2024-01-01"),col="orange",lty=3,lwd=1.5)
  legend("topleft",c("arm0 baseline","arm1 +B2 value","arm2 +Z6 value","benchmark(capw)","2024+ (value reversal)"),
    col=c(cols["arm0"],cols["arm1"],cols["arm2"],cols["bench"],"orange"),lwd=2,lty=c(1,1,1,2,3),bty="n",cex=0.9)})

## 2. OOS zoom (2020+) — recent 6Y with 2024 marker
png_safe(file.path(CH,"oos_zoom_chart.png"),1100,560,function(){
  z<-nav[date>=as.Date("2020-01-01")]; par(mar=c(4,4,3,1))
  reb<-function(x) x/x[1]
  ymax<-max(reb(z$arm1_ovl),reb(z$arm2_ovl),reb(z$arm0_ovl));ymin<-min(reb(z$bench))
  plot(z$date,reb(z$arm0_ovl),type="l",col=cols["arm0"],lwd=2,ylim=c(ymin,ymax),
    xlab="",ylab="NAV (rebased 2020=1)",main="R32 OOS zoom 2020+ : value adds pre-2024, REVERSES post-2024")
  lines(z$date,reb(z$arm1_ovl),col=cols["arm1"],lwd=2);lines(z$date,reb(z$arm2_ovl),col=cols["arm2"],lwd=2)
  lines(z$date,reb(z$bench),col=cols["bench"],lwd=1.5,lty=2)
  abline(v=as.Date("2024-01-01"),col="orange",lty=2,lwd=2)
  legend("topleft",c("arm0 baseline","arm1 +B2","arm2 +Z6","bench","2024-01 value reversal"),
    col=c(cols["arm0"],cols["arm1"],cols["arm2"],cols["bench"],"orange"),lwd=2,lty=c(1,1,1,2,2),bty="n",cex=0.9)})

## 3. risk-axis bars: SR / Calmar / MDD
png_safe(file.path(CH,"risk_bars.png"),1100,460,function(){
  par(mfrow=c(1,3),mar=c(5,4,3,1)); bc<-c(cols["arm0"],cols["arm1"],cols["arm2"]); nmv<-c("baseline","+B2","+Z6")
  barplot(TAB$SR_geo,names.arg=nmv,col=bc,main="Sharpe (geo)",ylim=c(0,1.5));abline(h=TAB$SR_geo[1],lty=3)
  barplot(TAB$Calmar,names.arg=nmv,col=bc,main="Calmar",ylim=c(0,1.3));abline(h=0.64,col="red",lty=2);abline(h=TAB$Calmar[1],lty=3)
  barplot(TAB$MDD,names.arg=nmv,col=bc,main="MDD (lower=better)",ylim=c(0,0.4));abline(h=TAB$MDD[1],lty=3)})

## 4. drawdown underwater
png_safe(file.path(CH,"drawdown.png"),1100,500,function(){
  par(mar=c(4,4,3,1))
  plot(nav$date,nav$arm0_dd,type="l",col=cols["arm0"],lwd=1.6,ylim=c(min(nav$arm0_dd),0),
    xlab="",ylab="drawdown",main="R32 drawdown (overlay applied) — value lowers MDD 0.349->0.278")
  lines(nav$date,nav$arm1_dd,col=cols["arm1"],lwd=1.6);lines(nav$date,nav$arm2_dd,col=cols["arm2"],lwd=1.6)
  abline(v=as.Date("2024-01-01"),col="orange",lty=3)
  legend("bottomleft",c("arm0 baseline","arm1 +B2","arm2 +Z6"),col=c(cols["arm0"],cols["arm1"],cols["arm2"]),lwd=2,bty="n",cex=0.9)})

## 5. value marginal by era (the key finding)
png_safe(file.path(CH,"value_marginal_era.png"),1000,480,function(){
  par(mar=c(4,4,3,1))
  m<-matrix(c(VM$pre2024_dbps,VM$post2024_dbps),nrow=2,byrow=TRUE)
  colnames(m)<-c("B2","Z6");rownames(m)<-c("pre-2024","post-2024(2024+)")
  barplot(m,beside=TRUE,col=c("#2ca02c","#d62728"),main="R32 value marginal (bps/mo, overlay active diff vs baseline)",
    ylab="bps/month",legend.text=TRUE,args.legend=list(x="topright",bty="n"))
  abline(h=0,lwd=1.5)})
cat("charts:",paste(list.files(CH),collapse=", "),"\n")
cat("R32_CHARTS_DONE\n")
