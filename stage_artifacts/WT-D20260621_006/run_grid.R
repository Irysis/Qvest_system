suppressMessages({library(arrow); library(data.table); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
returns_dt <- readRDS(file.path(OUT,"returns_dt.rds"))
ds <- open_dataset(".cache/rawdata.parquet")
raw <- ds %>% filter(Date >= as.Date("2003-06-01")) %>%
  select(Date,Ticker,Close,Vol,Ret,K200,KQ150,AdminStock,TradingHalt) %>% collect() %>% as.data.table()
raw[, Date := as.Date(Date)]; setorder(raw, Ticker, Date)
raw[, DolVol := Close*Vol]; raw[, ILLIQ := fifelse(!is.na(Ret)&DolVol>0, abs(Ret)/DolVol, NA_real_)]
all_dts <- sort(unique(raw$Date)); dt_dt <- data.table(Date=all_dts, ym=format(all_dts,"%Y-%m"))
month_end <- dt_dt[, .(Date=max(Date)), by=ym]; sig_grid <- month_end[Date>=as.Date("2005-01-01"), Date]
mes <- sort(sig_grid); cut_is <- mes[floor(length(mes)*0.60)]
flush.console()
compute_scores <- function(W=126L, estimator="OLS", denom="DolVol") {
  out <- vector("list", length(sig_grid))
  for (k in seq_along(sig_grid)) {
    sd <- sig_grid[k]
    univ <- raw[Date==sd & (K200==1|KQ150==1) & (AdminStock==0|is.na(AdminStock)) & (TradingHalt==0|is.na(TradingHalt)), unique(Ticker)]
    if(!length(univ)) next
    wdates <- tail(all_dts[all_dts<=sd], W); win <- raw[Date %in% wdates & Ticker %in% univ]
    if(denom=="rawVol") win[, IL := fifelse(!is.na(Ret)&Vol>0, abs(Ret)/Vol, NA_real_)] else win[, IL := ILLIQ]
    win <- win[!is.na(IL), .(Date,Ticker,IL)]; if(!nrow(win)) next
    win[, `:=`(lo=quantile(IL,.01,na.rm=T,type=7), hi=quantile(IL,.99,na.rm=T,type=7)), by=Ticker]
    win[, Y := log(pmin(pmax(IL,lo),hi)+1e-12)]; setorder(win,Ticker,Date); win[, dr:=seq_len(.N), by=Ticker]
    last20 <- tail(wdates,20); rec <- win[Date %in% last20, .(rn=.N), by=Ticker]
    agg <- merge(win[,.(no=.N),by=Ticker], rec, by="Ticker", all.x=T); agg[is.na(rn),rn:=0L]
    keep <- agg[no>=0.60*W & rn>=10, Ticker]; win <- win[Ticker %in% keep]; if(!nrow(win)) next
    win[, tau := { m<-mean(dr); s<-sd(dr); if(is.na(s)||s==0) rep(0,.N) else (dr-m)/s }, by=Ticker]
    if(estimator=="OLS") sl <- win[, .(sl={vt<-sum((tau-mean(tau))^2); if(vt<=0)NA_real_ else sum((tau-mean(tau))*(Y-mean(Y)))/vt}), by=Ticker]
    else { hl<-42; sl <- win[, {w<-exp(-(max(dr)-dr)/hl); wt<-sum(w*tau)/sum(w); wy<-sum(w*Y)/sum(w); vt<-sum(w*(tau-wt)^2); .(sl=if(vt<=0)NA_real_ else sum(w*(tau-wt)*(Y-wy))/vt)}, by=Ticker] }
    sl <- sl[!is.na(sl)]; if(!nrow(sl)) next; sl[, S := -sl]; mu<-mean(sl$S); sg<-sd(sl$S); if(is.na(sg)||sg==0) next
    sl[, score := pmin(pmax((S-mu)/sg,-3),3)]; sl[, Date:=sd]; out[[k]] <- sl[,.(Date,Ticker,score)]
  }
  rbindlist(out)
}
is_ic <- function(scores_dt){
  m <- merge(scores_dt[Date<=cut_is], returns_dt, by=c("Date","Ticker"))
  ics <- m[, .(ic=if(.N>=10) cor(score,Ret_1m,method="spearman") else NA_real_), by=Date][!is.na(ic)]
  c(ic_mean=mean(ics$ic), icir=mean(ics$ic)/sd(ics$ic))
}
res <- list()
for(g in list(c(63,"OLS"),c(126,"OLS"),c(252,"OLS"),c(126,"decay"))){
  W<-as.integer(g[1]); est<-g[2]; ic<-is_ic(compute_scores(W,est))
  cat(sprintf("GRID W=%d est=%s denom=DolVol : IS ic_mean=%.4f icir=%.3f\n",W,est,ic[1],ic[2])); flush.console()
  res[[length(res)+1]] <- data.table(W=W,est=est,denom="DolVol",is_ic_mean=ic[1],is_icir=ic[2])
}
ic_raw <- is_ic(compute_scores(126,"OLS","rawVol"))
cat(sprintf("GRID W=126 est=OLS denom=rawVol : IS ic_mean=%.4f icir=%.3f\n",ic_raw[1],ic_raw[2])); flush.console()
res[[length(res)+1]] <- data.table(W=126L,est="OLS",denom="rawVol",is_ic_mean=ic_raw[1],is_icir=ic_raw[2])
gres <- rbindlist(res); fwrite(gres, file.path(OUT,"grid_is_ic.csv")); print(gres); cat("GRID_DONE\n")
