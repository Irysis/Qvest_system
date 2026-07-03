## run_ramp_shumulvey_v4.R — RAMP_02 breadth 확대: N팩터 일반화 (도훈 "팩터DB 전체 투입").
## v3(인과 rolling re-tune) 일반화: FACN=인덱스 컬럼 자동, P N×(N+1), 월별 *가용 view만* BL(단기 history 팩터 대응).
## env: SMV_IDXFILE / SMV_MINY / SMV_KEY. 계약 build_benchmark_compare authoritative pt.
suppressPackageStartupMessages({library(data.table); library(arrow); library(Rcpp); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
IDXFILE<-Sys.getenv("SMV_IDXFILE","outputs/ramp/shumulvey_index_returns_broad.parquet"); MINY<-as.integer(Sys.getenv("SMV_MINY","5")); KEY<-Sys.getenv("SMV_KEY","broad_m5_roll")
PER<-252;MAXY<-12;VALY<-6;RETUNE<-6
PG<-sprintf(".cache/_smv4_%s_prog.txt",KEY);cat("start\n",file=PG);pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_;for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
rollmin<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-min(x[lo:i])};y};rollmax<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-max(x[lo:i])};y}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
cppFunction('IntegerVector jumpDP(NumericMatrix C,double lam){int n=C.nrow();NumericMatrix D(n,2);IntegerMatrix B(n,2);D(0,0)=C(0,0);D(0,1)=C(0,1);for(int t=1;t<n;t++){for(int k=0;k<2;k++){double st=D(t-1,k);double sw=D(t-1,1-k)+lam;if(st<=sw){D(t,k)=C(t,k)+st;B(t,k)=k;}else{D(t,k)=C(t,k)+sw;B(t,k)=1-k;}}}IntegerVector s(n);s[n-1]=D(n-1,0)<=D(n-1,1)?0:1;for(int t=n-2;t>=0;t--)s[t]=B(t+1,s[t+1]);return s+1;}')
sparse_jm<-function(X,lam=50,kappa=sqrt(9.5),outer=8,inner=10){X<-as.matrix(X);T<-nrow(X);p<-ncol(X);wj<-rep(1/sqrt(p),p);s<-as.integer(X[,1]>median(X[,1]))+1L;soft<-function(a,d)sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){for(it in 1:inner){th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)};C<-matrix(0,T,2);for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2;C[,k]<-as.numeric(d2%*%wj)};ns<-jumpDP(C,lam);if(all(ns==s))break;s<-ns}
    th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)};gm<-colMeans(X);TSS<-colSums(sweep(X,2,gm,"-")^2);WCSS<-rep(0,p);for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)};a<-pmax(TSS-WCSS,0)
    f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))};if(f(0)<=kappa){d<-0}else{lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi};sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p)else sw/nm;if(max(abs(wnew-wj))<1e-4){wj<-wnew;break};wj<-wnew}
  list(s=s,th=th,w=wj)}
build_feat<-function(a,m){n<-length(a);L<-cumprod(1+ifelse(is.finite(a),a,0));F<-list();for(hl in c(8,21,63))F[[paste0("e",hl)]]<-ewm(a,hl)
  for(wn in c(8,21,63)){up<-ewm(pmax(a,0),wn);dn<-ewm(pmax(-a,0),wn);F[[paste0("rsi",wn)]]<-100-100/(1+up/(dn+1e-12))};for(wn in c(8,21,63)){rmn<-rollmin(L,wn);rmx<-rollmax(L,wn);F[[paste0("k",wn)]]<-100*(L-rmn)/(rmx-rmn+1e-12)}
  F[["m1"]]<-(ewm(L,8)-ewm(L,21))/L;F[["m2"]]<-(ewm(L,21)-ewm(L,63))/L;F[["dd"]]<-log(sqrt(ewm(pmin(a,0)^2,21))+1e-8);ma<-ewm(a,21);mm<-ewm(m,21);F[["b"]]<-ewm((a-ma)*(m-mm),21)/(ewm((m-mm)^2,21)+1e-12)
  F[["mk"]]<-ewm(m,21);rv<-rep(NA_real_,n);for(i in 22:n)rv[i]<-sd(m[(i-20):i]);F[["vx"]]<-ewm(c(NA,diff(log(rv+1e-8))),21);as.data.table(F)}
