Sys.setenv(ARROW_IO_THREADS="2")
suppressWarnings(suppressMessages({library(arrow);library(data.table)}))
setDTthreads(1); try(arrow::set_io_thread_count(2L),silent=TRUE)
IN <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet"))
IN[, signal_date := as.Date(signal_date)]
ym <- function(d) as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m"))
ymshift <- function(v,k){y<-v%/%100L;m<-v%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
IN[, hy := ymshift(ym(signal_date),1L)]   # signal m -> holding m+1
# INS02 for the two tickers across recent holding months
for (tk in c("A011070","A004170","A005930")) {
  cat("\n==", tk, "==\n")
  x <- IN[security_id==tk & factor_id=="INS02_OffBuyBreadth6m" & hy %in% c(202604,202605,202606,202607),
          .(holding_ym=hy, signal_date, z=round(z,4))][order(holding_ym)]
  print(x)
  cat("  >=1.0 flag by holding_ym:\n")
  print(x[, .(holding_ym, on=z>=1.0)])
}
