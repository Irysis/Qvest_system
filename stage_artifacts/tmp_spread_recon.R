suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1L); 
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
t0 <- Sys.time()
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","Close","Vol")))
raw[, Date := as.IDate(as.character(Date))]
raw <- raw[Date >= as.IDate("2004-06-01")]
raw[, ym := as.integer(format(Date,"%Y%m"))]
raw[, tval := as.numeric(Close)*as.numeric(Vol)]
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(tval, 20L), by=Ticker]
me <- raw[, .SD[.N], by=.(Ticker, ym)]
me <- me[((K200==1)|(KQ150==1)) & is.finite(adv20) & adv20>=2e8, .(ym, Ticker, adv20)]
cat("[univ] rows", nrow(me), "months", uniqueN(me$ym), "elapsed", round(difftime(Sys.time(),t0,units="secs"),1),"s\n"); flush.console()
saveRDS(me, file.path(ROOT,"stage_artifacts/tmp_universe_monthly.rds"))

yms <- sort(unique(me$ym)); yms <- yms[yms>=200412L]
spr <- rbindlist(lapply(seq_along(yms), function(k){
  y <- yms[k]
  f <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%d.parquet", y))
  if(!file.exists(f)) return(NULL)
  d <- as.data.table(open_dataset(f) %>% select(Ticker,Factor_Name,Raw_Value) %>%
        filter(Factor_Name=="V02_EP") %>% collect())
  d <- d[is.finite(Raw_Value)]
  u <- me[ym==y]
  d <- merge(d, u[,.(Ticker)], by="Ticker")
  if(nrow(d)<30) return(NULL)
  q <- quantile(d$Raw_Value, c(.20,.50,.80), na.rm=TRUE)
  if(k %% 40 == 0) { cat("  ", y, "done, elapsed", round(difftime(Sys.time(),t0,units="secs"),1),"s\n"); flush.console() }
  data.table(ym=y, n=nrow(d), ep_p20=q[[1]], ep_med=q[[2]], ep_p80=q[[3]], spread=q[[3]]-q[[1]])
}), fill=TRUE)
setorder(spr, ym)
spr[, exp_pctile := sapply(seq_len(.N), function(i) mean(spread[1:i] <= spread[i]))]
saveRDS(spr, file.path(ROOT,"stage_artifacts/tmp_spread_recon.rds"))
cat("\n[SPREAD SUMMARY]\n")
print(spr[ym %in% c(200512L,200812L,202012L,202312L,202412L,202512L,max(spr$ym))])
n<-nrow(spr)
cat(sprintf("LATEST ym=%d spread=%.5f exp_pctile=%.3f\n", spr$ym[n], spr$spread[n], spr$exp_pctile[n]))
cat(sprintf("ALLTIME max=%.5f at ym=%d ; mean=%.5f ; cur/mean=%.2f\n",
    max(spr$spread), spr$ym[which.max(spr$spread)], mean(spr$spread), spr$spread[n]/mean(spr$spread)))
cat("[TOTAL elapsed]", round(difftime(Sys.time(),t0,units="secs"),1),"s\n")
