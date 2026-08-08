suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
IN9<-"stage_artifacts/WT_D20260802_009"; OUT<-"stage_artifacts/WT_D20260808_001"
say<-function(f,...)cat(sprintf(paste0("[v] ",f,"\n"),...))
BASE<-as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED<-as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW<-as.data.table(read_parquet(".cache/RAWDATA.parquet",col_select=c("Date","Ticker","K200","KQ150")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")];MEND<-sort(RAW[,.(Date=max(Date)),by=ym]$Date);RAWME<-RAW[Date%in%MEND];rm(RAW);gc(verbose=FALSE)
UNIV<-RAWME[(K200==TRUE|KQ150==TRUE),.(Date,Ticker)]
fwd<-readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
score_of<-function(f){sc<-if(f %in% BASE$Factor_Name)BASE[Factor_Name==f,.(Date,Ticker,score=z)] else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]
  merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
FILT<-c("D03_EWMA","Q01_EB")
E<-merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE);E<-E[is.na(adv)|adv>=2e8][,adv:=NULL]
E<-E[Date %in% returns_dt$Date]
FZe<-rbindlist(lapply(FILT,function(f)score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZe<-merge(FZe,E[,.(Date,Ticker)],by=c("Date","Ticker"));FZe[,q_rank:=frank(fz)/.N,by=.(Date,F_)]
# 비제한(TUNED 전체) 판
FZa<-rbindlist(lapply(FILT,function(f)TUNED[Factor_Name==f&!is.na(score),.(Date,Ticker,fz=score,F_=f)]))
FZa[,q_rank:=frank(fz)/.N,by=.(Date,F_)]
BETA<-readRDS("stage_artifacts/wt001_verify/BETA.rds")
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];fit<-lm(x~1);as.numeric(coeftest(fit,vcov.=NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3])}
say("== A 정의 민감도 (Q5 β vs 유니버스 중앙) ==")
for (f in FILT) for (tag in c("eligible","all_tuned")) {
  FZx <- if (tag=="eligible") FZe else FZa
  D<-merge(FZx[F_==f,.(Date,Ticker,q_rank)],BETA,by=c("Date","Ticker"))
  s<-D[,.(b_top=median(beta[q_rank>0.8]),b_med=median(beta)),by=Date][is.finite(b_top)&is.finite(b_med)]
  pooled_top<-median(D[q_rank>0.8]$beta); pooled_med<-median(D$beta)
  say("%-9s %-9s | 월별중앙평균: top %.3f univ %.3f diff %+.3f (NW3 t %+.2f, NW36 t %+.2f) | 풀드: top %.3f univ %.3f diff %+.3f | n_mo=%d n_row=%d",
      f,tag,mean(s$b_top),mean(s$b_med),mean(s$b_top-s$b_med),nw_t(s$b_top-s$b_med,3L),nw_t(s$b_top-s$b_med,36L),
      pooled_top,pooled_med,pooled_top-pooled_med,nrow(s),nrow(D))
}
say("== B 분위 평균/왜도 + Q5-Q1 검정 ==")
for (f in c("D03_EWMA","Q01_EB","M01_PATHQ")) {
  sc <- if (f=="M01_PATHQ") E[,.(Date,Ticker,score)] else FZe[F_==f,.(Date,Ticker,score=fz)]
  D<-merge(sc,returns_dt,by=c("Date","Ticker"))
  mono<-D[,{q<-cut(frank(score),breaks=5,labels=FALSE)
    .(m1=mean(Ret_1m[q==1],na.rm=TRUE),m2=mean(Ret_1m[q==2],na.rm=TRUE),m3=mean(Ret_1m[q==3],na.rm=TRUE),
      m4=mean(Ret_1m[q==4],na.rm=TRUE),m5=mean(Ret_1m[q==5],na.rm=TRUE),
      md1=median(Ret_1m[q==1],na.rm=TRUE),md5=median(Ret_1m[q==5],na.rm=TRUE))},by=Date]
  qm<-sapply(paste0("m",1:5),function(k)mean(mono[[k]],na.rm=TRUE))
  say("%-10s 분위평균연 %s  mono=%.2f", f, paste(sprintf("%+.1f",100*12*qm),collapse=" "), mean(diff(qm)>0))
  d51<-mono$m5-mono$m1
  say("   Q5-Q1 연 %+.2f%%  NW3 t=%+.2f | Q5-Q4 %+.2f t=%+.2f | Q2-Q1 %+.2f t=%+.2f",
      100*12*mean(d51,na.rm=TRUE),nw_t(d51),100*12*mean(mono$m5-mono$m4,na.rm=TRUE),nw_t(mono$m5-mono$m4),
      100*12*mean(mono$m2-mono$m1,na.rm=TRUE),nw_t(mono$m2-mono$m1))
  dmed<-mono$md5-mono$md1
  say("   [중앙값판] Q5-Q1 median-of-month 연 %+.2f%% NW3 t=%+.2f", 100*12*mean(dmed,na.rm=TRUE), nw_t(dmed))
  # 왜도: 분위별 풀드 skewness
  D[,q:=cut(frank(score),breaks=5,labels=FALSE),by=Date]
  sk<-D[,.(skew=mean((Ret_1m-mean(Ret_1m,na.rm=TRUE))^3,na.rm=TRUE)/sd(Ret_1m,na.rm=TRUE)^3,
           sdv=sd(Ret_1m,na.rm=TRUE),mn=mean(Ret_1m,na.rm=TRUE),mdn=median(Ret_1m,na.rm=TRUE),n=.N),by=q][order(q)]
  print(sk)
}
