## run_mfro_r55.R — MFRO(Multi-Factor Rotation Overlay) R55
## prereg outputs/ramp/mfro_v1_prereg_20260822.json (결과 산출 전 기록됨)
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}

## ── production 가중 규칙 (05_Production/.../forward_weights_R05_noLayer4.R:23-24 인용, 무개조) ──
UB<-0.20; LAMBDA<-1.5; N_TARGET<-25L; LIQ<-2e8   # N=25 = Production Constraints 상한(사전고정)
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}

P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney")
FK<-intersect(FK,names(P)); NF<-length(FK)
P<-P[is.finite(adv20) & adv20>=LIQ]                 # 유동성 t-1 (C10)
setorder(P,ym)
YM<-sort(unique(P$ym)); NM<-length(YM)
cat(sprintf("[panel] 월 %d (%s~%s) · 팩터 %d · 월당 종목 중앙 %d\n",NM,YM[1],YM[NM],NF,
  as.integer(median(P[,.N,by=ym]$N))))

## ── 로테이션 신호: DFA 21 지수 trailing 12M active ──
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym); NI<-nrow(mi)
S<-matrix(NA_real_,NI,NF); dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF) for(m in 12:NI) S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
## 익월 실현 active (oracle 상한용)
FA<-matrix(NA_real_,NI,NF); dimnames(FA)<-list(mi$ym,FK)
for(j in 1:NF) FA[1:(NI-1),j]<-(mi[[FK[j]]][-1]-mi$Market[-1])

winners<-function(ym_dec,k=5L,oracle=FALSE){
  r<-match(ym_dec,rownames(S)); if(is.na(r))return(character(0))
  s<-if(oracle) FA[r,] else S[r,]
  pos<-which(is.finite(s)&s>0); if(!length(pos))return(character(0))
  FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]] }

zmean<-function(D,cols){ if(!length(cols))return(rep(NA_real_,nrow(D)))
  M<-as.matrix(D[,cols,with=FALSE]); rowMeans(M,na.rm=TRUE) }

## ── 팔 실행 ──
run_arm<-function(arm,k=5L,bps=15,dec_lag=1L){
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); nsel<-rep(NA_real_,NM)
  wl<-vector("list",NM); wprev<-NULL; prevT<-character(0)
  for(m in seq_len(NM)){
    d<-m-dec_lag; if(d<1) next
    D<-P[ym==YM[m]]; if(nrow(D)<N_TARGET) next
    ymd<-YM[d]
    wk<-if(arm %in% c("B","A","P")) winners(ymd,k,oracle=(arm=="P")) else character(0)
    if(arm %in% c("B","A","P") && !length(wk)) wk<-FK          # 승자 없으면 전체(폴백 사전고정)
    base_s<-zmean(D,FK)
    if(arm=="C1"){                                            # 무신호: 시총 상위 25 · 시총가중
      o<-order(-D$mktcap); idx<-o[seq_len(N_TARGET)]
      w<-D$mktcap[idx]/sum(D$mktcap[idx]); w<-.norm(w)
    } else if(arm=="C0"){
      o<-order(-base_s); idx<-o[seq_len(N_TARGET)]; w<-.tilt(base_s[idx])
    } else if(arm=="B"){                                      # ★순수 오버레이: C0 와 동일 25종, 비중만 재틸트
      o<-order(-base_s); idx<-o[seq_len(N_TARGET)]; w<-.tilt(zmean(D,wk)[idx])
    } else {                                                  # A / P: 승리팩터로 선택+비중
      rs<-zmean(D,wk); o<-order(-rs); idx<-o[seq_len(N_TARGET)]; w<-.tilt(rs[idx])
    }
    tk<-D$Ticker[idx]; names(w)<-tk
    allt<-union(names(wprev),tk)
    a<-setNames(rep(0,length(allt)),allt); b<-a
    if(!is.null(wprev)) a[names(wprev)]<-wprev
    b[tk]<-w
    dlt<-sum(abs(b-a)); tov[m]<-dlt; nsel[m]<-length(tk)
    fr<-D$fwd_ret[idx]; fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dlt
    wl[[m]]<-w
    wd<-w*(1+fr); wprev<-wd/sum(wd)                            # drift
  }
  list(pr=pr,tov=tov,nsel=nsel,wl=wl) }

