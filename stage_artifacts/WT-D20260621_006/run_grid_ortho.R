# WT-D20260621_006 — pre-registered grid (chain, IS-only) + orthogonality
suppressMessages({library(arrow); library(data.table); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(1L); options(warn=1)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

returns_dt <- readRDS(file.path(OUT,"returns_dt.rds"))
bench_dt   <- readRDS(file.path(OUT,"bench_dt.rds"))
liq_dt     <- readRDS(file.path(OUT,"liq_dt.rds"))

# ---- rebuild compute_scores (variant grid) ----
ds <- open_dataset(".cache/rawdata.parquet")
raw <- ds %>% filter(Date >= as.Date("2003-06-01")) %>%
  select(Date,Ticker,Close,Vol,Ret,K200,KQ150,AdminStock,TradingHalt) %>%
  collect() %>% as.data.table()
raw[, Date := as.Date(Date)]; setorder(raw, Ticker, Date)
raw[, DolVol := Close*Vol]
raw[, ILLIQ := fifelse(!is.na(Ret) & DolVol>0, abs(Ret)/DolVol, NA_real_)]
all_dts <- sort(unique(raw$Date))
dt_dt <- data.table(Date=all_dts, ym=format(all_dts,"%Y-%m"))
month_end <- dt_dt[, .(Date=max(Date)), by=ym]
sig_grid <- month_end[Date>=as.Date("2005-01-01"), Date]

compute_scores <- function(W=126L, recency_min=10L, frac_min=0.60, estimator="OLS", denom="DolVol") {
  out <- vector("list", length(sig_grid))
  for (k in seq_along(sig_grid)) {
    sd <- sig_grid[k]
    univ <- raw[Date==sd & (K200==1|KQ150==1) & (AdminStock==0|is.na(AdminStock)) & (TradingHalt==0|is.na(TradingHalt)), unique(Ticker)]
    if(!length(univ)) next
    wdates <- tail(all_dts[all_dts<=sd], W)
    win <- raw[Date %in% wdates & Ticker %in% univ]
    if(denom=="rawVol") win[, ILLIQv := fifelse(!is.na(Ret)&Vol>0, abs(Ret)/Vol, NA_real_)] else win[, ILLIQv := ILLIQ]
    win <- win[!is.na(ILLIQv), .(Date,Ticker,ILLIQ=ILLIQv)]
    if(!nrow(win)) next
    win[, `:=`(lo=quantile(ILLIQ,.01,na.rm=T,type=7), hi=quantile(ILLIQ,.99,na.rm=T,type=7)), by=Ticker]
    win[, LOGILLIQ := log(pmin(pmax(ILLIQ,lo),hi)+1e-12)]
    setorder(win,Ticker,Date); win[, drank := seq_len(.N), by=Ticker]
    last20 <- tail(wdates,20)
    rec <- win[Date %in% last20, .(rec_n=.N), by=Ticker]
    agg <- merge(win[,.(nobs=.N),by=Ticker], rec, by="Ticker", all.x=TRUE); agg[is.na(rec_n),rec_n:=0L]
    keep <- agg[nobs>=frac_min*W & rec_n>=recency_min, Ticker]
    win <- win[Ticker %in% keep]; if(!nrow(win)) next
    win[, tau := { m<-mean(drank); s<-sd(drank); if(is.na(s)||s==0) rep(0,.N) else (drank-m)/s }, by=Ticker]
    if(estimator=="OLS"){
      sl <- win[, .(slope={vt<-sum((tau-mean(tau))^2); if(vt<=0) NA_real_ else sum((tau-mean(tau))*(LOGILLIQ-mean(LOGILLIQ)))/vt}), by=Ticker]
    } else if(estimator=="decay"){
      hl<-42; sl <- win[, {wts<-exp(-(max(drank)-drank)/hl); wmt<-sum(wts*tau)/sum(wts); wmy<-sum(wts*LOGILLIQ)/sum(wts); vt<-sum(wts*(tau-wmt)^2); .(slope=if(vt<=0)NA_real_ else sum(wts*(tau-wmt)*(LOGILLIQ-wmy))/vt)}, by=Ticker]
    } else if(estimator=="TheilSen"){
      sl <- win[, {idx<-seq(1,.N,by=3); n2<-length(idx); if(n2<3){.(slope=NA_real_)} else {x<-tau[idx];y<-LOGILLIQ[idx];ii<-combn(n2,2);dx<-x[ii[2,]]-x[ii[1,]];dy<-y[ii[2,]]-y[ii[1,]];ok<-dx!=0;.(slope=if(sum(ok)==0)NA_real_ else median(dy[ok]/dx[ok]))}}, by=Ticker]
    }
    sl <- sl[!is.na(slope)]; if(!nrow(sl)) next
    sl[, SIGNAL_raw := -slope]
    mu<-mean(sl$SIGNAL_raw); sg<-sd(sl$SIGNAL_raw); if(is.na(sg)||sg==0) next
    sl[, score := pmin(pmax((SIGNAL_raw-mu)/sg,-3),3)]; sl[, Date:=sd]
    out[[k]] <- sl[,.(Date,Ticker,SIGNAL_raw,score)]
  }
  rbindlist(out)
}

# IS-only rank-IC (chain selection protocol): use first 60% of months as IS
mes <- sort(sig_grid); cut_is <- mes[floor(length(mes)*0.60)]
is_rank_ic <- function(scores_dt){
  m <- merge(scores_dt[Date<=cut_is,.(Date,Ticker,score)], returns_dt, by=c("Date","Ticker"))
  ics <- m[, .(ic=if(.N>=10) cor(score,Ret_1m,method="spearman") else NA_real_), by=Date][!is.na(ic)]
  c(ic_mean=mean(ics$ic), icir=mean(ics$ic)/sd(ics$ic))
}

grid <- list(
  c(W=63, est="OLS"), c(W=126, est="OLS"), c(W=252, est="OLS"),
  c(W=126, est="decay"), c(W=126, est="TheilSen")
)
gres <- rbindlist(lapply(grid, function(g){
  W<-as.integer(g["W"]); est<-g["est"]
  sc <- compute_scores(W=W, estimator=est)
  ic <- is_rank_ic(sc)
  cat(sprintf("GRID W=%d est=%s : IS ic_mean=%.4f icir=%.3f\n", W, est, ic["ic_mean"], ic["icir"]))
  data.table(W=W, est=est, is_ic_mean=ic["ic_mean"], is_icir=ic["icir"])
}))
# denom comparability check (rawVol vs DolVol, primary W/est)
sc_raw <- compute_scores(W=126, estimator="OLS", denom="rawVol")
ic_raw <- is_rank_ic(sc_raw)
cat(sprintf("GRID W=126 OLS denom=rawVol : IS ic_mean=%.4f icir=%.3f\n", ic_raw["ic_mean"], ic_raw["icir"]))
fwrite(gres, file.path(OUT,"grid_is_ic.csv"))
print(gres)

# ---- ORTHOGONALITY vs L01/L09/L10/L29/M01/M08/L03/L28 ----
scores_primary <- readRDS(file.path(OUT,"scores_primary.rds"))
source("02_Infrastructure/factor_db/factor_db_connector.R")
targets <- c("L01_Amihud","L09_Amihud_20d","L10_Amihud_Ratio","L29_Illiq_Change",
             "M01_Mom_12_1","M08_Residual_Mom","L03_Volume_Mom","L28_Volume_Mom_3m")
# sample ~ every 6th month to bound cost
omonths <- sort(unique(scores_primary$Date)); omonths <- omonths[seq(1,length(omonths),by=6)]
cor_acc <- vector("list", length(omonths))
for(i in seq_along(omonths)){
  sd <- omonths[i]
  fdb <- tryCatch(load_month_factors(sd, factor_names=targets), error=function(e) NULL)
  if(is.null(fdb)||!nrow(fdb)) next
  wide <- dcast(fdb, Ticker~Factor_Name, value.var="Z_Score_Aligned")
  sc <- scores_primary[Date==sd, .(Ticker, score)]
  mg <- merge(sc, wide, by="Ticker")
  if(nrow(mg)<20) next
  fac_cols <- intersect(names(wide), targets)
  cc <- sapply(fac_cols, function(fc){
    v <- mg[[fc]]; if(sum(!is.na(v))<20) NA_real_ else cor(mg$score, v, method="spearman", use="complete.obs")
  })
  cor_acc[[i]] <- as.data.table(as.list(cc))
}
cor_dt <- rbindlist(cor_acc, fill=TRUE)
ortho <- data.table(factor=names(cor_dt), mean_abs_corr=sapply(cor_dt, function(x) mean(abs(x),na.rm=TRUE)),
                    mean_corr=sapply(cor_dt, function(x) mean(x,na.rm=TRUE)))
cat("\n=== ORTHOGONALITY (gross, Spearman, pooled-by-date mean) ===\n")
print(ortho)
fwrite(ortho, file.path(OUT,"orthogonality.csv"))
cat("\n=== run_grid_ortho.R DONE ===\n")
