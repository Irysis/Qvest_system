# Fix bm: use clean benchmark.parquet BM_Close monthly (RAWDATA BM_Ret corrupt for recent months)
suppressMessages({library(arrow);library(data.table)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
b <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
b[, Date := as.IDate(as.character(Date))]
b[, ym := as.integer(format(Date,"%Y%m"))]
setorder(b, Date)
bmm <- b[, .(bmc = BM_Close[.N]), by=ym][order(ym)]
bmm[, bm := bmc/shift(bmc) - 1]
bmm <- bmm[is.finite(bm) & ym>=200406L, .(ym, bm)]
p <- readRDS(file.path(OUT,"panel_universe_ret.rds"))
p$bm <- bmm
saveRDS(p, file.path(OUT,"panel_universe_ret.rds"))
cat("bm fixed: months", nrow(bmm), "range", min(bmm$ym), max(bmm$ym), "\n")
cat("bm summary: mean", round(mean(bmm$bm),4), "sd", round(sd(bmm$bm),4), "\n")
print(tail(bmm,4))
