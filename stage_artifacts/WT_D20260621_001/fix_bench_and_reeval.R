#==============================================================================
# FIX: rawdata.parquet BM_Ret is empty (known issue, MEMORY rawdata-bmret-empty).
# Rebuild forward 1M benchmark return from .cache/benchmark.parquet (real KOSPI200 TR),
# also rebuild M08 (residual momentum) using the real daily BM_Ret, then re-run eval.
#==============================================================================
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
           R_DATATABLE_NUM_THREADS="1")
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A <- file.path(ROOT, "stage_artifacts", "WT_D20260621_001")
LOG <- function(...) cat(sprintf("[%s] ", format(Sys.time(),"%H:%M:%S")), ..., "\n")

# --- real benchmark daily series ---
BM <- as.data.table(read_parquet(".cache/benchmark.parquet", col_select=c("Date","BM_Ret")))
BM[, Date := as.Date(Date)]
BM <- BM[is.finite(BM_Ret)]
setorder(BM, Date)
LOG("benchmark daily rows:", nrow(BM), " range:", as.character(min(BM$Date)),"->",as.character(max(BM$Date)))

# signal dates from panel
panel <- readRDS(file.path(OUT_A,"panel_raw.rds"))
sig_dates <- sort(unique(panel$Date))

# forward 1M benchmark return: from sd_i (exclusive) to next sd (inclusive)
bm_fwd <- vector("list", length(sig_dates)-1L)
for (i in seq_len(length(sig_dates)-1L)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i+1L]
  seg <- BM[Date > d0 & Date <= d1, BM_Ret]
  bm_fwd[[i]] <- data.table(Date=d0, BM_Ret = if (length(seg)) prod(1+seg)-1 else NA_real_)
}
bench_dt <- rbindlist(bm_fwd)
bench_dt <- bench_dt[is.finite(BM_Ret)]
LOG("forward benchmark rows:", nrow(bench_dt), " mean:", round(mean(bench_dt$BM_Ret),4),
    " sd:", round(sd(bench_dt$BM_Ret),4), " nonzero:", sum(bench_dt$BM_Ret!=0))
saveRDS(bench_dt, file.path(OUT_A,"bench_fwd_fixed.rds"))

# --- rebuild M08 residual momentum with real daily BM (replace NA M08) ---
# Need daily returns again — reuse rawdata for ever-member tickers, merge real BM_Ret.
LOG("Rebuilding M08 residual momentum with real BM ...")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Ret","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ever <- RAW[K200==1|KQ150==1, unique(Ticker)]
RAW <- RAW[Ticker %in% ever & Date >= as.Date("2002-01-01")]
RAW <- merge(RAW, BM, by="Date", all.x=TRUE)   # attach real daily BM_Ret
setorder(RAW, Ticker, Date)

resid_mom <- function(rets, bm) {
  ok <- is.finite(rets) & is.finite(bm); r <- rets[ok]; b <- bm[ok]; nm <- length(r)
  if (nm < 252L) return(NA_real_)
  fit <- .lm.fit(cbind(1,b), r); res <- fit$residuals; nr <- length(res)
  e <- nr-21L; s <- max(1L, nr-252L+1L); if (e<=s) return(NA_real_)
  sum(res[s:e])
}
m08_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd_i <- sig_dates[i]
  univ <- panel[Date==sd_i, Ticker]
  win <- RAW[Ticker %in% univ & Date <= sd_i]
  m08 <- win[, .(M08b = resid_mom(Ret, BM_Ret)), by=Ticker]
  m08[, Date := sd_i]
  m08_list[[i]] <- m08
}
M08DT <- rbindlist(m08_list)
panel <- merge(panel, M08DT, by=c("Date","Ticker"), all.x=TRUE)
panel[, M08 := M08b][, M08b := NULL]
LOG("M08 finite now:", sum(is.finite(panel$M08)), "/", nrow(panel))
saveRDS(panel, file.path(OUT_A,"panel_fixed.rds"))
LOG("DONE fix. panel_fixed.rds + bench_fwd_fixed.rds saved.")
