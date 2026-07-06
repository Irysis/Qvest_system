# sensitivity.R — WT-D20260706_013
# Adversarial robustness: is the reclassification-failure an artifact of TOO-WEAK intangible weighting?
# Test (a) heavier org-capital (theta=0.5, delta_SGA lower=0.15 -> larger stock),
#      (b) a DIRECT intangible-intensity tilt to force mega-cap R&D firms up,
#      (c) intangible-adj value restricted to R&D-reporting firms only (pre-2016 where R&D dense).
# Also: quality-orthogonality check (is iBM just re-labeled quality?).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
PAN <- file.path(ROOT, "stage_artifacts/WT-D20260706_013/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_013")

sc   <- as.data.table(read_parquet(file.path(PAN, "intan_scores_monthly.parquet")))
rets <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))[, .(Date,Ticker,Ret_1m)]
bm_cw<- as.data.table(read_parquet(file.path(PAN, "benchmark_capw.parquet")))
bm_ew<- as.data.table(read_parquet(file.path(PAN, "benchmark_ew.parquet")))
univ <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))
START<- as.Date("2005-01-01")
sc<-sc[Date>=START]; rets<-rets[Date>=START]; bm_cw<-bm_cw[Date>=START]; bm_ew<-bm_ew[Date>=START]; univ<-univ[Date>=START]
liq <- univ[, .(Date, Ticker, adv=adv20)]
all_m<-sort(unique(sc$Date)); post17<-all_m[all_m>=as.Date("2017-01-01")]

scr <- function(dt, scol, months, bench, top_n=25L){
  s<-dt[Date %in% months & is.finite(get(scol)), .(Date,Ticker,score=get(scol))]
  r<-rets[Date %in% months]; b<-bench[Date %in% months]; l<-liq[Date %in% months]
  if(uniqueN(s$Date)<6) return(list(port_t=NA,net_sr=NA,med_sizep=NA,frac40=NA))
  res<-canonical_screen_bt(s,r,b,top_n=top_n,cost_bps_oneway=15,liq_dt=l,liq_min=2e8,periods_per_year=12L,run_id="sens",strategy_id="sens")
  # mega-cap composition
  tmp<-copy(s); setorder(tmp,Date,-score); t25<-tmp[,.SD[seq_len(min(top_n,.N))],by=Date]
  szp<-merge(t25,dt[,.(Date,Ticker,size_pctile)],by=c("Date","Ticker"))
  list(port_t=round(res$portfolio_alpha_t_nw_lag3,3), net_sr=round(res$net_sr,3),
       med_sizep=round(100*median(szp$size_pctile),1), frac40=round(mean(szp$size_pctile>=0.60),3))
}

# (b) DIRECT intangible-intensity tilt: rank on (stdBM z + lambda * intan_intensity z)
zsc <- function(x) { x<-as.numeric(x); (x-mean(x,na.rm=TRUE))/sd(x,na.rm=TRUE) }
sc[, z_stdBM := zsc(stdBM), by=Date]
sc[, z_intan := zsc(pmin(intan_intensity, quantile(intan_intensity,0.99,na.rm=TRUE))), by=Date]  # winsor
for (lam in c(0.5, 1.0, 2.0)) {
  sc[, tilt := z_stdBM + lam*z_intan]
  cw<-scr(sc,"tilt",post17,bm_cw); ew<-scr(sc,"tilt",post17,bm_ew)
  cat(sprintf("[TILT lam=%.1f] POST2017 capw port_t=%s (sr %s) | ew port_t=%s | top25 med-size-pctile=%s%% frac40=%s\n",
      lam, cw$port_t, cw$net_sr, ew$port_t, cw$med_sizep, cw$frac40))
}
# pure intangible-intensity (does buying most-intangible firms pay post-2017?)
cwp<-scr(sc,"z_intan",post17,bm_cw); cat(sprintf("[PURE intan-intensity] POST2017 capw port_t=%s med-size-pctile=%s%% frac40=%s\n", cwp$port_t, cwp$med_sizep, cwp$frac40))

# (c) intangible-adj value on R&D-reporting firms only, pre-2016 (where thesis strongest data)
pre16<-all_m[all_m<as.Date("2016-01-01")]
sc_rd <- sc[has_rd==TRUE]
cw_rd<-scr(sc_rd,"iBM_full",pre16,bm_cw); cat(sprintf("[R&D-firms-only iBM_full] PRE2016 capw port_t=%s med-size-pctile=%s%% frac40=%s\n", cw_rd$port_t, cw_rd$med_sizep, cw_rd$frac40))
cw_rd2<-scr(sc_rd,"iBM_full",post17,bm_cw); cat(sprintf("[R&D-firms-only iBM_full] POST2017 capw port_t=%s (n small) med-size-pctile=%s%%\n", cw_rd2$port_t, cw_rd2$med_sizep))

# (d) quality orthogonality: correlation of iBM_orgc with a simple quality proxy (NI/equity = ROE) and with stdBM
sc[, roe := fifelse(is.finite(ni)&is.finite(eq)&eq>0, ni/eq, NA_real_)]
q <- sc[is.finite(iBM_orgc)&is.finite(stdBM)&is.finite(roe)]
cor_iBM_std <- q[, .(r=cor(iBM_orgc,stdBM,method="spearman")), by=Date][,mean(r,na.rm=TRUE)]
cor_iBM_roe <- q[, .(r=cor(iBM_orgc,roe,method="spearman")), by=Date][,mean(r,na.rm=TRUE)]
cor_std_roe <- q[, .(r=cor(stdBM,roe,method="spearman")), by=Date][,mean(r,na.rm=TRUE)]
cat(sprintf("[ortho] mean monthly Spearman: iBM_orgc~stdBM=%.3f  iBM_orgc~ROE=%.3f  stdBM~ROE=%.3f\n",
    cor_iBM_std, cor_iBM_roe, cor_std_roe))

# (e) STR_1715 book orthogonality proxy: iBM_orgc cor with size (mega-cap tilt of signal itself)
cor_iBM_size <- sc[is.finite(iBM_orgc), .(r=cor(iBM_orgc,size_pctile,method="spearman")), by=Date][,mean(r,na.rm=TRUE)]
cat(sprintf("[ortho] iBM_orgc ~ size_pctile mean Spearman=%.3f (negative = signal favors small)\n", cor_iBM_size))
cat("[sens] DONE\n")
