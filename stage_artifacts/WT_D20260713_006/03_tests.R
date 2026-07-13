`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a
# Step 03 — test battery: lift+CI, AUC+CI, controlled OR (cluster-robust), pre/post-2016 stability
suppressMessages({library(data.table); library(sandwich); library(lmtest); library(pROC)})
setDTthreads(1); set.seed(42)
OUT <- "stage_artifacts/WT_D20260713_006"
P <- readRDS(file.path(OUT,"panels.rds"))

wilson <- function(x,n){ if(n==0) return(c(NA,NA)); p<-x/n; z<-1.96; d<-1+z^2/n
  ctr<-(p+z^2/(2*n))/d; hw<-z*sqrt(p*(1-p)/n + z^2/(4*n^2))/d; c(ctr-hw, ctr+hw) }

# ticker-cluster bootstrap for lift ratio
boot_lift <- function(fp, R=1000){
  tk <- unique(fp$Ticker); base_ev <- fp$E; base_pr <- fp$pred
  br <- numeric(R)
  idxByTk <- split(seq_len(nrow(fp)), fp$Ticker)
  for(r in 1:R){
    samp <- sample(tk, length(tk), replace=TRUE)
    ii <- unlist(idxByTk[samp], use.names=FALSE)
    e <- base_ev[ii]; pr <- base_pr[ii]
    br[r] <- (mean(e[pr==1]) ) / (mean(e))
  }
  quantile(br, c(.025,.975), na.rm=TRUE)
}

run_one <- function(fp, nm){
  fp <- fp[!is.na(pred) & is.finite(log_size)]
  n <- nrow(fp); base <- mean(fp$E)
  x1 <- fp[pred==1, sum(E)]; n1 <- fp[pred==1,.N]
  evr1 <- x1/n1; lift <- evr1/base
  wl <- wilson(x1,n1)  # CI on event rate in worst decile; lift CI via /base
  lift_wl <- wl/base
  lift_boot <- boot_lift(fp, R=800)
  # AUC on continuous suspect
  au <- tryCatch({ r<-pROC::roc(fp$E, fp$susp, quiet=TRUE, direction="<"); ci<-as.numeric(pROC::ci.auc(r)); c(auc=as.numeric(r$auc), lo=ci[1], hi=ci[3]) },
                 error=function(e) c(auc=NA,lo=NA,hi=NA))
  # controlled logistic: E ~ pred + size_z + liq_z + K200 + KQ150
  fp[is.na(K200),K200:=0]; fp[is.na(KQ150),KQ150:=0]; fp[is.na(liq_z),liq_z:=0]; fp[is.na(size_z),size_z:=0]
  m0 <- glm(E ~ pred, data=fp, family=binomial)
  mc <- glm(E ~ pred + size_z + liq_z + K200 + KQ150, data=fp, family=binomial)
  cl <- tryCatch(coeftest(mc, vcov=vcovCL(mc, cluster=fp$Ticker)), error=function(e) coef(summary(mc)))
  or_raw <- exp(coef(m0)["pred"])
  b_c <- coef(mc)["pred"]; se_c <- cl["pred","Std. Error"]; p_c <- cl["pred",4]
  or_c <- exp(b_c); or_c_lo <- exp(b_c-1.96*se_c); or_c_hi <- exp(b_c+1.96*se_c)
  list(nm=nm, n=n, base=base, n1=n1, evr1=evr1, lift=lift, lift_wilson=lift_wl, lift_boot=lift_boot,
       auc=au, or_raw=as.numeric(or_raw), or_ctrl=as.numeric(or_c), or_ctrl_ci=c(or_c_lo,or_c_hi),
       or_ctrl_p=as.numeric(p_c), or_ctrl_se=as.numeric(se_c))
}

# stability pre/post 2016
run_split <- function(fp, nm){
  res <- list()
  for(seg in c("pre2016","post2016")){
    sub <- if(seg=="pre2016") fp[ym<201600] else fp[ym>=201600]
    sub <- sub[!is.na(pred) & is.finite(log_size)]
    if(nrow(sub)<200 || sub[pred==1,.N]<10){ res[[seg]] <- list(base=NA,lift=NA,or_ctrl=NA,p=NA,n=nrow(sub)); next }
    base<-mean(sub$E); evr1<-sub[pred==1,mean(E)]; lift<-evr1/base
    sub[is.na(K200),K200:=0]; sub[is.na(KQ150),KQ150:=0]; sub[is.na(liq_z),liq_z:=0]; sub[is.na(size_z),size_z:=0]
    mc <- tryCatch(glm(E~pred+size_z+liq_z+K200+KQ150,data=sub,family=binomial), error=function(e) NULL)
    if(is.null(mc)){res[[seg]]<-list(base=base,lift=lift,or_ctrl=NA,p=NA,n=nrow(sub));next}
    cl <- tryCatch(coeftest(mc,vcov=vcovCL(mc,cluster=sub$Ticker)),error=function(e) coef(summary(mc)))
    res[[seg]] <- list(base=base, lift=lift, or_ctrl=as.numeric(exp(coef(mc)["pred"])),
                       p=as.numeric(cl["pred",4]), n=nrow(sub), n1=sub[pred==1,.N])
  }
  res
}

RES <- list(); SPL <- list()
for(nm in c("F1","F2","F3","ST")){ RES[[nm]] <- run_one(P[[nm]], nm); SPL[[nm]] <- run_split(P[[nm]], nm) }
saveRDS(list(RES=RES,SPL=SPL), file.path(OUT,"test_results.rds"))

cat("\n================= MAIN RESULTS =================\n")
for(nm in c("F1","F2","F3","ST")){
  r<-RES[[nm]]
  cat(sprintf("\n[%s] n=%d base=%.4f | worst-decile n=%d evrate=%.4f\n", nm, r$n, r$base, r$n1, r$evr1))
  cat(sprintf("   LIFT=%.3f  Wilson95=[%.3f,%.3f]  bootTk95=[%.3f,%.3f]\n",
      r$lift, r$lift_wilson[1], r$lift_wilson[2], r$lift_boot[1], r$lift_boot[2]))
  cat(sprintf("   AUC=%.4f [%.4f,%.4f]\n", r$auc["auc"], r$auc["lo"], r$auc["hi"]))
  cat(sprintf("   OR_raw=%.3f | OR_ctrl=%.3f [%.3f,%.3f] p=%.4g (cluster-robust)\n",
      r$or_raw, r$or_ctrl, r$or_ctrl_ci[1], r$or_ctrl_ci[2], r$or_ctrl_p))
}
cat("\n================= STABILITY (pre/post 2016) =================\n")
for(nm in c("F1","F2","F3","ST")){
  s<-SPL[[nm]]
  cat(sprintf("[%s] pre2016: lift=%.2f OR_ctrl=%.2f p=%.3g (n=%s) | post2016: lift=%.2f OR_ctrl=%.2f p=%.3g (n=%s)\n",
      nm, s$pre2016$lift %||% NA, s$pre2016$or_ctrl %||% NA, s$pre2016$p %||% NA, s$pre2016$n,
      s$post2016$lift %||% NA, s$post2016$or_ctrl %||% NA, s$post2016$p %||% NA, s$post2016$n))
}
