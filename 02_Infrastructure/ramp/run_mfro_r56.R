## run_mfro_r56.R — R56: 표적-정합 신호 (prereg mfro_v2, chain of mfro_v1)
## ★자유도 1개 = 로테이션 신호의 표적만 "지수 active" -> "꼬리25종 active" 로 교체. 구성은 R55 와 동일.
## 근거: R55 전이 진단 — 지수 active 와 꼬리 active 의 월내 횡단면 순위상관 +0.262, clean 수준 갭 -9.1%/yr.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
zmean<-function(D,cols){if(!length(cols))return(rep(NA_real_,nrow(D)))
  v<-rowMeans(as.matrix(D[,cols,with=FALSE]),na.rm=TRUE);v[!is.finite(v)]<-NA_real_;v}
NAH<-new.env();NAH$n<-0L;NAH$tot<-0L
neutralize<-function(v){bad<-!is.finite(v);NAH$n<-NAH$n+sum(bad);NAH$tot<-NAH$tot+length(v)
  if(all(bad))return(rep(0,length(v)));v[bad]<-mean(v[!bad]);v}

P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney");NF<-length(FK)
P<-P[is.finite(adv20)&adv20>=LIQ];setorder(P,ym);YM<-sort(unique(P$ym));NM<-length(YM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym)
bm<-mi$Market[match(YM,mi$ym)];bmf<-c(bm[-1],NA_real_)
E<-list(full=rep(TRUE,NM),clean=YM>="2015-07")

## ── TA[m,j] = 팩터 j 꼬리25종(월 m 형성)이 월 m+1 에 버는 active. 월 m+1 말에 알 수 있다. ──
TA<-matrix(NA_real_,NM,NF);dimnames(TA)<-list(YM,FK)
for(m in seq_len(NM)){D<-P[ym==YM[m]];if(nrow(D)<N_TARGET)next
  fr0<-D$fwd_ret;fr0[!is.finite(fr0)]<-0
  for(j in 1:NF){z<-D[[FK[j]]];if(sum(is.finite(z))<N_TARGET)next
    z2<-z;z2[!is.finite(z2)]<--Inf;o<-order(-z2);idx<-o[seq_len(N_TARGET)]
    TA[m,j]<-sum(.tilt(neutralize(z[idx]))*fr0[idx])-bmf[m]}}

## 구 신호: 지수 active trailing 12M
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1

## ★신규 신호: 꼬리 active trailing 12M — 결정월 d 에서 가용 = TA[(d-12):(d-1)]
## PIT: TA[d-1] 은 월 d 에 실현되어 월 d 말에 알 수 있다. TA[d] 는 월 d+1 실현이라 사용 금지.
TS<-matrix(NA_real_,NM,NF);dimnames(TS)<-list(YM,FK)
for(j in 1:NF)for(d in 14:NM){v<-TA[(d-12):(d-1),j];v<-v[is.finite(v)]
  if(length(v)>=6) TS[d,j]<-sum(v)}
## TS2 = 덜 낡은 변형. 결정시점(월 m 말)에는 TA[m-1] 까지 알 수 있다. TS 는 TA[m-2] 까지만 써서
## 한 달 보수적이었다 — 그 보수성이 손해인지 진단용으로 병기한다.
TS2<-matrix(NA_real_,NM,NF);dimnames(TS2)<-list(YM,FK)
for(j in 1:NF)for(mm in 14:NM){v<-TA[(mm-12):(mm-1),j];v<-v[is.finite(v)]
  if(length(v)>=6) TS2[mm,j]<-sum(v)}
cat(sprintf("[신호] 지수 trailing 가용월 %d · 꼬리 trailing 가용월 %d\n",
  sum(rowSums(is.finite(S))>0),sum(rowSums(is.finite(TS))>0)))
## PIT 위반 주입 대조: TA[d] 를 포함시키면 값이 달라져야 한다(달라지지 않으면 창 계산이 무의미)
d0<-200L
pit_ok<-!isTRUE(all.equal(TS[d0,1],sum(TA[(d0-12):d0,1][is.finite(TA[(d0-12):d0,1])])))
cat(sprintf("[PIT 대조] TS[d] 에 TA[d] 가 섞이지 않았다: %s\n",pit_ok))
stopifnot(pit_ok)

