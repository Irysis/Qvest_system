# 02_build_factors.R — load value/quality Z_Score + build spread series (canonical BM ratio)
suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(2L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
t0 <- Sys.time()
pu <- readRDS(file.path(OUT,"panel_universe_ret.rds")); me <- pu$me

# factors to load: value composite inputs + quality composite inputs
val_facs  <- c("V01_BM","V02_EP","V10_FCF_Yield","V14_EBIT_EV","V20_SP")   # cheapness (higher=cheaper on Raw for BM/EP/SP)
qual_facs <- c("Q01_GPA","Q02_ROE","Q08_Composite_Quality","Q17_ROIC")
all_facs  <- c(val_facs, qual_facs)

yms <- sort(unique(me$ym)); yms <- yms[yms>=200412L]
cat("[start] months to process:", length(yms), "\n"); flush.console()

# per-month: pull Z_Score (for tilt, already unit-var) + Raw_Value (for BM spread), filter to universe
proc_month <- function(y){
  f <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%d.parquet", y))
  if(!file.exists(f)) return(NULL)
  d <- as.data.table(open_dataset(f) %>% select(Ticker,Factor_Name,Raw_Value,Z_Score) %>%
        filter(Factor_Name %in% all_facs) %>% collect())
  u <- me[ym==y, .(Ticker)]
  d <- merge(d, u, by="Ticker")
  if(uniqueN(d$Ticker) < 30) return(NULL)
  d[, ym := y]
  d[]
}
panel <- rbindlist(lapply(seq_along(yms), function(k){
  r <- proc_month(yms[k])
  if(k %% 40==0){cat("  ",yms[k],"elapsed",round(difftime(Sys.time(),t0,units="secs"),1),"s\n");flush.console()}
  r
}), fill=TRUE)
cat("[panel] rows", nrow(panel), "months", uniqueN(panel$ym), "\n"); flush.console()
saveRDS(panel, file.path(OUT,"factor_panel_long.rds"))

# ---- Value SPREAD (canonical, scale-free): BM ratio p80/p20 ----
# BM Raw_Value higher = cheaper. spread = median(BM cheap-quintile top20%) / median(BM expensive-quintile bottom20%).
# Guard positivity: BM can be tiny/negative -> use winsorized quantiles & positive floor.
spr <- panel[Factor_Name=="V01_BM" & is.finite(Raw_Value), {
  x <- Raw_Value
  qx <- quantile(x, c(.01,.20,.80,.99), na.rm=TRUE)
  xw <- pmin(pmax(x, qx[[1]]), qx[[4]])   # winsor 1-99
  p20 <- quantile(xw, .20); p80 <- quantile(xw, .80)
  # ratio spread (cheap/expensive); use positive-shifted medians of tails
  cheap <- median(xw[xw>=p80]); exp_ <- median(xw[xw<=p20])
  ratio <- if (is.finite(exp_) && exp_>0) cheap/exp_ else NA_real_
  .(n=.N, bm_p20=as.numeric(p20), bm_p80=as.numeric(p80),
    spread_ratio=as.numeric(ratio), spread_diff=as.numeric(p80-p20))
}, by=ym]
setorder(spr, ym)
# expanding percentile (C1 — no full-sample). also z of spread (expanding mean/sd)
spr[, exp_pctile_ratio := sapply(seq_len(.N), function(i) mean(spread_ratio[1:i] <= spread_ratio[i], na.rm=TRUE))]
spr[, exp_pctile_diff  := sapply(seq_len(.N), function(i) mean(spread_diff[1:i]  <= spread_diff[i],  na.rm=TRUE))]
spr[, exp_z_ratio := sapply(seq_len(.N), function(i){ h<-spread_ratio[1:i]; if(i<12||sd(h,na.rm=TRUE)==0) NA_real_ else (spread_ratio[i]-mean(h,na.rm=TRUE))/sd(h,na.rm=TRUE)})]
saveRDS(spr, file.path(OUT,"spread_series.rds"))
n<-nrow(spr)
cat("\n[SPREAD] ratio-based (BM p80/p20 median ratio):\n")
print(spr[ym %in% c(200812L,202012L,202112L,202212L,202412L,202512L,max(spr$ym)), .(ym,n,spread_ratio,exp_pctile_ratio,exp_z_ratio)])
cat(sprintf("LATEST ym=%d spread_ratio=%.2f exp_pctile=%.3f z=%.2f\n",
    spr$ym[n], spr$spread_ratio[n], spr$exp_pctile_ratio[n], spr$exp_z_ratio[n]))
cat(sprintf("ALLTIME max ratio=%.2f at ym=%d ; mean=%.2f ; cur/mean=%.2f\n",
    max(spr$spread_ratio,na.rm=TRUE), spr$ym[which.max(spr$spread_ratio)],
    mean(spr$spread_ratio,na.rm=TRUE), spr$spread_ratio[n]/mean(spr$spread_ratio,na.rm=TRUE)))
cat("[TOTAL]", round(difftime(Sys.time(),t0,units="secs"),1),"s\n")
