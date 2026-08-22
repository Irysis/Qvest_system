## run_mfro_r64_levers.R — R64: 효과/변동성 비의 크기 레버 3종 (prereg mfro_v6)
## ★판정 = 추세(Spearman) + 평탄도. argmax 셀 채택 금지(사전등록 binding_constraint).
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
UB<-0.20;LIQ<-2e8
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam,lb=0,ub=UB){if(!length(a))return(numeric(0))
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
CLEAN<-YM>="2015-07"
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
posrow<-function(d){if(d<1||d>NM)return(NULL);r<-match(YM[d],rownames(S));if(is.na(r))return(NULL)
  s<-S[r,];p<-which(is.finite(s)&s>0);if(!length(p))return(NULL);list(s=s,pos=p)}

## 랭킹 고유 기여 = top-k 틸트 - 양풀전체 틸트 (동일 우주·동일 lambda·동일 종목)
contrib<-function(lam=1.5,k=5L,N=25L,bps=15){
  pr_top<-rep(NA_real_,NM); pr_all<-rep(NA_real_,NM); wp1<-NULL; wp2<-NULL
  for(m in 2:NM){d<-m-1L
    D<-P[ym==YM[m]]; if(nrow(D)<N+5L) next
    p0<-posrow(d); if(is.null(p0)) next
    wk_top<-FK[p0$pos[order(p0$s[p0$pos],decreasing=TRUE)][seq_len(min(k,length(p0$pos)))]]
    wk_all<-FK[p0$pos]
    idx<-order(-D$mktcap)[seq_len(N)]; tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx]; fr[!is.finite(fr)]<-0
    for(a in 1:2){
      w<-.tilt(neut(zmean(D,if(a==1)wk_top else wk_all)[idx]),lam); names(w)<-tk
      wprev<-if(a==1)wp1 else wp2
      at<-union(names(wprev),tk);x<-setNames(rep(0,length(at)),at);y<-x
      if(!is.null(wprev))x[names(wprev)]<-wprev; y[tk]<-w
      dl<-sum(abs(y-x)); v<-sum(w*fr)-(bps/1e4)*dl
      if(a==1) pr_top[m]<-v else pr_all[m]<-v
      wd<-w*(1+fr); if(a==1) wp1<-wd/sum(wd) else wp2<-wd/sum(wd)}}
  s<-CLEAN&is.finite(pr_top)&is.finite(pr_all)&is.finite(bmf)
  dd<-(pr_top-pr_all)[s]
  list(n=sum(s),mean=mean(dd),sd=sd(dd),t=nwt(dd),ratio=mean(dd)/sd(dd))}

AX<-list(lambda=list(vals=c(0.5,1.0,1.5,2.5,4.0),cur=1.5,f=function(v)contrib(lam=v)),
         k     =list(vals=c(3L,5L,8L,11L),        cur=5L, f=function(v)contrib(k=as.integer(v))),
         N     =list(vals=c(15L,25L,40L,60L),     cur=25L,f=function(v)contrib(N=as.integer(v))))
cat("=== R64 크기 레버 (prereg mfro_v6) — 판정 = 추세 + 평탄도, argmax 채택 금지 ===\n")
RES<-list()
for(an in names(AX)){A<-AX[[an]]
  cat(sprintf("\n[축 %s]  현행값 = %s\n",an,A$cur))
  cat(sprintf("  %-8s %10s %10s %9s %9s\n","값","효과%/월","변동%/월","효과/변동","NW-t"))
  out<-lapply(A$vals,A$f)
  for(i in seq_along(A$vals)) cat(sprintf("  %-8s %+10.4f %10.4f %+9.4f %+9.3f %s\n",
    A$vals[i],100*out[[i]]$mean,100*out[[i]]$sd,out[[i]]$ratio,out[[i]]$t,
    ifelse(A$vals[i]==A$cur,"<- 현행","")))
  tv<-sapply(out,function(o)o$t); rv<-sapply(out,function(o)o$ratio)
  rho<-suppressWarnings(cor(as.numeric(A$vals),tv,method="spearman"))
  rng<-diff(range(tv)); mx<-max(abs(diff(tv)))
  cur_t<-tv[match(A$cur,A$vals)]; best<-max(tv); gain<-best/abs(cur_t)
  c1<-is.finite(rho)&&abs(rho)>=0.8; c2<-is.finite(rng)&&rng>0&&(mx<0.5*rng); c3<-is.finite(gain)&&gain>=1.17
  cat(sprintf("  판정: ①Spearman rho %+.3f %s  ②평탄 최대|Δt| %.3f / 범위 %.3f = %.0f%% %s  ③최대/현행 %.2f배 %s\n",
    rho,ifelse(c1,"PASS","FAIL"),mx,rng,100*mx/max(rng,1e-9),ifelse(c2,"PASS","FAIL"),
    gain,ifelse(c3,"PASS","FAIL")))
  cat(sprintf("  ⇒ 축 %s: %s\n",an,ifelse(c1&&c2&&c3,"★레버","레버 아님")))
  RES[[an]]<-list(vals=A$vals,out=out,rho=rho,flat=mx/max(rng,1e-9),gain=gain,pass=c1&&c2&&c3)}

cat("\n[★효과와 변동성이 함께 커졌나 — 비가 개선돼야 검정력이 오른다]\n")
for(an in names(RES)){r<-RES[[an]]
  me<-sapply(r$out,function(o)100*o$mean); sv<-sapply(r$out,function(o)100*o$sd)
  cat(sprintf("  %-8s 효과 %s | 변동 %s\n",an,
    paste(sprintf("%+.3f",me),collapse=" "),paste(sprintf("%.3f",sv),collapse=" ")))}
cat("\n[종합]\n")
np<-sum(sapply(RES,function(r)r$pass))
cat(sprintf("  통과 축 %d/3 ⇒ %s\n",np,ifelse(np==0,
  "★3축 전부 레버 아님 — 이 구성에서 효과/변동성 비는 조정 불가. 남는 경로 = 신호 교체 또는 시간(라이브 축적)",
  "통과 축 존재 — 다음 라운드에서 그 축 단독 사전등록 후 확인(본 라운드에서 채택 금지)")))
saveRDS(RES,".cache/_mfro_r64.rds")
cat("\nR64_DONE\n")
