## weight_advanced.R — RAMP_04 고급 통계 가중방법 하니스 (도훈 지시 2026-06-20)
## 공유캐시(.cache/_ramp04_shared.rds: HOLD 25종목 selection + score/Size/lv, RMm wide returns, OV 크래시오버레이) 소비.
## 방법별 weights → weighted_screen_bt(15bps) → 모멘텀-크래시 오버레이 → pt/oos/SR/calmar. vs Book 2.64/0.37/1.36/1.33.
## WEIGHT_METHOD env로 단일 방법 실행(워크플로우 병렬), 미지정 시 전체 순차.
suppressPackageStartupMessages({library(arrow);library(data.table);library(quadprog)}); setDTthreads(1); arrow::set_cpu_count(1); setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/weighted_screen_bt.R");suppressMessages({library(sandwich);library(lmtest)})
SH<-readRDS(".cache/_ramp04_shared.rds");HOLD<-SH$HOLD;RMm<-SH$RMm;OV<-SH$OV;dts<-SH$dts;ND<-SH$ND;fwd_ret<-SH$fwd_ret;bench<-SH$bench;liq<-SH$liq
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)};calf<-function(r){nav<-cumprod(1+r);cagr<-prod(1+r)^(12/length(r))-1;cagr/abs(min(nav/cummax(nav)-1))}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w);for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20;if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
## --- 공분산 추정기 ---
lw_shrink<-function(R){R<-R[,colSums(is.finite(R))>=nrow(R)*0.6,drop=FALSE];R[!is.finite(R)]<-0;n<-nrow(R);p<-ncol(R);if(p<2)return(list(S=diag(max(p,1)),cols=colnames(R)))
  S<-cov(R);d<-mean(diag(S));T0<-diag(d,p);   # shrink to scaled identity (Ledoit-Wolf 2004 단순형)
  # 최적 shrink 강도(근사): 분산의 분산 기반
  Xc<-scale(R,center=TRUE,scale=FALSE);phi<-sum((crossprod(Xc^2)/n - S^2))/n; gamma<-sum((S-T0)^2); lam<-max(0,min(1,(phi/gamma)/n*p)); if(!is.finite(lam))lam<-0.3
  list(S=(1-lam)*S+lam*T0,cols=colnames(R),lam=lam)}
denoise_cov<-function(R){R<-R[,colSums(is.finite(R))>=nrow(R)*0.6,drop=FALSE];R[!is.finite(R)]<-0;sdv0<-apply(R,2,sd);R<-R[,sdv0>1e-9,drop=FALSE];n<-nrow(R);p<-ncol(R);if(p<3)return(list(S=cov(R),cols=colnames(R)))
  sdv<-apply(R,2,sd);sdv[sdv<1e-8]<-1e-8;Cr<-cor(R);Cr[!is.finite(Cr)]<-0;diag(Cr)<-1;e<-eigen(Cr,symmetric=TRUE);ev<-pmax(e$values,1e-8);q<-n/p;lmax<-(1+sqrt(1/q))^2 # Marčenko-Pastur 상한
  ev2<-ev;noise<-ev<lmax;if(any(noise))ev2[noise]<-mean(ev[noise]);Cr2<-e$vectors%*%diag(ev2)%*%t(e$vectors);Cr2<-(Cr2+t(Cr2))/2;diag(Cr2)<-1;S<-outer(sdv,sdv)*Cr2;list(S=S,cols=colnames(R))}
