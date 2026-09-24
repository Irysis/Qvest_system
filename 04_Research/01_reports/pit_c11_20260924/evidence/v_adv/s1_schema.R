suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
s <- open_dataset(paste0(R,"RAWDATA.parquet"))$schema
print(names(s))
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE))
print(names(m)); print(head(m,3))
m[, Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & Date>=as.Date("2026-08-24") & Date<=as.Date("2026-09-05")]
print(v)
v2 <- m[Series_ID=="VIXCLS" & Date>=as.Date("2020-03-24") & Date<=as.Date("2020-04-03")]
print(v2)
f <- as.data.table(read_parquet(paste0(R,"factor_db/factor_db_202608.parquet"), mmap=FALSE))
print(names(f)); print(unique(f$Date)); print(f[Factor_Name=="D32_Beta_VIX"][1:5]); print(f[Factor_Name=="D32_Beta_VIX", .N])
