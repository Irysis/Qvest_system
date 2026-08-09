# v4_attrition.R — C6: forward 수익 결측(상폐/거래정지) 이 분위별로 편중되는가
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
W1 <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[v4] ",fmt,"\n"),...))
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close","Vol","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
fwd <- readRDS(file.path(W1,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
say("fwd firewall dropped = %s", as.character(fwd$ret_firewall_dropped))
score_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(score_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% ret$Date]
say("eligible %d행 (forward 수익 결측 포함 여부 확인용)", nrow(E))
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
for (f in c("D03_EWMA","Q01_EB")) {
  FZ <- merge(score_of(f)[, .(Date,Ticker,fz=score)], E[, .(Date,Ticker)], by=c("Date","Ticker"))
  FZ <- merge(FZ, ret[, .(Date,Ticker,has_ret=TRUE)], by=c("Date","Ticker"), all.x=TRUE)
  FZ[is.na(has_ret), has_ret:=FALSE]
  FZ[, q := cut(frank(fz), breaks=5, labels=FALSE), by=Date]
  tb <- FZ[, .(miss_rate=1-mean(has_ret), n=.N), by=q][order(q)]
  say("%s forward 수익 결측률 Q1..Q5 = %s (전체 %.4f, n=%d)", f,
      paste(sprintf("%.4f", tb$miss_rate), collapse=" "), 1-mean(FZ$has_ret), nrow(FZ))
  # 월별 결측률 차 Q1-Q5 의 유의성
  s <- FZ[, .(d = (1-mean(has_ret[q==1])) - (1-mean(has_ret[q==5]))), by=Date]
  say("   Q1-Q5 결측률 차 평균 %+.5f  NW t %+.2f", mean(s$d, na.rm=TRUE), nw_t(s$d))
}
say("=== v4 완료 ===")
