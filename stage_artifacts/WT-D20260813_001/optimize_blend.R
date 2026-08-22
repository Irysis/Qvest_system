## Turnover-constrained blend: w = (1-θ)·EW + θ·ScoreTilt, find max θ with ann_turnover ≤ 11.0
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT <- "WT-D20260813_001"; SA <- file.path("stage_artifacts", WT)
SRC <- "stage_artifacts/fq233_probe0_20260813"
inp <- readRDS(file.path(SRC, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date=as.Date(Date), Ticker=as.character(Ticker), Ret_1m=as.numeric(Ret_1m))][is.finite(Ret_1m)]
scores <- as.data.table(read_parquet(file.path(SA, "alpha_scores.parquet")))[
  , .(Date=as.Date(Date), sig_date=as.Date(sig_date), Ticker=as.character(Ticker), score=as.numeric(alpha_score))]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)][is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by=bm$Date), Return.cumulative)
bench_m <- data.table(ym=format(as.Date(index(bmm)),"%Y%m"), BM_Ret=as.numeric(bmm[,1]))
returns_dt[, ym := format(Date,"%Y%m")]
bench_dt <- merge(unique(returns_dt[,.(Date,ym)]), bench_m, by="ym")[,.(Date,BM_Ret)]

TOP_N <- 25L; COST <- 0.0015; BOUND_HI <- 0.20
nw_t <- function(x, lag=3L){x<-x[is.finite(x)];n<-length(x);m<-mean(x);e<-x-m;s<-sum(e^2)/n
  for(l in 1:lag){w<-1-l/(lag+1);s<-s+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n};m/sqrt(s/n)}

w_scheme <- function(scd, theta) {
  tk <- scd$Ticker; s <- scd$score; n <- length(tk)
  ew <- rep(1/n, n)
  a <- s - min(s) + 1e-6; tilt <- a/sum(a); tilt <- pmin(tilt, BOUND_HI); tilt <- tilt/sum(tilt)
  w <- (1-theta)*ew + theta*tilt
  w <- pmin(w, BOUND_HI); w <- w/sum(w); names(w) <- tk; w
}

eval_theta <- function(theta) {
  dts <- sort(unique(scores$sig_date)); map_dt <- unique(scores[,.(sig_date,Date)])
  rows <- list(); prev_w <- NULL
  for (sd_ in dts) {
    scd <- scores[sig_date==sd_][order(-score)][1:TOP_N]
    hd <- map_dt[sig_date==sd_]$Date[1]
    rr <- returns_dt[Date==hd & Ticker %in% scd$Ticker]
    if (nrow(rr) < TOP_N*0.8) next
    w <- w_scheme(scd, theta); common <- intersect(names(w), rr$Ticker)
    w <- w[common]; w <- w/sum(w); rvec <- setNames(rr$Ret_1m, rr$Ticker)[common]
    gross <- sum(w*rvec)
    if (is.null(prev_w)) to <- sum(w) else {
      allnm <- union(names(prev_w), names(w))
      pw <- setNames(rep(0,length(allnm)),allnm); pw[names(prev_w)] <- prev_w
      cw <- setNames(rep(0,length(allnm)),allnm); cw[names(w)] <- w; to <- sum(abs(cw-pw))
    }
    net <- gross - to*COST
    rows[[length(rows)+1]] <- data.table(date=hd, net=net, to=to); prev_w <- w
  }
  d <- rbindlist(rows); px <- xts(d$net, order.by=d$date)
  bm_al <- bench_dt[Date %in% d$date][order(Date)]
  act <- d$net - bm_al$BM_Ret[match(d$date, bm_al$Date)]
  data.table(theta=theta,
    net_sr=as.numeric(SharpeRatio.annualized(px,Rf=0,scale=12,geometric=FALSE)),
    cagr=as.numeric(Return.annualized(px,scale=12,geometric=TRUE)),
    mdd=as.numeric(maxDrawdown(px)),
    ann_turnover=mean(d$to)*12,
    active_ir=(mean(act,na.rm=TRUE)/sd(act,na.rm=TRUE))*sqrt(12),
    port_t_nw=nw_t(act,3))
}

res <- rbindlist(lapply(seq(0, 1, 0.1), eval_theta))
res[, calmar := cagr/pmax(mdd,1e-9)]
res[, to_ok := ann_turnover <= 11.0]
print(res)
fwrite(res, file.path(SA, "blend_theta_sweep.csv"))
cat("BLEND_DONE\n")
