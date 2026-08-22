suppressPackageStartupMessages({library(data.table);library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
cat("dim:",dim(R),"\n"); cat("cols:",paste(names(R),collapse=" | "),"\n")
R[,Date:=as.Date(Date)]; setorder(R,Date)
cat("date range:",as.character(min(R$Date)),"~",as.character(max(R$Date)),"\n")
cat("as_of:",as.character(unique(R$as_of_date)),"  src:",unique(R$source_version),"\n")
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
cat("n factors:",length(fac),"\n")
R[,yr:=format(Date,"%Y")]
# annualized vol by year, Market
v<-R[,.(nd=.N, mkt_vol=sd(Market,na.rm=TRUE)*sqrt(252), mkt_ann=prod(1+ifelse(is.finite(Market),Market,0))^(252/.N)-1,
        mkt_min=min(Market,na.rm=TRUE), mkt_max=max(Market,na.rm=TRUE)),by=yr]
print(v)
cat("\n-- monthly trading-day counts, last 18 months --\n")
R[,ym2:=format(Date,"%Y-%m")]
print(tail(R[,.(nd=.N, mkt=prod(1+ifelse(is.finite(Market),Market,0))-1),by=ym2],18))
cat("\n-- top 12 |Market| daily moves --\n")
print(head(R[order(-abs(Market)),.(Date,Market)],12))
cat("\n-- NA rate per column --\n")
print(R[,lapply(.SD,function(x)round(mean(!is.finite(x)),4)),.SDcols=c("Market",fac)])
