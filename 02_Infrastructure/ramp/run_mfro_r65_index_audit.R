## run_mfro_r65_index_audit.R — R65: 신호 원천 감사 (prereg mfro_v7)
## 무비용 지수가 고회전 팩터를 유리하게 만들어 R60 의 '랭킹 기여' 를 만든 것인가.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8;KW<-5L;TOPQ<-0.6667
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w)}
zmean<-function(D,cols){v<-rowMeans(as.matrix(D[,cols,with=FALSE]),na.rm=TRUE);v[!is.finite(v)]<-NA_real_;v}
neut<-function(v){bad<-!is.finite(v);if(all(bad))return(rep(0,length(v)));v[bad]<-mean(v[!bad]);v}

P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))   # ★유동성 미필터 = 지수 유니버스
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney");NF<-length(FK)
setorder(P,ym); YM<-sort(unique(P$ym)); NM<-length(YM)
cat(sprintf("[감사 대상] 월 %d · 팩터 %d · 월당 유니버스 중앙 %d (유동성 미필터)\n",
  NM,NF,as.integer(median(P[,.N,by=ym]$N))))

## ── ① 지수 멤버십 재구성 + 월별 회전율 + gross 수익 ──
##   빌더 정합: 상위 (1-TOPQ) 분위 이상, mktcap 가중, 익월 수익.
W<-vector("list",NF); names(W)<-FK          # 팩터별 월별 (Ticker, w)
GR<-matrix(NA_real_,NM,NF); dimnames(GR)<-list(YM,FK)   # gross 익월 수익
TO<-matrix(NA_real_,NM,NF); dimnames(TO)<-list(YM,FK)   # 회전율(L1, drift 보정)
prev<-vector("list",NF)
for(m in seq_len(NM)){D<-P[ym==YM[m]]
  fr<-D$fwd_ret; fr[!is.finite(fr)]<-0
  for(j in 1:NF){z<-D[[FK[j]]]; ok<-is.finite(z)&is.finite(D$mktcap)&D$mktcap>0
    if(sum(ok)<15L) next
    thr<-quantile(z[ok],TOPQ,na.rm=TRUE); sel<-which(ok & z>=thr)
    if(!length(sel)) next
    w<-D$mktcap[sel]/sum(D$mktcap[sel]); names(w)<-D$Ticker[sel]
    GR[m,j]<-sum(w*fr[sel])
    pv<-prev[[j]]
    if(!is.null(pv)){k<-union(names(pv),names(w))
      a<-setNames(rep(0,length(k)),k); b<-a; a[names(pv)]<-pv; b[names(w)]<-w
      TO[m,j]<-sum(abs(b-a))/2}                      # one-way
    ## drift: 이번 달 비중이 익월 수익으로 흘러간 상태를 다음 비교 기준으로
    wd<-w*(1+fr[sel]); prev[[j]]<-wd/sum(wd)}}
mkt<-{D<-NULL; sapply(seq_len(NM),function(m){D<-P[ym==YM[m]]
  ok<-is.finite(D$mktcap)&D$mktcap>0; fr<-D$fwd_ret; fr[!is.finite(fr)]<-0
  sum(D$mktcap[ok]*fr[ok])/sum(D$mktcap[ok])})}

cat("\n=== ① 팩터별 회전율 (one-way, 연환산) 과 gross active ===\n")
cat(sprintf("  %-14s %10s %12s %10s\n","factor","회전%/yr","gross act%/yr","유효월"))
TT<-data.table(factor=FK,
  to_yr=sapply(1:NF,function(j)100*12*mean(TO[,j],na.rm=TRUE)),
  act_yr=sapply(1:NF,function(j)100*12*mean(GR[,j]-mkt,na.rm=TRUE)),
  n=sapply(1:NF,function(j)sum(is.finite(GR[,j]))))
setorder(TT,-to_yr)
for(i in seq_len(nrow(TT))) cat(sprintf("  %-14s %10.1f %12.2f %10d\n",TT$factor[i],TT$to_yr[i],TT$act_yr[i],TT$n[i]))
rho1<-cor(TT$to_yr,TT$act_yr,method="spearman")
cat(sprintf("\n  ★진단1 — 회전율 vs gross active 순위상관 = %+.3f  %s\n",rho1,
  ifelse(rho1>0.3,"고회전이 유리(편향 기전 지지)",ifelse(rho1< -0.3,"고회전이 불리","관계 약함"))))

## ── ② 비용 부과 지수 + 신호 재구축 ──
mkS<-function(bps){NET<-GR-(bps/1e4)*TO; NET[!is.finite(NET)]<-GR[!is.finite(NET)]
  S<-matrix(NA_real_,NM,NF); dimnames(S)<-list(YM,FK)
  for(j in 1:NF)for(m in 13:NM){a<-NET[(m-12):(m-1),j]; b<-mkt[(m-12):(m-1)]
    if(sum(is.finite(a))<10) next
    a[!is.finite(a)]<-0; S[m,j]<-prod(1+a)/prod(1+b)-1}
  S}