view_for<-function(s,aok){cur<-s[length(s)];max(min(mean(aok[s==cur])*PER,0.05),-0.05)}
ls_sharpe<-function(s,aok){pos<-numeric(length(s));for(i in seq_along(s)){vr<-mean(aok[s==s[i]])*PER;pos[i]<-max(min(vr/0.05,1),-1)};net<-pos*aok-5e-4*abs(c(0,diff(pos)));net<-net[is.finite(net)];if(sd(net)<1e-9)return(-9);mean(net)/sd(net)*sqrt(PER)}
std<-function(M){mu<-colMeans(M);sg<-apply(M,2,sd);sg[!is.finite(sg)|sg<1e-9]<-1;sweep(sweep(M,2,mu,"-"),2,sg,"/")}

R<-as.data.table(read_parquet(IDXFILE));R[,Date:=as.Date(Date)];setorder(R,Date)
META<-c("Date","as_of_date","source_version"); FACN<-setdiff(names(R),c(META,"Market")); IDX<-c("Market",FACN); N<-length(FACN)
for(c in IDX)R[[c]][!is.finite(R[[c]])]<-NA;R<-R[is.finite(Market)];ACT<-copy(R[,.(Date)]);for(f in FACN)ACT[[f]]<-R[[f]]-R$Market
ym<-format(R$Date,"%Y-%m");meix<-which(!duplicated(ym,fromLast=TRUE));medates<-R$Date[meix];RM<-copy(R);RM[,ym:=format(Date,"%Y-%m")];mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX];setorder(mon,ym);mon[,medate:=medates]
feats<-lapply(FACN,function(f)build_feat(ACT[[f]],R$Market));names(feats)<-FACN;GRID<-expand.grid(lam=c(20,50,100),k2=c(6,9.5,14))
pg("loaded idx=%s N=%d months=%d\n",basename(IDXFILE),N,length(medates))

## 팩터별 인과 rolling re-tune view (가용월만 산출)
view<-data.table(medate=medates)
for(f in FACN){X0<-feats[[f]];a<-ACT[[f]];vr<-rep(NA_real_,length(medates));cur<-list(lam=50,k2=9.5);last_tune<- -999
  for(mi in seq_along(medates)){ei<-meix[mi];lo_i<-which(R$Date>=max(R$Date[1],medates[mi]-MAXY*365))[1];tr_i<-lo_i:ei
    if(length(tr_i)<MINY*PER)next;Xtr<-as.matrix(X0[tr_i]);atr<-a[tr_i];ok<-which(apply(Xtr,1,function(r)all(is.finite(r)))&is.finite(atr));if(length(ok)<MINY*PER)next;Xok<-Xtr[ok,,drop=FALSE];aok<-atr[ok];Xs<-std(Xok)
    if(mi-last_tune>=RETUNE){vlo<-which(R$Date>=max(R$Date[1],medates[mi]-VALY*365))[1];vi<-vlo:ei;Xv<-as.matrix(X0[vi]);av<-a[vi];vok<-which(apply(Xv,1,function(r)all(is.finite(r)))&is.finite(av))
      if(length(vok)>=VALY*PER*0.7){Xvs<-std(Xv[vok,,drop=FALSE]);avk<-av[vok];best<-list(sh=-Inf,lam=50,k2=9.5)
        for(g in 1:nrow(GRID)){fit<-tryCatch(sparse_jm(Xvs,lam=GRID$lam[g],kappa=sqrt(GRID$k2[g])),error=function(e)NULL);if(is.null(fit))next;sh<-ls_sharpe(fit$s,avk);if(is.finite(sh)&&sh>best$sh)best<-list(sh=sh,lam=GRID$lam[g],k2=GRID$k2[g])}
        cur<-list(lam=best$lam,k2=best$k2);last_tune<-mi}}
    fit<-tryCatch(sparse_jm(Xs,lam=cur$lam,kappa=sqrt(cur$k2)),error=function(e)NULL);if(!is.null(fit))vr[mi]<-view_for(fit$s,aok)}
  view[[f]]<-vr;pg("  SJM %s done (nn=%d)\n",f,sum(!is.na(vr)))}
saveRDS(list(view=view,medates=medates,meix=meix,idxfile=IDXFILE,miny=MINY,FACN=FACN),sprintf(".cache/_smv4_regime_%s.rds",KEY))

