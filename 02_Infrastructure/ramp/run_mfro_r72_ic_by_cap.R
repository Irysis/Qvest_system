## run_mfro_r72_ic_by_cap.R — R72: S1(rank-IC) 실패의 기전 확인 (prereg 헤더)
##
## ★사전 선언(결과 전 기록):
##   R71 에서 S1(전체 횡단면 rank-IC)로 팩터를 고르니 S0 대비 **-0.5620%/월 NW-t -2.611** 로 유의하게 나빴다.
##   내가 제시한 기전 추정 = "rank-IC 는 전체 횡단면을 재는데 전략은 시총 상위 25종만 본다.
##   팩터 프리미엄이 소형주에 집중되므로 전체 IC 로 고른 팩터가 대형주에서 역효과."
##   ★이 라운드는 그 추정을 **직접** 시험한다. 추정을 기전으로 승격하려면 두 가지가 필요하다:
##     ①진단: 팩터 rank-IC 가 실제로 시총 분위별로 갈리는가(소형 > 대형)
##     ②신호: 우주를 맞춘 IC(대형주 한정)로 고르면 S1 의 음수가 사라지거나 뒤집히는가
##   ★예상: ①은 확인되고(소형 IC > 대형 IC) ②는 S1 보다 낫지만 S0 는 못 넘을 것(60%).
##     ②까지 확인되면 기전 확정이고, ①만 확인되면 '상관 있으나 기전 미확정' 이다.
##   ★주의: top-25 IC 는 n=25 표본 상관이라 잡음이 크다. top-100 을 함께 재서 표본 크기 교란을 가른다.
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

## ── ① 진단: 시총 분위별 rank-IC ──
cat("=== ① 팩터 rank-IC 가 시총 분위별로 갈리는가 ===\n")
ICq<-array(NA_real_,c(NM,NF,3)); dimnames(ICq)<-list(YM,FK,c("대형","중형","소형"))
for(m in seq_len(NM)){D<-P[ym==YM[m]]; fr<-D$fwd_ret
  ok0<-is.finite(D$mktcap); if(sum(ok0)<60L) next
  q<-cut(rank(-D$mktcap[ok0]),breaks=3,labels=FALSE)   # 1=대형
  idxs<-split(which(ok0),q)
  for(g in 1:3){ii<-idxs[[as.character(g)]]; if(is.null(ii)||length(ii)<20L) next
    for(j in 1:NF){z<-D[[FK[j]]][ii]; f<-fr[ii]; o<-is.finite(z)&is.finite(f)
      if(sum(o)>=20L) ICq[m,j,g]<-cor(rank(z[o]),rank(f[o]))}}}
sel<-CLEAN
cat(sprintf("  %-14s %9s %9s %9s\n","factor","대형","중형","소형"))
tot<-c(0,0,0)
for(j in 1:NF){v<-sapply(1:3,function(g)mean(ICq[sel,j,g],na.rm=TRUE)); tot<-tot+v
  cat(sprintf("  %-14s %+9.4f %+9.4f %+9.4f\n",FK[j],v[1],v[2],v[3]))}
mv<-tot/NF
cat(sprintf("\n  ★평균 IC: 대형 %+.4f · 중형 %+.4f · 소형 %+.4f\n",mv[1],mv[2],mv[3]))
tt<-sapply(1:3,function(g)nwt(rowMeans(ICq[sel,,g],na.rm=TRUE)))
cat(sprintf("     NW-t : 대형 %+.3f · 중형 %+.3f · 소형 %+.3f\n",tt[1],tt[2],tt[3]))
cat(sprintf("  ⇒ ①%s\n",ifelse(mv[3]>mv[1],"확인 — 소형 IC 가 대형보다 높다","기각 — 소형이 더 높지 않다")))

## ── ② 신호: 우주를 맞춘 IC ──
mkIC<-function(topN){M<-matrix(NA_real_,NM,NF);dimnames(M)<-list(YM,FK)
  for(m in seq_len(NM)){D<-P[ym==YM[m]];ok<-is.finite(D$mktcap)
    ## ★수리: topN 이 유니버스보다 크면 skip 이 아니라 **전체 사용**(구판은 n=0 을 만들었다)
    nn<-min(topN,sum(ok)); if(nn<20L) next
    ii<-order(-D$mktcap)[seq_len(nn)];fr<-D$fwd_ret[ii]
    for(j in 1:NF){z<-D[[FK[j]]][ii];o<-is.finite(z)&is.finite(fr)
      if(sum(o)>=max(15L,nn%/%2L)) M[m,j]<-cor(rank(z[o]),rank(fr[o]))}}
  M}
