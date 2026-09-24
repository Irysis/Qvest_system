suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
fs <- c(list.files(root, pattern="^fred_macro[.]parquet[.]bak_", full.names=TRUE), file.path(root,c("fred_macro.parquet","macro_fred.parquet")))
fi <- file.info(fs); o <- order(fi$mtime); fs <- fs[o]; mt <- fi$mtime[o]
L <- lapply(seq_along(fs), function(i){ x <- as.data.table(read_parquet(fs[i], mmap=FALSE)); x[, Date:=as.Date(Date)]; x[, k := i]; x[, .(Series_ID, Date, Value, k)] })
A <- rbindlist(L)
K <- length(fs)
# content fetch window for snapshot k: bak -> [mt[k-1], mt[k]] ; current fred_macro/macro_fred -> [mt[k]-600, mt[k]]
lo <- c(NA, mt[-K]); hi <- mt
lo[K-1] <- mt[K-1] - 600; hi[K-1] <- mt[K-1]; lo[K] <- mt[K]-600; hi[K] <- mt[K]
fs_ <- A[, .(first_k = min(k)), by=.(Series_ID, Date)]
# only obs that were NOT present in first snapshot (so we observe the arrival)
fs_ <- fs_[first_k > 1]
# ensure obs absent in all snapshots before first_k (monotone) — check
fs_[, prev_k := first_k - 1L]
fs_[, avail_lo := as.POSIXct(lo[prev_k], origin="1970-01-01")]  # content of prev snapshot fetched >= lo[prev_k]; obs absent then
fs_[, avail_hi := as.POSIXct(hi[first_k], origin="1970-01-01")]
fs_[, lag_lo_d := as.numeric(difftime(avail_lo, as.POSIXct(paste(Date,"00:00:00"), tz="Asia/Seoul"), units="days"))]
fs_[, lag_hi_d := as.numeric(difftime(avail_hi, as.POSIXct(paste(Date,"00:00:00"), tz="Asia/Seoul"), units="days"))]
# drop obs whose snapshot window is huge (>7d) to keep bounds informative
fs_[, win := lag_hi_d - lag_lo_d]
options(width=200)
sm <- fs_[!is.na(lag_lo_d), .(n=.N, lag_lo_med=round(median(lag_lo_d),1), lag_hi_med=round(median(lag_hi_d),1),
                              lag_lo_min=round(min(lag_lo_d),1), lag_hi_max=round(max(lag_hi_d),1),
                              win_med=round(median(win),1)), by=Series_ID]
saveRDS(list(fs_=fs_, rv=A[, .(nval = uniqueN(round(Value,6)), v_first=Value[which.min(k)], v_last=Value[which.max(k)]), by=.(Series_ID, Date)][nval>1]), file.path("C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/b_data","firstseen.rds"))
