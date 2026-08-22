## run_mfro_r58.R — R58: 우주 교체 (prereg mfro_v3, chain of mfro_v2)
## ★자유도 1개 = base 우주만 "21팩터 composite 상위25" -> "시총 상위25" 로 교체. 신호·가중·비용 동일.
## 근거: R57b 분해 — clean 창 꼬리우주 -10.3%/yr 인데 선별 기여 +0.385%/월 은 era-안정.
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
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
winners<-function(d,k){r<-match(YM[d],rownames(S));if(is.na(r))return(character(0))
  s<-S[r,];pos<-which(is.finite(s)&s>0);if(!length(pos))return(character(0))
  FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]]}

## mode: capw(무신호) / comp_tilt(21팩터 틸트) / rot_tilt(승리팩터 틸트) / rot_sel(상위50중 승리z 상위25)
run<-function(mode,k=5L,bps=15,dec_lag=1L,seed=NA){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wl<-vector("list",NM);wprev<-NULL
  for(m in 2:NM){d<-m-dec_lag;if(d<1)next
    D<-P[ym==YM[m]];if(nrow(D)<50L)next
    wk<-if(!is.na(seed)){set.seed(seed*1000L+m);sample(FK,k)} else winners(d,k)
    if(!length(wk))wk<-FK
    ocap<-order(-D$mktcap)
    if(mode=="rot_sel"){
      pool<-ocap[seq_len(50L)]; rs<-neutralize(zmean(D,wk)[pool])
      idx<-pool[order(-rs)[seq_len(N_TARGET)]]; w<-.tilt(neutralize(zmean(D,wk)[idx]))
    } else {
      idx<-ocap[seq_len(N_TARGET)]
      w<-if(mode=="capw") .norm(D$mktcap[idx]/sum(D$mktcap[idx]))
         else if(mode=="comp_tilt") .tilt(neutralize(zmean(D,FK)[idx]))
         else .tilt(neutralize(zmean(D,wk)[idx]))}
    tk<-D$Ticker[idx];names(w)<-tk
    at<-union(names(wprev),tk);a<-setNames(rep(0,length(at)),at);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev;b[tk]<-w
    dl<-sum(abs(b-a));tov[m]<-dl
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dl;wl[[m]]<-w
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov,wl=wl)}

cat("=== R58 우주 교체 (prereg mfro_v3) ===\n[헤드라인: D1 - C1, clean, k=5, 15bps, dec_lag=1]\n\n")
AR<-list(C1_capw_no_signal=run("capw"), D0_composite_tilt=run("comp_tilt"),
         D1_rotation_tilt=run("rot_tilt"), D2_rotation_sel=run("rot_sel"))
for(n in names(AR))for(w in c("full","clean")){r<-AR[[n]];s<-E[[w]]&is.finite(r$pr)&is.finite(bmf)
  p<-r$pr[s];ac<-p-bmf[s];nav<-cumprod(1+p);mdd<-min(nav/cummax(nav)-1);cg<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-20s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | CAGR=%+.1f%% MDD=%.3f calmar=%.3f | TO=%.1f\n",
    n,w,length(p),nwt(ac),IRf(ac),100*cg,mdd,cg/abs(mdd),mean(r$tov[s],na.rm=TRUE)*12))}

cat("\n[★조작 확인 1 — D1 vs C1 비중 L1, 문턱 0.10]\n")
l1<-sapply(seq_len(NM),function(m){x<-AR$D1_rotation_tilt$wl[[m]];y<-AR$C1_capw_no_signal$wl[[m]]
  if(is.null(x)||is.null(y))return(NA_real_);kk<-union(names(x),names(y))
  a<-setNames(rep(0,length(kk)),kk);b<-a;a[names(x)]<-x;b[names(y)]<-y;sum(abs(a-b))})
cat(sprintf("  L1 중앙 %.4f -> %s\n",median(l1,na.rm=TRUE),
  ifelse(median(l1,na.rm=TRUE)>=0.10,"통과 (처치 전달)","미통과 -> 판정 '미결'")))

