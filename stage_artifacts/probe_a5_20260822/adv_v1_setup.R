suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
cat("dim:",dim(R),"\n"); cat("cols:",paste(names(R),collapse=", "),"\n")
R[,Date:=as.Date(Date)]; setorder(R,Date)
cat("date range:",format(min(R$Date)),"~",format(max(R$Date)),"\n")
cat("n rows with finite Market:",sum(is.finite(R$Market)),"\n")
if("as_of_date" %in% names(R)) cat("as_of_date uniq:",paste(unique(as.character(R$as_of_date))[1:3],collapse=","),"\n")
if("source_version" %in% names(R)) cat("source_version uniq:",paste(unique(as.character(R$source_version))[1:3],collapse=","),"\n")
R2<-R[is.finite(Market)]
R2[,ym:=format(Date,"%Y-%m")]
cnt<-R2[,.(nd=.N,first=min(Date),last=max(Date)),by=ym]
cat("n months:",nrow(cnt),"\n")
print(head(cnt,4)); print(tail(cnt,4))
## NA structure per factor
fac<-setdiff(names(R2),c("Date","ym","as_of_date","source_version","Market"))
cat("n factors:",length(fac),"\n")
naf<-sapply(fac,function(f) sum(!is.finite(R2[[f]])))
print(naf)
