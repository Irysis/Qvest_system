suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(...) cat(sprintf(...), "\n")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bch <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
sc_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(sc_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% ret$Date]
FZ <- rbindlist(lapply(c("D03_EWMA","Q01_EB"), function(f) sc_of(f)[, .(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]
RM <- merge(ret, bch, by="Date")
dts <- sort(unique(E$Date))
say("[SHAPE] eligible n_month=%d, FZ nrow=%d", length(dts), nrow(FZ))

beta_panel <- function(extra_lag=0L){
  L <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    if (i <= 36L+extra_lag) next
    hi <- i-1L-extra_lag; lo <- max(1L, hi-59L)
    w <- RM[Date %in% dts[lo:hi]]
    bb <- w[, {ok<-is.finite(Ret_1m)&is.finite(BM_Ret)
      if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_)}, by=Ticker][is.finite(beta)]
    bb[, Date:=dts[i]]; L[[i]] <- bb
  }
  rbindlist(L)
}
for (el in c(0L,1L,3L,6L)) {
  B <- beta_panel(el)
  for (f in c("D03_EWMA","Q01_EB")) {
    D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)], B, by=c("Date","Ticker"))
    s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), b_bot=median(beta[q_rank<=0.2])), by=Date]
    s <- s[is.finite(b_top)&is.finite(b_med)]
    say("[extra_lag=%d] %-9s top %.3f  univ_med %.3f  diff %+.3f  NW-t %+.2f | bot diff %+.3f (t %+.2f)  n=%d",
        el, f, mean(s$b_top), mean(s$b_med), mean(s$b_top-s$b_med), nw_t(s$b_top-s$b_med),
        mean(s$b_bot-s$b_med), nw_t(s$b_bot-s$b_med), nrow(s))
  }
}
# 순환성 점검: D03 = -EWMAvol 이면 trailing beta 와 기계적 중첩. 겹치지 않는 창으로 재측정
say("---- 비중첩 창 대조: 신호 창(252 거래일 ~ 12개월)과 겹치지 않게 beta 창을 12개월 더 뒤로 ----")
B12 <- beta_panel(12L)
for (f in c("D03_EWMA","Q01_EB")) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)], B12, by=c("Date","Ticker"))
  s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta)), by=Date][is.finite(b_top)&is.finite(b_med)]
  say("[non-overlap] %-9s top %.3f univ %.3f diff %+.3f NW-t %+.2f n=%d", f,
      mean(s$b_top), mean(s$b_med), mean(s$b_top-s$b_med), nw_t(s$b_top-s$b_med), nrow(s))
}
