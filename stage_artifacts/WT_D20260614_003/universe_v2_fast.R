# Fast FREEFLOAT comparison — build universe vectorized (no per-month full-parquet reads).
suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
FACTORS <- c("Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability")
TOP_N <- 30L; START <- as.Date("2005-01-01"); END <- as.Date("2026-06-30")
ds <- open_dataset(".cache/rawdata.parquet")
raw <- as.data.table(ds %>% select(Date,Ticker,K200,KQ150,Market,Float,Size,Close,Vol,BM_Ret) %>%
  filter(Date >= as.Date("2004-06-01")) %>% collect())
setorder(raw, Ticker, Date); raw[, Date := as.Date(Date)]
raw[, tv := Vol*Close]; raw[, adv20 := frollmean(tv,20,align="right"), by=Ticker]
raw[, ym := format(Date,"%Y%m")]
raw[, ff_mktcap := Size * fifelse(is.na(Float)|Float<=0, 1, Float)]   # free-float mktcap proxy
bm_daily <- unique(raw[,.(Date,BM_Ret)])[order(Date)]; bm_daily[, ymb := format(Date,"%Y%m")]
bm_monthly <- bm_daily[!is.na(BM_Ret), .(BM_Ret_m=prod(1+BM_Ret)-1), by=ymb]
me_dates <- raw[,.(me_date=max(Date)), by=ym]
me_dates <- merge(me_dates, bm_monthly, by.x="ym", by.y="ymb", all.x=TRUE)
me <- merge(raw, me_dates, by="ym"); me <- me[Date==me_date]; me[, ym_int := as.integer(ym)]
setorder(me, Ticker, ym_int)
me[, fwd_close := shift(Close,type="lead"), by=Ticker]
me[, fwd_ym_int := shift(ym_int,type="lead"), by=Ticker]
me[, Ret_1m := fwd_close/Close - 1]
me[, gap_ok := { y1<-ym_int%/%100;m1<-ym_int%%100;y2<-fwd_ym_int%/%100;m2<-fwd_ym_int%%100;(y2*12+m2)-(y1*12+m1)==1 }]
me[gap_ok==FALSE|is.na(gap_ok), Ret_1m := NA_real_]
bm_by_date <- me_dates[,.(Date=me_date, BM_Ret=BM_Ret_m)]
# FREEFLOAT membership: per month, KOSPI∪KOSDAQ (Market), liq>=2e8, top-500 by ff_mktcap
me[, is_kr := Market %in% c("KOSPI","KOSDAQ","KS","KQ") | K200==1 | KQ150==1]
me[, liq_ok := !is.na(adv20) & adv20 >= 2e8]
me[, ff_rank := frank(-ff_mktcap, ties.method="first"), by=ym]
me[, in_ff := is_kr==TRUE & liq_ok==TRUE & ff_rank <= 500]
sig_dates <- sort(unique(me_dates$me_date)); sig_dates <- sig_dates[sig_dates>=START & sig_dates<=END]
panel <- rbindlist(lapply(sig_dates, function(sd){
  ym_tag <- format(sd,"%Y%m"); univ <- me[ym==ym_tag & in_ff==TRUE]
  if(nrow(univ)<TOP_N) return(NULL)
  ff <- tryCatch(load_month_factors(sd, coverage_min=0.05, factor_names=FACTORS), error=function(e) NULL)
  if(is.null(ff)||nrow(ff)==0) return(NULL)
  ff <- ff[Ticker %in% univ$Ticker]
  w <- dcast(ff, Ticker~Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) x[1])
  have <- intersect(FACTORS, names(w)); if(length(have)<2L) return(NULL)
  for(f in have){ z<-w[[f]]; mu<-mean(z,na.rm=T); sg<-sd(z,na.rm=T); w[[f]] <- if(is.finite(sg)&&sg>0)(z-mu)/sg else NA_real_ }
  w[, score := rowMeans(.SD,na.rm=T), .SDcols=have]; w[, nh := rowSums(!is.na(.SD)), .SDcols=have]
  w <- w[nh>=2L & is.finite(score)]; if(nrow(w)<TOP_N) return(NULL)
  m <- merge(w[,.(Ticker,score)], univ[,.(Ticker,Ret_1m,adv20)], by="Ticker", all.x=TRUE)
  m[, Date := sd]; m
}), fill=TRUE)
panel <- panel[!is.na(score)]
ic <- panel[!is.na(Ret_1m), .(ic=suppressWarnings(cor(score,Ret_1m,method="spearman",use="complete.obs")), n=.N), by=Date][n>=10 & is.finite(ic)]
rank_ic <- mean(ic$ic); icir <- rank_ic/sd(ic$ic)
csb <- canonical_screen_bt(panel[,.(Date,Ticker,score)], panel[!is.na(Ret_1m),.(Date,Ticker,Ret_1m)],
  bm_by_date, top_n=TOP_N, cost_bps_oneway=20, liq_dt=panel[,.(Date,Ticker,adv=adv20)], liq_min=2e8,
  run_id="FREEFLOAT", strategy_id="FREEFLOAT")
r2 <- list(universe="KR_TOP500_FREEFLOAT", liq_min=2e8, cost_bps=20, n_months=uniqueN(panel$Date),
  rank_ic=round(rank_ic,4), icir=round(icir,3), portfolio_alpha_t_nw_lag3=round(csb$portfolio_alpha_t_nw_lag3,3),
  information_ratio=round(csb$information_ratio,3), net_sr=round(csb$net_sr,3),
  turnover_annual=round(csb$turnover_annual,2), alpha_annualized=round(csb$alpha_annualized,4))
# top342 from earlier diag
d <- readRDS("stage_artifacts/WT_D20260614_003/diag.rds")
r1 <- list(universe="KR_top342", liq_min=2e8, cost_bps=15, n_months=d$n_months_panel,
  rank_ic=round(d$rank_ic,4), icir=round(d$icir,3), portfolio_alpha_t_nw_lag3=round(d$portfolio_alpha_t_nw_lag3,3),
  information_ratio=round(d$information_ratio,3), net_sr=round(d$net_sr,3),
  turnover_annual=round(d$turnover_annual,2), alpha_annualized=round(d$alpha_annualized,4))
out <- list(KR_top342=r1, KR_TOP500_FREEFLOAT=r2,
  mandate=list(trigger="weak IR (<0.15) per L-227", note="cost: top342=15bps, FREEFLOAT=20bps per mandate"))
for(nm in c("KR_top342","KR_TOP500_FREEFLOAT")){ x<-out[[nm]]
  cat(sprintf("[%s] n=%d rank_ic=%.4f icir=%.3f port_t=%.3f IR=%.3f netSR=%.3f TO=%.2f alpha_ann=%.4f\n",
    nm,x$n_months,x$rank_ic,x$icir,x$portfolio_alpha_t_nw_lag3,x$information_ratio,x$net_sr,x$turnover_annual,x$alpha_annualized)) }
write_json(out, "stage_artifacts/WT_D20260614_003/universe_comparison.json", pretty=TRUE, auto_unbox=TRUE)
cat("saved universe_comparison.json\n")
