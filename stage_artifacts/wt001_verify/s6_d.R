suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
IN9<-"stage_artifacts/WT_D20260802_009"; OUT<-"stage_artifacts/WT_D20260808_001"
say<-function(f,...)cat(sprintf(paste0("[v] ",f,"\n"),...))
BASE<-as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED<-as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW<-as.data.table(read_parquet(".cache/RAWDATA.parquet",col_select=c("Date","Ticker","Size","K200","KQ150")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")];MEND<-sort(RAW[,.(Date=max(Date)),by=ym]$Date);RAWME<-RAW[Date%in%MEND];rm(RAW);gc(verbose=FALSE)
UNIV<-RAWME[(K200==TRUE|KQ150==TRUE),.(Date,Ticker)];SIZE<-RAWME[,.(Date,Ticker,Size)]
fwd<-readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
score_of<-function(f){sc<-if(f %in% BASE$Factor_Name)BASE[Factor_Name==f,.(Date,Ticker,score=z)] else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]
  merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
FILT<-c("D03_EWMA","Q01_EB")
E<-merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE);E<-E[is.na(adv)|adv>=2e8][,adv:=NULL]
E<-E[Date %in% returns_dt$Date]
FZ<-rbindlist(lapply(FILT,function(f)score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ<-merge(FZ,E[,.(Date,Ticker)],by=c("Date","Ticker"))
IND<-as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",col_select=c("Date","Ticker","NetBuy")))[,Date:=as.Date(Date)]
say("investor nrow=%d DAILY n_day=%d %s~%s",nrow(IND),uniqueN(IND$Date),min(IND$Date),max(IND$Date))
IND[,ym:=format(Date,"%Y-%m")];INM<-IND[,.(nb=sum(NetBuy,na.rm=TRUE)),by=.(ym,Ticker)];rm(IND);gc(verbose=FALSE)
SIGM<-data.table(Date=sort(unique(E$Date)))[,ym:=format(Date,"%Y-%m")]
INM<-merge(INM,SIGM,by="ym")[,ym:=NULL];INM<-merge(INM,SIZE,by=c("Date","Ticker"))[is.finite(Size)&Size>0]
INM[,`:=`(nb_norm=nb/Size,lsz=log(Size))]
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];fit<-lm(x~1);as.numeric(coeftest(fit,vcov.=NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3])}
for (f in FILT) {
  D<-merge(FZ[F_==f,.(Date,Ticker,fz)],INM[,.(Date,Ticker,nb_norm,lsz)],by=c("Date","Ticker"))
  s<-D[,{ok<-is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)
    if(sum(ok)>=30L){yz<-(nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok]);xz<-(fz[ok]-mean(fz[ok]))/sd(fz[ok]);sz<-(lsz[ok]-mean(lsz[ok]))/sd(lsz[ok])
      yr<-qnorm((frank(nb_norm[ok])-0.5)/sum(ok)); xr<-qnorm((frank(fz[ok])-0.5)/sum(ok)); sr<-qnorm((frank(lsz[ok])-0.5)/sum(ok))
      szd<-cut(frank(lsz[ok]),breaks=10,labels=FALSE)
      .(b_ctl=unname(coef(lm(yz~xz+sz))[2]),
        b_raw=unname(coef(lm(yz~xz))[2]),
        b_quad=unname(coef(lm(yz~xz+sz+I(sz^2)+I(sz^3)))[2]),
        b_fe=unname(coef(lm(yz~xz+factor(szd)))[2]),
        b_rank=unname(coef(lm(yr~xr+sr))[2]),
        n=sum(ok))} else .(b_ctl=NA_real_,b_raw=NA_real_,b_quad=NA_real_,b_fe=NA_real_,b_rank=NA_real_,n=sum(ok))},by=Date][is.finite(b_ctl)]
  say("%s  n_mo=%d n_avg=%.1f", f, nrow(s), mean(s$n))
  for (v in c("b_raw","b_ctl","b_quad","b_fe","b_rank"))
    say("   %-7s mean=%+.4f  NW3 t=%+.2f  NW12 t=%+.2f  iid t=%+.2f",
        v, mean(s[[v]]), nw_t(s[[v]],3L), nw_t(s[[v]],12L), mean(s[[v]])/(sd(s[[v]])/sqrt(nrow(s))))
  ac<-acf(s$b_ctl,lag.max=24,plot=FALSE)$acf[,,1]
  say("   ACF(b_ctl) rho1=%.3f rho3=%.3f rho6=%.3f rho12=%.3f rho24=%.3f", ac[2],ac[4],ac[7],ac[13],ac[25])
  say("   sign(b_ctl<0) months = %.3f", mean(s$b_ctl<0))
}
