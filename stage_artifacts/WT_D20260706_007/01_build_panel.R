# 01_build_panel.R v2 — incremental, memory-safe
suppressMessages({library(data.table); library(arrow)})
setDTthreads(2L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
t0 <- Sys.time()
log("[A] read RAWDATA...")
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","Close","Vol","Ret","BM_Ret")))
log("[A] read done rows", nrow(raw))
raw[, Date := as.IDate(as.character(Date))]
raw <- raw[Date >= as.IDate("2004-06-01")]
raw[, ym := as.integer(format(Date,"%Y%m"))]
gc()
log("[B] adv20 frollmean...")
raw[, tval := as.numeric(Close)*as.numeric(Vol)]
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(tval, 20L), by=Ticker]
log("[B] adv done")
log("[C] month-end snapshot...")
me <- raw[, .SD[.N], by=.(Ticker, ym), .SDcols=c("K200","KQ150","adv20")]
me <- me[((K200==1)|(KQ150==1)) & is.finite(adv20) & adv20>=2e8, .(ym, Ticker, adv20)]
log("[C] univ rows", nrow(me), "months", uniqueN(me$ym))
saveRDS(me, file.path(OUT,"me.rds")); log("[C] saved me.rds")
log("[D] monthly returns...")
mret <- raw[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]
bm <- raw[!is.na(BM_Ret), .(bm = prod(1+BM_Ret)-1), by=ym][order(ym)]
saveRDS(list(mret=mret, bm=bm), file.path(OUT,"ret.rds"))
log("[D] mret rows", nrow(mret), "bm months", nrow(bm))
saveRDS(list(me=me, mret=mret, bm=bm), file.path(OUT,"panel_universe_ret.rds"))
log("[DONE] total", round(difftime(Sys.time(),t0,units="secs"),1),"s")