## BL (가용 view subset) + 계약
RmatAll<-as.matrix(R[,..IDX]);RmatAll[!is.finite(RmatAll)]<-0;a126<-1-exp(log(0.5)/126);Sacc<-matrix(0,N+1,N+1);Sig_list<-vector("list",length(medates));.mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc;if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5;w_ew<-rep(1/(N+1),N+1);Pf<-matrix(0,N,N+1);for(j in 1:N)Pf[j,1+j]<-1;Pf[,1]<- -1;VIEW0<-as.matrix(view[,..FACN])
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-5,N+1);A<-cbind(rep(1,N+1),diag(N+1));b0<-c(1,rep(0,N+1));r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);ww<-pmax(r$solution,0);if(sum(ww)<1e-9)return(w_ew);ww/sum(ww)}
build_W<-function(cc){Wt<-matrix(NA_real_,length(medates),N+1);for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-VIEW0[mi,];av<-which(is.finite(vv));if(length(av)<2){Wt[mi,]<-w_ew;next}
  Pa<-Pf[av,,drop=FALSE];va<-vv[av];pri<-delta*as.numeric(Sig%*%w_ew);M<-Pa%*%Sig%*%t(Pa);Om<-cc*diag(diag(M),length(av));muBL<-pri+as.numeric(Sig%*%t(Pa)%*%solve(M+Om,(va-as.numeric(Pa%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
calib_c<-function(target){lo<-1e-3;hi<-50;for(b in 1:24){mid<-sqrt(lo*hi);W<-build_W(mid);tev<-c();for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig)||any(!is.finite(W[mi,])))next;tev<-c(tev,sqrt(as.numeric(t(W[mi,]-w_ew)%*%Sig%*%(W[mi,]-w_ew))))};mte<-mean(tev,na.rm=TRUE);if(!is.finite(mte)){hi<-mid;next};if(mte>target)lo<-mid else hi<-mid};sqrt(lo*hi)}
port<-function(W){keep<-which(apply(W,1,function(r)all(is.finite(r))));if(length(keep)<24)return(NULL);k0<-keep[1];rng<-k0:length(medates);mr<-as.matrix(mon[rng,..IDX]);dts<-mon$medate[rng];Wr<-W[rng,,drop=FALSE];for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,];Wr[!is.finite(Wr)]<-1/(N+1)
  pr<-numeric(nrow(mr));wprev<-rep(1/(N+1),N+1);to<-numeric(nrow(mr));for(i in 1:nrow(mr)){wt<-Wr[i,];ri<-mr[i,];d<-sum(abs(wt-wprev));pr[i]<-sum(wt*ri)-5e-4*d;to[i]<-d;wd<-wt*(1+ri);wprev<-wd/sum(wd)};data.table(date=dts,ret_net=pr,bm=mr[,1],to=to)}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
meas<-function(cc,lab){W<-build_W(cc);pp<-port(W);if(is.null(pp))return(NULL);prt<-data.table(date=pp$date,ret_net=pp$ret_net,frequency="monthly");bmt<-data.table(date=pp$date,benchmark_ret=pp$bm,benchmark_id="capw")
  bc<-build_benchmark_compare(prt,bmt,run_id="v4",strategy_id=lab,annualization_factor=12);pt<-bc[metric_name=="Portfolio_Alpha_t_NW_lag3",strategy_value];act<-pp$ret_net-pp$bm;nav<-cumprod(1+pp$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pp$ret_net)^(12/length(pp$ret_net))-1
  data.table(lab=lab,n_mo=length(pp$ret_net),test=as.character(min(pp$date)),pt=pt,IRm=bc[metric_name=="Information_Ratio",active_value],calmar=cagr/abs(mdd),oos=oos_ret(act),absSR=mean(pp$ret_net)/sd(pp$ret_net)*sqrt(12),TO=mean(pp$to)*12)}
cat(sprintf("=== RAMP_02 breadth v4 [%s] N=%d팩터 idx=%s MINY=%d ===\n",KEY,N,basename(IDXFILE),MINY))
out<-list();for(tgt in c(0.03,0.04)){cc<-calib_c(tgt);r<-meas(cc,sprintf("TE%.0f",tgt*100));if(!is.null(r)){r[,te:=tgt];out[[length(out)+1]]<-r}}
RES<-rbindlist(out,fill=TRUE)
cat(sprintf("  %-6s %5s %8s %6s %7s %6s %6s %6s %s\n","TE","n_mo","PORT_t","IRm","calmar","oos","absSR","TO","test"))
for(i in seq_len(nrow(RES))){r<-RES[i];cat(sprintf("  %-6s %5d %8.2f %6.2f %7.2f %6.2f %6.2f %6.1f  %s  [pt%s cal%s oos%s]\n",r$lab,r$n_mo,r$pt,r$IRm,r$calmar,r$oos,r$absSR,r$TO,r$test,ifelse(r$pt>=2.95,"P","F"),ifelse(r$calmar>=0.64,"P","F"),ifelse(!is.na(r$oos)&&r$oos>=0.7,"P",ifelse(!is.na(r$oos)&&r$oos>=0.5,"o","F"))))}
cat(sprintf("\n6팩터 RAMP_02 기준(MINY5 rolling): pt 7.72·calmar 0.92·oos 0.54\nV4_DONE %s\n",KEY))
