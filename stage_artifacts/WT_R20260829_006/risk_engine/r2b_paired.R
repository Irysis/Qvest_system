suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
source("02_Infrastructure/portfolio/hrp_core.R")
R2 <- readRDS(file.path(O,"r2_omega.rds")); Fm <- R2$Fm
win <- 60L; ts <- (win+1L):nrow(Fm)
METH <- c("sample","ledoit_wolf","lw_nls","gerber_rmt")
LL <- matrix(NA_real_, length(ts), length(METH), dimnames=list(rownames(Fm)[ts], METH))
CND <- LL
for (j in seq_along(METH)) for (ii in seq_along(ts)) {
  t <- ts[ii]
  S <- suppressWarnings(.get_cor_cov(Fm[(t-win):(t-1L),,drop=FALSE], METH[j]))$cov
  S <- (S+t(S))/2; ev <- eigen(S,symmetric=TRUE); lam <- pmax(ev$values,1e-12)
  Si <- ev$vectors %*% diag(1/lam) %*% t(ev$vectors); x <- Fm[t,]
  LL[ii,j] <- -0.5*(sum(log(lam)) + as.numeric(t(x)%*%Si%*%x))
  CND[ii,j] <- max(lam)/min(lam)
}
nwt <- function(d){ n<-length(d); m<-mean(d); L<-3
  g<-sapply(0:L,function(l) sum((d[(1+l):n]-m)*(d[1:(n-l)]-m))/n)
  v<-g[1]+2*sum(sapply(1:L,function(l)(1-l/(L+1))*g[l+1])); m/sqrt(v/n) }
cat("mean OOS logLik:\n"); print(round(colMeans(LL),3))
cat("mean rolling cond:\n"); print(round(colMeans(CND),1))
for (m in setdiff(METH,"ledoit_wolf")) {
  d <- LL[,m]-LL[,"ledoit_wolf"]
  cat(sprintf("%s vs ledoit_wolf : dLL %.3f  DM-t(NW3) %.2f\n", m, mean(d), nwt(d)))
}
saveRDS(list(LL=LL,CND=CND,ts=rownames(Fm)[ts]), file.path(O,"r2b_paired.rds"))
