# 01_build_panel.R v3 — drop columns early, gc aggressively
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
t0 <- Sys.time()

# --- Pass 1: universe + adv20 (only Close,Vol,membership) ---
log("[A1] read RAWDATA (univ cols)...")
u <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","Close","Vol")))
log("[A1] rows", nrow(u))
u[, Date := as.IDate(as.character(Date))]
u <- u[Date >= as.IDate("2004-06-01")]
u[, ym := as.integer(format(Date,"%Y%m"))]
u[, tval := as.numeric(Close)*as.numeric(Vol)]
u[, c("Close","Vol") := NULL]; gc()
setorder(u, Ticker, Date)
log("[A2] adv20...")
u[, adv20 := frollmean(tval, 20L), by=Ticker]
u[, tval := NULL]; gc()
me <- u[, .SD[.N], by=.(Ticker, ym), .SDcols=c("K200","KQ150","adv20")]
me <- me[((K200==1)|(KQ150==1)) & is.finite(adv20) & adv20>=2e8, .(ym, Ticker, adv20)]
rm(u); gc()
log("[A3] univ rows", nrow(me), "months", uniqueN(me$ym))
saveRDS(me, file.path(OUT,"me.rds"))

# --- Pass 2: returns (only Ret, BM_Ret) ---
log("[B1] read RAWDATA (ret cols)...")
r <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","Ret","BM_Ret")))
r[, Date := as.IDate(as.character(Date))]
r <- r[Date >= as.IDate("2004-06-01")]
r[, ym := as.integer(format(Date,"%Y%m"))]
log("[B2] monthly compound...")
mret <- r[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]
bm <- r[!is.na(BM_Ret), .(bm = prod(1+BM_Ret)-1), by=ym][order(ym)]
rm(r); gc()
log("[B3] mret rows", nrow(mret), "bm months", nrow(bm))
saveRDS(list(me=me, mret=mret, bm=bm), file.path(OUT,"panel_universe_ret.rds"))
log("[DONE] total", round(difftime(Sys.time(),t0,units="secs"),1),"s")