CLEAN<-YM>="2015-07"
contrib<-function(S,seed=NA,k=KW){
  pt<-rep(NA_real_,NM); pa<-rep(NA_real_,NM); w1<-NULL; w2<-NULL
  for(m in 2:NM){d<-m-1L; if(d<1) next
    s<-S[d,]; pos<-which(is.finite(s)&s>0); if(!length(pos)) next
    D<-P[ym==YM[m]]; D<-D[is.finite(adv20)&adv20>=LIQ]; if(nrow(D)<N_TARGET+5L) next
    wtop<-if(is.na(seed)) FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]]
          else {set.seed(seed*1000L+m); FK[sample(pos,min(k,length(pos)))]}
    wall<-FK[pos]
    idx<-order(-D$mktcap)[seq_len(N_TARGET)]; tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx]; fr[!is.finite(fr)]<-0
    for(a in 1:2){wk<-if(a==1)wtop else wall
      w<-.tilt(neut(zmean(D,wk)[idx])); names(w)<-tk
      wp<-if(a==1)w1 else w2
      at<-union(names(wp),tk); x<-setNames(rep(0,length(at)),at); y<-x
      if(!is.null(wp))x[names(wp)]<-wp; y[tk]<-w
      v<-sum(w*fr)-(15/1e4)*sum(abs(y-x))
      if(a==1) pt[m]<-v else pa[m]<-v
      wd<-w*(1+fr); if(a==1) w1<-wd/sum(wd) else w2<-wd/sum(wd)}}
  s<-CLEAN&is.finite(pt)&is.finite(pa); (pt-pa)[s]}

cat("\n=== ② 비용 부과 후 랭킹 고유 기여 (D1-AP, clean) ===\n")
cat(sprintf("  %-8s %8s %12s %10s %10s\n","bps","n","평균%/월","NW-t","permB p"))
OUT<-list()
for(bps in c(0,15,30)){S<-mkS(bps); d<-contrib(S)
  PM<-sapply(1:200,function(s_)mean(contrib(S,seed=s_)))
  pv<-mean(PM>=mean(d))
  OUT[[as.character(bps)]]<-list(mean=mean(d),t=nwt(d),p=pv,n=length(d))
  cat(sprintf("  %-8d %8d %+12.4f %+10.3f %10.3f %s\n",bps,length(d),100*mean(d),nwt(d),pv,
    ifelse(pv<0.05,"★귀무 밖","귀무 안")))}

cat("\n=== ③ 승자 선정이 고회전 팩터로 쏠리나 ===\n")
S0<-mkS(0); S15<-mkS(15)
cntf<-function(S){cnt<-setNames(rep(0L,NF),FK)
  for(d in 13:NM){s<-S[d,];pos<-which(is.finite(s)&s>0);if(!length(pos))next
    wk<-FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(KW,length(pos)))]];cnt[wk]<-cnt[wk]+1L}
  cnt}
c0<-cntf(S0); c15<-cntf(S15)
TT[,sel0:=c0[factor]][,sel15:=c15[factor]]
rho2<-cor(TT$to_yr,TT$sel0,method="spearman")
cat(sprintf("  ★진단2 — 회전율 vs 승자 선정 횟수(무비용) 순위상관 = %+.3f\n",rho2))
cat(sprintf("  비용 부과(15bps) 시 승자 집합 변화: 총 선정 %d -> %d · 팩터별 최대 변화 %d\n",
  sum(c0),sum(c15),max(abs(c15-c0))))
cat(sprintf("  %-14s %8s %8s %8s\n","factor","회전%/yr","선정(0)","선정(15)"))
for(i in seq_len(nrow(TT))) cat(sprintf("  %-14s %8.1f %8d %8d\n",TT$factor[i],TT$to_yr[i],TT$sel0[i],TT$sel15[i]))

cat("\n=== ④ 판정 (사전등록 규칙) ===\n")
b0<-OUT[["0"]]; b15<-OUT[["15"]]
drop<-1-abs(b15$t)/abs(b0$t)
cat(sprintf("  무비용 t %+.3f (p %.3f) -> 15bps t %+.3f (p %.3f) | t 감소 %.1f%%\n",
  b0$t,b0$p,b15$t,b15$p,100*drop))
keep<-(b15$p<0.05)&&(drop<=0.30)
cat(sprintf("  ⇒ %s\n",ifelse(keep,
  "★랭킹 기여는 비용 아티팩트가 아니다 — R60 결과 유지",
  "★랭킹 기여가 무비용 편향의 산물 — R60 결과와 FQ-247 라벨 철회 필요")))
fwrite(TT,"06_Registry/mfro_index_turnover_audit_20260822.csv")
saveRDS(list(TT=TT,OUT=OUT,rho1=rho1,rho2=rho2),".cache/_mfro_r65.rds")
cat("\n산출: 06_Registry/mfro_index_turnover_audit_20260822.csv\nR65_DONE\n")
