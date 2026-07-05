## ============================================================================
## 자가발전 사이클 1 — 대형주 leadership 알파 (post-2017 mega-cap driver 정면)
## 가설: 지금까지 실패 알파는 全 size-neutral/소형틸트라 mega-cap 레짐에 역행.
##   post-2017 driver(대형 quality-momentum 리더십)을 정면으로 타면 oos_retention(킬러)
##   통과 가능 — 감쇠 신호가 아니라 레짐 driver 자체이므로.
## 측정: canonical_screen_bt(권위 PORT_t NW-lag3) + oos_retention + post-2017 subperiod.
## 발견 기준: PORT_t≥2.95 AND oos_retention≥0.7 (deployment envelope, K200∪KQ150 top-20).
## ============================================================================
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
PG("[PG] merged. size cov=%.3f mom cov=%.3f", mean(is.finite(sp$size)), mean(is.finite(sp$mom)))

## cross-sectional z per Date
zc <- function(x){ mu<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); z<-(x-mu)/ifelse(is.finite(s)&s>0,s,1); z[!is.finite(z)]<-NA; z }
sp[, `:=`(z_size=zc(log(pmax(size,1))), z_mom=zc(mom), z_qual=zc(score_core_z), z_def=zc(score_defense_z)), by=Date]

## ---- benchmark: align pinned KOSPI200 monthly to panel via EW-universe beta-scan ----
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]
bmm <- bm[, .(bm_ret = prod(1+BM_Ret)-1), by=ym]   ## calendar-month market return
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off <- 0; best_cor <- -2
for(off in -1:3){ e2 <- copy(ew); e2[, key := format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm <- merge(e2, bmm[,.(key=ym, bm_ret)], by="key"); if(nrow(mm)>50){ cc<-cor(mm$ew, mm$bm_ret); if(cc>best_cor){best_cor<-cc; best_off<-off} } }
PG("[PG] benchmark align offset=%+d cor=%.3f", best_off, best_cor)
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench_map <- merge(ew[,.(Date, key)], bmm[,.(key=ym, BM_Ret=bm_ret)], by="key")[, .(Date, BM_Ret)]

returns_dt <- sp[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

## ---- variants (score: higher=preferred long) ----
mk <- function(expr) sp[, .(Date, Ticker, score=eval(expr))][is.finite(score)]
variants <- list(
  V0_base_earnings = mk(quote(score_eff)),                          # control: current book alpha
  V1_size_only     = mk(quote(z_size)),
  V2_mom_only      = mk(quote(z_mom)),
  V3_size_mom      = mk(quote(z_size + z_mom)),
  V4_size_mom_qual = mk(quote(z_size + z_mom + z_qual)),
  V5_largecap_mom  = mk(quote(ifelse(z_size > 0, z_mom, -99)))      # mega-cap universe, momentum within
)

oos_ret <- function(pr){ ## anchored IS/OOS split on active net_sr
  pr <- pr[order(date)]; n<-nrow(pr); act<-pr$ret_net - pr$benchmark_ret
  splits <- c(0.55,0.65,0.75); rr <- sapply(splits, function(q){ cut<-floor(n*q)
    is_sr<-mean(act[1:cut])/sd(act[1:cut]); oos_sr<-mean(act[(cut+1):n])/sd(act[(cut+1):n]); oos_sr/is_sr })
  median(rr, na.rm=TRUE) }
post2017_t <- function(pr){ p2<-pr[date>=as.Date("2017-01-01")]; if(nrow(p2)<24) return(NA_real_)
  a<-p2$ret_net-p2$benchmark_ret; mu<-mean(a); dm<-a-mu; n<-length(a); g0<-sum(dm^2)/n; gs<-0
  for(L in 1:3){ w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n }; mu/sqrt((g0+gs)/n) }

rows <- list()
for(nm in names(variants)){
  r <- canonical_screen_bt(variants[[nm]], returns_dt, bench_map, top_n=20L)
  pr <- r$period_returns
  rows[[nm]] <- data.table(variant=nm, n=r$n_months, PORT_t=r$portfolio_alpha_t_nw_lag3,
    IR=r$information_ratio, net_sr=r$net_sr, alpha_ann=r$alpha_annualized,
    TO=r$turnover_annual, oos_ret=oos_ret(pr), post2017_t=post2017_t(pr))
  PG("[PG] %s: PORT_t=%.3f IR=%.3f net_sr=%.3f oos_ret=%.3f post2017_t=%.3f",
     nm, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr, oos_ret(pr), post2017_t(pr))
}
res <- rbindlist(rows)
res[, DISCOVERY := is.finite(PORT_t) & PORT_t>=2.95 & is.finite(oos_ret) & oos_ret>=0.7]
print(res[, .(variant, PORT_t=round(PORT_t,3), IR=round(IR,3), net_sr=round(net_sr,3),
              oos_ret=round(oos_ret,3), post2017_t=round(post2017_t,3), TO=round(TO,2), DISCOVERY)])
fwrite(res, file.path(WD,"cycle1_leadership_results.csv"))
PG("[PG] DONE cycle1. discoveries=%d", sum(res$DISCOVERY, na.rm=TRUE))
