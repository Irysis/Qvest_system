# RK5 — walk-forward Σ 검증(bias statistic) + 최종 Σ 확정
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
source(file.path(ROOT,"02_Infrastructure/portfolio/hrp_core.R"))
o3 <- readRDS(file.path(OUT,"rk3_objects.rds")); o4 <- readRDS(file.path(OUT,"rk4_objects.rds"))
X <- o3$X; Fw <- o3$Fw; RES <- o3$RES; STY <- o3$STY
pn <- readRDS(file.path(OUT,"panel.rds")); RET <- as.data.table(pn$fwd$returns_dt)
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
PR <- fread(file.path(OUT,"period_returns_production.csv")); PR[,signal_date:=as.Date(signal_date)]
ME <- sort(unique(Fw$Date))            # 신호월말 t (요인수익 f_t 는 t->t+1 홀딩월 실현)
Fm <- as.matrix(Fw[,-1]); FN0 <- colnames(Fm); Fm[!is.finite(Fm)] <- 0
resw <- dcast(RES, Date~Ticker, value.var="resid")
RD <- as.matrix(resw[,-1]); rownames(RD) <- as.character(resw$Date)
RMall <- dcast(RET, Date~Ticker, value.var="Ret_1m"); RMm <- as.matrix(RMall[,-1]); rownames(RMm) <- as.character(RMall$Date)

lwcov <- function(M){ p<-ncol(M); n<-nrow(M); S<-cov(M); mu<-mean(diag(S))
  rho <- min(((n-2)/n*sum(diag(S)^2)+sum(S)^2)/((n+2)*(sum(S^2)-sum(diag(S)^2)/p)),1)
  list(cov=(1-rho)*S+rho*mu*diag(p), rho=rho) }
condf <- function(M){ e<-eigen((M+t(M))/2,symmetric=TRUE,only.values=TRUE)$values; c(mn=min(e),cond=max(e)/max(min(e),1e-16)) }