## ★버그 수리(자가 검거): oracle 은 **수익월**을 예지해야 한다. TA[m] = 월 m 형성 포트가 월 m+1 에 버는 active
##   = 이 라운드가 버는 바로 그 달. 구판은 TA[d]=TA[m-1](이미 실현)을 써서 oracle 이 아니라 1개월 후행 신호였다.
##   ⇒ 회수율 분모가 틀렸었다. src="oracle" 만 m 을 쓰고 나머지는 d 를 쓴다.
pickf<-function(d,k,src,m=NA_integer_){
  s<-if(src=="idx"){r<-match(YM[d],rownames(S));if(is.na(r))return(character(0));S[r,]}
     else if(src=="tail") TS[d,]
     else if(src=="tail_fresh") {stopifnot(!is.na(m)); TS2[m,]}   # 월 m 말 기준 최신(TA[m-1] 까지). PIT-safe
     else {stopifnot(!is.na(m)); TA[m,]}
  pos<-which(is.finite(s)&s>0);if(!length(pos))return(character(0))
  FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]]}

run<-function(mode,src,k=5L,bps=15,dec_lag=1L,seed=NA){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wl<-vector("list",NM);wprev<-NULL
  for(m in 2:NM){d<-m-dec_lag;if(d<1)next
    D<-P[ym==YM[m]];if(nrow(D)<N_TARGET)next
    wk<-if(!is.na(seed)){set.seed(seed*1000L+m);sample(FK,k)} else pickf(d,k,src,m)
    if(!length(wk))wk<-FK
    bs<-zmean(D,FK);bs[!is.finite(bs)]<--Inf
    if(mode=="weight_only"){o<-order(-bs);idx<-o[seq_len(N_TARGET)];w<-.tilt(neutralize(zmean(D,wk)[idx]))}
    else if(mode=="capw"){o<-order(-D$mktcap);idx<-o[seq_len(N_TARGET)];w<-.norm(D$mktcap[idx]/sum(D$mktcap[idx]))}
    else if(mode=="base"){o<-order(-bs);idx<-o[seq_len(N_TARGET)];w<-.tilt(neutralize(bs[idx]))}
    else {rs<-zmean(D,wk);rs[!is.finite(rs)]<--Inf;o<-order(-rs);idx<-o[seq_len(N_TARGET)];w<-.tilt(neutralize(rs[idx]))}
    tk<-D$Ticker[idx];names(w)<-tk
    at<-union(names(wprev),tk);a<-setNames(rep(0,length(at)),at);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev;b[tk]<-w
    dl<-sum(abs(b-a));tov[m]<-dl
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dl;wl[[m]]<-w
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov,wl=wl)}

cat("\n=== R56 표적-정합 신호 (prereg mfro_v2) ===\n[헤드라인: B2_tail_signal - C0_base, clean, k=5, 15bps]\n\n")
AR<-list(C0_base=run("base","idx"), C1_no_signal=run("capw","idx"),
         B1_idx_signal=run("weight_only","idx"), B2_tail_signal=run("weight_only","tail"),
         A2_tail_sel=run("sel_weight","tail"), B3_tail_fresh=run("weight_only","tail_fresh"),
         P_tail_oracle=run("weight_only","oracle"))
for(n in names(AR))for(w in c("full","clean")){r<-AR[[n]];s<-E[[w]]&is.finite(r$pr)&is.finite(bmf)
  p<-r$pr[s];ac<-p-bmf[s];nav<-cumprod(1+p);mdd<-min(nav/cummax(nav)-1);cg<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-16s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | CAGR=%+.1f%% MDD=%.3f calmar=%.3f | TO=%.1f\n",
    n,w,length(p),nwt(ac),IRf(ac),100*cg,mdd,cg/abs(mdd),mean(r$tov[s],na.rm=TRUE)*12))}

