suppressMessages({library(arrow);library(data.table)})
WD<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
car<-as.data.table(read_parquet(file.path(WD,"06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"))); car[,dd:=as.Date(decision_date)]
pm<-as.data.table(read_parquet(file.path(WD,"stage_artifacts/pg2_overlay_gate_composition_20260705/panel_size_mom.parquet"))); pm[,Date:=as.Date(Date)]
m<-merge(car,pm[,.(Date,Ticker,size)],by.x=c("dd","Ticker"),by.y=c("Date","Ticker"),all.x=TRUE)
sink(file.path(WD,"stage_artifacts/pg2_overlay_gate_composition_20260705/diag_size.txt"))
cat("carrier rows:",nrow(m)," size_NA_frac:",round(mean(is.na(m$size)),3),"\n")
cat("months with >=1 NA-size:",m[,sum(is.na(size))>0,by=dd][V1==TRUE,.N]," / ",uniqueN(m$dd),"\n")
m2<-m[!is.na(size)]; m2[order(-size),rk:=seq_len(.N),by=dd]
cat("Samsung A005930: present_frac:",round(uniqueN(m2[Ticker=='A005930']$dd)/uniqueN(m2$dd),3)," in_top2_frac:",round(m2[Ticker=='A005930',mean(rk<=2)],3),"\n")
cat("top-2-by-size ticker freq:\n"); print(m2[rk<=2,.N,by=Ticker][order(-N)][1:8])
cat("\nNA-size rows: are they high-weight? mean weight_strategy NA-size vs known:\n")
cat("  NA-size mean w:",round(m[is.na(size),mean(weight_strategy,na.rm=T)],4)," known-size mean w:",round(m[!is.na(size),mean(weight_strategy,na.rm=T)],4),"\n")
sink()
cat("done\n")
