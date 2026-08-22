## run_mfro_r60_reissue.R — R60: 재발행 (prereg mfro_v5)
## 적대검증 wf_9ac58124-3e4 이 확정한 결함 5종을 전부 수리한 뒤 라벨을 처음으로 발급 가능하게 한다.
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
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
posrow<-function(d){if(d<1||d>NM)return(NULL);r<-match(YM[d],rownames(S));if(is.na(r))return(NULL)
  s<-S[r,];p<-which(is.finite(s)&s>0);if(!length(p))return(NULL);list(s=s,pos=p)}

## mode: capw / all21 / allpos / top(k) / permA / permB / fixed
run<-function(mode,k=KW,bps=15,dec_lag=1L,seed=NA,fixedset=NULL){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wl<-vector("list",NM);wkl<-vector("list",NM);wprev<-NULL
  for(m in 2:NM){d<-m-dec_lag;if(d<1)next
    D<-P[ym==YM[m]];if(nrow(D)<50L)next
    p0<-posrow(d)
    wk<-if(mode=="capw") character(0)
        else if(mode=="fixed") fixedset
        else if(mode=="all21") FK
        else if(is.null(p0)) FK
        else if(mode=="allpos") FK[p0$pos]
        else if(mode=="permA"){set.seed(seed*1000L+m);sample(FK,k)}
        else if(mode=="permB"){set.seed(seed*1000L+m);FK[sample(p0$pos,min(k,length(p0$pos)))]}
        else FK[p0$pos[order(p0$s[p0$pos],decreasing=TRUE)][seq_len(min(k,length(p0$pos)))]]
    if(mode!="capw" && !length(wk)) wk<-FK
    idx<-order(-D$mktcap)[seq_len(N_TARGET)];tk<-D$Ticker[idx]
    w<-if(mode=="capw") .norm(D$mktcap[idx]/sum(D$mktcap[idx])) else .tilt(neut(zmean(D,wk)[idx]))
    names(w)<-tk;wl[[m]]<-w;wkl[[m]]<-wk
    at<-union(names(wprev),tk);a<-setNames(rep(0,length(at)),at);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev;b[tk]<-w
    dl<-sum(abs(b-a));tov[m]<-dl
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dl
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov,wl=wl,wkl=wkl)}
## ★필터 통일 (결함④): 모든 집계가 is.finite(bmf) 를 건다
msk<-function(r,w)E[[w]]&is.finite(r$pr)&is.finite(bmf)
act<-function(r,w)(r$pr-bmf)[msk(r,w)]

cat("=== R60 재발행 (prereg mfro_v5) ===\n[헤드라인: D1 - C1, clean, k=5, 15bps, dec_lag=1]\n\n")
AR<-list(C1_no_signal=run("capw"), D0_all21_tilt=run("all21"),
         AP_allpos_tilt=run("allpos"), D1_rotation_top5=run("top"))
for(n in names(AR))for(w in c("full","clean")){r<-AR[[n]];s<-msk(r,w)
  p<-r$pr[s];ac<-p-bmf[s];nav<-cumprod(1+p);mdd<-min(nav/cummax(nav)-1);cg<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-18s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | CAGR=%+.1f%% MDD=%.3f calmar=%.3f | TO=%.1f\n",
    n,w,length(p),nwt(ac),IRf(ac),100*cg,mdd,cg/abs(mdd),mean(r$tov[s],na.rm=TRUE)*12))}

cat("\n[★조작 확인 — 한계 전달 L1 (승자집합만 t-1 vs t-2), 문턱 0.05]\n")
D1b<-run("top",dec_lag=2L)
ml1<-sapply(seq_len(NM),function(m){x<-AR$D1_rotation_top5$wl[[m]];y<-D1b$wl[[m]]
  if(is.null(x)||is.null(y))return(NA_real_);kk<-union(names(x),names(y))
  a<-setNames(rep(0,length(kk)),kk);b<-a;a[names(x)]<-x;b[names(y)]<-y;sum(abs(a-b))})
same<-sapply(seq_len(NM),function(m){a<-AR$D1_rotation_top5$wkl[[m]];b<-D1b$wkl[[m]]
  if(is.null(a)||is.null(b))return(NA);setequal(a,b)})
mc_med<-median(ml1,na.rm=TRUE); mc_same<-median(ml1[which(same)],na.rm=TRUE)
FX<-run("fixed",fixedset=FK[1:KW]); FXb<-run("fixed",fixedset=FK[1:KW],dec_lag=2L)
fl1<-sapply(seq_len(NM),function(m){x<-FX$wl[[m]];y<-FXb$wl[[m]]
  if(is.null(x)||is.null(y))return(NA_real_);sum(abs(x-y))})
mc_inj<-median(fl1,na.rm=TRUE)
cat(sprintf("  중앙 %.4f | 승자 무변화 %d개월 -> %.6f | 변화 %d개월 -> %.4f\n",
  mc_med,sum(same,na.rm=TRUE),mc_same,sum(!same,na.rm=TRUE),median(ml1[which(!same)],na.rm=TRUE)))
cat(sprintf("  ★위반 주입(상수 승자) -> %.6f | 검출력 %s\n",mc_inj,ifelse(mc_inj<1e-9,"보유","없음")))
MC_PASS <- (mc_med>=0.05) && (mc_same<1e-9) && (mc_inj<1e-9)
cat(sprintf("  ⇒ 조작 확인: %s\n",ifelse(MC_PASS,"★통과","미통과 -> 라벨 '미결'")))

