## p1b_ret1m_offset_scan.R — identify original panel Ret_1m month convention (beta-scan pattern)
suppressPackageStartupMessages({library(arrow); library(data.table); library(lubridate)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
BKP <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(BKP)); bk[,Date:=as.Date(Date)]
SI <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fw <- SI$fwd_ret[,.(d0=Date,Ticker,R=Ret_1m)]
fw[, fym := format(d0 %m+% months(1), "%Y-%m")]   # month in which R is earned
bk2 <- bk[is.finite(Ret_1m),.(Date,Ticker,Ro=Ret_1m)]
for(off in -2:2){
  b <- copy(bk2); b[, tym := format(Date %m+% months(off), "%Y-%m")]
  m <- merge(b, fw, by.x=c("tym","Ticker"), by.y=c("fym","Ticker"))
  cat(sprintf("off=%+d (Ret_1m earned in label-month%+d): n=%d cor=%.4f share|d|<1e-8=%.3f\n",
    off, off, nrow(m), m[,cor(Ro,R)], m[,mean(abs(Ro-R)<1e-8)]))
}
cat("SCAN_DONE\n")
