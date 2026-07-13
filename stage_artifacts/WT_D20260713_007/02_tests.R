# R23 Step 02 — test battery on severity-restricted target (hardened = authoritative; pure-flag = robustness)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
suppressMessages({library(data.table); library(sandwich); library(lmtest); library(pROC)})
setDTthreads(1); set.seed(42)
OUT <- "stage_artifacts/WT_D20260713_007"
S <- readRDS(file.path(OUT,"target.rds"))

wilson <- function(x,n){ if(n==0) return(c(NA,NA)); p<-x/n; z<-1.96; d<-1+z^2/n
  ctr<-(p+z^2/(2*n))/d; hw<-z*sqrt(p*(1-p)/n + z^2/(4*n^2))/d; c(ctr-hw, ctr+hw) }

boot_lift <- function(fp, R=1000){
  tk <- unique(fp$Ticker); base_ev <- fp$E; base_pr <- fp$pred
  idxByTk <- split(seq_len(nrow(fp)), fp$Ticker); br <- numeric(R)
  for(r in 1:R){ samp <- sample(tk, length(tk), replace=TRUE)
    ii <- unlist(idxByTk[samp], use.names=FALSE); e<-base_ev[ii]; pr<-base_pr[ii]
    br[r] <- mean(e[pr==1]) / mean(e) }
  quantile(br, c(.025,.975), na.rm=TRUE)
}

run_one <- function(fp, nm){
  fp <- fp[!is.na(pred) & is.finite(log_size)]
  fp[is.na(K200),K200:=0]; fp[is.na(KQ150),KQ150:=0]; fp[is.na(liq_z),liq_z:=0]; fp[is.na(size_z),size_z:=0]
  n<-nrow(fp); base<-mean(fp$E); x1<-fp[pred==1,sum(E)]; n1<-fp[pred==1,.N]
  evr1<-x1/n1; lift<-evr1/base; lift_wl<-wilson(x1,n1)/base; lift_bt<-boot_lift(fp,1000)
  au <- tryCatch({ r<-pROC::roc(fp$E, fp$susp, quiet=TRUE, direction="<"); ci<-as.numeric(pROC::ci.auc(r)); c(auc=as.numeric(r$auc),lo=ci[1],hi=ci[3]) }, error=function(e) c(auc=NA,lo=NA,hi=NA))
  m0 <- glm(E ~ pred, data=fp, family=binomial)
  mc <- glm(E ~ pred + size_z + liq_z + K200 + KQ150, data=fp, family=binomial)
  cl <- tryCatch(coeftest(mc, vcov=vcovCL(mc, cluster=fp$Ticker)), error=function(e) coef(summary(mc)))
  b<-coef(mc)["pred"]; se<-cl["pred","Std. Error"]; p<-cl["pred",4]
  list(nm=nm, n=n, base=base, n1=n1, x1=x1, evr1=evr1, lift=lift, lift_wilson=lift_wl, lift_boot=lift_bt,
       auc=au, or_raw=as.numeric(exp(coef(m0)["pred"])), or_ctrl=as.numeric(exp(b)),
       or_ctrl_ci=c(exp(b-1.96*se),exp(b+1.96*se)), or_ctrl_p=as.numeric(p), or_ctrl_se=as.numeric(se))
}

run_split <- function(fp){
  res<-list()
  for(seg in c("pre2016","post2016")){
    sub <- if(seg=="pre2016") fp[ym<201600] else fp[ym>=201600]
    sub <- sub[!is.na(pred)&is.finite(log_size)]
    ne <- sub[pred==1,sum(E)]
    if(nrow(sub)<200 || sub[pred==1,.N]<10 || ne<5){ res[[seg]]<-list(base=NA,lift=NA,or_ctrl=NA,p=NA,n=nrow(sub),n1=sub[pred==1,.N],ev1=ne,estimable=FALSE); next }
    sub[is.na(K200),K200:=0]; sub[is.na(KQ150),KQ150:=0]; sub[is.na(liq_z),liq_z:=0]; sub[is.na(size_z),size_z:=0]
    base<-mean(sub$E); lift<-sub[pred==1,mean(E)]/base
    mc<-tryCatch(glm(E~pred+size_z+liq_z+K200+KQ150,data=sub,family=binomial),error=function(e) NULL)
    if(is.null(mc)){res[[seg]]<-list(base=base,lift=lift,or_ctrl=NA,p=NA,n=nrow(sub),n1=sub[pred==1,.N],ev1=ne,estimable=FALSE);next}
    cl<-tryCatch(coeftest(mc,vcov=vcovCL(mc,cluster=sub$Ticker)),error=function(e) coef(summary(mc)))
    res[[seg]]<-list(base=base,lift=lift,or_ctrl=as.numeric(exp(coef(mc)["pred"])),p=as.numeric(cl["pred",4]),
                     n=nrow(sub),n1=sub[pred==1,.N],ev1=ne,estimable=TRUE)
  }
  res
}

