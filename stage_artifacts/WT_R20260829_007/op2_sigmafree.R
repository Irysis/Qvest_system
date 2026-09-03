# OP2 — Σ-free 방법론 (M1/M2/M3) + 진단
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1 <- readRDS(file.path(OUT,"op1_objects.rds")); A<-o1$A; BM<-o1$BM; DTS_BT<-o1$DTS_BT
COST_BPS <- 0.0015

run_wf <- function(wfun, dates=DTS_BT, label="M"){
  prev <- setNames(numeric(0), character(0)); rows<-list(); wl<-list()
  for(i in seq_along(dates)){
    dd <- dates[i]; x <- A[Date==dd]
    w <- wfun(x, prev, i); w <- w[w>1e-12]; w <- w/sum(w)
    stopifnot(length(w)<=25, all(w>=0))
    tick<-names(w); r<-x$Ret_1m[match(tick,x$Ticker)]; r[!is.finite(r)]<-0
    pg <- sum(w*r)
    allt<-union(names(prev),tick); a<-setNames(numeric(length(allt)),allt); a[names(prev)]<-prev
    b<-setNames(numeric(length(allt)),allt); b[tick]<-w; dw<-b-a; to<-sum(abs(dw))
    adv <- x$adv[match(allt,x$Ticker)]; adv[!is.finite(adv)] <- NA_real_
    trd <- abs(dw)>1e-8
    cap <- if(any(trd)) min(0.10*adv[trd]/abs(dw)[trd], na.rm=TRUE) else NA_real_
    rows[[i]] <- data.table(signal_date=dd,n=length(w),ret_gross=pg,traded=to,cost=COST_BPS*to,
                            ret_net=pg-COST_BPS*to,bm=BM$BM_Ret[match(dd,BM$Date)],
                            hhi=sum(w^2),maxw=max(w),cap_aum=cap,
                            n_new=sum(!tick %in% names(prev)))
    wl[[i]] <- data.table(as_of_date=dd,Ticker=tick,weight=as.numeric(w))
    prev <- setNames(w*(1+r)/(1+pg), tick)
  }
  list(perf=rbindlist(rows), weights=rbindlist(wl), method=label)
}

# --- M1 ---
f_ew <- function(x,prev,i){ tk<-x[order(-fh_lag1d,Ticker)]$Ticker[1:25]; setNames(rep(1/25,25),tk) }
# --- M2 buffer(B) ---
mk_buf <- function(B){ function(x,prev,i){
  xo <- x[order(-fh_lag1d,Ticker)]; rk <- setNames(seq_len(nrow(xo)), xo$Ticker)
  keep <- intersect(names(prev), names(rk)); keep <- keep[rk[keep] <= B]
  if(length(keep)>25){ keep <- keep[order(rk[keep])][1:25] }
  fill <- setdiff(xo$Ticker, keep)[seq_len(25-length(keep))]
  tk <- c(keep, fill); setNames(rep(1/length(tk),length(tk)), tk) } }
# --- M3 alpha tilt (rank-linear on α̂ within selected 25, confidence-scaled, floor 0.5/25) ---
CV <- NULL
f_tilt <- function(x,prev,i){
  xo <- x[order(-fh_lag1d,Ticker)][1:25]
  a <- xo$alpha_hat; cf <- CVEC[match(xo$Ticker, names(CVEC))]; cf[!is.finite(cf)] <- median(CVEC,na.rm=TRUE)
  s <- a*cf
  rk <- rank(s, ties.method="average")            # 1..25
  base <- 1/25; lo <- 0.5*base
  w <- lo + (2*base-2*lo)*(rk-1)/24               # 선형 tilt: 평균 = base
  setNames(w/sum(w), xo$Ticker)
}
CVEC <- { cj <- jsonlite::fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))$confidence_vector
          setNames(as.numeric(unlist(cj)), names(cj)) }
cat("confidence_vector n:",length(CVEC)," range:",range(CVEC),"\n")

summ <- function(m){ p<-m$perf; act <- p$ret_net - p$bm
  data.table(method=m$method, months=nrow(p),
    to_annual_2way=mean(p$traded)*12,
    net_ir = mean(act)*12/(sd(act)*sqrt(12)),
    active_ann = mean(act)*12,
    net_cagr = prod(1+p$ret_net)^(12/nrow(p))-1,
    net_sr = mean(p$ret_net)*12/(sd(p$ret_net)*sqrt(12)),
    hhi = mean(p$hhi), maxw = max(p$maxw), n_med = median(p$n),
    cap_med = median(p$cap_aum,na.rm=TRUE), cap_p10 = quantile(p$cap_aum,0.10,na.rm=TRUE),
    cap_12m = median(tail(p$cap_aum,12),na.rm=TRUE),
    new_names_m = mean(p$n_new)) }

RES <- list()
RES$M1 <- run_wf(f_ew, label="EW25_base")
for(B in c(40,50,60,75)) RES[[paste0("M2_B",B)]] <- run_wf(mk_buf(B), label=paste0("EW25_buffer",B))
RES$M3 <- run_wf(f_tilt, label="ALPHA_TILT")
S <- rbindlist(lapply(RES, summ))
S[, cap_med:=round(cap_med/1e8,2)][, cap_p10:=round(cap_p10/1e8,2)][, cap_12m:=round(cap_12m/1e8,2)]
print(S[, .(method, to_annual_2way=round(to_annual_2way,3), G5=to_annual_2way<=11.0,
            net_ir=round(net_ir,4), active_ann=round(active_ann,4), net_cagr=round(net_cagr,4),
            net_sr=round(net_sr,4), hhi=round(hhi,4), cap_med_e8=cap_med, cap_12m_e8=cap_12m,
            new_nm=round(new_names_m,2))])
saveRDS(RES, file.path(OUT,"op2_objects.rds")); saveRDS(S, file.path(OUT,"op2_summary.rds"))