MINW <- 60L
res <- list(); k <- 0L
for(j in seq_along(ME)){
  if(j <= MINW) next
  t_d <- ME[j]
  hold <- A[Date==t_d & in_top25==TRUE, Ticker]; if(length(hold)<10) next
  pr <- PR[signal_date==t_d]; if(nrow(pr)!=1) next
  w <- rep(1/length(hold), length(hold))
  # ---- PIT: 결정시점 t 에서 알려진 요인수익 = f_1..f_{j-1} ----
  Fh <- Fm[1:(j-1), , drop=FALSE]
  xd <- X[Date==t_d & Ticker %in% hold]
  if(nrow(xd) < length(hold)) { hold <- xd$Ticker; w <- rep(1/length(hold),length(hold)) }
  if(length(hold)<10) next
  secs <- sort(unique(xd$sec))
  Dm <- matrix(0,nrow(xd),length(secs),dimnames=list(NULL,secs)); Dm[cbind(seq_len(nrow(xd)),match(xd$sec,secs))] <- 1
  Bm <- cbind(MKT=1, Dm, as.matrix(xd[,..STY])); rownames(Bm) <- xd$Ticker
  cn <- colnames(Bm); Fh2 <- matrix(0,nrow(Fh),length(cn),dimnames=list(NULL,cn))
  cc <- intersect(cn,colnames(Fh)); Fh2[,cc] <- Fh[,cc]
  Om_s <- cov(Fh2); Om_l <- lwcov(Fh2)$cov
  # ---- D: 결정시점까지 잔차 (rolling 60, min 24) ----
  rlo <- max(1,(j-1)-59); Rh <- RD[rlo:(j-1), , drop=FALSE]
  dvv <- sapply(xd$Ticker, function(tk){ if(!(tk %in% colnames(Rh))) return(NA_real_)
      v<-Rh[,tk]; v<-v[is.finite(v)]; if(length(v)<24) return(NA_real_); var(v) })
  allv <- sapply(xd$Ticker, function(tk){ if(!(tk %in% colnames(RD))) return(NA_real_)
      v<-RD[1:(j-1),tk]; v<-v[is.finite(v)]; if(length(v)<12) return(NA_real_); var(v) })
  dvv[!is.finite(dvv)] <- allv[!is.finite(dvv)]
  med <- median(c(dvv,allv), na.rm=TRUE); if(!is.finite(med)) med <- 0.01
  dvv[!is.finite(dvv)] <- med
  Sst_s <- Bm%*%Om_s%*%t(Bm); diag(Sst_s) <- diag(Sst_s)+dvv
  Sst_l <- Bm%*%Om_l%*%t(Bm); diag(Sst_l) <- diag(Sst_l)+pmax(dvv, quantile(dvv,0.10))
  # ---- 직접 추정기 (보유 25종, 직전 60개월 실현수익) ----
  rr <- RMm[max(1,(j-1)-59):(j-1), intersect(hold,colnames(RMm)), drop=FALSE]
  ok <- colSums(is.finite(rr))==nrow(rr); rr <- rr[,ok,drop=FALSE]
  vd_s <- vd_l <- vd_n <- NA_real_
  if(ncol(rr)>=10 && nrow(rr)>=30){
    ws <- rep(1/ncol(rr), ncol(rr))
    Cs <- cov(rr); vd_s <- as.numeric(t(ws)%*%Cs%*%ws)
    Cl <- lwcov(rr)$cov; vd_l <- as.numeric(t(ws)%*%Cl%*%ws)
    Cn <- tryCatch(.get_cor_cov(rr,"lw_nls")$cov, error=function(e) NULL)
    if(!is.null(Cn)) vd_n <- as.numeric(t(ws)%*%Cn%*%ws)
  }
  k <- k+1L
  res[[k]] <- data.table(signal_date=t_d, holding_ym=pr$holding_ym, n=length(hold),
    ret=pr$ret_gross, bm=pr$benchmark_ret,
    v_struct_s=as.numeric(t(w)%*%Sst_s%*%w), v_struct_l=as.numeric(t(w)%*%Sst_l%*%w),
    v_dir_s=vd_s, v_dir_l=vd_l, v_dir_n=vd_n,
    cond_s=condf(Sst_s)["cond"], cond_l=condf(Sst_l)["cond"], mineig_l=condf(Sst_l)["mn"])
}
WF <- rbindlist(res)
cat("[RK5] walk-forward 월",nrow(WF),"·",WF$holding_ym[1],"~",WF$holding_ym[nrow(WF)],"\n")
mu_r <- mean(WF$ret)
bias <- function(v){ z <- (WF$ret-mu_r)/sqrt(v); c(bias=sd(z,na.rm=TRUE), mad=mean(abs(z),na.rm=TRUE),
   mape=mean(abs(sqrt(v)-abs(WF$ret-mu_r))/pmax(abs(WF$ret-mu_r),1e-6),na.rm=TRUE)) }
tab <- rbind(struct_sampleOmega=bias(WF$v_struct_s), struct_lwOmega=bias(WF$v_struct_l),
             direct_sample=bias(WF$v_dir_s), direct_lw=bias(WF$v_dir_l), direct_lwnls=bias(WF$v_dir_n))
print(round(tab,4))
cat("[RK5] 예측 연율 vol 평균: struct_lw",round(100*mean(sqrt(WF$v_struct_l*12)),2),"% · 실현(전체)",
    round(100*sd(WF$ret)*sqrt(12),2),"%\n")
cat("[RK5] walk-forward cond(25종 Σ) 중앙 struct_lw",round(median(WF$cond_l),1)," sample_omega",round(median(WF$cond_s),1),"\n")
saveRDS(WF, file.path(OUT,"rk5_wf.rds")); fwrite(WF, file.path(OUT,"rk_walkforward_sigma.csv"))
cat("[RK5] done\n")
