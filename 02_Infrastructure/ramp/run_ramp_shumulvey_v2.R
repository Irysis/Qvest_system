## run_ramp_shumulvey_v2.R — Shu-Mulvey 옵션1(확장기간/MINY) + 옵션2(per-factor λ/κ CV튜닝).
## online filter = 월간 last-state에선 smoother와 동일(Viterbi 역추적 마지막점 = forward argmin) → CV튜닝만 실효.
## env: SMV_IDXFILE / SMV_MINY / SMV_TUNE(cv|fixed) / SMV_KEY. 계약(build_benchmark_compare) authoritative pt.
suppressPackageStartupMessages({library(data.table); library(arrow); library(Rcpp); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
IDXFILE<-Sys.getenv("SMV_IDXFILE","outputs/ramp/shumulvey_index_returns_ext.parquet")
MINY<-as.integer(Sys.getenv("SMV_MINY","5")); TUNE<-Sys.getenv("SMV_TUNE","cv"); KEY<-Sys.getenv("SMV_KEY","ext_m5_cv")
PER<-252; MAXY<-12
PG<-sprintf(".cache/_smv2_%s_prog.txt",KEY); cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_
  for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
rollmin<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-min(x[lo:i])};y}
rollmax<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-max(x[lo:i])};y}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
cppFunction('IntegerVector jumpDP(NumericMatrix C, double lam){int n=C.nrow();NumericMatrix D(n,2);IntegerMatrix B(n,2);
  D(0,0)=C(0,0);D(0,1)=C(0,1);for(int t=1;t<n;t++){for(int k=0;k<2;k++){double stay=D(t-1,k);double sw=D(t-1,1-k)+lam;
  if(stay<=sw){D(t,k)=C(t,k)+stay;B(t,k)=k;}else{D(t,k)=C(t,k)+sw;B(t,k)=1-k;}}}
  IntegerVector s(n);s[n-1]=D(n-1,0)<=D(n-1,1)?0:1;for(int t=n-2;t>=0;t--)s[t]=B(t+1,s[t+1]);return s+1;}')
sparse_jm<-function(X,lam=50,kappa=sqrt(9.5),outer=8,inner=10){X<-as.matrix(X);T<-nrow(X);p<-ncol(X)
  wj<-rep(1/sqrt(p),p);s<-as.integer(X[,1]>median(X[,1]))+1L;soft<-function(a,d)sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){for(it in 1:inner){th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)}
    C<-matrix(0,T,2);for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2;C[,k]<-as.numeric(d2%*%wj)};ns<-jumpDP(C,lam);if(all(ns==s))break;s<-ns}
    th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)}
    gm<-colMeans(X);TSS<-colSums(sweep(X,2,gm,"-")^2);WCSS<-rep(0,p);for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)}
    a<-pmax(TSS-WCSS,0);f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))}
    if(f(0)<=kappa){d<-0}else{lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi}
    sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p)else sw/nm;if(max(abs(wnew-wj))<1e-4){wj<-wnew;break};wj<-wnew}
  list(s=s,th=th,w=wj)}
build_feat<-function(a,m){n<-length(a);L<-cumprod(1+ifelse(is.finite(a),a,0));F<-list()
  for(hl in c(8,21,63))F[[paste0("ewma",hl)]]<-ewm(a,hl)
  for(wn in c(8,21,63)){up<-ewm(pmax(a,0),wn);dn<-ewm(pmax(-a,0),wn);F[[paste0("rsi",wn)]]<-100-100/(1+up/(dn+1e-12))}
  for(wn in c(8,21,63)){rmn<-rollmin(L,wn);rmx<-rollmax(L,wn);F[[paste0("k",wn)]]<-100*(L-rmn)/(rmx-rmn+1e-12)}
  F[["macd_8_21"]]<-(ewm(L,8)-ewm(L,21))/L;F[["macd_21_63"]]<-(ewm(L,21)-ewm(L,63))/L
  F[["logdd21"]]<-log(sqrt(ewm(pmin(a,0)^2,21))+1e-8);ma<-ewm(a,21);mm<-ewm(m,21);F[["beta21"]]<-ewm((a-ma)*(m-mm),21)/(ewm((m-mm)^2,21)+1e-12)
  F[["mkt21"]]<-ewm(m,21);rv<-rep(NA_real_,n);for(i in 22:n)rv[i]<-sd(m[(i-20):i]);F[["vix21"]]<-ewm(c(NA,diff(log(rv+1e-8))),21)
  as.data.table(F)}

R<-as.data.table(read_parquet(IDXFILE));R[,Date:=as.Date(Date)];setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth");IDX<-c("Market",FACN)
for(c in IDX)R[[c]][!is.finite(R[[c]])]<-NA;R<-R[is.finite(Market)]
ACT<-copy(R[,.(Date)]);for(f in FACN)ACT[[f]]<-R[[f]]-R$Market
ym<-format(R$Date,"%Y-%m");meix<-which(!duplicated(ym,fromLast=TRUE));medates<-R$Date[meix]
RM<-copy(R);RM[,ym:=format(Date,"%Y-%m")];mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX];setorder(mon,ym);mon[,medate:=medates]
pg("loaded idx=%s rows=%d months=%d\n",IDXFILE,nrow(R),length(medates))

