# RK2 — 실현 book 재구성(일간) + 월간 대조
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
rl <- load_rawdata(use_cache=TRUE); RAW <- as.data.table(rl$RAWDATA); BM <- as.data.table(rl$BM_DT); rm(rl); gc(verbose=FALSE)
RAW[,Date:=as.Date(Date)]; BM[,Date:=as.Date(Date)]
RAW <- RAW[Date>=as.Date("2004-06-01") & is.finite(Ret)]
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
PR <- fread(file.path(OUT,"period_returns_production.csv"))
PR[,signal_date:=as.Date(signal_date)]

hold <- A[in_top25==TRUE,.(Date,Ticker)]           # Date = 신호월말 t → 홀딩월 t+1
hold[,holding_ym := format(as.Date(format(Date+31,"%Y-%m-01"))-0,"%Y-%m")]
hold[,holding_ym := PR[match(hold$Date, PR$signal_date), holding_ym]]
stopifnot(!any(is.na(hold$holding_ym)))
cat("[RK2] 홀딩 월 수",uniqueN(hold$holding_ym),"· 종목-월",nrow(hold),"\n")

DX <- RAW[,.(Date,Ticker,Ret,Close,Vol,Size,Sector)]
DX[,ym:=format(Date,"%Y-%m")]
setkey(DX,ym,Ticker)
H <- merge(hold[,.(ym=holding_ym,Ticker)], DX, by=c("ym","Ticker"), allow.cartesian=TRUE)
setorder(H,ym,Ticker,Date)
# 홀딩월 내 buy-and-hold: 월초 EW → 일간 drift
H[,cum:=cumprod(1+Ret),by=.(ym,Ticker)]
H[,w_prev:=shift(cum,fill=1),by=.(ym,Ticker)]
day <- H[,.(ret_d=sum(w_prev*Ret)/sum(w_prev), n=.N), by=.(ym,Date)][order(Date)]
cat("[RK2] 일간 book 관측",nrow(day),"·",as.character(range(day$Date)),"\n")
mon <- day[,.(ret_m=prod(1+ret_d)-1, nd=.N),by=ym]
chk <- merge(PR[,.(ym=holding_ym, ret_gross)], mon, by="ym")
cat(sprintf("[RK2] 월간 재구성 vs CSV ret_gross: cor=%.6f · maxabs=%.5f · mean|diff|=%.6f\n",
  cor(chk$ret_gross,chk$ret_m), max(abs(chk$ret_gross-chk$ret_m)), mean(abs(chk$ret_gross-chk$ret_m))))
bmd <- BM[,.(Date,BM_Ret)][Date %in% day$Date]
day <- merge(day, bmd, by="Date", all.x=TRUE)
fwrite(day, file.path(OUT,"rk_book_daily.csv"))
saveRDS(list(hold=hold, day=day, chk=chk), file.path(OUT,"rk2_objects.rds"))
cat("[RK2] done\n")
