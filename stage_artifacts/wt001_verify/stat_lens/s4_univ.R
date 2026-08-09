suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
VOUT <- file.path(ROOT,"stage_artifacts/wt001_verify/stat_lens")
say <- function(fmt,...) cat(sprintf(paste0("[U] ",fmt,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
raw_score <- function(f) if (f %in% BASE$Factor_Name) BASE[Factor_Name==f & !is.na(z), .(Date,Ticker,score=z)] else TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)]
E <- merge(merge(raw_score("M01_PATHQ"), UNIV, by=c("Date","Ticker")), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% returns_dt$Date]
RM <- merge(returns_dt, bench_dt, by="Date"); dts <- sort(unique(E$Date))
bl <- vector("list", length(dts))
for (i in seq_along(dts)) { if (i<=36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[, {ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
    if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_)}, by=Ticker][is.finite(beta)]
  bb[, Date:=dts[i]]; bl[[i]] <- bb }
BETA <- rbindlist(bl)
nwt <- function(x,lag){x<-x[is.finite(x)];f<-lm(x~1);as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3])}
for (f in FILT) {
  for (mode in c("eligible","full_tuned")) {
    sc <- raw_score(f)
    if (mode=="eligible") sc <- merge(sc, E[,.(Date,Ticker)], by=c("Date","Ticker"))
    sc[, q_rank:=frank(score)/.N, by=Date]
    D <- merge(sc, BETA, by=c("Date","Ticker"))
    s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), nn=.N), by=Date]
    s <- s[is.finite(b_top)&is.finite(b_med)]
    x <- s$b_top - s$b_med
    say("%-9s %-11s: top %.3f  univ %.3f  gap %+.4f | t(L3)=%.2f t(L59)=%.2f | 월평균 종목 %.0f · n=%d",
        f, mode, mean(s$b_top), mean(s$b_med), mean(x), nwt(x,3), nwt(x,59), mean(s$nn), nrow(s))
  }
  # 풀링 중앙값 (1차 실행 방식)
  sc <- raw_score(f); sc[, q_rank:=frank(score)/.N, by=Date]
  D <- merge(sc, BETA, by=c("Date","Ticker"))
  say("%-9s pooled(1차식) : Q5 median %.4f  univ median %.4f  gap %+.4f",
      f, D[q_rank>0.8, median(beta)], D[, median(beta)], D[q_rank>0.8, median(beta)] - D[, median(beta)])
}
