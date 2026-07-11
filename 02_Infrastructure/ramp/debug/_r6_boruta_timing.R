## _r6_boruta_timing.R — 단일 Boruta 호출 실제 비용 측정 (R4 params vs 축소안)
suppressPackageStartupMessages({library(data.table); library(arrow); library(Boruta)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "outputs/ramp"

## load pure z for approved, build fw + y (subset months for speed)
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
approved <- af[status=="approved", factor_id]
sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% approved]; sc[, signal_date := as.Date(signal_date)]

## a representative pool from cached selection
sel <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
tj <- sel[["36"]]$traj
mid_key <- names(tj)[length(tj) %/% 2]
pool <- tj[[mid_key]]$pool[["K20"]]
a_idx <- tj[[mid_key]]$anchor_idx
cat("pool (K20):", paste(pool, collapse=","), "\n")

g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"), col_select=c("signal_date")))
sig_dates <- sort(unique(as.Date(g$signal_date)))
W <- 36L; lo <- a_idx - W; hi <- a_idx - 1L; win_dates <- sig_dates[lo:hi]

## build a slim fw restricted to pool + window (fast)
sub <- sc[factor_id %in% pool & signal_date %in% win_dates]
fw <- dcast(sub, signal_date + security_id ~ factor_id, value.var="z")
## simple y: random for timing purposes (Boruta cost ~ invariant to y distribution)
set.seed(1); fw[, y := rnorm(.N)]
pan <- fw[is.finite(y)]
cat("window rows:", nrow(pan), "pool size:", length(pool), "\n")

time_boruta <- function(nmax, ntree, maxRuns){
  set.seed(42); idx <- if(nrow(pan)>nmax) sample(nrow(pan), nmax) else seq_len(nrow(pan))
  X <- pan[idx, ..pool]; for(f in pool) X[[f]][is.na(X[[f]])] <- 0
  yv <- pan$y[idx]
  t0 <- Sys.time()
  set.seed(42)
  b <- Boruta(x=as.data.frame(X), y=yv, maxRuns=maxRuns, doTrace=0, ntree=ntree)
  as.numeric(Sys.time()-t0, units="secs")
}
cat(sprintf("\nR4 params (nmax=3000 ntree=100 maxRuns=40): %.1fs\n", time_boruta(3000,100,40)))
cat(sprintf("축소안A (nmax=1500 ntree=80 maxRuns=30): %.1fs\n", time_boruta(1500,80,30)))
cat(sprintf("축소안B (nmax=2000 ntree=100 maxRuns=40): %.1fs\n", time_boruta(2000,100,40)))
cat("\nTIMING_DONE\n")
