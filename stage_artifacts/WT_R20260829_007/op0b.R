suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
pn <- readRDS(file.path(OUT,"panel.rds"))
for(nm in names(pn$fwd)){ x<-pn$fwd[[nm]]; cat(nm,":",class(x)[1], paste(dim(x),collapse="x"), if(is.data.frame(x)) paste0(" cols=",paste(names(x),collapse=",")) else "", "\n") }
cat("\nreturns_dt head:\n"); print(head(as.data.table(pn$fwd$returns_dt),3))
cat("\nliq_dt head:\n"); print(head(as.data.table(pn$fwd$liq_dt),3))
cat("\nbench_dt head:\n"); print(head(as.data.table(pn$fwd$bench_dt),3))
cat("\nSIG cols:", paste(names(pn$SIG),collapse=", "), "\n"); print(head(pn$SIG,2))
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
# tie structure at top
d <- A[Date==as.Date("2026-07-31")][order(-alpha_hat)]
cat("\n2026-07-31 top30 z_fh:\n"); print(d[1:30, .(Ticker, fh_lag1d, z_fh, in_top25)])
cat("\nties at threshold? n with z_fh >= 25th:", sum(d$z_fh >= d$z_fh[25]), "\n")
