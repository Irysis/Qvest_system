suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
t0 <- Sys.time()
log("[R1] arrow read+filter (Date>=2004 push-down)...")
# push filter + ym compute to arrow to avoid materializing 13.9M rows in R
raw <- as.data.table(open_dataset(file.path(ROOT,".cache/RAWDATA.parquet")) %>%
  select(Date, Ticker, Ret, BM_Ret) %>%
  filter(Date >= as.Date("2004-06-01")) %>%
  collect())
log("[R1] rows", nrow(raw))
raw[, ym := as.integer(format(Date, "%Y%m"))]
raw[, Date := NULL]; gc()
log("[R2] compound monthly...")
mret <- raw[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]
log("[R2] mret done rows", nrow(mret))
bm <- raw[!is.na(BM_Ret), .(bm = prod(1+BM_Ret)-1), by=ym][order(ym)]
log("[R3] bm months", nrow(bm))
me <- readRDS(file.path(OUT,"..","tmp_universe_monthly.rds"))
saveRDS(list(me=me, mret=mret, bm=bm), file.path(OUT,"panel_universe_ret.rds"))
log("[DONE]", round(difftime(Sys.time(),t0,units="secs"),1),"s")
