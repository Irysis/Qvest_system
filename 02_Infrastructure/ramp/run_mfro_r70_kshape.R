## run_mfro_r70_kshape.R — R70: 승자 폭 k 의 형태 — 좁은 봉우리(잡음)인가 넓은 고원(구조)인가
##
## ★사전 선언(결과 전 기록):
##   R64 가 k 사다리를 {3,5,8,11} 로 성기게 재서 t = -0.431 / +1.671 / +0.144 / -0.812 을 얻었고
##   '고립 봉우리 = 잡음' 으로 판정해 구성 민감도 FAIL(낙폭 91%)을 냈다. 그러나 4·6·7 을 안 쟀다.
##   질문 = k=5 주변이 **고원**이면 그 판정이 뒤집힌다.
##   ★판정 지표는 **형태**이지 최대값이 아니다(argmax 채택 금지) — 구체적으로:
##     ①인접 3점(k-1,k,k+1) 평균이 전체 사다리 중앙값보다 높은가
##     ②봉우리 반치폭(최대값의 50% 이상을 유지하는 k 구간의 폭)이 2 이상인가
##   ★두 조건 모두 충족하면 '고원(구조)', 아니면 '봉우리(잡음)' 이고 R64 판정 유지.
##   ★예상: 좁은 봉우리(잡음)일 것으로 본다(60:40). 근거 = R58 의 IR 사다리도 k=5 가 고립이었고
##     R62/R68 이 이미 취약성을 세 겹 실측했다. 그러나 4·6 이 비어 있었으므로 확인 없이 단정은 부당하다.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8
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
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
posrow<-function(d){if(d<1||d>NM)return(NULL);r<-match(YM[d],rownames(S));if(is.na(r))return(NULL)
  s<-S[r,];p<-which(is.finite(s)&s>0);if(!length(p))return(NULL);list(s=s,pos=p)}
contrib<-function(k,seed=NA){pt<-rep(NA_real_,NM);pa<-rep(NA_real_,NM);w1<-NULL;w2<-NULL
  for(m in 2:NM){d<-m-1L;p0<-posrow(d);if(is.null(p0))next
    D<-P[ym==YM[m]];if(nrow(D)<N_TARGET+5L)next
    wtop<-if(is.na(seed))FK[p0$pos[order(p0$s[p0$pos],decreasing=TRUE)][seq_len(min(k,length(p0$pos)))]]
          else{set.seed(seed*1000L+m);FK[sample(p0$pos,min(k,length(p0$pos)))]}
    wall<-FK[p0$pos];idx<-order(-D$mktcap)[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    for(a in 1:2){wk<-if(a==1)wtop else wall
      w<-.tilt(neut(zmean(D,wk)[idx]));names(w)<-tk;wp<-if(a==1)w1 else w2
      at<-union(names(wp),tk);x<-setNames(rep(0,length(at)),at);y<-x
      if(!is.null(wp))x[names(wp)]<-wp;y[tk]<-w
      v<-sum(w*fr)-(15/1e4)*sum(abs(y-x))
      if(a==1)pt[m]<-v else pa[m]<-v
      wd<-w*(1+fr);if(a==1)w1<-wd/sum(wd) else w2<-wd/sum(wd)}}
  s<-CLEAN&is.finite(pt)&is.finite(pa);(pt-pa)[s]}

KS<-2:11
cat("=== R70 승자 폭 k 의 형태 (촘촘 사다리) ===\n")
cat(sprintf("  %-4s %11s %9s %9s %8s\n","k","평균%/월","NW-t","permB p","양(+)풀 중 비율"))
np<-sapply(seq_len(NM),function(d){p<-posrow(d);if(is.null(p))NA_integer_ else length(p$pos)})
med_pos<-median(np,na.rm=TRUE)
RES<-list()
for(k in KS){d<-contrib(k)
  PM<-sapply(1:120,function(s_)mean(contrib(k,seed=s_)));pv<-mean(PM>=mean(d))
  RES[[as.character(k)]]<-list(mean=mean(d),t=nwt(d),p=pv)
  cat(sprintf("  %-4d %+11.4f %+9.3f %9.3f %8.0f%%\n",k,100*mean(d),nwt(d),pv,100*k/med_pos))}

tv<-sapply(RES,function(o)o$t); names(tv)<-KS
cat(sprintf("\n[사다리] %s\n",paste(sprintf("k%d:%+.3f",KS,tv),collapse="  ")))
pk<-KS[which.max(tv)]; mx<-max(tv)
## ①인접 3점 평균 vs 사다리 중앙값
i<-match(pk,KS); nb<-tv[max(1,i-1):min(length(KS),i+1)]
c1<-mean(nb) > median(tv)
## ②반치폭: 최대의 50% 이상 유지하는 연속 구간 폭
half<-mx*0.5; run<-0L; best<-0L
for(v in tv){ if(is.finite(v)&&v>=half){run<-run+1L; best<-max(best,run)} else run<-0L }
c2<- best >= 2L
cat(sprintf("\n[형태 판정 — 사전등록 지표]\n"))
cat(sprintf("  최대 k=%d (t %+.3f) · 사다리 중앙값 t %+.3f\n",pk,mx,median(tv)))
cat(sprintf("  ①인접3점 평균 %+.3f > 중앙값 %+.3f ? %s\n",mean(nb),median(tv),ifelse(c1,"YES","NO")))
cat(sprintf("  ②반치폭(최대의 50%%=%.3f 이상 연속 구간) = %d ( >=2 ? %s )\n",half,best,ifelse(c2,"YES","NO")))
cat(sprintf("  ⇒ %s\n", if(c1&&c2) "★고원(구조) — R64 의 구성 민감도 FAIL 재검토 대상" else
                        "★봉우리(잡음) — R64 판정 유지, 구성 민감도 FAIL"))
cat(sprintf("\n[참고] 양(+) 팩터 수 중앙 %d — k=%d 는 그 %.0f%%\n",med_pos,pk,100*pk/med_pos))
saveRDS(list(KS=KS,RES=RES,peak=pk,halfwidth=best,plateau=(c1&&c2)),".cache/_mfro_r70.rds")
cat("\nR70_DONE\n")
