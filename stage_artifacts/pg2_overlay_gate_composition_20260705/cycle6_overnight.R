## ============================================================================
## 자가발전 사이클 6 — overnight/intraday 분해 (Tug of War, Lou-Polk-Skouras 2019)
## 미탐색 microstructure 원천(earnings/quality/momentum과 직교). RAWDATA Open/Close.
## overnight_d = Open_t/Close_{t-1}-1 (기관/정보), intraday_d = Close_t/Open_t-1 (유동성/리테일)
## 신호: on_mom(12M overnight누적)·id_mom·tug(on-id)·on_rev(1M overnight reversal)
## 측정: canonical_screen_bt PORT_t + cycle5 렌즈(cap-w AND EW 벤치) + oos + post2017.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]; uni_tk <- unique(sp$Ticker); dts <- sort(unique(sp$Date))

## ---- overnight/intraday panel from RAWDATA ----
ovf <- file.path(WD,"panel_overnight.parquet")
if(!file.exists(ovf)){
  d <- as.data.table(read_parquet("C:/qm_cache/RAWDATA.parquet", col_select=c("Date","Ticker","Open","Close")))
  d <- d[Ticker %in% uni_tk]; d[, Date := as.Date(Date)]; setkey(d, Ticker, Date)
  d <- d[is.finite(Open) & is.finite(Close) & Open>0 & Close>0]
  d[, pclose := shift(Close,1), by=Ticker]
  d[, `:=`(on = Open/pclose - 1, id = Close/Open - 1)]
  d <- d[is.finite(on) & is.finite(id) & abs(on)<0.4 & abs(id)<0.4]   ## clip data errors
  PG("[PG] RAWDATA on/id daily rows=%d", nrow(d))
  outl <- vector("list", length(dts))
  for(k in seq_along(dts)){ D<-dts[k]; win <- d[Date < D & Date > (D-400L)]
    if(nrow(win)<50) next
    info <- win[order(Date), {
      n<-.N; lo <- Date < (D-21L)   ## 12-1 (skip last month)
      .(on12 = if(sum(lo)>=100) sum(on[lo]) else NA_real_,
        id12 = if(sum(lo)>=100) sum(id[lo]) else NA_real_,
        on1  = if(n>=15) sum(on[Date>=(D-21L)]) else NA_real_,
        nobs = n) }, by=Ticker]
    info <- info[is.finite(on12)|is.finite(on1)]; if(nrow(info)){ info[,Date:=D]; outl[[k]]<-info[,.(Date,Ticker,on12,id12,on1,nobs)] }
    if(k %% 60 == 0) PG("[PG] %d/%d D=%s n=%d", k, length(dts), as.character(D), nrow(info)) }
  po <- rbindlist(outl); write_parquet(po, ovf)
  PG("[PG] overnight panel rows=%d saved", nrow(po))
} else { po <- as.data.table(read_parquet(ovf)); po[,Date:=as.Date(Date)]; PG("[PG] overnight panel cached rows=%d", nrow(po)) }

sp <- merge(sp, po, by=c("Date","Ticker"), all.x=TRUE)
zc <- function(x){ mu<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); z<-(x-mu)/ifelse(is.finite(s)&s>0,s,1); z[!is.finite(z)]<-NA; z }
sp[, `:=`(z_on12=zc(on12), z_id12=zc(id12), z_on1=zc(on1)), by=Date]
returns_dt <- sp[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

## benchmarks: cap-w aligned + EW-universe
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]
bm<-bm[is.finite(BM_Ret)];bm[,ym:=format(Date,"%Y-%m")];bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
ew<-sp[is.finite(Ret_1m),.(ew=mean(Ret_1m)),by=Date];ew[,ym:=format(Date,"%Y-%m")]
bo<-0;bc0<--2;for(off in -1:3){e2<-copy(ew);e2[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key");if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret);if(cc>bc0){bc0<-cc;bo<-off}}}
ew[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]
bench_capw<-merge(ew[,.(Date,key)],bmm[,.(key=ym,BM_Ret=bm_ret)],by="key")[,.(Date,BM_Ret)]
bench_ew<-ew[,.(Date,BM_Ret=ew)]

oos<-function(pr){pr<-pr[order(date)];n<-nrow(pr);a<-pr$ret_net-pr$benchmark_ret
  median(sapply(c(0.55,0.65,0.75),function(q){c<-floor(n*q);(mean(a[(c+1):n])/sd(a[(c+1):n]))/(mean(a[1:c])/sd(a[1:c]))}),na.rm=TRUE)}
p17<-function(pr){p<-pr[date>=as.Date("2017-01-01")];a<-p$ret_net-p$benchmark_ret;mu<-mean(a);dm<-a-mu;n<-length(a)
  g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n};mu/sqrt((g0+gs)/n)}
mk<-function(expr) sp[,.(Date,Ticker,score=eval(expr))][is.finite(score)]
vars<-list(on_mom=mk(quote(z_on12)), id_mom=mk(quote(z_id12)), tug_on_minus_id=mk(quote(z_on12-z_id12)),
           on_reversal=mk(quote(-z_on1)), tug_plus_alpha=mk(quote(zc(score_eff)+0.5*(z_on12-z_id12))))
rows<-list()
for(nm in names(vars)){ for(bnm in c("capw","ew")){ bench<-if(bnm=="capw")bench_capw else bench_ew
  r<-canonical_screen_bt(vars[[nm]], returns_dt, bench, top_n=20L); pr<-r$period_returns
  rows[[paste0(nm,"_",bnm)]]<-data.table(sig=nm,bench=bnm,PORT_t=r$portfolio_alpha_t_nw_lag3,net_sr=r$net_sr,oos=oos(pr),post2017_t=p17(pr))
  PG("[PG] %-16s vs %-4s: PORT_t=%.3f net_sr=%.3f oos=%.3f post2017_t=%.3f",nm,bnm,r$portfolio_alpha_t_nw_lag3,r$net_sr,oos(pr),p17(pr)) }}
res<-rbindlist(rows); res[,DISCOVERY:=bench=="capw"&is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos)&oos>=0.7]
print(res[,.(sig,bench,PORT_t=round(PORT_t,3),net_sr=round(net_sr,3),oos=round(oos,3),post2017_t=round(post2017_t,3),DISCOVERY)])
fwrite(res, file.path(WD,"cycle6_overnight_results.csv"))
PG("[PG] DONE cycle6. capw-discoveries=%d", sum(res$DISCOVERY,na.rm=TRUE))
