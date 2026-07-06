# 02_build_factors.R — load value/quality Z_Score + BM-ratio spread series (expanding percentile, C1)
suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
t0 <- Sys.time()
pu <- readRDS(file.path(OUT,"panel_universe_ret.rds")); me <- pu$me

val_facs  <- c("V01_BM","V02_EP","V10_FCF_Yield","V14_EBIT_EV","V20_SP")   # cheapness
qual_facs <- c("Q01_GPA","Q02_ROE","Q08_Composite_Quality","Q17_ROIC")     # profitability/quality
all_facs  <- c(val_facs, qual_facs)

yms <- sort(unique(me$ym)); yms <- yms[yms>=200412L]
log("[start] months", length(yms))

proc_month <- function(y){
  f <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%d.parquet", y))
  if(!file.exists(f)) return(NULL)
  d <- tryCatch(as.data.table(open_dataset(f) %>% select(Ticker,Factor_Name,Raw_Value,Z_Score) %>%
        filter(Factor_Name %in% all_facs) %>% collect()), error=function(e) NULL)
  if(is.null(d)||nrow(d)==0) return(NULL)
  u <- me[ym==y, .(Ticker)]
  d <- merge(d, u, by="Ticker")
  if(uniqueN(d$Ticker) < 30) return(NULL)
  d[, ym := y]; d[]
}
panel <- rbindlist(lapply(seq_along(yms), function(k){
  r <- proc_month(yms[k])
  if(k %% 50==0){log("  ",yms[k],round(difftime(Sys.time(),t0,units="secs"),1),"s")}
  r
}), fill=TRUE)
log("[panel] rows", nrow(panel), "months", uniqueN(panel$ym))
saveRDS(panel, file.path(OUT,"factor_panel_long.rds"))

# ---- Value SPREAD (scale-free ratio): BM p80/p20 median ratio, winsor 1-99, expanding percentile ----
spr <- panel[Factor_Name=="V01_BM" & is.finite(Raw_Value), {
  x <- Raw_Value
  qx <- quantile(x, c(.01,.99), na.rm=TRUE)
  xw <- pmin(pmax(x, qx[[1]]), qx[[2]])
  p20 <- as.numeric(quantile(xw,.20)); p80 <- as.numeric(quantile(xw,.80))
  cheap <- median(xw[xw>=p80]); exp_ <- median(xw[xw<=p20])
  ratio <- if(is.finite(exp_) && exp_>0) cheap/exp_ else NA_real_
  .(n=.N, bm_p20=p20, bm_p80=p80, spread_ratio=ratio, spread_diff=p80-p20)
}, by=ym][order(ym)]
spr[, exp_pctile := sapply(seq_len(.N), function(i) mean(spread_ratio[1:i] <= spread_ratio[i], na.rm=TRUE))]
spr[, exp_z := sapply(seq_len(.N), function(i){h<-spread_ratio[1:i]; if(i<12||sd(h,na.rm=TRUE)==0) NA_real_ else (spread_ratio[i]-mean(h,na.rm=TRUE))/sd(h,na.rm=TRUE)})]
saveRDS(spr, file.path(OUT,"spread_series.rds"))
n<-nrow(spr)
log("[SPREAD ratio-based BM p80/p20]")
print(spr[ym %in% c(200812L,202012L,202112L,202212L,202412L,202512L,max(spr$ym)), .(ym,n,spread_ratio,exp_pctile,exp_z)])
cat(sprintf("LATEST ym=%d ratio=%.2f pctile=%.3f z=%.2f | ALLTIME max=%.2f@%d mean=%.2f cur/mean=%.2f\n",
    spr$ym[n],spr$spread_ratio[n],spr$exp_pctile[n],spr$exp_z[n],
    max(spr$spread_ratio,na.rm=TRUE),spr$ym[which.max(spr$spread_ratio)],
    mean(spr$spread_ratio,na.rm=TRUE),spr$spread_ratio[n]/mean(spr$spread_ratio,na.rm=TRUE)))
log("[TOTAL]", round(difftime(Sys.time(),t0,units="secs"),1),"s")
