## run_mfro_r59_stability.R — R59: 신호 안정화 (prereg mfro_v4, chain of mfro_v3)
## ★1급 판정지표 = lag 격자 평탄도. 성과 헤드라인 금지(사전등록 binding_constraint).
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8;KW<-5L
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
zmean<-function(D,cols){v<-rowMeans(as.matrix(D[,cols,with=FALSE]),na.rm=TRUE);v[!is.finite(v)]<-NA_real_;v}
neut<-function(v){bad<-!is.finite(v);if(all(bad))return(rep(0,length(v)));v[bad]<-mean(v[!bad]);v}

P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney");NF<-length(FK)
P<-P[is.finite(adv20)&adv20>=LIQ];setorder(P,ym);YM<-sort(unique(P$ym));NM<-length(YM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym);bm<-mi$Market[match(YM,mi$ym)];bmf<-c(bm[-1],NA_real_)
E<-list(full=rep(TRUE,NM),clean=YM>="2015-07")

## 신호 행렬: 12M 과 24M trailing active. 행 = YM 축으로 정렬해 lag 인덱싱을 단순화.
mkS<-function(win){M<-matrix(NA_real_,NM,NF);dimnames(M)<-list(YM,FK)
  ri<-match(YM,mi$ym)
  for(j in 1:NF)for(i in seq_len(NM)){r<-ri[i];if(is.na(r)||r<win)next
    M[i,j]<-prod(1+mi[[FK[j]]][(r-win+1):r])/prod(1+mi$Market[(r-win+1):r])-1}
  M}
S12<-mkS(12L); S24<-mkS(24L)
rank_of<-function(v){r<-rep(NA_real_,length(v));o<-is.finite(v);r[o]<-rank(v[o]);r}

## 승자 선정: arm 별
pick<-function(d,arm,prev=NULL){
  if(d<1||d>NM)return(character(0))
  s<-switch(arm,
    V0 = S12[d,],
    V4 = S24[d,],
    V1 = {r<-rowSums(sapply(0:2,function(g){dd<-d-g;if(dd<1)return(rep(NA_real_,NF));rank_of(S12[dd,])}),na.rm=TRUE)
          ifelse(r==0,NA_real_,r)},
    V3 = S12[d,],
    S12[d,])
  names(s)<-FK
  pos<-which(is.finite(s)&(if(arm=="V1") TRUE else s>0))
  if(!length(pos))return(character(0))
  ord<-FK[pos[order(s[pos],decreasing=TRUE)]]
  if(arm!="V3") return(head(ord,KW))
  ## V3 히스테리시스: 진입 top5, 이탈은 top8 밖
  keep<-intersect(prev, head(ord,8L))
  add<-setdiff(head(ord,KW), keep)
  head(c(keep,add),KW)}

runw<-function(arm,dec_lag=1L,bps=15){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wprev<-NULL;prevw<-character(0);nchg<-c()
  for(m in 2:NM){
    D<-P[ym==YM[m]];if(nrow(D)<50L)next
    oc<-order(-D$mktcap);idx<-oc[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    if(arm=="V2"){
      ws<-lapply(0:2,function(g){d<-m-1L-g;wk<-pick(d,"V0");if(!length(wk))wk<-FK
        .tilt(neut(zmean(D,wk)[idx]))})
      w<-Reduce(`+`,ws)/length(ws); w<-.norm(w/sum(w))
    } else {
      d<-m-dec_lag; wk<-pick(d,arm,prevw)
      if(!length(wk))wk<-FK
      nchg<-c(nchg, if(length(prevw)) 1-length(intersect(wk,prevw))/KW else NA_real_)
      prevw<-wk
      w<-.tilt(neut(zmean(D,wk)[idx]))}
    names(w)<-tk
    at<-union(names(wprev),tk);a<-setNames(rep(0,length(at)),at);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev;b[tk]<-w
    dl<-sum(abs(b-a));tov[m]<-dl
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dl
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov,winner_churn=mean(nchg,na.rm=TRUE))}

ir_clean<-function(p){s<-E$clean&is.finite(p)&is.finite(bmf);IRf((p-bmf)[s])}
ARMS<-c(V0="V0_baseline",V1="V1_rank_smooth",V2="V2_lag_ensemble",V3="V3_hysteresis",V4="V4_long_window")

cat("=== R59 신호 안정화 (prereg mfro_v4) ===\n")
cat("★1급 판정 = lag 격자 평탄도. 성과 헤드라인 금지.\n\n")
cat(sprintf("  %-18s %s   | %s\n","arm","lag0     lag1     lag2     lag3","flat_sd  mean_IR  t_adj   승자교체율"))
RES<-list()
for(a in names(ARMS)){
  v<-sapply(0:3,function(dl) ir_clean(runw(a,dec_lag=as.integer(dl))$pr))
  r1<-runw(a,dec_lag=1L);r2<-runw(a,dec_lag=2L)
  s<-E$clean&is.finite(r1$pr)&is.finite(r2$pr)
  tadj<-nwt((r1$pr-r2$pr)[s])
  RES[[a]]<-list(v=v,flat=sd(v),mean=mean(v),tadj=tadj,churn=r1$winner_churn)
  cat(sprintf("  %-18s %s   | %7.4f  %+7.4f  %+6.3f   %s\n",ARMS[a],
    paste(sprintf("%+8.3f",v),collapse=" "),sd(v),mean(v),tadj,
    ifelse(is.finite(r1$winner_churn),sprintf("%.3f",r1$winner_churn),"n/a")))}

cat("\n[★사전등록 판정 — V0 대비]\n")
b<-RES$V0
cat(sprintf("  기준 V0: flat_sd %.4f · mean_IR %+.4f · t_adj %+.3f\n",b$flat,b$mean,b$tadj))
for(a in setdiff(names(ARMS),"V0")){r<-RES[[a]]
  c1<-r$flat <= 0.7*b$flat; c2<-abs(r$tadj)<1.96; c3<-r$mean >= b$mean
  cat(sprintf("  %-18s ①flat_sd -%.0f%% %s  ②|t_adj|<1.96 %s  ③mean_IR %s  => %s\n",
    ARMS[a],100*(1-r$flat/b$flat),ifelse(c1,"PASS","FAIL"),ifelse(c2,"PASS","FAIL"),
    ifelse(c3,"PASS","FAIL"),ifelse(c1&&c2&&c3,"★통과","미통과")))}

cat("\n[전 셀 전수 — clean IR: arm x lag x cost]\n")
for(a in names(ARMS))for(bp in c(5,15,25)){
  v<-sapply(0:3,function(dl) ir_clean(runw(a,dec_lag=as.integer(dl),bps=bp)$pr))
  cat(sprintf("  %-18s %dbps  %s\n",ARMS[a],bp,paste(sprintf("%+8.3f",v),collapse=" ")))}

cat("\n[해석 주의 — 사전등록 expected_failure_mode 재확인]\n")
cat("  V2(다중 lag 앙상블)의 평탄도 감소는 기계적이다(lag0/1/2 평균 = lag 민감도가 정의상 축소).\n")
cat("  따라서 V2 의 ① 통과는 증거로 약하고 판정은 ③(수준 유지)에 달린다 — 결과 전에 못박은 대로.\n")
saveRDS(list(RES=RES,YM=YM,E=E,bmf=bmf),".cache/_mfro_r59.rds")
cat("\nR59_DONE\n")
