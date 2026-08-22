## run_mfro_r67_k200_full.R — R67: K200 전용 유니버스로 full 창 열기 (prereg mfro_v8)
## ★선행 게이트: K200 멤버십 정상성 확인 → 비정상이면 중단.
## ★창 자유도 없음: full = 가용 전체, clean = 2015-07 고정. 중간 시작점 탐색 금지.
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

## ── 선행 게이트: K200 멤버십 정상성 ──
cat("=== 선행 게이트: K200 멤버십 정상성 ===\n")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")))
rd[,Date:=as.Date(Date)];rd[,ym:=format(Date,"%Y-%m")]
eom<-rd[,.(Date=max(Date)),by=ym];M<-merge(rd,eom,by=c("ym","Date"))
mem<-function(col){L<-split(M[get(col)==1,Ticker],M[get(col)==1,ym]); ys<-sort(names(L))
  ent<-exi<-integer(0)
  for(i in 2:length(ys)){a<-L[[ys[i-1]]];b<-L[[ys[i]]]
    ent<-c(ent,length(setdiff(b,a))); exi<-c(exi,length(setdiff(a,b)))}
  list(ys=ys[-1],ent=ent,exi=exi)}
for(cc in c("K200","KQ150")){z<-mem(cc)
  pre<-z$ys<"2015-07"
  cat(sprintf("  %-6s 전체: 편입 %d · 퇴출 %d | 백필구간(pre-2015-07): 편입 %d · **퇴출 %d**\n",
    cc,sum(z$ent),sum(z$exi),sum(z$ent[pre]),sum(z$exi[pre])))}
k2<-mem("K200"); ok_k200 <- sum(k2$exi[k2$ys<"2015-07"]) > 50L
cat(sprintf("  ⇒ K200 백필구간 퇴출 %d건 -> %s\n",sum(k2$exi[k2$ys<"2015-07"]),
  ifelse(ok_k200,"★정상(게이트 통과)","비정상 -> 중단")))
stopifnot(ok_k200)

## ── 패널: K200 전용 ──
P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney");NF<-length(FK)
M[,is_k200:=(!is.na(K200)&K200==1)]
P<-merge(P,M[,.(ym,Ticker,is_k200)],by=c("ym","Ticker"),all.x=TRUE)
P[is.na(is_k200),is_k200:=FALSE]
setorder(P,ym)
cat(sprintf("\n[패널] 전체 %d행 · K200 전용 %d행(%.1f%%)\n",nrow(P),sum(P$is_k200),100*mean(P$is_k200)))

build<-function(k200_only){
  Q<-if(k200_only) P[is_k200==TRUE] else P
  YM<-sort(unique(Q$ym)); NM<-length(YM)
  GR<-matrix(NA_real_,NM,NF); dimnames(GR)<-list(YM,FK); mkt<-rep(NA_real_,NM)
  for(m in seq_len(NM)){D<-Q[ym==YM[m]]; fr<-D$fwd_ret; fr[!is.finite(fr)]<-0
    ok0<-is.finite(D$mktcap)&D$mktcap>0
    if(sum(ok0)>=15L) mkt[m]<-sum(D$mktcap[ok0]*fr[ok0])/sum(D$mktcap[ok0])
    for(j in 1:NF){z<-D[[FK[j]]];ok<-is.finite(z)&ok0
      if(sum(ok)<15L) next
      thr<-quantile(z[ok],TOPQ,na.rm=TRUE);sel<-which(ok&z>=thr);if(!length(sel))next
      w<-D$mktcap[sel]/sum(D$mktcap[sel]); GR[m,j]<-sum(w*fr[sel])}}
  S<-matrix(NA_real_,NM,NF); dimnames(S)<-list(YM,FK)
  for(j in 1:NF)for(m in 13:NM){a<-GR[(m-12):(m-1),j];b<-mkt[(m-12):(m-1)]
    if(sum(is.finite(a))<10) next
    a[!is.finite(a)]<-0; S[m,j]<-prod(1+a)/prod(1+b)-1}
  list(Q=Q,YM=YM,NM=NM,S=S,mkt=mkt)}

