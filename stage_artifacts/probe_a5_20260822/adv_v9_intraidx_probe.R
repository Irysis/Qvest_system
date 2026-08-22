QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
t0<-Sys.time()
f<-tryCatch(as.data.table(load_month_factors(as.Date("2020-06-30"),
    factor_names=c("V12_Composite_Value","M09_Composite_Mom","D03_RealVol"))),error=function(e){print(e);NULL})
cat("elapsed:",as.numeric(difftime(Sys.time(),t0,units="secs")),"sec ; rows=",if(is.null(f))0 else nrow(f),"\n")
if(!is.null(f)) print(head(f,3))