## ── 벤치 (유니버스 시총가중 월수익) ──
bm<-mi$Market[match(YM,mi$ym)]
## fwd 정렬: 팔의 pr[m] 은 YM[m] 결정 → 익월 실현. 벤치도 익월로 맞춘다.
bmf<-c(bm[-1],NA_real_)

cat("\n=== R55 MFRO (prereg mfro_v1) ===\n[헤드라인 사전지정: B - C0, clean(2015-07~), k=5, 15bps, dec_lag=1]\n\n")
ARMS<-c("C0","C1","B","A","P")
res<-list(); for(a in ARMS) res[[a]]<-run_arm(a)
E<-list(full=rep(TRUE,NM), clean=YM>="2015-07")
rep1<-function(r,lab,w){ s<-E[[w]]&is.finite(r$pr)&is.finite(bmf); p<-r$pr[s]; ac<-p-bmf[s]
  nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); cagr<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-24s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | CAGR=%+.1f%% MDD=%.3f calmar=%.3f | TO=%.2f 종목=%.0f\n",
    lab,w,length(p),nwt(ac),IRf(ac),100*cagr,mdd,cagr/abs(mdd),mean(r$tov[s],na.rm=TRUE)*12,mean(r$nsel,na.rm=TRUE))) }
LBL<-c(C0="C0_base_no_rotation",C1="C1_no_signal_control",B="B_weight_only_rotation",
       A="A_selection_and_weight",P="P_oracle_ceiling")
for(a in ARMS) for(w in c("full","clean")) rep1(res[[a]],LBL[a],w)

cat("\n[★조작 확인 — 사전등록 문턱: 중앙 L1 >= 0.10]\n")
l1<-sapply(seq_len(NM),function(m){x<-res$B$wl[[m]];y<-res$C0$wl[[m]]
  if(is.null(x)||is.null(y))return(NA_real_); k<-union(names(x),names(y))
  a<-setNames(rep(0,length(k)),k);b<-a;a[names(x)]<-x;b[names(y)]<-y;sum(abs(a-b))})
medL1<-median(l1,na.rm=TRUE)
wt<-sapply(2:NM,function(m){w1<-winners(YM[m-1]);w0<-winners(YM[m-2]);if(!length(w1)||!length(w0))return(NA_real_)
  1-length(intersect(w1,w0))/length(union(w1,w0))})
cat(sprintf("  B vs C0 월별 비중 L1 거리: 중앙 %.4f (범위 %.4f~%.4f)\n",medL1,min(l1,na.rm=TRUE),max(l1,na.rm=TRUE)))
cat(sprintf("  승리팩터 집합 월별 교체율: 중앙 %.3f (0 이면 정적 선택)\n",median(wt,na.rm=TRUE)))
cat(sprintf("  ⇒ 처치 전달 판정: %s\n", ifelse(medL1>=0.10,"★통과 — 결과 해석 가능",
    "미통과 — 어떤 결과든 '미결(처치 미전달)' 이며 '효과없음' 으로 쓸 수 없다")))

cat("\n[대응표본 — 사전지정 판정]\n")
pair<-function(x,y,w){ s<-E[[w]]&is.finite(res[[x]]$pr)&is.finite(res[[y]]$pr)
  d<-(res[[x]]$pr-res[[y]]$pr)[s]
  cat(sprintf("  %-26s %-5s n=%3d mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(LBL[x]," - ",y),w,sum(s),100*mean(d),nwt(d))) }
for(w in c("full","clean")){ pair("B","C0",w); pair("A","C0",w); pair("B","C1",w); pair("P","C0",w) }

cat("\n[전 셀 전수 보고 — clean 창 IR: arm x k x cost x dec_lag]\n")
cat(sprintf("  %-24s %-4s %-6s %s\n","arm","k","cost","lag1     lag2"))
for(a in c("B","A")) for(k in c(3L,5L,10L)) for(bp in c(5,15,25)){
  v<-sapply(1:2,function(dl){r<-run_arm(a,k=k,bps=bp,dec_lag=dl)
    s<-E$clean&is.finite(r$pr)&is.finite(bmf); IRf((r$pr-bmf)[s])})
  cat(sprintf("  %-24s %-4d %-6s %s\n",LBL[a],k,paste0(bp,"bps"),paste(sprintf("%+8.3f",v),collapse=" "))) }
saveRDS(list(res=res,YM=YM,E=E,bmf=bmf,l1=l1,medL1=medL1),".cache/_mfro_r55.rds")
cat("\nR55_DONE\n")
