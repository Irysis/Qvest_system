suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
pn <- readRDS(file.path(OUT,"panel.rds")); LQ <- as.data.table(pn$fwd$liq_dt); RT <- as.data.table(pn$fwd$returns_dt)
A <- merge(A, LQ, by=c("Date","Ticker"), all.x=TRUE)
A <- merge(A, RT, by=c("Date","Ticker"), all.x=TRUE)
dts <- sort(unique(A[Date<as.Date("2026-08-01")]$Date))
res <- rbindlist(lapply(dts, function(dd){
  x <- A[Date==dd]
  sel <- x[in_top25==TRUE]$Ticker
  # H1: top25 by raw fh among all rows in alpha_scores
  c1 <- x[order(-fh_lag1d)]$Ticker[1:25]
  # H2: top25 by raw fh among adv>=2e8
  c2 <- x[is.finite(adv)&adv>=2e8][order(-fh_lag1d)]$Ticker[1:25]
  # H3: top25 by raw fh among adv>=2e8 & finite ret
  c3 <- x[is.finite(adv)&adv>=2e8&is.finite(Ret_1m)][order(-fh_lag1d)]$Ticker[1:25]
  data.table(Date=dd, n=nrow(x), h1=length(intersect(sel,c1)), h2=length(intersect(sel,c2)), h3=length(intersect(sel,c3)),
             minadv=min(x[in_top25==TRUE]$adv, na.rm=TRUE))
}))
cat("H1 exact:", sum(res$h1==25), "/", nrow(res), "  H2 exact:", sum(res$h2==25), "  H3 exact:", sum(res$h3==25), "\n")
cat("mean overlaps h1/h2/h3:", round(mean(res$h1),2), round(mean(res$h2),2), round(mean(res$h3),2), "\n")
cat("min adv over all top25 selections:", min(res$minadv,na.rm=TRUE)/1e8, "e8\n")
print(res[h3<25][1:10])
