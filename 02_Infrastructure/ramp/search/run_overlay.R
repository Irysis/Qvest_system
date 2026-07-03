## run_overlay.R — base selection(grid 승자) + regime 디리스크 오버레이 (Book의 M4/AR/R05식). 25종목·PIT 유지.
## 오버레이: 위험국면서 exposure 축소(현금) → 폭락월 active(port−market) 양수화 → pt↑. lagged 1(PIT). 15bps net.
suppressPackageStartupMessages({library(data.table)}); setDTthreads(1); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
C<-readRDS(".cache/_search_cache.rds");FN<-C$FN;dts<-C$dts;ND<-C$ND;ACT<-C$ACT;IC<-C$IC;SIG<-C$SIG;fwd_ret<-C$fwd_ret;bench<-C$bench;liq<-C$liq;UNI<-C$UNI;book<-C$book
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
csna<-function(x){x[!is.finite(x)]<-0;cumsum(x)};lagv<-function(x)c(NA,x[-length(x)]);zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
ZC<-vector("list",ND);for(i in seq_len(ND)){fw<-C$ZL[[as.character(dts[i])]];M<-matrix(0,nrow(fw),length(FN),dimnames=list(fw$Ticker,FN));for(j in seq_along(FN)){id<-C$FAC[FN[j]];if(id%in%names(fw)){z<-zc(fw[[id]]);z[!is.finite(z)]<-0;M[,j]<-z}};ZC[[i]]<-M}
UNIVS<-list(all24=FN,mom_cons=c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M01_Mom121","M08_ResidMom","C04_ESBR","C19_CompEarn"))
membership<-function(regime,tau){a3<-c(-1,0,1)/tau;sm<-function(z,a)t(sapply(z,function(zz){e<-exp(a*zz);e/sum(e)}));if(regime=="none")return(matrix(1,ND,1));s<-switch(regime,trend=SIG$trend,cascade=SIG$cascade,vol=SIG$vol,SIG$trend);sm(s,a3)}
build_W<-function(MEM,perf,shrink,fidx){NS<-ncol(MEM);Fn<-length(fidx);W<-matrix(0,ND,Fn);PV<-if(perf=="ic")IC[,fidx,drop=FALSE] else ACT[,fidx,drop=FALSE]
  for(s in 1:NS){ms<-MEM[,s];for(jj in seq_len(Fn)){pv<-PV[,jj];fin<-is.finite(pv);ws<-lagv(csna(ms*ifelse(fin,pv,0)));wc<-lagv(csna(ms*fin));fs<-lagv(csna(ifelse(fin,pv,0)));fc<-lagv(csna(fin))
    Cstate<-ws/pmax(wc,1e-9);Cfull<-fs/pmax(fc,1e-9);lam<-shrink/(wc+shrink);lam[!is.finite(lam)]<-1;Csh<-(1-lam)*Cstate+lam*Cfull;Csh[!is.finite(Csh)]<-0;W[,jj]<-W[,jj]+ms*pmax(Csh,0)}}
  W[1:36,]<-1;W}
base_pr<-function(regime,tau,perf,shrink,univ){fidx<-match(UNIVS[[univ]],FN);fidx<-fidx[!is.na(fidx)];MEM<-membership(regime,tau);W<-build_W(MEM,perf,shrink,fidx)
  rows<-vector("list",ND);for(i in seq_len(ND)){wf<-W[i,];if(sum(wf)<1e-9)wf<-rep(1,length(fidx));wf<-wf/sum(wf);X<-ZC[[i]][,fidx,drop=FALSE];rows[[i]]<-data.table(Date=dts[i],Ticker=rownames(ZC[[i]]),score=as.numeric(X%*%wf))}
  SC<-merge(rbindlist(rows),UNI,by=c("Date","Ticker"));cs<-canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="b",strategy_id="b")
  as.data.table(cs$period_returns)}
metr<-function(pr){setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  data.table(pt=nwt(act),IR=IRf(act),SR=IRf(pr$ret_net),calmar=cagr/abs(mdd),oos_ret=oosr(act),CAGR=cagr,MDD=mdd)}

## base (grid robust 승자: trend/tau2/ic/shrink16/mom_cons)
pr<-base_pr("trend",2,"ic",16,"mom_cons"); prm<-merge(pr,data.table(date=dts,trend=SIG$trend,cascade=SIG$cascade,vol=SIG$vol,msm=SIG$msm),by="date",all.x=TRUE);setorder(prm,date)
cat("=== base (no overlay) ===\n");print(metr(copy(pr)))

## 오버레이 sweep: risk signal × depth. exposure e=clamp(1−depth·pnorm(risk_z),1−depth,1) lagged.
ov<-function(prm,sigcol,sign,depth){r<-sign*prm[[sigcol]];e<-pmax(1-depth*pnorm(r),1-depth);e<-c(1,e[-length(e)]) # lag1 PIT
  pr2<-copy(prm);pr2[,ret_net:=e*ret_net];pr2[,.(date,ret_net,benchmark_ret)]}
cat("\n=== regime 디리스크 오버레이 sweep (base trend/ic/mom_cons, pt비교) ===\n")
cat(sprintf("  %-18s %5s | %6s %6s %6s %7s %7s %7s %7s\n","overlay","depth","pt","IR","SR","calmar","oos_ret","CAGR","MDD"))
best<-NULL
for(cfg in list(c("msm","1"),c("vol","1"),c("cascade","-1"),c("trend","-1"))){sc<-cfg[1];sg<-as.numeric(cfg[2])
  for(dp in c(0.3,0.5,0.7)){m<-metr(ov(prm,sc,sg,dp));m[,`:=`(sig=sc,depth=dp)];cat(sprintf("  %-18s %5.1f | %6.2f %6.2f %6.2f %7.2f %7.2f %7.3f %7.3f\n",sprintf("%s%s",sc,ifelse(sg<0,"(neg)","")),dp,m$pt,m$IR,m$SR,m$calmar,m$oos_ret,m$CAGR,m$MDD))
    if(is.null(best)||(!is.na(m$pt)&&m$pt>best$pt))best<-m}}
cat(sprintf("\nBook target: pt 5.0(gross) SR 1.57-1.80 calmar 1.16-1.79\n최강 오버레이: sig=%s depth=%.1f pt=%.2f SR=%.2f calmar=%.2f\n",best$sig,best$depth,best$pt,best$SR,best$calmar))
saveRDS(list(prm=prm,best=best),".cache/_overlay.rds");cat("OVERLAY_DONE\n")
