suppressPackageStartupMessages({library(data.table);library(arrow)})
parts<-list.files("text_cache",pattern="parquet$",full.names=TRUE)
M<-unique(rbindlist(lapply(parts,function(p)as.data.table(read_parquet(p))),fill=TRUE),by="rcept_no")
cat("total docs:",nrow(M)," status:",paste(names(table(M$status)),table(M$status),collapse=" "),"\n")
ok<-M[status=="ok"]
cat("ok:",nrow(ok)," tickers:",uniqueN(ok$Ticker)," fy:",min(ok$fy),"-",max(ok$fy),"\n")
pool<-as.data.table(read_parquet("candidate_pool_full.parquet"))
cat("pool (ticker,fy):",nrow(pool)," matched ok:",nrow(ok)," coverage:",round(100*nrow(ok)/nrow(pool),1),"%\n")
print(ok[,.N,by=fy][order(fy)])
