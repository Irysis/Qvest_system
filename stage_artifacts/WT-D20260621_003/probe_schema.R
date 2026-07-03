suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
OUT <- "stage_artifacts/WT-D20260621_003/probe_out.txt"
w <- function(...) cat(paste0(..., "\n"), file=OUT, append=TRUE)
cat("", file=OUT)  # truncate

sc <- function(f){ tryCatch({ s <- arrow::open_dataset(f)$schema; paste(names(s), collapse=", ") }, error=function(e) paste("ERR", e$message)) }
w("rawdata cols: ", sc(".cache/rawdata.parquet"))
w("investor_wide cols: ", sc(".cache/investor_stock/investor_wide.parquet"))
w("eps_chg_1m cols: ", sc(".cache/consensus/eps_chg_1m.parquet"))
w("esbr cols: ", sc(".cache/consensus/esbr.parquet"))
w("benchmark cols: ", sc(".cache/benchmark.parquet"))

rd <- as.data.table(arrow::read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Size","Ret","BM_Ret")))
w("rawdata Date range: ", as.character(min(rd$Date,na.rm=T)), " to ", as.character(max(rd$Date,na.rm=T)), " nrow=", nrow(rd))
w("rawdata BM_Ret non-NA frac: ", round(mean(!is.na(rd$BM_Ret)),4))
w("rawdata Ret non-NA frac: ", round(mean(!is.na(rd$Ret)),4), " Size non-NA: ", round(mean(!is.na(rd$Size)),4))
w("rawdata n tickers: ", uniqueN(rd$Ticker))
w("rawdata sample Ret values: ", paste(round(head(rd[!is.na(Ret)]$Ret,5),4), collapse=" "))
rm(rd); gc()

iv <- as.data.table(arrow::read_parquet(".cache/investor_stock/investor_wide.parquet"))
w("investor cols actual: ", paste(names(iv), collapse=", "))
w("investor Date range: ", as.character(min(iv$Date,na.rm=T)), " to ", as.character(max(iv$Date,na.rm=T)))
w("investor Foreign nonzero frac: ", round(mean(iv$Foreign!=0 & !is.na(iv$Foreign)),4), " Inst: ", round(mean(iv$Institutional!=0 & !is.na(iv$Institutional)),4))
w("investor head:\n", paste(capture.output(print(head(iv,2))), collapse="\n"))
rm(iv); gc()

ep <- as.data.table(arrow::read_parquet(".cache/consensus/eps_chg_1m.parquet"))
w("eps_chg_1m cols actual: ", paste(names(ep), collapse=", "), " nrow=", nrow(ep))
w("eps_chg_1m Date range: ", as.character(min(ep$Date,na.rm=T)), " to ", as.character(max(ep$Date,na.rm=T)))
w("eps_chg_1m head:\n", paste(capture.output(print(head(ep,2))), collapse="\n"))

bm <- as.data.table(arrow::read_parquet(".cache/benchmark.parquet"))
w("benchmark cols actual: ", paste(names(bm), collapse=", "))
w("benchmark Date range: ", as.character(min(bm$Date,na.rm=T)), " to ", as.character(max(bm$Date,na.rm=T)))
w("benchmark head:\n", paste(capture.output(print(head(bm,3))), collapse="\n"))
w("DONE")
