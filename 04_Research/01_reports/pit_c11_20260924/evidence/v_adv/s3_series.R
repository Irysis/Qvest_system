suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
print(m[, .(n=.N, first=min(Date), last=max(Date), freq=Frequency[1], nm=Series[1]), by=Series_ID])
print(m[Series_ID=="CPIAUCSL" & Date>=as.Date("2026-05-01")])
print(m[Series_ID=="INDPRO" & Date>=as.Date("2026-05-01")])