contrib<-function(B,win,seed=NA){
  Q<-B$Q;YM<-B$YM;NM<-B$NM;S<-B$S
  sel_w<-if(win=="clean") YM>="2015-07" else rep(TRUE,NM)
  pt<-rep(NA_real_,NM);pa<-rep(NA_real_,NM);w1<-NULL;w2<-NULL
  for(m in 2:NM){d<-m-1L;if(d<1)next
    s<-S[d,];pos<-which(is.finite(s)&s>0);if(!length(pos))next
    D<-Q[ym==YM[m]];D<-D[is.finite(adv20)&adv20>=LIQ];if(nrow(D)<N_TARGET+5L)next
    wtop<-if(is.na(seed)) FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(KW,length(pos)))]]
          else {set.seed(seed*1000L+m);FK[sample(pos,min(KW,length(pos)))]}
    wall<-FK[pos]
    idx<-order(-D$mktcap)[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    for(a in 1:2){wk<-if(a==1)wtop else wall
      w<-.tilt(neut(zmean(D,wk)[idx]));names(w)<-tk
      wp<-if(a==1)w1 else w2
      at<-union(names(wp),tk);x<-setNames(rep(0,length(at)),at);y<-x
      if(!is.null(wp))x[names(wp)]<-wp;y[tk]<-w
      v<-sum(w*fr)-(15/1e4)*sum(abs(y-x))
      if(a==1)pt[m]<-v else pa[m]<-v
      wd<-w*(1+fr);if(a==1)w1<-wd/sum(wd) else w2<-wd/sum(wd)}}
  s<-sel_w&is.finite(pt)&is.finite(pa);(pt-pa)[s]}

cat("\n=== 셀 측정 ===\n")
B_all<-build(FALSE); B_k2<-build(TRUE)
cells<-list(REF_both_clean=list(B=B_all,win="clean"),
            A_k200_clean =list(B=B_k2, win="clean"),
            B_k200_full  =list(B=B_k2, win="full"))
OUT<-list()
cat(sprintf("  %-18s %6s %12s %10s %10s\n","cell","n","평균%/월","NW-t","permB p"))
for(nm in names(cells)){cc<-cells[[nm]]
  d<-contrib(cc$B,cc$win)
  PM<-sapply(1:200,function(s_)mean(contrib(cc$B,cc$win,seed=s_)))
  pv<-mean(PM>=mean(d))
  OUT[[nm]]<-list(n=length(d),mean=mean(d),t=nwt(d),p=pv)
  cat(sprintf("  %-18s %6d %+12.4f %+10.3f %10.3f %s\n",nm,length(d),100*mean(d),nwt(d),pv,
    ifelse(pv<0.05,"★귀무 밖","귀무 안")))}

cat("\n=== gate_0: 유니버스 제한이 clean 결과를 바꾸는가 (문턱 30%) ===\n")
r<-OUT$REF_both_clean; a<-OUT$A_k200_clean
dch<-abs(a$mean-r$mean)/abs(r$mean)
cat(sprintf("  REF %+.4f%%/월 -> A(K200) %+.4f%%/월 | 변화 %.1f%% -> %s\n",
  100*r$mean,100*a$mean,100*dch,ifelse(dch<=0.30,"★통과(B 해석 가능)","실패 -> 유니버스 교란, 중단")))

cat("\n=== 판정 (사전등록 규칙) ===\n")
b<-OUT$B_k200_full
pred<-abs(a$t)*sqrt(b$n/max(a$n,1))
cat(sprintf("  사전 고정 예측: t ≈ %.3f x sqrt(%d/%d) = **%.3f**\n",abs(a$t),b$n,a$n,pred))
cat(sprintf("  실측 B: n=%d · 평균 %+.4f%%/월 · t %+.3f · permB p %.3f\n",b$n,100*b$mean,b$t,b$p))
lab<-if(dch>0.30) "유니버스 교란 — 중단" else
     if(b$p<0.05 && b$t>=1.96) "★PASS — 이 아크 최초 t>=1.96. 즉시 계약 측정(HARD 3종) full 창 재산출" else
     if(b$t<1.4) "★fail_rule_a — era 불안정. pre-2015 에서 신호가 다르게 작동했고 창 확장으로 해결 안 됨" else
     "fail_rule_b — 검정력은 올랐으나 효과가 예상보다 작음"
cat(sprintf("  ⇒ %s\n",lab))
saveRDS(list(OUT=OUT,pred=pred,label=lab),".cache/_mfro_r67.rds")
cat("\nR67_DONE\n")
