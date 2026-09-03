setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table)})
S <- readRDS("stage_artifacts/WT_R20260829_005/opt_r5.rds")
RET <- S$RET; PRD <- S$PRD; ew <- S$ew
W2 <- merge(ew, RET, by=c("Date","Ticker"), all.x=TRUE); W2[is.na(Ret_1m), Ret_1m := 0]
ds <- sort(unique(W2$Date))

run <- function(drift) {
  prev <- data.table(Ticker=character(), wd=numeric()); out <- vector("list", length(ds))
  for (i in seq_along(ds)) {
    d <- ds[i]; cur <- W2[Date==d, .(Ticker,w,Ret_1m)]
    m <- merge(cur[,.(Ticker,w)], prev, by="Ticker", all=TRUE); m[is.na(w),w:=0]; m[is.na(wd),wd:=0]
    to <- sum(abs(m$w-m$wd)); g <- sum(cur$w*cur$Ret_1m)
    out[[i]] <- data.table(Date=d, to=to, net=g-0.0015*to)
    prev <- if (drift) cur[, .(Ticker, wd=w*(1+Ret_1m)/sum(w*(1+Ret_1m)))] else cur[, .(Ticker, wd=w)]
  }
  rbindlist(out)
}
for (dr in c(TRUE, FALSE)) {
  r <- run(dr); cmp <- merge(r, PRD[, .(Date=signal_date, ret_net)], by="Date")
  cat(sprintf("drift=%-5s  maxdiff=%.3e  meandiff=%.3e  TO_ann=%.4f\n", dr,
      max(abs(cmp$net-cmp$ret_net)), mean(abs(cmp$net-cmp$ret_net)), mean(r$to)*12))
}
## also: first period treated as full buy-in?  and cost on gross-vs-net timing
r <- run(FALSE); cmp <- merge(r, PRD[,.(Date=signal_date, ret_net)], by="Date"); cmp[, d:=net-ret_net]
print(head(cmp[order(-abs(d))],5))
