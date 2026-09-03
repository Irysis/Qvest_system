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
  w <- setNames(as.numeric(w0 + M%*%r$solution), names(w0)); w[w<1e-8]<-0; if(sum(w)<=0) return(NULL); w/sum(w)
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
  nm <- z$names; FLR$n <- c(FLR$n, sum(z$floored)); FLR$rat <- c(FLR$rat, mean(z$d_floored/z$d_raw))
  al <- x$alpha_hat[match(nm,x$Ticker)]; al[!is.finite(al)]<-0
  cv <- CVEC[match(nm,names(CVEC))]; cv[!is.finite(cv)]<-median(CVEC,na.rm=TRUE)
  w0 <- setNames(numeric(length(nm)),nm); ov<-intersect(nm,names(prev)); w0[ov]<-prev[ov]
  mvo_to(al, z$S, cv, w0)
}
size_tilt <- function(x,prev,tk,j){
  a <- x$alpha_hat[match(tk,x$Ticker)]; cf<-CVEC[match(tk,names(CVEC))]; cf[!is.finite(cf)]<-median(CVEC,na.rm=TRUE)
  rk <- rank(a*cf, ties.method="average"); n<-length(tk); base<-1/n; lo<-0.5*base
  w <- lo + (2*base-2*lo)*(rk-1)/(n-1); setNames(w/sum(w), tk)
}
