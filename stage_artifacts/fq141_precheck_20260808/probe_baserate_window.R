suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker")); setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
M <- P[, .(ms = mean(Ret_1m[rk<=10]) - median(Ret_1m)), by=Date][order(Date)]
M[, ms_lag := shift(ms,1)]
W <- M[Date >= as.Date("2019-12-01") & Date <= as.Date("2026-07-31") & is.finite(ms_lag)]
cat(sprintf("panelx_A 창(2019-12~2026-07): %d개월\n", nrow(W)))
cat(sprintf("  t-1 mega_spread<=0 = %d개월 (%.1f%%)\n", sum(W$ms_lag<=0), mean(W$ms_lag<=0)*100))
cat(sprintf("  전 구간 base rate  = %.1f%%\n", mean(M[is.finite(ms_lag)]$ms_lag<=0)*100))
cat(sprintf("  ★보고된 n=27 대비: 본 창 실측 %d\n", sum(W$ms_lag<=0)))
