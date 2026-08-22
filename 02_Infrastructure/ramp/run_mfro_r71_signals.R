## run_mfro_r71_signals.R — R71: 신호 교체 1차 (prereg mfro_v10)
## ★표적을 '지수 수익' 에서 '예측력' 으로. 보유·가중·비용·창 전부 고정, 승자 선정 신호만 교체.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8;KW<-5L
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a){z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+LAMBDA*z/length(a))
  if(sum(w)>0)w<-w/sum(w);.norm(w)}
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
setorder(mi,ym);bm<-mi$Market[match(YM,mi$ym)];bmf<-c(bm[-1],NA_real_);CLEAN<-YM>="2015-07"

cat("[월별 원재료 산출 — rank-IC · 분산]\n")
IC<-matrix(NA_real_,NM,NF); DP<-matrix(NA_real_,NM,NF)
dimnames(IC)<-dimnames(DP)<-list(YM,FK)
for(m in seq_len(NM)){D<-P[ym==YM[m]]; fr<-D$fwd_ret
  for(j in 1:NF){z<-D[[FK[j]]]; ok<-is.finite(z)&is.finite(fr)
    if(sum(ok)>=30L) IC[m,j]<-cor(rank(z[ok]),rank(fr[ok]))
    zz<-z[is.finite(z)]; if(length(zz)>=30L) DP[m,j]<-sd(zz)}}
cat(sprintf("  rank-IC 유효 셀 %.1f%% · 분산 유효 %.1f%%\n",
  100*mean(is.finite(IC)),100*mean(is.finite(DP))))

## ── 신호 행렬 (전부 결정월 d 까지의 trailing 12M, 미래 미사용) ──
mkS<-function(kind){
  S<-matrix(NA_real_,NM,NF); dimnames(S)<-list(YM,FK)
  ri<-match(YM,mi$ym)
  for(j in 1:NF)for(d in 13:NM){
    if(kind=="S0"||kind=="S3"){r<-ri[d]; if(is.na(r)||r<12) next
      a<-mi[[FK[j]]][(r-11):r]; b<-mi$Market[(r-11):r]
      if(sum(is.finite(a))<10) next
      act<-a-b
      S[d,j]<-if(kind=="S0") prod(1+a)/prod(1+b)-1 else {sdv<-sd(act,na.rm=TRUE)
        if(!is.finite(sdv)||sdv<=0) NA_real_ else mean(act,na.rm=TRUE)/sdv}}
    else if(kind=="S1"){v<-IC[(d-12):(d-1),j];v<-v[is.finite(v)]
      if(length(v)>=8) S[d,j]<-mean(v)}
    else {v<-DP[(d-12):(d-1),j];v<-v[is.finite(v)]
      if(length(v)>=8) S[d,j]<-mean(v)}}
  S}

## ★S2(분산)는 부호가 '클수록 좋다' 이나 0 초과가 항상 참이므로 양(+)풀 정의를 바꾼다:
##   중앙값 초과를 '양(+)' 으로 본다. 다른 신호는 0 초과.
poolf<-function(S,d,kind){s<-S[d,]
  thr<-if(kind=="S2") median(s,na.rm=TRUE) else 0
  p<-which(is.finite(s)&s>thr); if(!length(p)) NULL else list(s=s,pos=p)}

contrib<-function(S,kind,seed=NA){
  pt<-rep(NA_real_,NM);pa<-rep(NA_real_,NM);w1<-NULL;w2<-NULL;npool<-c()
  for(m in 2:NM){d<-m-1L; p0<-poolf(S,d,kind); if(is.null(p0))next
    npool<-c(npool,length(p0$pos))
    D<-P[ym==YM[m]];if(nrow(D)<N_TARGET+5L)next
    wtop<-if(is.na(seed))FK[p0$pos[order(p0$s[p0$pos],decreasing=TRUE)][seq_len(min(KW,length(p0$pos)))]]
          else{set.seed(seed*1000L+m);FK[sample(p0$pos,min(KW,length(p0$pos)))]}
    wall<-FK[p0$pos];idx<-order(-D$mktcap)[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    for(a in 1:2){wk<-if(a==1)wtop else wall
      w<-.tilt(neut(zmean(D,wk)[idx]));names(w)<-tk;wp<-if(a==1)w1 else w2
      at<-union(names(wp),tk);x<-setNames(rep(0,length(at)),at);y<-x
      if(!is.null(wp))x[names(wp)]<-wp;y[tk]<-w
      v<-sum(w*fr)-(15/1e4)*sum(abs(y-x))
      if(a==1)pt[m]<-v else pa[m]<-v
      wd<-w*(1+fr);if(a==1)w1<-wd/sum(wd) else w2<-wd/sum(wd)}}
  s<-CLEAN&is.finite(pt)&is.finite(pa)
  list(d=(pt-pa)[s], npool=mean(npool,na.rm=TRUE))}

SIG<-c(S0="S0_index_active",S1="S1_rank_ic",S2="S2_dispersion",S3="S3_vol_adj_mom")
cat("\n=== R71 신호 후보 (보유·가중·창 고정) ===\n")
cat(sprintf("  %-18s %8s %6s %11s %9s %9s\n","signal","양(+)풀","n","평균%/월","NW-t","permB p"))
OUT<-list()
for(k in names(SIG)){S<-mkS(k); r<-contrib(S,k)
  PM<-sapply(1:150,function(s_)mean(contrib(S,k,seed=s_)$d)); pv<-mean(PM>=mean(r$d))
  OUT[[k]]<-list(mean=mean(r$d),t=nwt(r$d),p=pv,n=length(r$d),npool=r$npool)
  cat(sprintf("  %-18s %8.1f %6d %+11.4f %+9.3f %9.3f %s\n",SIG[k],r$npool,length(r$d),
    100*mean(r$d),nwt(r$d),pv,ifelse(pv<0.05,"★밖","안")))}

cat("\n=== 사전등록 문턱: 효과 2배 이상 AND permB p<0.05 ===\n")
b<-OUT$S0
for(k in c("S1","S2","S3")){o<-OUT[[k]]
  ratio<-o$mean/b$mean
  ok<-(ratio>=2)&&(o$p<0.05)
  cat(sprintf("  %-18s 효과 배수 %+.2fx (기준 %+.4f%%/월) · permB p %.3f ⇒ %s\n",
    SIG[k],ratio,100*b$mean,o$p,ifelse(ok,"★통과 — 독립 확인 라운드로","미달")))}
np<-sum(sapply(c("S1","S2","S3"),function(k)(OUT[[k]]$mean/b$mean>=2)&&(OUT[[k]]$p<0.05)))
cat(sprintf("\n  통과 %d/3 ⇒ %s\n",np,ifelse(np==0,
  "★전 후보 미달 — '팩터 지수/패널 파생 신호 계열' 로는 2배 도달 불가. 남는 것은 별도 데이터 원천",
  "통과 후보 존재 — 본 라운드 채택 금지, 독립 확인 라운드 사전등록")))

cat("\n[대응표본 vs S0]\n")
for(k in c("S1","S2","S3")){S<-mkS(k);r<-contrib(S,k);S0<-mkS("S0");r0<-contrib(S0,"S0")
  n<-min(length(r$d),length(r0$d)); dd<-r$d[1:n]-r0$d[1:n]
  cat(sprintf("  %-18s mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(SIG[k]," - S0"),100*mean(dd),nwt(dd)))}
saveRDS(list(OUT=OUT,IC=IC,DP=DP),".cache/_mfro_r71.rds")
cat("\nR71_DONE\n")
