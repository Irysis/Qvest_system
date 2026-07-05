## 자가발전 사이클 2 — 진단: post-2017 "감쇠"는 알파소멸인가 cap-weighted 벤치 아티팩트인가?
## 동일 알파를 (A) cap-weighted KOSPI200 vs (B) EW-유니버스 벤치 대비 oos_retention 비교.
## EW 대비 oos 통과 & cap-w 대비 실패 → 벽은 알파 아닌 벤치(mega-cap gap) → 리프레임.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
zc <- function(x){ mu<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); z<-(x-mu)/ifelse(is.finite(s)&s>0,s,1); z[!is.finite(z)]<-NA; z }
sp[, `:=`(z_size=zc(log(pmax(size,1))), z_mom=zc(mom), z_qual=zc(score_core_z)), by=Date]
returns_dt <- sp[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

## cap-weighted benchmark (aligned) + EW-universe benchmark
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench_capw <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]
bench_ew   <- ew[, .(Date, BM_Ret=ew)]   ## EW-universe as benchmark
PG("[PG] bench align offset=%+d cor=%.3f", best_off, best_cor)

oos_ret <- function(pr){ pr<-pr[order(date)]; n<-nrow(pr); act<-pr$ret_net-pr$benchmark_ret
  median(sapply(c(0.55,0.65,0.75), function(q){cut<-floor(n*q); (mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE) }
p17t <- function(pr){ p2<-pr[date>=as.Date("2017-01-01")]; a<-p2$ret_net-p2$benchmark_ret; mu<-mean(a); dm<-a-mu; n<-length(a)
  g0<-sum(dm^2)/n; gs<-0; for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }
mk <- function(expr) sp[, .(Date, Ticker, score=eval(expr))][is.finite(score)]
vars <- list(V0_earnings=mk(quote(score_eff)), V2_mom=mk(quote(z_mom)), V4_lead=mk(quote(z_size+z_mom+z_qual)))

rows <- list()
for(nm in names(vars)){ for(bnm in c("capw","ew")){ bench <- if(bnm=="capw") bench_capw else bench_ew
  r <- canonical_screen_bt(vars[[nm]], returns_dt, bench, top_n=20L); pr<-r$period_returns
  rows[[paste0(nm,"_",bnm)]] <- data.table(variant=nm, bench=bnm, PORT_t=r$portfolio_alpha_t_nw_lag3,
    net_sr=r$net_sr, oos_ret=oos_ret(pr), post2017_t=p17t(pr))
  PG("[PG] %s vs %s: PORT_t=%.3f net_sr=%.3f oos_ret=%.3f post2017_t=%.3f", nm, bnm, r$portfolio_alpha_t_nw_lag3, r$net_sr, oos_ret(pr), p17t(pr)) } }
res <- rbindlist(rows)
print(res[, .(variant, bench, PORT_t=round(PORT_t,3), net_sr=round(net_sr,3), oos_ret=round(oos_ret,3), post2017_t=round(post2017_t,3))])
fwrite(res, file.path(WD,"cycle2_benchdiag_results.csv"))
PG("[PG] DONE cycle2 benchmark-diagnostic")