mkS<-function(kind,topN=NA){S<-matrix(NA_real_,NM,NF);dimnames(S)<-list(YM,FK);ri<-match(YM,mi$ym)
  if(kind=="S0"){for(j in 1:NF)for(d in 13:NM){r<-ri[d];if(is.na(r)||r<12)next
      a<-mi[[FK[j]]][(r-11):r];b<-mi$Market[(r-11):r];if(sum(is.finite(a))<10)next
      S[d,j]<-prod(1+a)/prod(1+b)-1}
    return(S)}
  IC<-mkIC(topN)
  for(j in 1:NF)for(d in 13:NM){v<-IC[(d-12):(d-1),j];v<-v[is.finite(v)];if(length(v)>=8)S[d,j]<-mean(v)}
  S}
contrib<-function(S,seed=NA){pt<-rep(NA_real_,NM);pa<-rep(NA_real_,NM);w1<-NULL;w2<-NULL
  for(m in 2:NM){d<-m-1L;s<-S[d,];pos<-which(is.finite(s)&s>0);if(!length(pos))next
    D<-P[ym==YM[m]];if(nrow(D)<N_TARGET+5L)next
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
  s<-CLEAN&is.finite(pt)&is.finite(pa);(pt-pa)[s]}

cat("\n=== ② 우주를 맞춘 IC 로 고르면 ===\n")
cat(sprintf("  %-22s %6s %11s %9s %9s\n","signal","n","평균%/월","NW-t","permB p"))
CAND<-list(S0_index_active=list(k="S0"), S1_ic_full=list(k="IC",N=NA_integer_),
           S1b_ic_top25=list(k="IC",N=25L), S1c_ic_top100=list(k="IC",N=100L),
           S1d_ic_top200=list(k="IC",N=200L))
OUT<-list()
for(nm in names(CAND)){cc<-CAND[[nm]]
  S<-if(cc$k=="S0") mkS("S0") else if(is.na(cc$N)) mkS("IC",topN=10000L) else mkS("IC",topN=cc$N)
  d<-contrib(S); PM<-sapply(1:120,function(s_)mean(contrib(S,seed=s_))); pv<-mean(PM>=mean(d))
  OUT[[nm]]<-list(mean=mean(d),t=nwt(d),p=pv,n=length(d))
  cat(sprintf("  %-22s %6d %+11.4f %+9.3f %9.3f %s\n",nm,length(d),100*mean(d),nwt(d),pv,
    ifelse(pv<0.05,"★밖","안")))}

cat("\n=== 판정 ===\n")
s0<-OUT$S0_index_active$mean; sf<-OUT$S1_ic_full$mean; s25<-OUT$S1b_ic_top25$mean
c1<-mv[3]>mv[1]                      # 소형 IC > 대형 IC
c2<-s25>sf                           # 우주 맞춤이 전체보다 나음
cat(sprintf("  ①소형 IC %+.4f > 대형 IC %+.4f ? %s\n",mv[3],mv[1],ifelse(c1,"YES","NO")))
cat(sprintf("  ②top25 IC %+.4f%%/월 > 전체 IC %+.4f ? %s\n",100*s25,100*sf,ifelse(c2,"YES","NO")))
cat(sprintf("  ③top25 IC 가 S0(%+.4f)을 넘나 ? %s\n",100*s0,ifelse(s25>s0,"YES","NO")))
cat(sprintf("  ⇒ %s\n", if(c1&&c2&&s25>s0) "★기전 확정 + 새 후보 등장" else
                        if(c1&&c2) "★기전 확정 — 그러나 S0 는 못 넘음(예상대로)" else
                        if(c1) "①만 확인 — 상관 있으나 기전 미확정" else
                        "★기전 추정 기각 — S1 실패는 다른 이유"))
saveRDS(list(ICq=ICq,OUT=OUT,mv=mv),".cache/_mfro_r72.rds")
cat("\nR72_DONE\n")
