## 축2 안정성 점검 — 월간CS 왜도 vs 일간CS 왜도 추정기 불일치의 정체
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
G <- readRDS("stage_artifacts/WT-D20260821_002/gate_series.rds")
frd <- S$frd
skew_pop <- function(x){x<-x[is.finite(x)];n<-length(x);if(n<3)return(NA_real_);m<-mean(x);s<-sqrt(sum((x-m)^2)/n);if(s<=0)return(NA_real_);sum((x-m)^3)/(n*s^3)}
setDT(frd)
cat("frd cols:", paste(names(frd), collapse=", "), "\n")
mk <- frd[, .(skew_m = skew_pop(Ret_1m), disp = sd(Ret_1m, na.rm=TRUE), nn=.N), by = .(ym = format(Date, "%Y-%m"))]
setorder(mk, ym)
## 일간 왜도 (RAWDATA)
rp <- ".cache/RAWDATA.parquet"
cat("RAWDATA exists:", file.exists(rp), "\n")
rd <- as.data.table(read_parquet(rp, col_select = c("Date","Ticker","Ret")))
rd[, ym := format(Date, "%Y-%m")]
dk <- rd[is.finite(Ret), .(sk_day = skew_pop(Ret)), by = .(ym, Date)][, .(skew_d = mean(sk_day, na.rm=TRUE), ndays=.N), by = ym]
setorder(dk, ym)
K <- merge(mk, dk, by="ym")
cat("\n월간CS vs 일간CS 왜도 상관:", round(cor(K$skew_m, K$skew_d, use="complete.obs"), 4), "\n")
cat("월간CS 왜도 vs 분산:", round(cor(K$skew_m, K$disp, use="complete.obs"),4),
    " | 일간CS 왜도 vs 분산:", round(cor(K$skew_d, K$disp, use="complete.obs"),4), "\n")
## diff 계열과 정렬
nw_t_indep <- function(x, lag=3L){x<-as.numeric(x);n<-length(x);m<-mean(x);e<-x-m;g0<-sum(e*e)/n;s<-g0
  for(k in 1:lag){gk<-sum(e[(k+1):n]*e[1:(n-k)])/n;s<-s+2*(1-k/(lag+1))*gk};m/sqrt(s/n)}
nw_slope_t <- function(y, X, lag=3L){
  X <- cbind(1, as.matrix(X)); fit <- lm.fit(X, y); b <- fit$coefficients; e <- fit$residuals
  n <- length(y); XtXi <- solve(crossprod(X)); k <- ncol(X)
  S <- matrix(0,k,k); for(i in 1:n) S <- S + e[i]^2 * tcrossprod(X[i,])
  for(L in 1:lag){w <- 1-L/(lag+1); for(i in (L+1):n){u<-e[i]*X[i,];v<-e[i-L]*X[i-L,];S<-S+w*(tcrossprod(u,v)+tcrossprod(v,u))}}
  V <- XtXi %*% S %*% XtXi; list(b=b, t=b/sqrt(diag(V)))
}
res <- list(cor_skew_m_d = cor(K$skew_m,K$skew_d,use="complete.obs"))
for (pn in c("c_vs_a","b_vs_a")) {
  dd <- G$diffs[[paste0("F3L|",pn)]]
  dd[, ym := format(date, "%Y-%m")]
  M <- merge(dd, K, by="ym"); setorder(M, ym)
  r1 <- nw_slope_t(M$d, M$skew_m); r2 <- nw_slope_t(M$d, M$skew_d)
  r3 <- nw_slope_t(M$d, cbind(M$skew_m, M$skew_d))
  cat(sprintf("\n[%s] n=%d\n  monthlyCS slope %+ .6f t %+.3f | dailyCS slope %+ .6f t %+.3f\n  둘 다 투입: skew_m t %+.3f · skew_d t %+.3f\n",
      pn, nrow(M), r1$b[2], r1$t[2], r2$b[2], r2$t[2], r3$t[2], r3$t[3]))
  res[[pn]] <- list(n=nrow(M), monthly_t=r1$t[[2]], daily_t=r2$t[[2]],
                    joint_monthly_t=r3$t[[2]], joint_daily_t=r3$t[[3]],
                    monthly_slope=r1$b[[2]], daily_slope=r2$b[[2]])
}
write_json(res, "stage_artifacts/WT-D20260821_002/axis2_probe.json", auto_unbox=TRUE, pretty=TRUE, digits=8)