cat("\n[★조작 확인 — 사전등록 문턱 0.10]\n")
l1<-sapply(seq_len(NM),function(m){x<-AR$B2_tail_signal$wl[[m]];y<-AR$C0_base$wl[[m]]
  if(is.null(x)||is.null(y))return(NA_real_);k<-union(names(x),names(y))
  a<-setNames(rep(0,length(k)),k);b<-a;a[names(x)]<-x;b[names(y)]<-y;sum(abs(a-b))})
cat(sprintf("  B2 vs C0 비중 L1 중앙 %.4f -> %s\n",median(l1,na.rm=TRUE),
  ifelse(median(l1,na.rm=TRUE)>=0.10,"통과 (처치 전달)","미통과 (미결)")))

act<-function(r,w){s<-E[[w]]&is.finite(r$pr)&is.finite(bmf);mean((r$pr-bmf)[s])}
cat("\n[★순열 대조 200회 — 무작위 5팩터 재틸트 대비 (사전등록 2차 조작확인)]\n")
PERM<-sapply(1:200,function(sd_){r<-run("weight_only","tail",seed=sd_);c(full=act(r,"full"),clean=act(r,"clean"))})
for(w in c("full","clean")){obs<-act(AR$B2_tail_signal,w);pv<-mean(PERM[w,]>=obs)
  cat(sprintf("  %-5s 관측 %+.4f%%/월 | 순열 평균 %+.4f · sd %.4f | 우측 p=%.3f  %s\n",
    w,100*obs,100*mean(PERM[w,]),100*sd(PERM[w,]),pv,
    ifelse(pv<0.05,"★순열 밖 = 신호 기여","순열 안 = 재틸트 자체와 구별 불가")))}

cat("\n[대응표본 — 사전지정 판정]\n")
## ★필터 비대칭 수리(적대검증 결함④) — 부분월(bmf=NA)이 대응표본에만 들어가던 경로
pr2<-function(x,y,w){s<-E[[w]]&is.finite(AR[[x]]$pr)&is.finite(AR[[y]]$pr)&is.finite(bmf)
  d<-(AR[[x]]$pr-AR[[y]]$pr)[s]
  cat(sprintf("  %-32s %-5s mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(x," - ",y),w,100*mean(d),nwt(d)))}
for(w in c("full","clean")){pr2("B2_tail_signal","C0_base",w);pr2("B2_tail_signal","B1_idx_signal",w)
  pr2("B2_tail_signal","C1_no_signal",w);pr2("A2_tail_sel","C0_base",w)}

cat("\n[★회수율 — R55 비중만 clean -28.2% 대비 개선되는가]\n")
for(w in c("full","clean")){
  a0<-act(AR$C0_base,w);a1<-act(AR$B1_idx_signal,w);a2<-act(AR$B2_tail_signal,w);ao<-act(AR$P_tail_oracle,w)
  cat(sprintf("  %-5s | C0 %+.4f · B1(지수) %+.4f · B2(꼬리) %+.4f · 상한 %+.4f (%%/월)  ⇒ 회수율 B1 %.1f%% -> B2 %.1f%%\n",
    w,100*a0,100*a1,100*a2,100*ao,100*a1/ao,100*a2/ao))}

cat("\n[전 셀 전수 — clean IR: arm x k x cost]\n")
for(nm in c("B2_tail_signal","A2_tail_sel")){md<-if(nm=="B2_tail_signal")"weight_only" else "sel_weight"
  for(k in c(3L,5L,10L)){
    v<-sapply(c(5,15,25),function(bp){r<-run(md,"tail",k=k,bps=bp)
      s<-E$clean&is.finite(r$pr)&is.finite(bmf);IRf((r$pr-bmf)[s])})
    cat(sprintf("  %-16s k=%-3d %s\n",nm,k,paste(sprintf("%dbps:%+7.3f",c(5,15,25),v),collapse="  ")))}}
cat(sprintf("\n[결측 중립화] %d / %d (%.3f%%)\n",NAH$n,NAH$tot,100*NAH$n/max(NAH$tot,1)))
saveRDS(list(AR=AR,TA=TA,TS=TS,YM=YM,E=E,bmf=bmf,PERM=PERM,l1=l1),".cache/_mfro_r56.rds")
cat("\nR56_DONE\n")
