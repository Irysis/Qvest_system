#==============================================================================
# C2 resolution: produce RF-R1 beta-cap=1.00 variant weights for FULL schedule.
# Delivered as selectable secondary book (Forge/Judge elect). No silent override.
#==============================================================================
suppressPackageStartupMessages({library(data.table);library(arrow);library(quadprog)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot";setwd(ROOT)
WT<-"WT-D20260528_003";ABASE<-"stage_artifacts/WT_D20260528_003";RBASE<-"stage_artifacts/WT_D20260528_003_risk_PROD"
WMAX<-0.20
sched<-as.data.table(read_parquet(file.path(ABASE,"weights_schedule.parquet")));sched[,Date:=as.Date(Date)]
B<-as.data.table(read_parquet(file.path(RBASE,"B_loadings.parquet")));setkey(B,Ticker)
.norm<-function(w){w[w<0]<-0;if(sum(w)<=0)w<-rep(1,length(w));w/sum(w)}
.cap<-function(w,wmax=WMAX){for(i in 1:200){w<-.norm(w);o<-w>wmax+1e-12;if(!any(o))break;ex<-sum(w[o]-wmax);w[o]<-wmax;u<-!o&w>0;if(!any(u)){w<-w/sum(w);break};w[u]<-w[u]+ex*w[u]/sum(w[u])};.norm(pmin(w,wmax))}
betacap<-function(w0,bk,cap){n<-length(w0);Dmat<-diag(n)+diag(1e-8,n);dvec<-w0
  Amat<-cbind(rep(1,n),diag(n),-diag(n),-bk);bvec<-c(1,rep(0,n),rep(-WMAX,n),-cap)
  sol<-tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1)$solution,error=function(e)w0);.cap(sol)}

dates<-sort(unique(sched$Date));out<-list()
for(d in dates){sd<-sched[Date==d];tk<-sd$Ticker;w0<-.norm(sd$weight)
  bk<-B[match(tk,Ticker),MKT];bk[is.na(bk)]<-mean(bk,na.rm=TRUE)
  # only cap if beta exceeds 1.00; else keep schedule (minimal deviation QP returns ~w0 anyway)
  w<-if(sum(w0*bk)>1.0) betacap(as.numeric(w0),bk,1.0) else w0
  out[[as.character(d)]]<-data.table(as_of_date=as.Date(d),Ticker=tk,weight=round(w,8),
                                     method="Schedule_EWbase_betacap1.00",task_id=WT)}
W<-rbindlist(out)
W[,weight:=weight/sum(weight),by=as_of_date]
fwrite(W[order(as_of_date,-weight)],file.path(ABASE,"weights_betacap1.00.csv"))
cat(sprintf("betacap variant: %d dates, %d rows, max_w %.4f, Σw all=1 %s\n",
  W[,uniqueN(as_of_date)],nrow(W),W[,max(weight)],W[,.(s=sum(weight)),by=as_of_date][,all(abs(s-1)<1e-6)]))
