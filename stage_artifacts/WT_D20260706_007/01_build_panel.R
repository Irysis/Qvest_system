# 01_build_panel.R — WT-D20260706_007 value/quality spread-reversion
# Build monthly panel: universe (K200|KQ150, t-1 ADV>=2e8) + forward 1M return + value/quality composites.
# PIT: month-end t snapshot; forward return = month t+1; factors via Z_Score at t (aligned separately).
suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(2L)   # avoid 1L io-thread hang; 2 safe
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
t0 <- Sys.time()

# ---- [1] Universe monthly (reuse recon cache if present) + monthly return ----
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","Close","Vol","Ret","BM_Ret")))
raw[, Date := as.IDate(as.character(Date))]
raw <- raw[Date >= as.IDate("2004-06-01")]
raw[, ym := as.integer(format(Date,"%Y%m"))]
raw[, tval := as.numeric(Close)*as.numeric(Vol)]
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(tval, 20L), by=Ticker]
# month-end snapshot (t-1 info: adv20 through month-end, membership at t)
me <- raw[, .SD[.N], by=.(Ticker, ym)]
me <- me[((K200==1)|(KQ150==1)) & is.finite(adv20) & adv20>=2e8, .(ym, Ticker, adv20)]
cat("[univ]", nrow(me), "rows", uniqueN(me$ym), "months", round(difftime(Sys.time(),t0,units="secs"),1),"s\n"); flush.console()

# monthly realized return per ticker (compounded daily). This is FORWARD input.
mret <- raw[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]
# benchmark monthly (compound BM daily). BM_Ret is per-row daily benchmark return.
bm <- raw[!is.na(BM_Ret), .(bm = prod(1+BM_Ret)-1), by=ym]
setorder(bm, ym)
cat("[ret] mret rows", nrow(mret), "bm months", nrow(bm), "\n"); flush.console()
saveRDS(list(me=me, mret=mret, bm=bm), file.path(OUT,"panel_universe_ret.rds"))
cat("[TOTAL]", round(difftime(Sys.time(),t0,units="secs"),1),"s\n")