## --- 트레일링 수익(36m) for month i, held tickers ---
trail<-function(i,tk,k=36){ri<-which(rownames(RMm)==as.character(dts[i]));if(length(ri)==0)return(NULL);tk<-tk[tk%in%colnames(RMm)];if(length(tk)<3)return(NULL);M<-RMm[max(1,ri-k):(ri-1),tk,drop=FALSE];M}
## --- 최적화기 (모두 long-only, Σw=1, [0,0.20]) ---
minvar<-function(S){p<-ncol(S);Dm<-S+diag(1e-5,p);A<-cbind(rep(1,p),diag(p),-diag(p));b<-c(1,rep(0,p),rep(-0.20,p));r<-tryCatch(solve.QP(Dm,rep(0,p),A,b,meq=1),error=function(e)NULL);if(is.null(r))return(rep(1/p,p));cap_norm(pmax(r$solution,0))}
maxsharpe<-function(S,mu,delta=2.5){p<-ncol(S);Dm<-delta*(S+diag(1e-5,p));A<-cbind(rep(1,p),diag(p),-diag(p));b<-c(1,rep(0,p),rep(-0.20,p));r<-tryCatch(solve.QP(Dm,mu,A,b,meq=1),error=function(e)NULL);if(is.null(r))return(rep(1/p,p));cap_norm(pmax(r$solution,0))}
erc<-function(S){p<-ncol(S);w<-1/sqrt(diag(S));w<-w/sum(w);for(it in 1:200){mrc<-as.numeric(S%*%w);rc<-w*mrc;tgt<-mean(rc);w<-w*(tgt/(rc+1e-12))^0.1;w[w<0]<-0;w<-w/sum(w)};cap_norm(w)}
maxdiv<-function(S){p<-ncol(S);sdv<-sqrt(diag(S));Dm<-S+diag(1e-5,p);A<-cbind(rep(1,p),diag(p),-diag(p));b<-c(1,rep(0,p),rep(-0.20,p));r<-tryCatch(solve.QP(Dm,rep(0,p),A,b,meq=1),error=function(e)NULL) # maxdiv = minvar of corr → 근사: minvar on corr matrix
  Cr<-S/outer(sdv,sdv);Dc<-Cr+diag(1e-5,p);r2<-tryCatch(solve.QP(Dc,rep(0,p),A,b,meq=1),error=function(e)NULL);if(is.null(r2))return(rep(1/p,p));w<-pmax(r2$solution,0)/sdv;cap_norm(w)}
hrp<-function(S){p<-ncol(S);if(p<3)return(rep(1/p,p));sdv<-sqrt(diag(S));Cr<-S/outer(sdv,sdv);Cr[!is.finite(Cr)]<-0;d<-sqrt(pmax(0.5*(1-Cr),0));hc<-tryCatch(hclust(as.dist(d),method="single"),error=function(e)NULL);if(is.null(hc))return(cap_norm(1/sdv))
  ord<-hc$order;w<-rep(1,p);names(w)<-1:p;cl<-list(ord)
  while(length(cl)>0){nc<-list();for(items in cl){if(length(items)<=1)next;half<-floor(length(items)/2);c1<-items[1:half];c2<-items[(half+1):length(items)]
    getIV<-function(idx){sub<-S[idx,idx,drop=FALSE];iv<-1/diag(sub);iv<-iv/sum(iv);as.numeric(t(iv)%*%sub%*%iv)};v1<-getIV(c1);v2<-getIV(c2);a<-1-v1/(v1+v2);w[c1]<-w[c1]*a;w[c2]<-w[c2]*(1-a);nc<-c(nc,list(c1),list(c2))};cl<-nc}
  cap_norm(w)}
nco<-function(S,mu=NULL){p<-ncol(S);if(p<4)return(if(is.null(mu))minvar(S) else maxsharpe(S,mu));sdv<-sqrt(diag(S));Cr<-S/outer(sdv,sdv);Cr[!is.finite(Cr)]<-0;d<-sqrt(pmax(0.5*(1-Cr),0))
  hc<-tryCatch(hclust(as.dist(d),method="ward.D2"),error=function(e)NULL);if(is.null(hc))return(minvar(S));K<-max(2,min(8,round(sqrt(p))));cl<-cutree(hc,k=K)
  # intra-cluster minvar → cluster reduced cov → inter minvar
  wIntra<-rep(0,p);for(k in 1:K){idx<-which(cl==k);if(length(idx)==1){wIntra[idx]<-1}else{sub<-S[idx,idx,drop=FALSE];wi<-minvar(sub);wIntra[idx]<-wi}}
  # reduced cov between clusters
  Sred<-matrix(0,K,K);for(a in 1:K)for(b in 1:K){ia<-which(cl==a);ib<-which(cl==b);Sred[a,b]<-as.numeric(t(wIntra[ia])%*%S[ia,ib,drop=FALSE]%*%wIntra[ib])}
  wInter<-minvar(Sred+diag(1e-8,K));w<-rep(0,p);for(k in 1:K){idx<-which(cl==k);w[idx]<-wIntra[idx]*wInter[k]};cap_norm(w)}
