## run_mfro_r55b.R — R55b: 짝 맞춘 상한(P_B) + 지수→종목꼬리 전이 진단
## ★사전등록 결함 정정: prereg 의 P_oracle 은 A(선택+비중)의 oracle 이라 헤드라인 B(비중만)와 짝이 안 맞았다.
##   상한은 반드시 **같은 형태**로 재야 한다 — 아니면 '실현이 완전예지를 이긴다' 는 가짜 모순이 생긴다.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
UB<-0.20; LAMBDA<-1.5; N_TARGET<-25L; LIQ<-2e8
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney"); NF<-length(FK)
P<-P[is.finite(adv20)&adv20>=LIQ]; setorder(P,ym); YM<-sort(unique(P$ym)); NM<-length(YM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym); NI<-nrow(mi)
S<-matrix(NA_real_,NI,NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF) for(m in 12:NI) S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
FA<-matrix(NA_real_,NI,NF);dimnames(FA)<-list(mi$ym,FK)
for(j in 1:NF) FA[1:(NI-1),j]<-(mi[[FK[j]]][-1]-mi$Market[-1])
winners<-function(y,k=5L,oracle=FALSE){ if(length(y)!=1L||is.na(y))return(character(0))
  r<-match(y,rownames(S)); if(is.na(r))return(character(0))
  s<-if(oracle) FA[r,] else S[r,]; pos<-which(is.finite(s)&s>0); if(!length(pos))return(character(0))
  FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]] }
zmean<-function(D,cols){if(!length(cols))return(rep(NA_real_,nrow(D)));rowMeans(as.matrix(D[,cols,with=FALSE]),na.rm=TRUE)}
run_arm<-function(mode,oracle=FALSE,k=5L,bps=15,dec_lag=1L){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wprev<-NULL
  for(m in seq_len(NM)){ d<-m-dec_lag; if(d<1)next
    D<-P[ym==YM[m]]; if(nrow(D)<N_TARGET)next
    wk<-winners(YM[d],k,oracle); if(!length(wk)) wk<-FK
    base_s<-zmean(D,FK)
    if(mode=="weight_only"){o<-order(-base_s);idx<-o[seq_len(N_TARGET)];w<-.tilt(zmean(D,wk)[idx])}
    else {rs<-zmean(D,wk);o<-order(-rs);idx<-o[seq_len(N_TARGET)];w<-.tilt(rs[idx])}
    tk<-D$Ticker[idx];names(w)<-tk
    allt<-union(names(wprev),tk);a<-setNames(rep(0,length(allt)),allt);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev; b[tk]<-w
    dlt<-sum(abs(b-a));tov[m]<-dlt
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dlt
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov)}
bm<-mi$Market[match(YM,mi$ym)]; bmf<-c(bm[-1],NA_real_)
E<-list(full=rep(TRUE,NM),clean=YM>="2015-07")
cat("=== R55b: 짝 맞춘 상한 ===\n")
AR<-list(B_realized=run_arm("weight_only",FALSE), B_oracle=run_arm("weight_only",TRUE),
         A_realized=run_arm("sel_weight",FALSE),  A_oracle=run_arm("sel_weight",TRUE))
for(n in names(AR)) for(w in c("full","clean")){r<-AR[[n]];s<-E[[w]]&is.finite(r$pr)&is.finite(bmf)
  cat(sprintf("  %-12s [%-5s] IR=%+.3f pt=%+.3f\n",n,w,IRf((r$pr-bmf)[s]),nwt((r$pr-bmf)[s])))}
cat("\n[★짝 맞춘 대응표본 — oracle 이 realized 를 이기는가]\n")
for(f in c("B","A")) for(w in c("full","clean")){
  x<-AR[[paste0(f,"_oracle")]]$pr; y<-AR[[paste0(f,"_realized")]]$pr
  s<-E[[w]]&is.finite(x)&is.finite(y); d<-(x-y)[s]
  cat(sprintf("  %s_oracle - %s_realized  %-5s mean=%+.4f%%/월 NW-t=%+.3f  %s\n",f,f,w,100*mean(d),nwt(d),
    ifelse(mean(d)>0,"(정상: 완전예지 우위)","★역전: 완전예지가 더 나쁨")))}

cat("\n=== 전이 진단: 지수 active 가 '그 팩터 극단꼬리 25종' 수익을 예측하나 ===\n")
## 각 팩터 j, 각 월: top-25 by z_j (동일 제약 tilt) 의 익월 active vs 그 팩터 지수의 익월 active
TT<-list()
for(j in 1:NF){ f<-FK[j]; v1<-v2<-rep(NA_real_,NM)
  for(m in seq_len(NM)){ D<-P[ym==YM[m]]; if(nrow(D)<N_TARGET)next
    z<-D[[f]]; if(sum(is.finite(z))<N_TARGET)next
    o<-order(-z);idx<-o[seq_len(N_TARGET)];w<-.tilt(z[idx])
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    r<-match(YM[m],rownames(FA)); if(is.na(r))next
    v1[m]<-sum(w*fr)-bmf[m]     # 종목 꼬리 25종 active
    v2[m]<-FA[r,j] }            # 지수 active
  TT[[f]]<-data.table(ym=YM,tail_act=v1,idx_act=v2) }
D2<-rbindlist(TT,idcol="factor")
for(w in c("full","clean")){ s<-if(w=="full") rep(TRUE,nrow(D2)) else D2$ym>="2015-07"
  x<-D2[s&is.finite(tail_act)&is.finite(idx_act)]
  cc<-cor(x$tail_act,x$idx_act)
  bycol<-x[,.(rho=cor(tail_act,idx_act),n=.N),by=factor]
  cat(sprintf("  [%-5s] 전체 상관 rho=%+.4f (n=%d) | 팩터별 rho: 중앙 %+.3f · 양수 %d/%d · 범위 %+.3f~%+.3f\n",
    w,cc,nrow(x),median(bycol$rho),sum(bycol$rho>0),nrow(bycol),min(bycol$rho),max(bycol$rho)))
  ## 지수 active 부호가 꼬리 active 부호를 맞히는 비율
  cat(sprintf("           부호 일치율 %.1f%% (무정보=50%%) | 평균 꼬리 active %+.3f%%/월 vs 지수 %+.3f%%/월\n",
    100*mean(sign(x$tail_act)==sign(x$idx_act)),100*mean(x$tail_act),100*mean(x$idx_act))) }
saveRDS(list(AR=AR,D2=D2,YM=YM,E=E,bmf=bmf),".cache/_mfro_r55b.rds")
cat("\nR55B_DONE\n")
