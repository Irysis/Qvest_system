# OP3 — risk 모형의 결정시점 인스턴스화 (재추정 아님: 추정기/창/floor 전량 risk 승계)
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3 <- readRDS(file.path(OUT,"rk3_objects.rds"))
X <- o3$X; Fw <- o3$Fw; RES <- o3$RES; STY <- o3$STY
ME <- sort(unique(Fw$Date))
Fm <- as.matrix(Fw[,-1]); Fm[!is.finite(Fm)] <- 0
resw <- dcast(RES, Date~Ticker, value.var="resid"); RD <- as.matrix(resw[,-1]); rownames(RD)<-as.character(resw$Date)

# risk 의 lwcov (rk5_walkforward.R 그대로 — 파라미터 선택 없음)
lwcov <- function(M){ p<-ncol(M); n<-nrow(M); S<-cov(M); mu<-mean(diag(S))
  rho <- min(((n-2)/n*sum(diag(S)^2)+sum(S)^2)/((n+2)*(sum(S^2)-sum(diag(S)^2)/p)),1)
  (1-rho)*S+rho*mu*diag(p) }

# 결정시점 t=ME[j] 에서 종목집합 tk 의 Σ (f_1..f_{j-1}, u_1..u_{j-1} 만)
sigma_at <- function(j, tk){
  Fh <- Fm[1:(j-1), , drop=FALSE]
  xd <- X[Date==ME[j] & Ticker %in% tk]
  if(nrow(xd) < 2) return(NULL)
  secs <- sort(unique(xd$sec))
  Dm <- matrix(0,nrow(xd),length(secs),dimnames=list(NULL,secs)); Dm[cbind(seq_len(nrow(xd)),match(xd$sec,secs))] <- 1
  Bm <- cbind(MKT=1, Dm, as.matrix(xd[,..STY])); rownames(Bm) <- xd$Ticker
  cn <- colnames(Bm); Fh2 <- matrix(0,nrow(Fh),length(cn),dimnames=list(NULL,cn))
  cc <- intersect(cn,colnames(Fh)); Fh2[,cc] <- Fh[,cc]
  Om <- lwcov(Fh2)
  rlo <- max(1,(j-1)-59); Rh <- RD[rlo:(j-1), , drop=FALSE]
  dvv <- sapply(xd$Ticker, function(t2){ if(!(t2 %in% colnames(Rh))) return(NA_real_)
      v<-Rh[,t2]; v<-v[is.finite(v)]; if(length(v)<24) return(NA_real_); var(v) })
  allv <- sapply(xd$Ticker, function(t2){ if(!(t2 %in% colnames(RD))) return(NA_real_)
      v<-RD[1:(j-1),t2]; v<-v[is.finite(v)]; if(length(v)<12) return(NA_real_); var(v) })
  dvv[!is.finite(dvv)] <- allv[!is.finite(dvv)]
  med <- median(c(dvv,allv),na.rm=TRUE); if(!is.finite(med)) med <- 0.01
  dvv[!is.finite(dvv)] <- med
  dfloor <- pmax(dvv, quantile(dvv,0.10,na.rm=TRUE))
  S <- Bm%*%Om%*%t(Bm); diag(S) <- diag(S)+dfloor
  S <- (S+t(S))/2
  list(S=S, names=xd$Ticker, d_raw=dvv, d_floored=dfloor, floored=dfloor>dvv+1e-14)
}
saveRDS(list(sigma_at=sigma_at, ME=ME, lwcov=lwcov), file.path(OUT,"op3_sigma_fn.rds"))
# 자기점검: 임의 3시점 PD/조건수
for(j in c(20, 120, 259)){
  A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
  tk <- A[Date==ME[j]][order(-fh_lag1d,Ticker)]$Ticker[1:25]
  z <- sigma_at(j, tk); e <- eigen(z$S,symmetric=TRUE,only.values=TRUE)$values
  cat(sprintf("j=%3d %s  n=%d  mineig=%.3e cond=%.1f  vol_ann_EW=%.4f  floored=%d/%d\n",
      j, as.character(ME[j]), length(z$names), min(e), max(e)/min(e),
      sqrt(as.numeric(t(rep(1/length(z$names),length(z$names)))%*%z$S%*%rep(1/length(z$names),length(z$names)))*12),
      sum(z$floored), length(z$floored)))
}
