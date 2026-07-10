# H-b bad-news exclusion: proper NA->0 + trailing windows + book-marginal vs score_eff top-25
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")

flg <- readRDS(file.path(OUT,"flags_me.rds"))  # Ticker, ym, u,a,h,anybad, Size (from K200|KQ150 month-end)
# NA->0 for flags (missing = not flagged)
for(c in c("u","a","h")) flg[is.na(get(c)), (c):=0L]
flg[, anybad := pmax(u,a,h)]
setorder(flg, Ticker, ym)

# trailing-12M "ever flagged in past 12 months" (governance deterioration memory)
# build per-ticker cumulative window via rolling on ym-indexed monthly series
flg[, t12_u := as.integer(frollapply(u, 12, function(x) as.integer(any(x>0)), align="right", fill=0)), by=Ticker]
flg[, t12_bad := as.integer(frollapply(anybad, 12, function(x) as.integer(any(x>0)), align="right", fill=0)), by=Ticker]

agg <- flg[, .(univ=.N, unfaith=sum(u), admin=sum(a), halt=sum(h),
               anybad=sum(anybad), t12_bad=sum(t12_bad)), by=ym][order(ym)]
cat("=== H-b flag frequency (NA->0), K200|KQ150 month-end ===\n")
cat(sprintf("univ median=%d | per-month avg: unfaith=%.2f admin=%.2f halt=%.2f anybad=%.2f t12_bad(trailing12M)=%.2f\n",
  median(agg$univ), mean(agg$unfaith), mean(agg$admin), mean(agg$halt), mean(agg$anybad), mean(agg$t12_bad)))
cat(sprintf("months w/ >=1 anybad: %d/%d | >=1 t12_bad: %d/%d\n",
  sum(agg$anybad>0), nrow(agg), sum(agg$t12_bad>0), nrow(agg)))

# ---- book-marginal: does excluding flagged from score_eff top-25 change realized active? ----
seff <- as.data.table(read_parquet(file.path(OUT,"..","WT_D20260425_010/alpha_scores.parquet"),
  col_select=c("Date","Ticker","score_eff","Ret_1m")))
seff[, ym := as.integer(format(as.IDate(as.character(Date)),"%Y%m"))]
seff <- seff[is.finite(score_eff) & is.finite(Ret_1m)]
# benchmark per month
bench <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","BM_Ret")))
bench[, ym := as.integer(format(as.IDate(as.character(Date)),"%Y%m"))]
bm <- bench[, .(BM_Ret=prod(1+BM_Ret,na.rm=TRUE)-1), by=ym]  # monthly bench compound (approx)
# actually BM_Ret is daily; use last-available monthly. Simpler: mean is wrong. Use score_eff's own bench later.
# merge flags
M <- merge(seff, flg[, .(Ticker, ym, anybad, t12_bad)], by=c("Ticker","ym"), all.x=TRUE)
M[is.na(anybad), anybad:=0L][is.na(t12_bad), t12_bad:=0L]

# monthly top-25 by score_eff: baseline vs exclude-flagged
pick_active <- function(dt, exclude_col=NULL){
  res <- dt[, {
    d <- .SD
    if(!is.null(exclude_col)) d <- d[get(exclude_col)==0]
    setorder(d, -score_eff)
    n <- min(25, nrow(d))
    list(port=mean(d$Ret_1m[seq_len(n)]), n=n, dropped=(.N - nrow(d)))
  }, by=ym, .SDcols=names(dt)]
  res
}
base <- pick_active(M)
ex_any <- pick_active(M, "anybad")
ex_t12 <- pick_active(M, "t12_bad")
cmp <- merge(base[, .(ym, port_base=port)], ex_any[, .(ym, port_exany=port, drop_any=dropped)], by="ym")
cmp <- merge(cmp, ex_t12[, .(ym, port_ext12=port, drop_t12=dropped)], by="ym")
# how often does exclusion actually change the top-25?
cmp[, changed_any := as.integer(abs(port_base-port_exany)>1e-12)]
cmp[, changed_t12 := as.integer(abs(port_base-port_ext12)>1e-12)]
cat(sprintf("\n=== book-marginal reach ===\n"))
cat(sprintf("months where anybad-exclusion changed top-25: %d/%d (%.1f%%)\n",
  sum(cmp$changed_any), nrow(cmp), 100*mean(cmp$changed_any)))
cat(sprintf("months where t12_bad-exclusion changed top-25: %d/%d (%.1f%%)\n",
  sum(cmp$changed_t12), nrow(cmp), 100*mean(cmp$changed_t12)))
cat(sprintf("avg names dropped from candidate pool: anybad=%.3f t12=%.3f\n",
  mean(cmp$drop_any), mean(cmp$drop_t12)))
# paired diff (exclusion - base) on the portfolio return series (not active yet; relative delta)
d_any <- cmp$port_exany - cmp$port_base
d_t12 <- cmp$port_ext12 - cmp$port_base
nwt <- function(x){ x<-x[is.finite(x)]; n<-length(x); if(n<12) return(NA)
  m<-mean(x); ac<-acf(x, lag.max=3, plot=FALSE, demean=TRUE)$acf[-1]
  v<-var(x); s<-v*(1+2*sum((1-(1:3)/n)*ac)); (m)/sqrt(s/n) }
cat(sprintf("\npaired delta (exclude - base) mean/mo: anybad=%.5f (NWt=%.2f) t12=%.5f (NWt=%.2f)\n",
  mean(d_any), nwt(d_any), mean(d_t12), nwt(d_t12)))
saveRDS(list(agg=agg, cmp=cmp, d_any=d_any, d_t12=d_t12), file.path(OUT,"hb_result.rds"))
cat("DONE\n")
