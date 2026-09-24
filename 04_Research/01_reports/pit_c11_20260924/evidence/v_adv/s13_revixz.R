suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
st <- unique(as.data.table(read_parquet(paste0(R,"factor_db_daily/fdb_daily_202003.parquet"), col_select=c("Date","RE_VIX_z","RE_MRS"), mmap=FALSE))); st[, Date:=as.Date(Date)]
rg <- as.data.table(read_parquet(paste0(R,"regime_daily_v2.parquet"), mmap=FALSE))[, .(Date=as.Date(Date), VZ=VIX_z_smooth, MRS)]
x <- merge(st, rg, by="Date"); x[, VZ_prev := rg[.(x$Date-1L), on="Date", roll=TRUE]$VZ]
cat(sprintf("n=%d  mean|RE_VIX_z - VZ(same)|=%.4f  mean|RE_VIX_z - VZ(prev row)|=%.4f  mean|RE_MRS-MRS|=%.4f\n", nrow(x), mean(abs(x$RE_VIX_z-x$VZ),na.rm=T), mean(abs(x$RE_VIX_z-x$VZ_prev),na.rm=T), mean(abs(x$RE_MRS-x$MRS),na.rm=T)))
print(x[Date %in% as.Date(c("2020-03-13","2020-03-16","2020-03-17"))])
