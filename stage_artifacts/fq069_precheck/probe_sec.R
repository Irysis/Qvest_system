suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector","Size","K200","KQ150")))
R[, Date := as.Date(Date)]
U <- R[Date>=as.Date("2015-01-01") & (K200==TRUE|KQ150==TRUE) & !is.na(Size)]
sec <- U[!is.na(Sector), .(n=uniqueN(Ticker)), by=Sector][order(-n)]
cat(sprintf("RAWDATA Sector %d종 (총 %d종목)\n", nrow(sec), sum(sec$n)))
for (i in seq_len(nrow(sec))) cat(sprintf("%2d. %-22s %3d\n", i, sec$Sector[i], sec$n[i]))