RES<-list(); SPL<-list()
RES[["hardened"]] <- run_one(S$Fhard, "hardened")
RES[["pureflag"]] <- run_one(S$Fflag, "pureflag")
SPL[["hardened"]] <- run_split(S$Fhard)

# ---------- (C) auxiliary discrete-time delisting hazard w/ continuous days-late ----------
# use F3 panel susp (higher = later filer). outcome = delisting onset in [t+1,t+12] only.
del <- S$sev_hard[type=="Delisting"]
Fh <- copy(S$Fhard); Fh[, sc := sub("^A","",Ticker)]
ym_add <- function(ym,k){ y<-ym%/%100; m<-ym%%100; t<-(y*12+(m-1))+k; (t%/%12)*100+(t%%12)+1 }
Fh[, lo:=ym_add(ym,1)]; Fh[, hi:=ym_add(ym,12)]
delset <- unique(del[, .(sc, ev_ym)]); setkey(delset, sc)
jj <- delset[Fh, on="sc", allow.cartesian=TRUE, nomatch=NULL]
delhit <- jj[ev_ym>=lo & ev_ym<=hi, .(D=1L), by=.(sc,ym)]
Fh <- merge(Fh, delhit, by=c("sc","ym"), all.x=TRUE); Fh[is.na(D),D:=0L]
Fh[, susp_z := as.numeric(scale(susp)), by=ym]
Fh[is.na(susp_z),susp_z:=0]; Fh[is.na(size_z),size_z:=0]; Fh[is.na(liq_z),liq_z:=0]
hz <- tryCatch({ mc<-glm(D ~ susp_z + size_z + liq_z, data=Fh, family=binomial)
  cl<-coeftest(mc, vcov=vcovCL(mc, cluster=Fh$Ticker))
  list(or=as.numeric(exp(coef(mc)["susp_z"])), p=as.numeric(cl["susp_z",4]),
       n=nrow(Fh), n_del=sum(Fh$D), se=as.numeric(cl["susp_z","Std. Error"])) },
  error=function(e) list(or=NA,p=NA,n=nrow(Fh),n_del=sum(Fh$D),se=NA))

saveRDS(list(RES=RES,SPL=SPL,HZ=hz), file.path(OUT,"test_results.rds"))

cat("\n================= R23 SEVERITY-RESTRICTED RESULTS =================\n")
for(nm in c("hardened","pureflag")){
  r<-RES[[nm]]
  cat(sprintf("\n[%s] n=%d base=%.5f | worst-decile n=%d ev=%d evrate=%.5f\n", nm, r$n, r$base, r$n1, r$x1, r$evr1))
  cat(sprintf("   LIFT=%.3f  Wilson95=[%.3f,%.3f]  bootTk95=[%.3f,%.3f]\n", r$lift, r$lift_wilson[1], r$lift_wilson[2], r$lift_boot[1], r$lift_boot[2]))
  cat(sprintf("   AUC=%.4f [%.4f,%.4f]\n", r$auc["auc"], r$auc["lo"], r$auc["hi"]))
  cat(sprintf("   OR_raw=%.3f | OR_ctrl=%.3f [%.3f,%.3f] p=%.4g (cluster-robust)\n", r$or_raw, r$or_ctrl, r$or_ctrl_ci[1], r$or_ctrl_ci[2], r$or_ctrl_p))
}
cat("\n================= STABILITY (hardened, pre/post 2016) =================\n")
s<-SPL[["hardened"]]
for(seg in c("pre2016","post2016")){ q<-s[[seg]]
  cat(sprintf("[%s] estimable=%s lift=%.2f OR_ctrl=%.3f p=%.4g (n=%d worst-dec_n=%d ev=%d)\n",
    seg, q$estimable, q$lift %||% NA, q$or_ctrl %||% NA, q$p %||% NA, q$n, q$n1, q$ev1)) }
cat("\n================= AUX DELISTING HAZARD (continuous days-late z) =================\n")
cat(sprintf("[hazard] OR/SD(susp_z)=%.3f p=%.4g (n=%d, delist-hits=%d)\n", hz$or %||% NA, hz$p %||% NA, hz$n, hz$n_del))
cat("\n[02] DONE\n")