## --- 방법 디스패치: month i, held d(Ticker,score,Size,lv,momz) → weights ---
build_weights<-function(method){WL<-vector("list",ND)
  for(i in seq_len(ND)){d<-HOLD[Date==dts[i]];if(nrow(d)<10){WL[[i]]<-d[,.(Date,Ticker,w=1/.N)];next};tk<-d$Ticker
    w<-NULL
    if(method=="capmlowvol"){x<-d$Size*exp(pmax(d$lv,-2));w<-cap_norm(x)
    }else if(method=="ew"){w<-rep(1/nrow(d),nrow(d))
    }else if(method=="score_iv"){iv<-exp(pmax(d$lv,-2));sc<-pmax(d$score-min(d$score)+0.1,0.01);w<-cap_norm(sc*iv) # alpha × inverse-vol proxy
    }else{ Mtr<-trail(i,tk);if(is.null(Mtr)||ncol(Mtr)<5){x<-d$Size*exp(pmax(d$lv,-2));w<-cap_norm(x)}else{
      keep<-match(colnames(Mtr),tk);dk<-d[keep];
      est<-if(method%in%c("denoise_mvo","denoise_minvar"))denoise_cov(Mtr) else lw_shrink(Mtr);S<-est$S;ci<-match(est$cols,tk);ci<-ci[!is.na(ci)];S<-S[seq_along(ci),seq_along(ci),drop=FALSE];dk<-d[ci]
      mu<-{s<-dk$score;0.02*((s-mean(s))/ (sd(s)+1e-9))} # score→월 기대초과수익 스케일
      wsub<-switch(method, lw_minvar=minvar(S), lw_maxsharpe=maxsharpe(S,mu), hrp=hrp(S), erc=erc(S), maxdiv=maxdiv(S), denoise_mvo=maxsharpe(S,mu), denoise_minvar=minvar(S), nco=nco(S), nco_alpha=nco(S,mu), rp_alpha={rp<-erc(S);sc<-pmax(dk$score-min(dk$score)+0.1,0.01);cap_norm(rp*sc)}, bayes_mvo={mus<-0.5*mu;maxsharpe(S,mus)}, minvar(S))
      w<-rep(0,nrow(d));w[ci]<-wsub;if(sum(w)<=0)w<-rep(1/nrow(d),nrow(d));w<-cap_norm(w)}}
    WL[[i]]<-data.table(Date=dts[i],Ticker=tk,w=w)}
  rbindlist(WL)}
measure<-function(method){W<-build_weights(method);r<-tryCatch(weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id=paste0("w_",method),strategy_id=method),error=function(e)NULL);if(is.null(r$period_returns))return(NULL)
  pr<-as.data.table(r$period_returns);setorder(pr,date);pr<-merge(pr,OV,by="date",all.x=T);pr[is.na(crash_exp),crash_exp:=1]
  res<-list()
  for(ov in c("none","crash")){e<-if(ov=="none")rep(1,nrow(pr)) else pr$crash_exp;rn<-e*pr$ret_net;act<-rn-pr$benchmark_ret
    res[[ov]]<-data.table(method=method,overlay=ov,pt=nwt(act),oos=oosr(act),SR=IRf(rn),calmar=calf(rn),TO=r$turnover_annual)}
  rbindlist(res)}
METHODS<-c("capmlowvol","ew","score_iv","lw_minvar","lw_maxsharpe","hrp","erc","maxdiv","denoise_mvo","denoise_minvar","nco","nco_alpha","rp_alpha","bayes_mvo")
sel<-Sys.getenv("WEIGHT_METHOD","");if(nzchar(sel))METHODS<-strsplit(sel,",")[[1]]
out<-list();for(m in METHODS){r<-tryCatch(measure(m),error=function(e){cat("ERR",m,conditionMessage(e),"\n");NULL});if(!is.null(r))out[[m]]<-r}
R<-rbindlist(out);saveRDS(R,sprintf(".cache/_wadv_%s.rds",ifelse(nzchar(sel),gsub(",","_",sel),"all")))
cat("=== 고급 가중방법 × 오버레이 (vs Book 2.64/0.37/1.36/1.33) ===\n")
cat(sprintf("  %-15s %-6s %5s %5s %5s %6s %5s\n","method","ov","pt","oos","SR","calmar","TO"))
setorder(R,-SR)
for(i in seq_len(nrow(R))){r<-R[i];win<-isTRUE(r$SR>1.36&&r$calmar>1.33&&r$pt>2.64&&r$oos>0.37);cat(sprintf("  %-15s %-6s %5.2f %5.2f %5.2f %6.2f %5.1f%s\n",r$method,r$overlay,r$pt,r$oos,r$SR,r$calmar,r$TO,ifelse(win," ★★ALL>Book",""))) }
cat("WADV_DONE\n")