act<-function(r,w){s<-E[[w]]&is.finite(r$pr)&is.finite(bmf);(r$pr-bmf)[s]}
cat("\n[★조작 확인 2 — 순열 대조 200회 (무작위 5팩터 재틸트)]\n")
PERM<-sapply(1:200,function(sd_){r<-run("rot_tilt",seed=sd_)
  c(full=mean(act(r,"full")),clean=mean(act(r,"clean")))})
for(w in c("full","clean")){obs<-mean(act(AR$D1_rotation_tilt,w));pv<-mean(PERM[w,]>=obs)
  cat(sprintf("  %-5s 관측 %+.4f%%/월 | 순열 평균 %+.4f · sd %.4f | 우측 p=%.3f  %s\n",
    w,100*obs,100*mean(PERM[w,]),100*sd(PERM[w,]),pv,
    ifelse(pv<0.05,"★순열 밖 = 로테이션 기여","순열 안 = 재틸트 자체와 구별 불가")))}

cat("\n[대응표본 — 사전지정 판정]\n")
## ★필터 비대칭 수리(적대검증 결함④) — 실측: 이 결함으로 R58 헤드라인이 +0.2043(n=133)로 보고됐고
##   수리 후 +0.1925(n=132). 두 구현 비트 동일 대조로 확정(불일치 0).
pr2<-function(x,y,w){s<-E[[w]]&is.finite(AR[[x]]$pr)&is.finite(AR[[y]]$pr)&is.finite(bmf)
  d<-(AR[[x]]$pr-AR[[y]]$pr)[s];cat(sprintf("  %-42s %-5s mean=%+.4f%%/월 NW-t=%+.3f\n",
    paste0(x," - ",y),w,100*mean(d),nwt(d)))}
for(w in c("full","clean")){pr2("D1_rotation_tilt","C1_capw_no_signal",w)
  pr2("D1_rotation_tilt","D0_composite_tilt",w); pr2("D0_composite_tilt","C1_capw_no_signal",w)
  pr2("D2_rotation_sel","C1_capw_no_signal",w)}

cat("\n[β-통제 α (measurement-graduation §2, 2026-08-22 의무)]\n")
for(n in names(AR))for(w in c("clean")){r<-AR[[n]];s<-E[[w]]&is.finite(r$pr)&is.finite(bmf)
  y<-r$pr[s];x<-bmf[s];fm<-lm(y~x);ct<-coeftest(fm,vcov=sandwich::NeweyWest(fm,lag=3,prewhite=FALSE))
  cat(sprintf("  %-20s [clean] α=%+.4f%%/월 t(α)=%+.3f · β=%.3f | PORT_t=%+.3f\n",
    n,100*ct[1,1],ct[1,3],ct[2,1],nwt(y-x)))}

cat("\n[전 셀 전수 — clean IR: arm x k x cost x dec_lag]\n")
for(nm in c("D1_rotation_tilt","D2_rotation_sel")){md<-if(nm=="D1_rotation_tilt")"rot_tilt" else "rot_sel"
  for(k in c(3L,5L,10L))for(dl in c(1L,2L)){
    v<-sapply(c(5,15,25),function(bp){r<-run(md,k=k,bps=bp,dec_lag=dl)
      s<-E$clean&is.finite(r$pr)&is.finite(bmf);IRf((r$pr-bmf)[s])})
    cat(sprintf("  %-18s k=%-3d lag=%d  %s\n",nm,k,dl,paste(sprintf("%dbps:%+7.3f",c(5,15,25),v),collapse="  ")))}}
cat(sprintf("\n[결측 중립화] %d / %d (%.3f%%)\n",NAH$n,NAH$tot,100*NAH$n/max(NAH$tot,1)))
saveRDS(list(AR=AR,YM=YM,E=E,bmf=bmf,PERM=PERM,l1=l1),".cache/_mfro_r58.rds")
cat("\nR58_DONE\n")
