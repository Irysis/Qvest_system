#==============================================================================
# R20 (WT-D20260713_004) Step 01 — monthly panel for index-level Benford filter
#   per (code, ym): month-return, month-start Size (weight), K200/KQ150 membership
#   as-of month-start, exchange (static KRX map), carried Benford raw score.
#   API=0. cached only. single-thread. reuses tmp_fsd_monthly + tmp_exch_map.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_004")

xm       <- readRDS(file.path(ROOT,"stage_artifacts/tmp_exch_map.rds"))          # code, exch
scoreFSD <- readRDS(file.path(ROOT,"stage_artifacts/tmp_fsd_monthly.rds"))        # Ticker, ym, raw, code
scoreFSD[, code := sub("^A","",Ticker)]

rd <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
      col_select=c("Date","Ticker","K200","KQ150","Size","Ret")))
rd[, code := sub("^A","",Ticker)]
rd[, ym := as.integer(format(Date,"%Y"))*100L + as.integer(format(Date,"%m"))]
rd <- rd[ym>=200812 & ym<=202506]            # +1yr lead margin for Size_prev
rd <- rd[is.finite(Ret)]

# monthly compound return (single-asset return construction; exact-adjusted per Ret==Close-ratio)
mo <- rd[, .(ret_m = prod(1+Ret)-1, ndays=.N), by=.(code, ym)]
# month-end attributes (last obs of month)
me <- rd[order(Date), .SD[.N], by=.(code, ym)][, .(code, ym, Size_end=Size, K200_end=K200, KQ150_end=KQ150)]
setorder(me, code, ym)
me[, ym_idx := (ym%/%100L)*12L + (ym%%100L)]
# month-start = previous available month-end within code (weight & membership PIT at month start)
me[, `:=`(Size_prev = shift(Size_end), K200_prev = shift(K200_end),
          KQ150_prev = shift(KQ150_end), ym_idx_prev = shift(ym_idx)), by=code]
me <- me[is.finite(ym_idx_prev) & (ym_idx - ym_idx_prev)==1L]   # contiguous months only

pan <- merge(me[, .(code, ym, Size_prev, K200_prev, KQ150_prev)],
             mo[, .(code, ym, ret_m)], by=c("code","ym"))
pan <- merge(pan, xm, by="code", all.x=TRUE)                    # exch
pan <- merge(pan, scoreFSD[, .(code, ym, bf_raw=raw)], by=c("code","ym"), all.x=TRUE)
pan <- pan[is.finite(Size_prev) & Size_prev>0 & is.finite(ret_m)]
pan <- pan[ym>=201001 & ym<=202506]

cat("[01] panel rows:", nrow(pan), " months:", uniqueN(pan$ym),
    " range:", paste(range(pan$ym),collapse=".."), "\n")
cat("[01] with Benford score:", round(100*mean(is.finite(pan$bf_raw)),1),"%\n")
# light winsor of extreme monthly returns (data artifacts) at 99.5% both tails, per month
q <- pan[, .(lo=quantile(ret_m,0.0005,na.rm=TRUE), hi=quantile(ret_m,0.9995,na.rm=TRUE))]
pan[, ret_m := pmin(pmax(ret_m, q$lo), q$hi)]
saveRDS(pan, file.path(OUT,"panel_r20.rds"))
cat("[01] DONE saved panel_r20.rds\n")