## CV튜닝: 초기윈도(첫 MINY년, pre-test)에서 단일팩터 LS Sharpe 최대 (λ,κ²) per factor — no look-ahead
GRID<-expand.grid(lam=c(20,50,100),k2=c(6,9.5,14))
ls_sharpe<-function(s,th,aok){mret<-c(mean(aok[s==1]),mean(aok[s==2]));bull<-which.max(mret)
  pos<-numeric(length(s));for(i in seq_along(s)){vr<-mean(aok[s==s[i]])*PER;pos[i]<-max(min(vr/0.05,1),-1)}
  net<-pos*aok-5e-4*abs(c(0,diff(pos)));net<-net[is.finite(net)];if(sd(net)<1e-9)return(-9);mean(net)/sd(net)*sqrt(PER)}
feats<-lapply(FACN,function(f)build_feat(ACT[[f]],R$Market));names(feats)<-FACN
start_i<-1; first_test_i<-which(R$Date>=R$Date[1]+MINY*365)[1]
tune<-list()
for(f in FACN){ if(TUNE=="fixed"){tune[[f]]<-list(lam=50,k2=9.5);next}
  tr_i<-start_i:(first_test_i-1); X0<-feats[[f]];a<-ACT[[f]]
  Xtr<-as.matrix(X0[tr_i]);atr<-a[tr_i];ok<-which(apply(Xtr,1,function(r)all(is.finite(r)))&is.finite(atr))
  Xok<-Xtr[ok,,drop=FALSE];aok<-atr[ok];mu<-colMeans(Xok);sg<-apply(Xok,2,sd);sg[!is.finite(sg)|sg<1e-9]<-1;Xs<-sweep(sweep(Xok,2,mu,"-"),2,sg,"/")
  best<-list(sh=-Inf,lam=50,k2=9.5)
  for(g in 1:nrow(GRID)){fit<-tryCatch(sparse_jm(Xs,lam=GRID$lam[g],kappa=sqrt(GRID$k2[g])),error=function(e)NULL);if(is.null(fit))next
    sh<-ls_sharpe(fit$s,fit$th,aok);if(is.finite(sh)&&sh>best$sh)best<-list(sh=sh,lam=GRID$lam[g],k2=GRID$k2[g])}
  tune[[f]]<-list(lam=best$lam,k2=best$k2);pg("  tune %s lam=%g k2=%g sh=%.2f\n",f,best$lam,best$k2,best$sh)}

## walk-forward SJM (last state = online==smoother), view ±5%cap
regime<-data.table(medate=medates);view_ann<-data.table(medate=medates)
for(f in FACN){X0<-feats[[f]];a<-ACT[[f]];lam<-tune[[f]]$lam;kap<-sqrt(tune[[f]]$k2)
  vw<-rep(NA_real_,length(medates))
  for(mi in seq_along(medates)){ei<-meix[mi];lo_i<-which(R$Date>=max(R$Date[1],medates[mi]-MAXY*365))[1];tr_i<-lo_i:ei
    if(length(tr_i)<MINY*PER)next;Xtr<-as.matrix(X0[tr_i]);atr<-a[tr_i];ok<-which(apply(Xtr,1,function(r)all(is.finite(r)))&is.finite(atr))
    if(length(ok)<MINY*PER)next;Xok<-Xtr[ok,,drop=FALSE];aok<-atr[ok];mu<-colMeans(Xok);sg<-apply(Xok,2,sd);sg[!is.finite(sg)|sg<1e-9]<-1;Xs<-sweep(sweep(Xok,2,mu,"-"),2,sg,"/")
    fit<-tryCatch(sparse_jm(Xs,lam=lam,kappa=kap),error=function(e)NULL);if(is.null(fit))next;s<-fit$s;cur<-s[length(s)]
    vraw<-mean(aok[s==cur])*PER;vw[mi]<-max(min(vraw,0.05),-0.05)}
  view_ann[[f]]<-vw;pg("  SJM %s done (non-NA=%d)\n",f,sum(!is.na(vw)))}
saveRDS(list(view_ann=view_ann,medates=medates,meix=meix,tune=tune,idxfile=IDXFILE,miny=MINY),sprintf(".cache/_smv2_regime_%s.rds",KEY))

