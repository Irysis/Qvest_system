# build_deliverable_weights.R — final weights.csv schedule + package numbers.
# Selected method = BLIND EW top-25 (== baseline A): strongest PORT_t (0.9698 full), 196/196 sig_dates,
#   Sum w=1, [0,0.20] (each 0.04), 25 names, turnover 12.28 <= disqual, long-only.
#   metric_type = weighted_screen (estimated; forge authoritative).
# Rationale: uncertainty-aware sizing/selection tested and REJECTED (AWARE does not beat BLIND);
#   among ALL methods EW is best (DeMiguel 1/N). No aware method delivered; deliver blind best.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; SA<-file.path(ROOT,"stage_artifacts","WT-D20260705_004")
pan<-as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
setorder(pan,ym,-mu_hat)
top25<-pan[,head(.SD,25L),by=ym]
ym2date<-function(y) as.Date(paste0(y,"-01"))
W<-top25[,.(as_of_date=ym2date(ym), Ticker, weight=1/25, mu_hat, sigma_hat)]
# schedule density vs alpha sig_dates
sig_dates<-length(unique(pan$ym)); wt_dates<-length(unique(W$as_of_date))
cat(sprintf("weights.csv unique_dates=%d ; alpha sig_dates=%d ; density_ratio=%.4f (>=0.95 required)\n",
    wt_dates, sig_dates, wt_dates/sig_dates))
fwrite(W[,.(as_of_date,Ticker,weight,mu_hat,sigma_hat)], file.path(SA,"weights.csv"))
# per-name check on final as_of (2026-04)
last<-W[as_of_date==max(as_of_date)]
cat(sprintf("final as_of %s: n=%d sum_w=%.6f max_w=%.4f min_w=%.4f\n",
    as.character(max(W$as_of_date)), nrow(last), sum(last$weight), max(last$weight), min(last$weight)))
cat("[saved] weights.csv (", nrow(W), "rows,", wt_dates, "months )\n")
