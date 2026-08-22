suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac; S<-Z$S12
NM<-nrow(mon); NAx<-1+length(fac); RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
run<-function(Sx,fsub=fac,bps=15,freq=3,dec_lag=1){ idx<-c(1,1+match(fsub,fac)); NA2<-length(idx)
 pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); wprev<-rep(1/NA2,NA2); wcur<-NULL
 for(m in 13:NM){ d<-m-dec_lag; if(d<1)next
  if(is.null(wcur)||((m-13)%%freq==0)){ s<-Sx[d,fsub]; pos<-which(is.finite(s)&s>0); w<-rep(0,NA2)
   if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
  ri<-RET[m,idx]; dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; pr[m]<-sum(wcur*ri)-(bps/1e4)*dlt
  wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
 k<-is.finite(pr); list(pt=nwt(pr[k]-RET[k,1]),n=sum(k),act=pr[k]-RET[k,1],tov=mean(tov[k])*12) }
cat("== 1. shift ladder (dec_lag 0/1/2) ==\n")
for(dl in 0:2) cat(sprintf("   dec_lag=%d -> pt=%.3f\n",dl,run(S,dec_lag=dl)$pt))
cat("\n== 2. leave-one-factor-out (21) ==\n")
LO<-rbindlist(lapply(fac,function(f){r<-run(S,setdiff(fac,f)); data.table(drop=f,pt=r$pt)}))[order(pt)]
print(LO,digits=4); cat("   min=",round(min(LO$pt),3)," median=",round(median(LO$pt),3),
  " max=",round(max(LO$pt),3)," n<2.95 =",sum(LO$pt<2.95),"/21\n")
cat("\n== 3. random k-factor subsets ==\n")
set.seed(4242)
for(k in c(6,12,18)){ v<-replicate(200,run(S,sample(fac,k))$pt)
 cat(sprintf("   k=%2d mean=%.3f sd=%.3f  frac>=2.95=%.3f  pctile(3.232)=%.1f\n",k,mean(v),sd(v),mean(v>=2.95),100*mean(v<3.2318))) }
cat("\n== 4. expanding-window pt & effect size ==\n")
r<-run(S); a<-r$act; d<-mon$medate[is.finite(mon$medate)][13:NM]
for(y in c(2015,2017,2019,2021,2023,2025,2026)){ s<-format(d,"%Y")<=as.character(y)
 cat(sprintf("   ~%d n=%3d pt=%6.3f mean_act_ann=%.4f\n",y,sum(s),nwt(a[s]),mean(a[s])*12)) }
cat("\n== 5. robustness: winsorize / LOO-month / annual jackknife ==\n")
for(p in c(.01,.025,.05)){ q<-quantile(a,c(p,1-p)); aw<-pmin(pmax(a,q[1]),q[2])
 cat(sprintf("   winsor %.1f%%: pt=%.3f\n",p*100,nwt(aw))) }
lo<-sapply(seq_along(a),function(i)nwt(a[-i])); cat(sprintf("   LOO-month pt range %.3f ~ %.3f (n<2.95: %d)\n",min(lo),max(lo),sum(lo<2.95)))
yy<-format(d,"%Y"); jk<-sapply(unique(yy),function(y)nwt(a[yy!=y]))
cat(sprintf("   annual jackknife range %.3f ~ %.3f (n<2.95: %d/%d)  worst-drop-year=%s\n",min(jk),max(jk),sum(jk<2.95),length(jk),names(which.min(jk))))
cat("\n== 6. rolling 120M pt ==\n")
rl<-sapply(120:length(a),function(i)nwt(a[(i-119):i]))
cat(sprintf("   frac>=2.95 = %.3f  min=%.3f max=%.3f\n",mean(rl>=2.95),min(rl),max(rl)))
cat("\n== 7. stock-level cost: charge strategy only (benchmark gross) ==\n")
drag<-(0.005742-0.003722)/12   # measured stock-level 0.574%/yr minus index-layer already charged 0.372%/yr
cat(sprintf("   pt = %.3f (base 3.232, incremental drag %.3f%%/yr)\n",nwt(a-drag),(0.005742-0.003722)*100))
drag2<-(0.005742-0.001465-0.003722)/12
cat(sprintf("   pt = %.3f (benchmark also charged its own 0.147%%/yr)\n",nwt(a-drag2)))
