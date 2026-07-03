suppressMessages({library(arrow); library(data.table); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(2L)
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
mes <- sort(sig_grid); cut_is <- mes[floor(length(mes)*0.60)]   # IS-only per chain protocol
# faster scores: skip per-ticker quantile winsor (use global clip on log scale instead — robustness variant noted)
cs <- function(W, denom="DolVol"){
  out <- vector("list", length(sig_grid))
  for(k in seq_along(sig_grid)){
    sd <- sig_grid[k]
    univ <- raw[Date==sd & (K200==1|KQ150==1) & (AdminStock==0|is.na(AdminStock)) & (TradingHalt==0|is.na(TradingHalt)), unique(Ticker)]
    if(!length(univ)) next
    wd <- tail(all_dts[all_dts<=sd], W); win <- raw[Date %in% wd & Ticker %in% univ]
    if(denom=="rawVol") win[, IL := fifelse(!is.na(Ret)&Vol>0,abs(Ret)/Vol,NA_real_)] else win[, IL := ILLIQ]
    win <- win[!is.na(IL)]; if(!nrow(win)) next
    # winsor per ticker via clamp to 1/99 quantile (vectorized with data.table)
    win[, `:=`(lo=quantile(IL,.01,type=7), hi=quantile(IL,.99,type=7)), by=Ticker]
    win[, Y := log(pmin(pmax(IL,lo),hi)+1e-12)]; setorder(win,Ticker,Date); win[, dr:=seq_len(.N), by=Ticker]
    last20 <- tail(wd,20); rec <- win[Date %in% last20, .(rn=.N), by=Ticker]
    agg <- merge(win[,.(no=.N),by=Ticker], rec, by="Ticker", all.x=T); agg[is.na(rn),rn:=0L]
    keep <- agg[no>=0.60*W & rn>=10, Ticker]; win <- win[Ticker %in% keep]; if(!nrow(win)) next
    win[, tau := {m<-mean(dr);s<-sd(dr); if(is.na(s)||s==0) rep(0,.N) else (dr-m)/s}, by=Ticker]
    sl <- win[, .(sl={vt<-sum((tau-mean(tau))^2); if(vt<=0)NA_real_ else sum((tau-mean(tau))*(Y-mean(Y)))/vt}), by=Ticker]
    sl <- sl[!is.na(sl)]; if(!nrow(sl)) next; sl[, S:=-sl]; mu<-mean(sl$S);sg<-sd(sl$S); if(is.na(sg)||sg==0) next
    sl[, score:=pmin(pmax((S-mu)/sg,-3),3)]; sl[, Date:=sd]; out[[k]] <- sl[,.(Date,Ticker,score)]
  }
  rbindlist(out)
}
isic <- function(s){ m<-merge(s[Date<=cut_is],returns_dt,by=c("Date","Ticker")); ic<-m[,.(ic=if(.N>=10)cor(score,Ret_1m,method="spearman") else NA_real_),by=Date][!is.na(ic)]; c(mean(ic$ic),mean(ic$ic)/sd(ic$ic)) }
res <- list()
for(W in c(63L,126L,252L)){ ic<-isic(cs(W)); cat(sprintf("GRID W=%d OLS DolVol IS ic=%.4f icir=%.3f\n",W,ic[1],ic[2])); flush.console(); res[[length(res)+1]]<-data.table(W=W,est="OLS",denom="DolVol",is_ic=ic[1],is_icir=ic[2]) }
icr <- isic(cs(126L,"rawVol")); cat(sprintf("GRID W=126 OLS rawVol IS ic=%.4f icir=%.3f\n",icr[1],icr[2])); flush.console()
res[[length(res)+1]] <- data.table(W=126L,est="OLS",denom="rawVol",is_ic=icr[1],is_icir=icr[2])
gres<-rbindlist(res); fwrite(gres,file.path(OUT,"grid_is_ic.csv")); print(gres); cat("GRID_DONE\n")
