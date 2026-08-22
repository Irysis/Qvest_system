## run_mfro_r68_crosscap.R — R68: cross-cap 정보 전이 직접 시험 (prereg mfro_v9)
## ★보유 완전 고정. 신호를 만드는 지수 **공간만** 바꾼다.
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
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")))
rd[,Date:=as.Date(Date)];rd[,ym:=format(Date,"%Y-%m")]
eom<-rd[,.(Date=max(Date)),by=ym];M<-merge(rd,eom,by=c("ym","Date"))
M[,`:=`(is_k200=(!is.na(K200)&K200==1), is_kq=(!is.na(KQ150)&KQ150==1))]
P<-merge(P,M[,.(ym,Ticker,is_k200,is_kq)],by=c("ym","Ticker"),all.x=TRUE)
P[is.na(is_k200),is_k200:=FALSE];P[is.na(is_kq),is_kq:=FALSE]
setorder(P,ym); YM<-sort(unique(P$ym)); NM<-length(YM)
cat(sprintf("[공간 크기] 전체 %d · K200 %d · KQ150 %d (월당 중앙)\n",
  as.integer(median(P[,.N,by=ym]$N)),
  as.integer(median(P[is_k200==TRUE,.N,by=ym]$N)),
  as.integer(median(P[is_kq==TRUE,.N,by=ym]$N))))

## ── 신호 빌더: 공간 필터 + 분위 ──
mkS<-function(spacefun,topq){
  GR<-matrix(NA_real_,NM,NF);dimnames(GR)<-list(YM,FK);mkt<-rep(NA_real_,NM);ns<-c()
  for(m in seq_len(NM)){D<-spacefun(P[ym==YM[m]])
    if(nrow(D)<20L) next
    fr<-D$fwd_ret;fr[!is.finite(fr)]<-0;ok0<-is.finite(D$mktcap)&D$mktcap>0
    if(sum(ok0)>=15L) mkt[m]<-sum(D$mktcap[ok0]*fr[ok0])/sum(D$mktcap[ok0])
    cnt<-c()
    for(j in 1:NF){z<-D[[FK[j]]];ok<-is.finite(z)&ok0;if(sum(ok)<15L)next
      thr<-quantile(z[ok],topq,na.rm=TRUE);sel<-which(ok&z>=thr);if(!length(sel))next
      cnt<-c(cnt,length(sel));w<-D$mktcap[sel]/sum(D$mktcap[sel]);GR[m,j]<-sum(w*fr[sel])}
    if(length(cnt))ns<-c(ns,mean(cnt))}
  S<-matrix(NA_real_,NM,NF);dimnames(S)<-list(YM,FK)
  for(j in 1:NF)for(m in 13:NM){a<-GR[(m-12):(m-1),j];b<-mkt[(m-12):(m-1)]
    if(sum(is.finite(a))<10||sum(is.finite(b))<10)next
    a[!is.finite(a)]<-0;b[!is.finite(b)]<-0;S[m,j]<-prod(1+a)/prod(1+b)-1}
  list(S=S,nsel=mean(ns,na.rm=TRUE))}

## ── 보유는 항상 동일: 전체 유니버스 시총 상위 25 ──
contrib<-function(S,seed=NA){
  pt<-rep(NA_real_,NM);pa<-rep(NA_real_,NM);w1<-NULL;w2<-NULL
  for(m in 2:NM){d<-m-1L;s<-S[d,];pos<-which(is.finite(s)&s>0);if(!length(pos))next
    D<-P[ym==YM[m]];D<-D[is.finite(adv20)&adv20>=LIQ];if(nrow(D)<N_TARGET+5L)next
    wtop<-if(is.na(seed))FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(KW,length(pos)))]]
          else{set.seed(seed*1000L+m);FK[sample(pos,min(KW,length(pos)))]}
    wall<-FK[pos];idx<-order(-D$mktcap)[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    for(a in 1:2){wk<-if(a==1)wtop else wall
      w<-.tilt(neut(zmean(D,wk)[idx]));names(w)<-tk;wp<-if(a==1)w1 else w2
      at<-union(names(wp),tk);x<-setNames(rep(0,length(at)),at);y<-x
      if(!is.null(wp))x[names(wp)]<-wp;y[tk]<-w
      v<-sum(w*fr)-(15/1e4)*sum(abs(y-x))
      if(a==1)pt[m]<-v else pa[m]<-v
      wd<-w*(1+fr);if(a==1)w1<-wd/sum(wd) else w2<-wd/sum(wd)}}
  s<-(YM>="2015-07")&is.finite(pt)&is.finite(pa);list(d=(pt-pa)[s],pr=pt,pa=pa,msk=s)}

