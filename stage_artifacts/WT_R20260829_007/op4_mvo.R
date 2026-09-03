# OP4 — M4/M5 (confidence-aware MVO + 명시 회전 페널티) · 공통창 비교
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(quadprog); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1 <- readRDS(file.path(OUT,"op1_objects.rds")); A<-o1$A; BM<-o1$BM; DTS_BT<-o1$DTS_BT
source(file.path(OUT,"op3_sigma_mod.R"))
CVEC <- { cj <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))$confidence_vector
          setNames(as.numeric(unlist(cj)), names(cj)) }
COST_BPS<-0.0015; LAM<-2.0; PSI<-0.3; PHI<-0.00405

mvo_to <- function(alpha, S, cvec, w0, lam=LAM, psi=PSI, phi=PHI){
  n <- length(alpha); K <- diag((1-cvec)^2, n)
  Q <- lam*S + 2*psi*K; Q <- (Q+t(Q))/2
  M <- cbind(diag(n), -diag(n))
  D <- t(M)%*%Q%*%M; D <- (D+t(D))/2 + diag(1e-6*mean(diag(Q)), 2*n)
  dv <- as.numeric(t(M)%*%(alpha*cvec - Q%*%w0)) - phi
  Am <- cbind(as.numeric(t(rep(1,n))%*%M), t(M), diag(2*n))
  bv <- c(1-sum(w0), -w0, rep(0,2*n))
  r <- tryCatch(solve.QP(D, dv, Am, bv, meq=1), error=function(e) NULL)
  if(is.null(r)) return(NULL)
  w <- as.numeric(w0 + M%*%r$solution); w[w<1e-8]<-0; if(sum(w)<=0) return(NULL); w/sum(w)
}

run_wf <- function(selfun, sizefun, dates, label){
  prev<-setNames(numeric(0),character(0)); rows<-list(); wl<-list(); nfail<-0; nflr<-c()
  for(i in seq_along(dates)){
    dd<-dates[i]; j<-match(dd, ME); x<-A[Date==dd]
    tk <- selfun(x, prev)
    w  <- sizefun(x, prev, tk, j)
    if(is.null(w)){ nfail<-nfail+1; w<-setNames(rep(1/length(tk),length(tk)),tk) }
    w<-w[w>1e-12]; w<-w/sum(w); stopifnot(length(w)<=25, all(w>=0))
    tick<-names(w); r<-x$Ret_1m[match(tick,x$Ticker)]; r[!is.finite(r)]<-0; pg<-sum(w*r)
    allt<-union(names(prev),tick); a<-setNames(numeric(length(allt)),allt); a[names(prev)]<-prev
    b<-setNames(numeric(length(allt)),allt); b[tick]<-w; dw<-b-a; to<-sum(abs(dw))
    adv<-x$adv[match(allt,x$Ticker)]; trd<-abs(dw)>1e-8
    cap<-if(any(trd)) suppressWarnings(min(0.10*adv[trd]/abs(dw)[trd],na.rm=TRUE)) else NA_real_
    rows[[i]]<-data.table(signal_date=dd,n=length(w),ret_gross=pg,traded=to,cost=COST_BPS*to,
      ret_net=pg-COST_BPS*to,bm=BM$BM_Ret[match(dd,BM$Date)],hhi=sum(w^2),maxw=max(w),
      cap_aum=cap,n_new=sum(!tick %in% names(prev)))
    wl[[i]]<-data.table(as_of_date=dd,Ticker=tick,weight=as.numeric(w))
    prev<-setNames(w*(1+r)/(1+pg),tick)
  }
  list(perf=rbindlist(rows), weights=rbindlist(wl), method=label, qp_fail=nfail)
}
sel_top <- function(x,prev) x[order(-fh_lag1d,Ticker)]$Ticker[1:25]
mk_selbuf <- function(B) function(x,prev){
  xo<-x[order(-fh_lag1d,Ticker)]; rk<-setNames(seq_len(nrow(xo)),xo$Ticker)
  keep<-intersect(names(prev),names(rk)); keep<-keep[rk[keep]<=B]
  if(length(keep)>25) keep<-keep[order(rk[keep])][1:25]
  c(keep, setdiff(xo$Ticker,keep)[seq_len(25-length(keep))]) }
size_ew  <- function(x,prev,tk,j) setNames(rep(1/length(tk),length(tk)),tk)
FLR <- new.env(); FLR$n <- c()
size_mvo <- function(x,prev,tk,j){
  z <- sigma_at(j, tk); if(is.null(z)) return(NULL)
  nm <- z$names; FLR$n <- c(FLR$n, sum(z$floored))
  al <- x$alpha_hat[match(nm,x$Ticker)]; al[!is.finite(al)]<-0
  cv <- CVEC[match(nm,names(CVEC))]; cv[!is.finite(cv)]<-median(CVEC,na.rm=TRUE)
  w0 <- setNames(numeric(length(nm)),nm); ov<-intersect(nm,names(prev)); w0[ov]<-prev[ov]
  mvo_to(al, z$S, cv, w0)
}
DTS_C <- DTS_BT[13:length(DTS_BT)]   # 공통 비교창 (Σ warm-up 12M) — 247개월
R4 <- list()
R4$M4 <- run_wf(sel_top, size_mvo, DTS_C, "MVO_TO")
for(B in c(40,50,60,75)) R4[[paste0("M5_B",B)]] <- run_wf(mk_selbuf(B), size_mvo, DTS_C, paste0("BUF",B,"_MVO_TO"))
cat("QP fallback counts:", sapply(R4, function(z) z$qp_fail), "\n")
cat("D-floor: 25종 중 floor 발동 평균", round(mean(FLR$n),2), "종 (범위", range(FLR$n), ")\n")
saveRDS(R4, file.path(OUT,"op4_objects.rds"))
