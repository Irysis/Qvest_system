# Chain iteration mechanism diagnosis — IS-ONLY selection (oos_retention integrity).
# Hypothesis: reconstructed "+0.5*Tail_Risk" tilt mis-scaled (R05 aligned-Z fat
# right tail sd~1 with 99pct 4.5 hijacks top-20 -> 1487% turnover, net SR 0.375).
# Diagnose on IS window (first 65% of dates) which composite recovers value sleeve
# signal at sane turnover. OOS untouched (selection IS-only per measurement-grad §3).

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE <- file.path(PROJECT_ROOT,".cache")
OUTDIR <- file.path(PROJECT_ROOT,"04_Research/strategies/STR_WT-D20260611_001_value_sleeve")
source(file.path(PROJECT_ROOT,"02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

scores <- as.data.table(read_parquet(file.path(OUTDIR,"scores_cache.parquet")))
# rebuild returns/bench/liq from cached pieces? Recompute minimal: reuse main run alignment.
# Load RAWDATA monthly + liq + bench (same as run_alpha.R, lightweight cols).
raw <- as.data.table(read_parquet(file.path(CACHE,"rawdata.parquet"),
  col_select=c("Date","Ticker","Close","Vol","Ret","AdminStock","TradingHalt","UnfaithfulDisc")))
raw[,Date:=as.Date(Date)]; raw <- raw[Date>=as.Date("2005-01-01")&Date<=as.Date("2026-06-30")]
raw[,ym:=format(Date,"%Y%m")]; setorder(raw,Ticker,Date)
me_dates <- raw[,.(eom=max(Date)),by=ym]; setorder(me_dates,ym)
mret <- raw[!is.na(Ret),.(mret=prod(1+Ret)-1,ndays=.N),by=.(Ticker,ym)][ndays>=5]
raw[,tv:=Vol*Close]; raw[,adv20:=frollmean(tv,20,align="right"),by=Ticker]
me_liq <- raw[Date %in% me_dates$eom,.(Ticker,ym,adv20,
  bad=(AdminStock %in% 1)|(TradingHalt %in% 1)|(UnfaithfulDisc %in% 1))]
me_liq[is.na(bad),bad:=FALSE]
bm <- as.data.table(read_parquet(file.path(CACHE,"benchmark.parquet")))
bm[,Date:=as.Date(Date)]; bm <- bm[Date>=as.Date("2005-01-01")]; bm[,ym:=format(Date,"%Y%m")]
bmret <- bm[!is.na(BM_Ret),.(bm_mret=prod(1+BM_Ret)-1),by=ym]
ym_sorted <- sort(unique(me_dates$ym))
next_map <- data.table(ym=ym_sorted[-length(ym_sorted)], ym_next=ym_sorted[-1])
ym2date <- me_dates[,.(ym,Date=eom)]
fwd <- merge(next_map, mret[,.(Ticker,ym_next=ym,Ret_1m=mret)],by="ym_next",allow.cartesian=TRUE)[,.(ym,Ticker,Ret_1m)]
returns_dt <- merge(fwd,ym2date,by="ym")[,.(Date,Ticker,Ret_1m)]
liq_dt <- merge(me_liq[bad==FALSE,.(ym,Ticker,adv=adv20)],ym2date,by="ym")[,.(Date,Ticker,adv)]
bench_fwd <- merge(next_map,bmret[,.(ym_next=ym,BM_Ret=bm_mret)],by="ym_next")
bench_dt <- merge(bench_fwd[,.(ym,BM_Ret)],ym2date,by="ym")[,.(Date,BM_Ret)]

LIQ_MIN<-2e8; TOP_N<-20L; COST<-15
all_dates <- sort(unique(merge(scores[,.(ym)],ym2date,by="ym")$Date))
all_dates <- intersect(all_dates, intersect(returns_dt$Date,bench_dt$Date))
all_dates <- sort(as.Date(all_dates, origin="1970-01-01"))
# IS window = first 65%
cut <- all_dates[floor(length(all_dates)*0.65)]
is_dates <- all_dates[all_dates<=cut]
cat("IS window:", as.character(min(is_dates)),"to",as.character(max(is_dates)),"n=",length(is_dates),"\n\n")

# per-month standardized tail (clip to symmetric) + rank-based tail
sc <- copy(scores)
sc[, tail_z_winz := pmin(pmax(tail_z, -3), 3)]                       # symmetric clip
sc[, tail_rank := frank(tail_z, ties.method="average")/.N*2-1, by=ym] # [-1,1] rank
# re-standardize value_z per month to unit sd (it's 0.59 now)
sc[, value_z_std := value_z / sd(value_z, na.rm=TRUE), by=ym]

variants <- list(
  V0_reconstructed = sc[,.(ym,Ticker, s = value_z + 0.5*tail_z)],
  V1_value_only    = sc[,.(ym,Ticker, s = value_z)],
  V2_val_clip_tail = sc[,.(ym,Ticker, s = value_z_std + 0.5*tail_z_winz)],
  V3_val_rank_tail = sc[,.(ym,Ticker, s = value_z_std + 0.5*tail_rank)],
  V4_val_top30     = sc[,.(ym,Ticker, s = value_z)]   # top30 diversification (run below)
)

run_is <- function(sdt_ym, topn){
  sdt <- merge(sdt_ym, ym2date, by="ym")[,.(Date,Ticker,score=s)]
  sdt <- sdt[Date %in% is_dates]
  canonical_screen_bt(sdt, returns_dt[Date %in% is_dates], bench_dt[Date %in% is_dates],
    top_n=topn, cost_bps_oneway=COST, liq_dt=liq_dt[Date %in% is_dates], liq_min=LIQ_MIN,
    run_id="diag", strategy_id="diag")
}
for(nm in names(variants)){
  tn <- if(nm=="V4_val_top30") 30L else TOP_N
  r <- run_is(variants[[nm]], tn)
  cat(sprintf("%-18s [top%d IS] net_SR=%.3f PORT_t=%.3f IR=%.3f TO=%.0f%%/yr\n",
      nm, tn, r$net_sr, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$turnover_annual*100))
}
cat("\nDONE_DIAG\n")
