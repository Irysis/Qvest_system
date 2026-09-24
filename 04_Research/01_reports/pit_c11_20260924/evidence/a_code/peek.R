suppressMessages({library(arrow);library(data.table)})
f <- function(p){ if(!file.exists(p)) {cat("MISSING",p,"\n");return(invisible())}; d<-as.data.table(read_parquet(p, mmap=FALSE)); cat("==",p,nrow(d),"rows\n"); print(names(d)); print(head(d,3)); print(tail(d,3)); d}
m <- f(".cache/macro_fred.parquet")
if(!is.null(m)){ sc <- intersect(c("Series","Series_ID"),names(m)); for(s in sc) print(m[, .(n=.N, min=min(Date), max=max(Date)), by=s])}
w <- f(".cache/fred_macro_wide.parquet")
l <- f(".cache/fred_macro.parquet")
if(!is.null(l)){ sc <- intersect(c("Series","Series_ID"),names(l)); for(s in sc) print(l[, .(n=.N, min=min(Date), max=max(Date)), by=s])}
r <- f(".cache/macro_regime.parquet")
