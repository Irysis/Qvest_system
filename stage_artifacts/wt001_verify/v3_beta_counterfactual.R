# v3 — 주장 A 의 대조군: (i) M01(선별 기준 팩터) 최상위 분위도 같은 β 격차를 보이는가
#      (ii) 관련 반사실은 '유니버스 중앙'이 아니라 '실제 base top-25' 다
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
VER <- file.path(ROOT,"stage_artifacts/wt001_verify")
say <- function(fmt,...) cat(sprintf(paste0("[v3] ",fmt,"\n"),...))
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",col_select=c("Date","Ticker","K200","KQ150")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
UNIV <- RAW[Date %in% MEND][(K200==TRUE|KQ150==TRUE),.(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][,adv:=NULL]; setorder(E,Date,-score); E[,rk:=seq_len(.N),by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(c("D03_EWMA","Q01_EB","M01_PATHQ"),function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ,E[,.(Date,Ticker)],by=c("Date","Ticker")); FZ[,q_rank:=frank(fz)/.N,by=.(Date,F_)]
RM <- merge(returns_dt,bench_dt,by="Date"); dts <- sort(unique(E$Date))
bl <- vector("list",length(dts))
for (i in seq_along(dts)) { if (i<=36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[,{ok<-is.finite(Ret_1m)&is.finite(BM_Ret)
    if(sum(ok)>=24L&&var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_)},by=Ticker][is.finite(beta)]
  bb[,Date:=dts[i]]; bl[[i]] <- bb[,.(Date,Ticker,beta)] }
BETA <- rbindlist(bl)
say("beta panel n=%d months=%d", nrow(BETA), uniqueN(BETA$Date))
for (f in c("D03_EWMA","Q01_EB","M01_PATHQ")) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)],BETA,by=c("Date","Ticker"))
  s <- D[,.(b_top=median(beta[q_rank>0.8]),b_med=median(beta)),by=Date][is.finite(b_top)&is.finite(b_med)]
  say("  [분위] %-10s top-quintile beta %.3f vs univ median %.3f  diff %+.3f  NW3 t %+.2f  NW60 t %+.2f",
      f, mean(s$b_top), mean(s$b_med), mean(s$b_top-s$b_med), nw_t(s$b_top-s$b_med,3L), nw_t(s$b_top-s$b_med,60L))
}
# 실제 top-25 반사실
TOP <- merge(E[rk<=25L,.(Date,Ticker)],BETA,by=c("Date","Ticker"))[,.(b=mean(beta)),by=Date]
UNIVB <- BETA[,.(b_med=median(beta), b_mean=mean(beta)),by=Date]
sel <- list()
for (f in c("D03_EWMA","Q01_EB")) {
  S <- merge(FZ[F_==f,.(Date,Ticker,q_rank)],BETA,by=c("Date","Ticker"))
  setorder(S,Date,-q_rank); S[,r2:=seq_len(.N),by=Date]
  sel[[f]] <- S[r2<=25L,.(b=mean(beta)),by=Date]
}
M <- merge(TOP[,.(Date,b_m01=b)],UNIVB,by="Date")
M <- merge(M,sel$D03_EWMA[,.(Date,b_d03=b)],by="Date")
M <- merge(M,sel$Q01_EB[,.(Date,b_q01=b)],by="Date")
say("  [실제 top-25 EW beta 평균] M01 base %.3f | D03-top25 %.3f | Q01-top25 %.3f | 유니버스 median %.3f mean %.3f",
    mean(M$b_m01), mean(M$b_d03), mean(M$b_q01), mean(M$b_med), mean(M$b_mean))
say("  D03top25 - M01base : %+.3f  NW3 t %+.2f  NW60 t %+.2f", mean(M$b_d03-M$b_m01), nw_t(M$b_d03-M$b_m01,3L), nw_t(M$b_d03-M$b_m01,60L))
say("  M01base  - univMed : %+.3f  NW3 t %+.2f  NW60 t %+.2f", mean(M$b_m01-M$b_med), nw_t(M$b_m01-M$b_med,3L), nw_t(M$b_m01-M$b_med,60L))
saveRDS(M, file.path(VER,"v3_res.rds"))
say("=== v3 완료 ===")
