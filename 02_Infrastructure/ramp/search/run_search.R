## run_search.R — 8-구성요소 config 평가 엔진 (도훈 goal). 캐시 1회로드 → config grid 배치 평가.
## env SEARCH_BATCH="start-end" (config index, 0-based). 결과 .cache/_search_res_<start>_<end>.csv
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
C<-readRDS(".cache/_search_cache.rds"); FN<-C$FN; dts<-C$dts; ND<-C$ND; ACT<-C$ACT; IC<-C$IC; SIG<-C$SIG
fwd_ret<-C$fwd_ret; bench<-C$bench; liq<-C$liq; UNI<-C$UNI; book<-C$book
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
csna<-function(x){x[!is.finite(x)]<-0;cumsum(x)}; lagv<-function(x)c(NA,x[-length(x)])

## 표준화 z 행렬 미리계산: 월별 Ticker×F (zc per factor)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
ZC<-vector("list",ND)
for(i in seq_len(ND)){fw<-C$ZL[[as.character(dts[i])]];M<-matrix(0,nrow(fw),length(FN),dimnames=list(fw$Ticker,FN))
  for(j in seq_along(FN)){id<-C$FAC[FN[j]];if(id%in%names(fw)){z<-zc(fw[[id]]);z[!is.finite(z)]<-0;M[,j]<-z}};ZC[[i]]<-M}

## 팩터 유니버스 정의
SURV<-c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M24_SectorRelMom","M01_Mom121","M08_ResidMom","M14_RiskAdjMom","C04_ESBR","C19_CompEarn")
UNIVS<-list(all24=FN, survivors=SURV, mom_cons=c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M01_Mom121","M08_ResidMom","C04_ESBR","C19_CompEarn"),
  mom_only=c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M24_SectorRelMom","M01_Mom121","M08_ResidMom"))

## 국면 membership (config: regime, tau, nstate)
membership<-function(regime,tau){ a3<-c(-1,0,1)/tau; a2<-c(-1,1)/tau
  sm<-function(z,a)t(sapply(z,function(zz){e<-exp(a*zz);e/sum(e)}))
  if(regime=="none")return(matrix(1,ND,1))
  if(regime=="cascade_vol2d"){Mc<-sm(SIG$cascade,a3);Mv<-sm(SIG$vol,a2);M<-matrix(0,ND,6);for(i in 1:ND)M[i,]<-as.numeric(outer(Mc[i,],Mv[i,]));return(M)}
  s<-switch(regime,cascade=SIG$cascade,msm=SIG$msm,mrs9=SIG$mrs9,vol=SIG$vol,trend=SIG$trend,SIG$cascade); sm(s,a3) }

## 국면조건부 가중 W (perf: active|ic|ir, shrink, window, mombase) — cumsum 최적
build_W<-function(MEM,perf,shrink,window,mombase,fidx){NS<-ncol(MEM);Fn<-length(fidx);W<-matrix(0,ND,Fn)
  PV<-if(perf=="ic")IC[,fidx,drop=FALSE] else ACT[,fidx,drop=FALSE]  # ir도 ACT 기반
  for(s in 1:NS){ms<-MEM[,s]
    for(jj in seq_len(Fn)){pv<-PV[,jj]; fin<-is.finite(pv)
      if(window=="full"){ ws<-lagv(csna(ms*ifelse(fin,pv,0)));wc<-lagv(csna(ms*fin));fs<-lagv(csna(ifelse(fin,pv,0)));fc<-lagv(csna(fin))
        if(perf=="ir"){ws2<-lagv(csna(ms*ifelse(fin,pv^2,0)))}
      }else{ Wd<-60;rs<-function(x){y<-rep(NA_real_,ND);cx<-csna(x);for(i in 1:ND){lo<-max(0,i-Wd);y[i]<-cx[i]-(if(lo>0)cx[lo] else 0)};lagv(y)}
        ws<-rs(ms*ifelse(fin,pv,0));wc<-rs(ms*fin);fs<-rs(ifelse(fin,pv,0));fc<-rs(fin);if(perf=="ir")ws2<-rs(ms*ifelse(fin,pv^2,0))}
      Cstate<-ws/pmax(wc,1e-9);Cfull<-fs/pmax(fc,1e-9);neff<-wc
      if(perf=="ir"){v<-ws2/pmax(wc,1e-9)-Cstate^2;sdv<-sqrt(pmax(v,1e-8));Cstate<-Cstate/sdv}  # 위험조정
      lam<-shrink/(neff+shrink);lam[!is.finite(lam)]<-1;Csh<-(1-lam)*Cstate+lam*Cfull;Csh[!is.finite(Csh)]<-0
      W[,jj]<-W[,jj]+ms*pmax(Csh,0)} }
  W[1:36,]<-1  # 초기 균등
  if(mombase>0){momcols<-which(grepl("^M0|^M1|^M3",fidxnames(fidx)));base<-apply(W,1,function(r)max(sum(r),1e-9));for(mc in momcols)W[,mc]<-W[,mc]+mombase*base/max(length(momcols),1)}
  W}
fidxnames<-function(fidx)FN[fidx]

## config 평가 → 메트릭
eval_cfg<-function(cfg){fidx<-match(UNIVS[[cfg$univ]],FN);fidx<-fidx[!is.na(fidx)]
  MEM<-membership(cfg$regime,cfg$tau);W<-build_W(MEM,cfg$perf,cfg$shrink,cfg$window,cfg$mombase,fidx)
  rows<-vector("list",ND)
  for(i in seq_len(ND)){wf<-W[i,];if(sum(wf)<1e-9)wf<-rep(1,length(fidx));wf<-wf/sum(wf)
    X<-ZC[[i]][,fidx,drop=FALSE];sc<-as.numeric(X%*%wf);rows[[i]]<-data.table(Date=dts[i],Ticker=rownames(ZC[[i]]),score=sc)}
  SC<-merge(rbindlist(rows),UNI,by=c("Date","Ticker"))
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="s",strategy_id="s"),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  data.table(pt_full=nwt(act),pt_IS=nwt(act[1:k]),pt_OOS=nwt(act[(k+1):n]),oos_ret=oosr(act),calmar=cagr/abs(mdd),SR=IRf(pr$ret_net),IR=IRf(act),TO=cs$turnover_annual)}

## grid 생성 (deterministic)
grid<-CJ(regime=c("cascade","msm","mrs9","vol","trend","cascade_vol2d","none"),tau=c(0.5,1,2),perf=c("active","ic","ir"),
  shrink=c(0,4,16),univ=c("all24","survivors","mom_cons","mom_only"),window=c("full","recent"),mombase=c(0,0.4),sorted=FALSE)
ba<-strsplit(Sys.getenv("SEARCH_BATCH","0-20"),"-")[[1]];s0<-as.integer(ba[1]);s1<-min(as.integer(ba[2]),nrow(grid)-1)
out<-list();for(gi in s0:s1){cfg<-as.list(grid[gi+1]);r<-tryCatch(eval_cfg(cfg),error=function(e)NULL)
  if(!is.null(r)){r[,`:=`(idx=gi,regime=cfg$regime,tau=cfg$tau,perf=cfg$perf,shrink=cfg$shrink,univ=cfg$univ,window=cfg$window,mombase=cfg$mombase)];out[[length(out)+1]]<-r}}
RES<-rbindlist(out,fill=TRUE);fwrite(RES,sprintf(".cache/_search_res_%d_%d.csv",s0,s1));cat(sprintf("BATCH %d-%d done: %d configs, grid_total=%d\n",s0,s1,nrow(RES),nrow(grid)))
