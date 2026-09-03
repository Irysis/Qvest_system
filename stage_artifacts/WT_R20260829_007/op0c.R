suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
pn <- readRDS(file.path(OUT,"panel.rds")); LQ <- as.data.table(pn$fwd$liq_dt); RT <- as.data.table(pn$fwd$returns_dt)
d <- A[Date==as.Date("2026-07-31")]
d <- merge(d, LQ[Date==as.Date("2026-07-31")], by=c("Date","Ticker"), all.x=TRUE)
d <- merge(d, RT[Date==as.Date("2026-07-31")], by=c("Date","Ticker"), all.x=TRUE)
setorder(d, -alpha_hat)
print(d[1:30, .(Ticker, mkt, fh=round(fh_lag1d,4), z=round(z_fh,3), adv=round(adv/1e8,1), hasret=is.finite(Ret_1m), top=in_top25)])
cat("\nby mkt in_top25 counts:\n"); print(d[, .(n=.N, ntop=sum(in_top25)), by=mkt])
cat("\nmin adv among top25:", min(d[in_top25==TRUE]$adv,na.rm=TRUE)/1e8, "\n")
# test hypothesis: top25 = top25 by alpha_hat within adv>=2e8 & finite ret
cand <- d[is.finite(adv) & adv>=2e8]
setorder(cand,-alpha_hat)
cat("match test:", identical(sort(cand$Ticker[1:25]), sort(d[in_top25==TRUE]$Ticker)), "\n")
cat("\nrank-check across 5 random dates:\n")
set.seed(1); dts <- sample(unique(A$Date[A$Date<as.Date("2026-08-01")]), 5)
for(dd in dts){ dd<-as.Date(dd)
  x <- merge(A[Date==dd], LQ[Date==dd], by=c("Date","Ticker"), all.x=TRUE)
  x <- merge(x, RT[Date==dd], by=c("Date","Ticker"), all.x=TRUE)
  cc <- x[is.finite(adv) & adv>=2e8]; setorder(cc,-alpha_hat)
  cat(as.character(dd), " nsel:", sum(x$in_top25), " match:", identical(sort(cc$Ticker[1:25]), sort(x[in_top25==TRUE]$Ticker)),
      " overlap:", length(intersect(cc$Ticker[1:25], x[in_top25==TRUE]$Ticker)), "\n")
}
