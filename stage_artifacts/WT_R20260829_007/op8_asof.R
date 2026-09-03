suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1<-readRDS(file.path(OUT,"op1_objects.rds")); o6<-readRDS(file.path(OUT,"op6_objects.rds"))
A<-o1$A; SELW<-o6$SELW; SELP<-o6$SELP; m1<-o6$m1
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); X<-o3$X
CV <- read_parquet(file.path(OUT,"covariance.parquet"))
cat("cov dim:",dim(CV)," first cols:",paste(head(names(CV),4),collapse=","),"\n")
S <- as.matrix(CV[,-1]); rownames(S) <- CV[[1]]
aso <- as.Date("2026-08-28")
w <- SELW[as_of_date==aso]; setorder(w,-weight,Ticker)
AP <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))
AV <- setNames(as.numeric(unlist(AP$alpha_vector)), names(AP$alpha_vector))
nm <- rownames(S)
tw <- setNames(numeric(length(nm)), nm); tw[w$Ticker] <- w$weight
xa <- X[Date==aso]; cw <- setNames(numeric(length(nm)),nm)
cwv <- xa$wcap[match(nm,xa$Ticker)]; cwv[!is.finite(cwv)]<-0; cw <- cwv/sum(cwv)
act <- tw - cw
al <- AV[nm]; al[!is.finite(al)] <- 0
TEm <- sqrt(as.numeric(t(act)%*%S%*%act)); TE <- TEm*sqrt(12)
ARm <- as.numeric(t(act)%*%al); AR <- ARm*12
volm <- sqrt(as.numeric(t(tw)%*%S%*%tw)); VOL <- volm*sqrt(12)
covb <- as.numeric(t(tw)%*%S%*%cw); varb <- as.numeric(t(cw)%*%S%*%cw)
cat(sprintf("\n[as-of %s] n=%d  Sw=%.10f  max_w=%.4f  min_w=%.4f  HHI=%.4f\n",
  aso, nrow(w), sum(w$weight), max(w$weight), min(w$weight), sum(w$weight^2)))
cat(sprintf("expected_active_return=%.4f  expected_TE=%.4f  expected_IR=%.4f  predicted_vol=%.4f\n",AR,TE,AR/TE,VOL))
cat(sprintf("(diag) Sigma-predicted beta vs cap-w = %.4f  <- 위험 대리 아님, 진단만\n", covb/varb))
sec <- merge(w, X[Date==aso,.(Ticker,Sector,mkt)], by="Ticker")
print(sec[, .(w=round(sum(weight),4), n=.N), by=Sector][order(-w)])
print(sec[, .(w=round(sum(weight),4), n=.N), by=mkt])
cat("\nTop holdings (rank_proximity):\n"); print(head(w[,.(Ticker,weight=round(weight,4),rank_proximity)],10))
# EVT ES99 (선택 book)
gpd_es99 <- function(r){ L<--r; u<-quantile(L,0.90); ex<-L[L>u]-u; n<-length(L); k<-length(ex)
  nll<-function(p){xi<-p[1];b<-exp(p[2]);if(any(1+xi*ex/b<=0))return(1e10);k*log(b)+(1+1/xi)*sum(log(1+xi*ex/b))}
  op<-optim(c(0.1,log(sd(ex))),nll); xi<-op$par[1]; b<-exp(op$par[2])
  q<-u+b/xi*(((n/k)*(1-0.99))^(-xi)-1); c(xi=xi, VaR99=as.numeric(q), ES99=as.numeric(q+(b+xi*(q-u))/(1-xi))) }
cat("\nEVT(GPD) 월간 net — M1:", round(gpd_es99(m1$ret_net),4), "\n")
cat("EVT(GPD) 월간 net — SELECTED:", round(gpd_es99(SELP$ret_net),4), "\n")
# MDD (진단 라벨만)
mdd <- function(r){ e<-cumprod(1+r); min(e/cummax(e)-1) }
cat("MDD(진단 라벨) M1:",round(mdd(m1$ret_net),4)," SELECTED:",round(mdd(SELP$ret_net),4),"\n")
# 위기국면 beta (진단)
cr <- SELP$signal_date >= as.Date("2020-01-01") & SELP$signal_date <= as.Date("2020-06-30")
cat("COVID 구간 beta(진단) SELECTED:", round(coef(lm(SELP$ret_net[cr]~SELP$bm[cr]))[2],3),
    " 무조건부:", round(coef(lm(SELP$ret_net~SELP$bm))[2],3), "\n")
saveRDS(list(tw=tw,cw=cw,act=act,AR=AR,TE=TE,IR=AR/TE,VOL=VOL,beta_diag=covb/varb,w=w,sec=sec),
        file.path(OUT,"op8_objects.rds"))