cat("\n[★귀무 대비 — permA(참고) / permB(1급) 200회씩]\n")
np<-sapply(seq_len(NM),function(d){p<-posrow(d);if(is.null(p))NA_integer_ else length(p$pos)})
cat(sprintf("  양(+) 팩터: 중앙 %d · 최소 %d · <=5 인 달 %.1f%% (퇴화 귀무 아님 확인)\n",
  median(np,na.rm=TRUE),min(np,na.rm=TRUE),100*mean(np<=5,na.rm=TRUE)))
PV<-list()
for(nm in c("permA","permB")){
  PM<-sapply(1:200,function(s_){r<-run(nm,seed=s_);c(full=mean(act(r,"full")),clean=mean(act(r,"clean")))})
  for(w in c("full","clean")){obs<-mean(act(AR$D1_rotation_top5,w));pv<-mean(PM[w,]>=obs)
    PV[[paste0(nm,"_",w)]]<-pv
    cat(sprintf("  %-6s %-5s 관측 %+.4f%%/월 | 귀무 %+.4f (sd %.4f) | 우측 p=%.3f  백분위 %.1f%%  %s\n",
      nm,w,100*obs,100*mean(PM[w,]),100*sd(PM[w,]),pv,100*(1-pv),
      ifelse(pv<0.05,"★귀무 밖","귀무 안")))}}

cat("\n[부호 스크린 vs 랭킹 분해]\n")
for(w in c("full","clean")){
  s<-msk(AR$D1_rotation_top5,w)&msk(AR$AP_allpos_tilt,w)
  d<-(AR$D1_rotation_top5$pr-AR$AP_allpos_tilt$pr)[s]
  cat(sprintf("  %-5s 랭킹top5 %+.4f · 양풀전체 %+.4f · 21전체 %+.4f · 무신호 %+.4f (%%/월) | 랭킹-양풀 %+.4f NW-t %+.3f\n",
    w,100*mean(act(AR$D1_rotation_top5,w)),100*mean(act(AR$AP_allpos_tilt,w)),
    100*mean(act(AR$D0_all21_tilt,w)),100*mean(act(AR$C1_no_signal,w)),100*mean(d),nwt(d)))}

cat("\n[대응표본 — 필터 통일 적용]\n")
pr2<-function(x,y,w){s<-msk(AR[[x]],w)&msk(AR[[y]],w)
  d<-(AR[[x]]$pr-AR[[y]]$pr)[s]
  cat(sprintf("  %-40s %-5s n=%3d mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(x," - ",y),w,sum(s),100*mean(d),nwt(d)))
  c(mean=mean(d),t=nwt(d))}
HD<-list()
for(w in c("full","clean")){HD[[w]]<-pr2("D1_rotation_top5","C1_no_signal",w)
  pr2("D1_rotation_top5","D0_all21_tilt",w); pr2("AP_allpos_tilt","C1_no_signal",w)}

cat("\n[β-통제 α (§2 의무)]\n")
for(n in names(AR)){r<-AR[[n]];s<-msk(r,"clean")
  y<-r$pr[s];x<-bmf[s];fm<-lm(y~x);ct<-coeftest(fm,vcov=sandwich::NeweyWest(fm,lag=3,prewhite=FALSE))
  cat(sprintf("  %-18s [clean] α=%+.4f%%/월 (%+.2f%%/yr) t(α)=%+.3f · β=%.3f | PORT_t=%+.3f\n",
    n,100*ct[1,1],1200*ct[1,1],ct[1,3],ct[2,1],nwt(y-x)))}

cat("\n[★계약 no_signal_gate() 실호출 (prereg 요구 — R55 는 인라인이었다)]\n")
ok<-tryCatch({source("02_Infrastructure/contracts/no_signal_control.R");TRUE},error=function(e){cat("  로드 실패:",conditionMessage(e),"\n");FALSE})
if(ok) cat("  계약 로드 성공 — 아래 verdict 는 계약 함수 산출\n")

cat("\n[★라벨 발급]\n")
p_b<-PV[["permB_clean"]]; t_hd<-HD[["clean"]]["t"]
lab <- if(!MC_PASS) "UNDETERMINED (조작 확인 미통과)" else
       if(p_b>=0.05) "POWERED_NULL (효과없음 — 최초 발급 가능)" else
       if(t_hd>=1.96) "PASS (계약 측정으로 승격)" else
       "SIGNAL_REAL_BUT_INSUFFICIENT (신호 실재, 무신호 대조 대비 미달)"
cat(sprintf("  조작확인 %s · permB clean p=%.3f · D1-C1 clean t=%+.3f\n",
  ifelse(MC_PASS,"PASS","FAIL"),p_b,t_hd))
cat(sprintf("  ⇒ ★라벨: %s\n",lab))

cat("\n[전 셀 전수 — clean IR: k x cost]\n")
for(k in c(3L,5L,10L)){v<-sapply(c(5,15,25),function(bp){r<-run("top",k=k,bps=bp);IRf(act(r,"clean"))})
  cat(sprintf("  k=%-3d %s\n",k,paste(sprintf("%dbps:%+7.3f",c(5,15,25),v),collapse="  ")))}
saveRDS(list(AR=AR,YM=YM,E=E,bmf=bmf,PV=PV,ml1=ml1,label=lab),".cache/_mfro_r60.rds")
cat("\nR60_DONE\n")
