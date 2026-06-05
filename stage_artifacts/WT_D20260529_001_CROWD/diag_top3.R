suppressMessages({library(data.table); library(arrow)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
panel <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")))[,.(Date=as.Date(Date),Ticker,Ret_1m,score_1715=score_eff)][!is.na(Ret_1m)]
TOP3 <- c("CR06_DTC_Proxy","CR04_Ownership_Concentration","CR08_Volume_Price_Divergence")
sds <- sort(unique(panel$Date))
load_cr <- function(sd){ff<-tryCatch(load_month_factors(sd,0.05),error=function(e)NULL); if(is.null(ff))return(NULL); ff<-ff[Factor_Name%in%TOP3]; if(!nrow(ff))return(NULL); w<-dcast(ff,Ticker~Factor_Name,value.var="Z_Score_Aligned",fun.aggregate=function(x)x[1]); w[,Date:=sd];w}
cr_all <- rbindlist(lapply(sds,load_cr),fill=TRUE)
present <- intersect(TOP3,names(cr_all))
dt <- merge(panel,cr_all,by=c("Date","Ticker"),all.x=TRUE)
dt[, comp := rowMeans(.SD,na.rm=TRUE),.SDcols=present]
dt[, comp := {m<-mean(comp,na.rm=TRUE);s<-sd(comp,na.rm=TRUE);if(is.na(s)||s<1e-9)comp-m else (comp-m)/s},by=Date]
md <- dt[!is.na(comp)&!is.na(Ret_1m)]
# IC
ics <- md[,.(ic=if(.N>=20)cor(frank(comp),frank(Ret_1m))else NA),by=Date][!is.na(ic)]
cat(sprintf("TOP3 composite: rank_IC=%.4f ICIR=%.3f IC_t=%.2f n=%d\n", mean(ics$ic), mean(ics$ic)/sd(ics$ic), mean(ics$ic)/(sd(ics$ic)/sqrt(nrow(ics))), nrow(ics)))
md[, dec := cut(frank(comp)/.N,breaks=seq(0,1,.1),labels=FALSE,include.lowest=TRUE),by=Date]
dr <- md[,.(mr=mean(Ret_1m)),by=dec][order(dec)]
cat("mono=",round(cor(dr$dec,dr$mr,method="spearman"),3),"\n")
print(dr)
# top20 portfolio active net
md[, sc:=comp]; setorder(md,Date,-sc); sel <- md[,head(.SD,20),by=Date]
mr <- sel[,.(gross=mean(Ret_1m)),by=Date]
bench <- dt[!is.na(Ret_1m),.(bm=mean(Ret_1m)),by=Date]
mr <- merge(mr,bench,by="Date"); mr[,active:=gross-bm]
cat(sprintf("TOP3 top20 active mean=%.4f t=%.2f cor_1715(rank)=%.3f\n", mean(mr$active), mean(mr$active)/(sd(mr$active)/sqrt(nrow(mr))),
  {d2<-dt[!is.na(comp)&!is.na(score_1715)];mean(d2[,.(c=if(.N>=20)cor(frank(comp),frank(score_1715))else NA),by=Date][!is.na(c),c])}))
