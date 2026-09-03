suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
R1<-readRDS(file.path(OUT,"risk_r1.rds")); R2<-readRDS(file.path(OUT,"risk_r2.rds"))
R3<-readRDS(file.path(OUT,"risk_r3.rds")); R4<-readRDS(file.path(OUT,"risk_r4.rds")); R5<-readRDS(file.path(OUT,"risk_r5.rds"))
D<-R1$D; win_d<-R2$win_d; ASSETS<-R2$ASSETS; B<-R2$B; Om<-R2$Omega_d; Sig_d<-R3$Sigma_d
dvec<-R3$dvec_final; fac_names<-R2$fac_names; STY<-R2$STY; FR<-R2$FR

Dw <- D[Date %in% win_d & Ticker %in% ASSETS, .(Date,Ticker,Ret)]
W <- dcast(Dw, Date ~ Ticker, value.var="Ret"); dts<-W$Date; W[,Date:=NULL]; W<-as.matrix(W)

chk <- function(lbl, wv) {
  wv <- wv[ASSETS]; wv[!is.finite(wv)] <- 0
  Wf <- W[, ASSETS, drop=FALSE]
  ok <- is.finite(Wf); Wf[!ok] <- 0
  denom <- as.numeric(ok %*% wv); denom[denom<=0]<-NA
  r <- as.numeric(Wf %*% wv)/denom
  pred_d <- as.numeric(t(wv) %*% Sig_d %*% wv)
  x <- as.numeric(t(B) %*% wv); names(x)<-fac_names
  fv <- as.numeric(t(x) %*% Om %*% x); sv <- sum(wv^2*dvec[ASSETS])
  cat(sprintf("%-22s pred_ann=%6.2f%%  realized_ann=%6.2f%%  ratio=%.2f | fac %.1f%% spec %.1f%% | x_MKT=%.2f x_SIZE=%.2f x_RVOL=%.2f\n",
      lbl, 100*sqrt(pred_d*252), 100*sd(r,na.rm=TRUE)*sqrt(252), sqrt(pred_d)/sd(r,na.rm=TRUE),
      100*fv/pred_d, 100*sv/pred_d, x["MKT"], x["X_SIZE"], x["X_RVOL"]))
  invisible(x)
}
w25 <- setNames(rep(0,length(ASSETS)), ASSETS); w25[R4$top25] <- 1/length(R4$top25)
chk("EW top-25", w25)
wew <- setNames(rep(1/length(ASSETS),length(ASSETS)), ASSETS); chk("EW universe 340", wew)
xk <- chk("K200 cap-w proxy", R5$wb)

cat("\n-- K200 proxy factor exposure detail --\n")
print(round(xk[c("MKT",STY)],3))
sec <- grep("^SEC_", fac_names)
cat(sprintf("sector exposure: sum=%.3f  max|x|=%.3f  sum|x|=%.3f\n", sum(xk[sec]), max(abs(xk[sec])), sum(abs(xk[sec]))))
Omx <- as.numeric(Om %*% xk); ctr <- xk*Omx
cat(sprintf("variance contrib: MKT=%.3g SECTORS=%.3g STYLES=%.3g (total fac=%.3g)\n",
            ctr[1], sum(ctr[sec]), sum(ctr[match(STY,fac_names)]), sum(ctr)))
cat("style contribs:\n"); print(signif(ctr[match(STY,fac_names)],3))
cat("\nfactor daily vol (ann %):\n")
Fm <- as.matrix(FR[Date %in% win_d, ..fac_names])
print(round(100*apply(Fm,2,sd)*sqrt(252),2)[c("MKT",STY)])
cat("\nfactor corr (MKT vs styles):\n"); print(round(cor(Fm)[ "MKT", c(STY)],3))
cat("\nkey style |corr|>0.8 pairs:\n")
kf <- c("MKT",STY); fc <- cor(Fm[,kf]); hp <- which(abs(fc)>0.8 & upper.tri(fc), arr.ind=TRUE)
if (nrow(hp)) for (i in 1:nrow(hp)) cat(sprintf("  %s ~ %s = %.3f\n", kf[hp[i,1]], kf[hp[i,2]], fc[hp[i,1],hp[i,2]]))
cat("\nrealized BM daily vol ann (window):", sprintf("%.2f%%", 100*sd(R1$BMd[Date %in% win_d, BM_Ret])*sqrt(252)), "\n")
