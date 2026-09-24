suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
source_lines <- readLines("s4_monthly.R"); eval(parse(text=source_lines[5:11]))
rd_all <- as.data.table(read_parquet(paste0(R,"RAWDATA.parquet"), col_select=c("Date","Ticker","Ret"), mmap=FALSE)); rd_all[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]; m[, Series:=Series_ID]
sig <- as.Date("2020-03-31")
st <- as.data.table(read_parquet(paste0(R,"factor_db/factor_db_202003.parquet"), mmap=FALSE))[Factor_Name=="MA02_CPI_Sensitivity", .(Ticker, stored=Raw_Value)]
MA <- m[Date <= sig-1L & !is.na(Value)]
a <- mb(MA, rd_all[Date<=sig & Date>=sig-365], "CPIAUCSL")
x <- merge(st, a, by="Ticker"); cat(sprintf("2020-03 MA02 stored n=%d matched=%d exactA=%.3f; safe-variant months available=%d (<12 => factor would not exist)\n", nrow(st), nrow(x), mean(abs(x$stored-x$beta)<1e-9), 11L))