## BL → 월간 포트 → 계약 측정
RmatAll<-as.matrix(R[,..IDX]);RmatAll[!is.finite(RmatAll)]<-0;a126<-1-exp(log(0.5)/126);Sacc<-matrix(0,7,7);Sig_list<-vector("list",length(medates));.mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc;if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5;w_ew<-rep(1/7,7);P<-matrix(0,6,7);for(j in 1:6)P[j,1+j]<-1;P[,1]<- -1;VIEW0<-as.matrix(view_ann[,..FACN])
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-6,7);A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7));r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);pmax(r$solution,0)/sum(pmax(r$solution,0))}
build_W<-function(cc){Wt<-matrix(NA_real_,length(medates),7);for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-VIEW0[mi,];if(any(!is.finite(vv)))next
  pri<-delta*as.numeric(Sig%*%w_ew);M<-P%*%Sig%*%t(P);Om<-cc*diag(diag(M));muBL<-pri+as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv-as.numeric(P%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
port<-function(cc){W<-build_W(cc);keep<-which(apply(W,1,function(r)all(is.finite(r))));if(length(keep)<24)return(NULL);k0<-keep[1];rng<-k0:length(medates)
  mr<-as.matrix(mon[rng,..IDX]);dts<-mon$medate[rng];Wr<-W[rng,,drop=FALSE];for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,];Wr[!is.finite(Wr)]<-1/7
  pr<-numeric(nrow(mr));wprev<-rep(1/7,7);to<-numeric(nrow(mr));for(i in 1:nrow(mr)){wt<-Wr[i,];ri<-mr[i,];d<-sum(abs(wt-wprev));pr[i]<-sum(wt*ri)-5e-4*d;to[i]<-d;wd<-wt*(1+ri);wprev<-wd/sum(wd)}
  data.table(date=dts,ret_net=pr,bm=mr[,1],to=to)}
calib_c<-function(target){lo<-1e-3;hi<-50;for(b in 1:26){mid<-sqrt(lo*hi);W<-build_W(mid)
  tev<-c();for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig)||any(!is.finite(W[mi,])))next;tev<-c(tev,sqrt(as.numeric(t(W[mi,]-w_ew)%*%Sig%*%(W[mi,]-w_ew))))}
  mte<-mean(tev,na.rm=TRUE);if(!is.finite(mte)){hi<-mid;next};if(mte>target)lo<-mid else hi<-mid};sqrt(lo*hi)}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
measure<-function(cc,lab){pp<-port(cc);if(is.null(pp))return(NULL)
  prt<-data.table(date=pp$date,ret_net=pp$ret_net,frequency="monthly");bmt<-data.table(date=pp$date,benchmark_ret=pp$bm,benchmark_id="capw")
  bc<-build_benchmark_compare(prt,bmt,run_id="smv2",strategy_id=lab,annualization_factor=12)
  pt<-bc[metric_name=="Portfolio_Alpha_t_NW_lag3",strategy_value];ir<-bc[metric_name=="Information_Ratio",active_value]
  act<-pp$ret_net-pp$bm;nav<-cumprod(1+pp$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pp$ret_net)^(12/length(pp$ret_net))-1
  data.table(lab=lab,n_mo=length(pp$ret_net),test_start=as.character(min(pp$date)),pt=pt,IR_vsMkt=ir,calmar=cagr/abs(mdd),oos=oos_ret(act),absSR=mean(pp$ret_net)/sd(pp$ret_net)*sqrt(12),absCAGR=cagr,absMDD=mdd,TO=mean(pp$to)*12)}

cat(sprintf("=== Shu-Mulvey v2 [%s] idx=%s MINY=%d TUNE=%s ===\n",KEY,basename(IDXFILE),MINY,TUNE))
cat(sprintf("  tuned λ/κ²: %s\n",paste(sapply(FACN,function(f)sprintf("%s=%g/%g",f,tune[[f]]$lam,tune[[f]]$k2)),collapse=" ")))
out<-list()
for(tgt in c(0.03,0.04)){cc<-calib_c(tgt);r<-measure(cc,sprintf("TE%.0f",tgt*100));if(!is.null(r)){r[,c_used:=round(cc,2)][,te_tgt:=tgt];out[[length(out)+1]]<-r}}
RES<-rbindlist(out,fill=TRUE)
cat(sprintf("  %-6s %6s %10s %8s %8s %8s %8s %8s\n","TE","n_mo","PORT_t","IR","calmar","oos","absSR","test_start"))
for(i in seq_len(nrow(RES))){r<-RES[i];cat(sprintf("  %-6s %6d %10.2f %8.2f %8.2f %8.2f %8.2f  %s  [pt%s cal%s oos%s]\n",
  r$lab,r$n_mo,r$pt,r$IR_vsMkt,r$calmar,r$oos,r$absSR,r$test_start,ifelse(r$pt>=2.95,"P","F"),ifelse(r$calmar>=0.64,"P","F"),ifelse(!is.na(r$oos)&&r$oos>=0.7,"P","F")))}
# JSON 결과 (collision-free)
library(jsonlite)
write_json(list(key=KEY,idx=basename(IDXFILE),miny=MINY,tune=TUNE,tuned=lapply(FACN,function(f)tune[[f]]),results=RES),
  sprintf(".cache/_smv2_%s.json",KEY),auto_unbox=TRUE,digits=4)
cat(sprintf("V2_DONE %s\n",KEY))
