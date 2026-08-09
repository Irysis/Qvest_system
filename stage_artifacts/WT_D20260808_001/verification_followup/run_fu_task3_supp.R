# =============================================================================
# run_fu_task3_supp.R — ③ 보충: 렌즈4 의 (D03 0.46 / Q01 0.24) 가 어떤 사양에서 나오는가.
#   내 1차 실측은 0.549 / 0.345 (RAWDATA Sector, 중앙값 gap). 방향은 같으나 크기가 다르다.
#   ★"재현/불재현 명시 판정" 의무 → 섹터 정의 3종 x gap 통계 2종을 전수로 재서 판정한다.
#   섹터 정의: RAWDATA Sector / RAWDATA Sector_Lv2 / WT-009 sector_panel.parquet
#   gap 통계: median(top20%)−median(univ) / mean(top20%)−mean(univ)
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(f,...) cat(sprintf(paste0("[fu3s] ",f,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}

BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","K200","KQ150","Sector","Sector_Lv2")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE),.(Date,Ticker)]
SECS <- list(rawdata_Sector = RAWME[,.(Date,Ticker,sec=Sector)],
             rawdata_Sector_Lv2 = RAWME[,.(Date,Ticker,sec=Sector_Lv2)])
sp <- file.path(IN9,"sector_panel.parquet")
if (file.exists(sp)) {
  SP <- as.data.table(read_parquet(sp))[,Date:=as.Date(Date)]
  say("sector_panel 컬럼: %s · %d행 · 고유 섹터 %d", paste(names(SP),collapse=","), nrow(SP),
      uniqueN(SP[[setdiff(names(SP),c("Date","Ticker"))[1]]]))
  sc <- setdiff(names(SP), c("Date","Ticker"))[1]
  SECS$wt009_sector_panel <- SP[, .(Date, Ticker, sec = get(sc))]
} else say("★sector_panel.parquet 부재 — 이 정의는 검사 불가")

fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
score_of <- function(f){s <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(s[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][,adv:=NULL]; E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ,E[,.(Date,Ticker)],by=c("Date","Ticker")); FZ[,q_rank:=frank(fz)/.N,by=.(Date,F_)]

RM <- merge(returns_dt,bench_dt,by="Date"); dts <- sort(unique(E$Date))
bl <- vector("list",length(dts))
for (i in seq_along(dts)) { if (i<=36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[,{ok<-is.finite(Ret_1m)&is.finite(BM_Ret)
    if(sum(ok)>=24L&&var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_)},by=Ticker][is.finite(beta)]
  bb[,Date:=dts[i]]; bl[[i]] <- bb[,.(Date,Ticker,beta)] }
BETA <- rbindlist(bl); say("β 패널 %d행 / %d개월", nrow(BETA), uniqueN(BETA$Date))

gap_of <- function(D, col, stat) {
  f <- if (stat=="median") median else mean
  s <- D[, .(g_top=f(get(col)[q_rank>0.8]), g_all=f(get(col))), by=Date]
  s <- s[is.finite(g_top)&is.finite(g_all)][order(Date)]
  s$g_top - s$g_all
}
GRID <- list()
for (fac in FILT) {
  Draw <- merge(FZ[F_==fac,.(Date,Ticker,q_rank)], BETA, by=c("Date","Ticker"))
  for (stat in c("median","mean")) {
    graw <- gap_of(Draw, "beta", stat)
    for (sn in names(SECS)) {
      SS <- SECS[[sn]][!is.na(sec)]
      X <- merge(BETA, SS, by=c("Date","Ticker"))
      X[, ncell := .N, by=.(Date,sec)]; X[ncell<3L, sec:="OTHER_SMALL"]
      X[, beta_res := beta - mean(beta), by=.(Date,sec)]
      D <- merge(FZ[F_==fac,.(Date,Ticker,q_rank)], X[,.(Date,Ticker,beta_res)], by=c("Date","Ticker"))
      gres <- gap_of(D, "beta_res", stat)
      n <- min(length(graw), length(gres))
      ret <- mean(gres)/mean(graw)
      key <- sprintf("%s|%s|%s", fac, sn, stat)
      GRID[[key]] <- list(factor=fac, sector_def=sn, stat=stat,
        gap_raw=mean(graw), gap_resid=mean(gres), retention=ret,
        t_nw_lag3_resid=nw_t(gres), n_raw=length(graw), n_resid=length(gres))
      say("  %-11s %-20s %-6s : raw %+.4f → 잔차 %+.4f  잔존 **%.3f**  (n=%d)",
          fac, sn, stat, mean(graw), mean(gres), ret, length(gres))
    }
  }
}
saveRDS(GRID, file.path(FU,"fu_task3_supp.rds"))
say("=== 렌즈4 주장(D03 0.46 / Q01 0.24) 대조 ===")
d <- sapply(GRID[grep("^D03", names(GRID))], function(x) x$retention)
q <- sapply(GRID[grep("^Q01", names(GRID))], function(x) x$retention)
say("  D03 잔존 범위 [%.3f, %.3f] — 0.46 포함? %s", min(d), max(d), min(d)<=0.46 && 0.46<=max(d))
say("  Q01 잔존 범위 [%.3f, %.3f] — 0.24 포함? %s", min(q), max(q), min(q)<=0.24 && 0.24<=max(q))
