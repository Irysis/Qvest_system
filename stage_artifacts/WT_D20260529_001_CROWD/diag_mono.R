suppressMessages({library(data.table); library(arrow)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
panel <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")))[,.(Date=as.Date(Date),Ticker,Ret_1m)][!is.na(Ret_1m)]
CR <- c("CR01_Sector_Comovement","CR02_Volume_Concentration","CR03_Herding_Dispersion","CR04_Ownership_Concentration","CR05_Short_Pressure_Proxy","CR06_DTC_Proxy","CR08_Volume_Price_Divergence","CR09_Money_Flow_Ratio","CR10_Convergence_Premium","CR11_Idiosyncratic_Return")
sds <- sort(unique(panel$Date))
load_cr <- function(sd){ff<-tryCatch(load_month_factors(sd,0.05),error=function(e)NULL); if(is.null(ff))return(NULL); ff<-ff[Factor_Name%in%CR]; if(!nrow(ff))return(NULL); w<-dcast(ff,Ticker~Factor_Name,value.var="Z_Score_Aligned",fun.aggregate=function(x)x[1]); w[,Date:=sd];w}
cr_all <- rbindlist(lapply(sds,load_cr),fill=TRUE)
present <- intersect(CR,names(cr_all))
dt <- merge(panel,cr_all,by=c("Date","Ticker"),all.x=TRUE)
dt[, cr_raw := rowMeans(.SD,na.rm=TRUE),.SDcols=present]
dt[, cr_composite := {m<-mean(cr_raw,na.rm=TRUE);s<-sd(cr_raw,na.rm=TRUE);if(is.na(s)||s<1e-9)cr_raw-m else (cr_raw-m)/s},by=Date]
md <- dt[!is.na(cr_composite)&!is.na(Ret_1m)]
md[, dec := cut(frank(cr_composite)/.N,breaks=seq(0,1,.1),labels=FALSE,include.lowest=TRUE),by=Date]
cat("Decile mean Ret_1m (1=lowest composite, 10=highest):\n")
print(md[,.(mean_ret=round(mean(Ret_1m),5),n=.N),by=dec][order(dec)])
# bad-month only decile
bench <- dt[!is.na(Ret_1m),.(bm=mean(Ret_1m)),by=Date]
bench[, bad := bm<=quantile(bm,0.2)]
md <- merge(md, bench[,.(Date,bad)],by="Date")
cat("\nBad-month decile mean Ret_1m:\n")
print(md[bad==TRUE,.(mean_ret=round(mean(Ret_1m),5),n=.N),by=dec][order(dec)])
