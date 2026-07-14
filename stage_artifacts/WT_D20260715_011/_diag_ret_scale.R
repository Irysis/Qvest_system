Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))
setDTthreads(1); try(arrow::set_io_thread_count(2L), silent=TRUE)
ym <- function(d){ d<-as.Date(d); as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m")) }
diag_one <- function(path, lbl){
  cat(sprintf("\n===== %s (%s) =====\n", lbl, path))
  if(!file.exists(path)){ cat("  (부재)\n"); return(invisible()) }
  rw <- as.data.table(read_parquet(path, col_select=c("Date","Ticker","Ret")))
  rw[, Date:=as.Date(Date)]; rw[, ymv:=ym(Date)]
  cat(sprintf("  overall Ret: min=%.4f p1=%.4f med=%.4f mean=%.5f p99=%.4f max=%.4f  N=%d\n",
      min(rw$Ret,na.rm=T), quantile(rw$Ret,.01,na.rm=T), median(rw$Ret,na.rm=T),
      mean(rw$Ret,na.rm=T), quantile(rw$Ret,.99,na.rm=T), max(rw$Ret,na.rm=T), nrow(rw)))
  s <- rw[Ticker=="A011070" & ymv==202605][order(Date)]
  cat(sprintf("  A011070 202605: n=%d  Ret 값들: %s\n", nrow(s),
      paste(sprintf("%.4f", s$Ret), collapse=" ")))
  cat(sprintf("  A011070 202605 prod(1+Ret)-1 = %+.4f\n", prod(1+s$Ret)-1))
}
diag_one("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/rawdata.parquet", "LIVE rawdata")
diag_one("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/pin/rawdata_r9_pin_20260715.parquet", "R40 PINNED rawdata")
