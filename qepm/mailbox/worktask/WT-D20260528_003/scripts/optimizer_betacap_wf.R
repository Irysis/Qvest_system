#==============================================================================
# RF-R1: Walk-forward net-SR impact of MKT beta-cap on the Schedule book.
# Compare Schedule (selected) vs Schedule+betacap1.00 vs Schedule+betacap0.95.
#==============================================================================
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)
  library(PerformanceAnalytics);library(xts);library(quadprog)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot";setwd(ROOT)
WT<-"WT-D20260528_003";ABASE<-"stage_artifacts/WT_D20260528_003";RBASE<-"stage_artifacts/WT_D20260528_003_risk_PROD"
COMMISSION<-0.0015;WMAX<-0.20
sched<-as.data.table(read_parquet(file.path(ABASE,"weights_schedule.parquet")));sched[,Date:=as.Date(Date)]
alpha<-as.data.table(read_parquet(file.path(ABASE,"alpha_scores.parquet")));alpha[,Date:=as.Date(Date)]
B<-as.data.table(read_parquet(file.path(RBASE,"B_loadings.parquet")));setkey(B,Ticker)
raw<-as.data.table(read_parquet(".cache/rawdata.parquet"))[,.(Date,Ticker,Ret,BM_Ret)];raw[,Date:=as.Date(Date)]
raw<-raw[Date>=as.Date("2014-01-01")&Date<=as.Date("2024-01-31")]
held<-sort(unique(sched$Ticker));rh<-raw[Ticker%in%held]
WIDE<-dcast(rh,Date~Ticker,value.var="Ret");WD<-WIDE$Date;WM<-as.matrix(WIDE[,-1,with=FALSE]);WC<-colnames(WM);WM[!is.finite(WM)]<-NA
bmd<-unique(raw[,.(Date,BM_Ret)])[order(Date)]
sig<-sort(unique(alpha$Date));NS<-length(sig)
.norm<-function(w){w[w<0]<-0;if(sum(w)<=0)w<-rep(1,length(w));w/sum(w)}
.cap<-function(w,wmax=WMAX){for(i in 1:200){w<-.norm(w);o<-w>wmax+1e-12;if(!any(o))break;ex<-sum(w[o]-wmax);w[o]<-wmax;u<-!o&w>0;if(!any(u)){w<-w/sum(w);break};w[u]<-w[u]+ex*w[u]/sum(w[u])};.norm(pmin(w,wmax))}
betacap<-function(w0,bk,cap){n<-length(w0);Dmat<-diag(n)+diag(1e-8,n);dvec<-w0
  Amat<-cbind(rep(1,n),diag(n),-diag(n),-bk);bvec<-c(1,rep(0,n),rep(-WMAX,n),-cap)
  sol<-tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1)$solution,error=function(e)w0);.cap(sol)}
bmfwd<-function(d0,d1){r<-bmd[Date>d0&Date<=d1,BM_Ret];if(!length(r))return(NA);prod(1+r[!is.na(r)])-1}

simbc<-function(cap=NULL){
  pr<-c();br<-c();dts<-as.Date(character(0));pw<-NULL;tl<-c();betas<-c()
  for(i in 1:(NS-1)){d0<-sig[i];d1<-sig[i+1];sd<-sched[Date==d0];tk<-sd$Ticker;if(!length(tk))next
    w<-setNames(.norm(sd$weight),tk);bk<-B[match(tk,Ticker),MKT];bk[is.na(bk)]<-mean(bk,na.rm=TRUE)
    if(!is.null(cap))w<-setNames(betacap(as.numeric(w),bk,cap),tk)
    betas<-c(betas,sum(w*bk))
    if(is.null(pw))turn<-1 else{ak<-union(names(w),names(pw));wv<-setNames(numeric(length(ak)),ak);wv[names(w)]<-w;pv<-setNames(numeric(length(ak)),ak);pv[names(pw)]<-pw;turn<-sum(abs(wv-pv))/2}
    tl<-c(tl,turn)
    fw<-which(WD>d0&WD<=d1);ci<-match(tk,WC)
    fr<-sapply(seq_along(tk),function(j){c2<-ci[j];if(is.na(c2))return(NA);rr<-WM[fw,c2];rr<-rr[is.finite(rr)];if(!length(rr))return(NA);prod(1+rr)-1})
    v<-!is.na(fr);if(!any(v)){pw<-w;next};w2<-w[v]/sum(w[v]);p<-sum(w2*fr[v])-turn*COMMISSION
    pr<-c(pr,p);br<-c(br,bmfwd(d0,d1));dts<-c(dts,d1);pw<-w}
  rx<-xts(pr,as.Date(dts));bx<-xts(br,as.Date(dts));ar<-table.AnnualizedReturns(rx,scale=12)
  act<-rx-bx
  list(sr=as.numeric(ar[3,1]),ir=as.numeric(mean(act)/sd(act)*sqrt(12)),te=as.numeric(sd(act)*sqrt(12)),
       mdd=as.numeric(maxDrawdown(rx)),to=mean(tl[-1])*2*12,beta_mean=mean(betas),beta_asof=tail(betas,1))
}
cat("=== RF-R1 walk-forward beta-cap impact ===\n")
for(lab in c("none","1.00","0.95")){cap<-if(lab=="none")NULL else as.numeric(lab);s<-simbc(cap)
  cat(sprintf("  cap=%-5s netSR %.4f | netIR %.4f | TE %.4f | MDD %.4f | TO/yr %.3f | mean_beta %.3f\n",
    lab,s$sr,s$ir,s$te,s$mdd,s$to,s$beta_mean))}
