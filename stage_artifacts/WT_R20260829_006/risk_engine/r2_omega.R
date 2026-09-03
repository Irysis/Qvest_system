## RISK Stage 2 — Ω 추정기 method shopping (estimation-quality only) + 구간 이질성
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
source("02_Infrastructure/portfolio/hrp_core.R")

R1 <- readRDS(file.path(O,"r1_reg.rds")); FR<-R1$FR; CV<-R1$CV; FAMS<-R1$FAMS
FW <- dcast(FR, Date ~ factor, value.var="fret")
setorder(FW, Date)
fac_names <- setdiff(names(FW),"Date")
na_ct <- sapply(fac_names, function(k) sum(is.na(FW[[k]])))
cat("[NA per factor]\n"); print(na_ct[na_ct>0])
for (k in fac_names) { v<-FW[[k]]; v[!is.finite(v)]<-0; set(FW,j=k,value=v) }
Fm <- as.matrix(FW[, ..fac_names]); rownames(Fm) <- as.character(FW$Date)
cat("[F] months",nrow(Fm)," factors",ncol(Fm),"\n")
cat("[F] annualized factor vol (%):\n"); print(round(apply(Fm,2,sd)*sqrt(12)*100,2))

cn <- function(M){ e<-eigen(M,symmetric=TRUE,only.values=TRUE)$values; max(e)/max(min(e),1e-16) }
relfro <- function(A,B){ norm(A-B,"F")/norm((A+B)/2,"F") }

METHODS <- c("sample","ledoit_wolf","lw_nls","gerber_rmt")
h1 <- 1:124; h2 <- 125:nrow(Fm)
ll_oos <- function(meth, win=60L){
  ll<-c()
  for (t in (win+1L):nrow(Fm)) {
    S <- suppressWarnings(.get_cor_cov(Fm[(t-win):(t-1L),,drop=FALSE], meth))$cov
    S <- (S+t(S))/2; ev <- eigen(S,symmetric=TRUE)
    lam <- pmax(ev$values, 1e-12)
    Sinv <- ev$vectors %*% diag(1/lam) %*% t(ev$vectors)
    x <- Fm[t,]
    ll <- c(ll, -0.5*(sum(log(lam)) + as.numeric(t(x)%*%Sinv%*%x)))
  }
  mean(ll)
}
mlog <- list()
for (m in METHODS) {
  Sm <- suppressWarnings(.get_cor_cov(Fm, m))$cov
  Sm <- (Sm+t(Sm))/2
  S1 <- suppressWarnings(.get_cor_cov(Fm[h1,,drop=FALSE], m))$cov
  S2 <- suppressWarnings(.get_cor_cov(Fm[h2,,drop=FALSE], m))$cov
  st <- relfro(cov2cor(S1+diag(1e-14,ncol(S1))), cov2cor(S2+diag(1e-14,ncol(S2))))
  lo <- ll_oos(m)
  ev <- eigen(Sm,symmetric=TRUE,only.values=TRUE)$values
  mlog[[m]] <- list(name=m, condition=cn(Sm), min_eigen=min(ev), pd=min(ev)>0,
                    splithalf_relfro=st, oos_mean_loglik=lo)
  cat(sprintf("[%s] cond %.1f  min_eig %.3e  splithalf %.4f  oosLL %.3f\n",
      m, cn(Sm), min(ev), st, lo))
}
saveRDS(list(Fm=Fm, mlog=mlog, fac_names=fac_names, na_ct=na_ct), file.path(O,"r2_omega.rds"))
cat("[done]\n")
