## _r2_build_slim.R — race-free local slim RDS 사전 생성 (R2용)
## rawdata를 sig_date month-end 거래일로만 제한 → asof_close/fwd 동일(결과불변), 세그폴트/race 회피.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "outputs/ramp"
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date))
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
.me <- .me[!is.na(.me)]
slim <- rawdata[Date %in% .me]
out <- Sys.getenv("RAMP_R1_SLIM_RDS")
saveRDS(slim, out)
cat(sprintf("SLIM_DONE rows=%d dates=%d out=%s\n", nrow(slim), length(.me), out))