## KQ150 개수 맞춤 분위: KQ150 공간에서 전체 top-tercile 과 같은 개수를 뽑으려면
n_all<-median(P[,.N,by=ym]$N); n_kq<-median(P[is_kq==TRUE,.N,by=ym]$N)
TQ_KQ<-max(0, 1-(n_all/3)/n_kq)
cat(sprintf("[분위] KQ150 에서 %d종을 뽑으려면 분위 %.4f (음수면 전량)\n",round(n_all/3),TQ_KQ))

SPACES<-list(
  SP_both        =list(f=function(D)D,                 q=0.6667),
  SP_k200        =list(f=function(D)D[is_k200==TRUE],  q=0.6667),
  SP_kq150       =list(f=function(D)D[is_kq==TRUE],    q=0.6667),
  SP_kq150_match =list(f=function(D)D[is_kq==TRUE],    q=TQ_KQ))
cat("\n=== 신호 공간별 랭킹 고유 기여 (보유 고정, clean 창) ===\n")
cat(sprintf("  %-18s %9s %6s %11s %9s %9s\n","space","지수구성","n","평균%/월","NW-t","permB p"))
OUT<-list()
for(nm in names(SPACES)){sp<-SPACES[[nm]]
  B<-mkS(sp$f,sp$q); r<-contrib(B$S)
  PM<-sapply(1:150,function(s_)mean(contrib(B$S,seed=s_)$d)); pv<-mean(PM>=mean(r$d))
  OUT[[nm]]<-list(nsel=B$nsel,n=length(r$d),mean=mean(r$d),t=nwt(r$d),p=pv,S=B$S,r=r)
  cat(sprintf("  %-18s %9.0f %6d %+11.4f %+9.3f %9.3f %s\n",nm,B$nsel,length(r$d),
    100*mean(r$d),nwt(r$d),pv,ifelse(pv<0.05,"★밖","안")))}

cat("\n=== 대응표본 (동일 보유·동일 창이므로 직접 비교 가능) ===\n")
pp<-function(a,b){x<-OUT[[a]]$r; y<-OUT[[b]]$r
  n<-min(length(x$d),length(y$d)); dd<-x$d[1:n]-y$d[1:n]
  cat(sprintf("  %-22s mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(a," - ",b),100*mean(dd),nwt(dd)))}
pp("SP_kq150","SP_both"); pp("SP_kq150","SP_k200"); pp("SP_both","SP_k200")
pp("SP_kq150_match","SP_both")

cat("\n=== 가설 판별 (사전등록 순서) ===\n")
mb<-OUT$SP_both$mean; mk<-OUT$SP_kq150$mean; m2<-OUT$SP_k200$mean
pk<-OUT$SP_kq150$p
cat(sprintf("  관측 순서: both %+.4f · kq150 %+.4f · k200 %+.4f (%%/월)\n",100*mb,100*mk,100*m2))
h<-if(mk>=mb && pk<0.05) "★H1 cross-cap 전이 확정 (kq150 >= both > k200, permB 유의)" else
   if(mb>mk && mb>m2 && mk>m2) "★H3 KQ150 은 잡음 감소 기여 (both > kq150 > k200)" else
   if(mb>mk && mb>m2) "★H2 다양성 (both 가 두 단일 공간 각각보다 큼)" else
   "★미확정 — 사전등록 세 순서 중 어느 것도 아님. 대안 가설 필요"
cat(sprintf("  ⇒ %s\n",h))
saveRDS(list(OUT=lapply(OUT,function(o)o[c("nsel","n","mean","t","p")]),hyp=h),".cache/_mfro_r68.rds")
cat("\nR68_DONE\n")
