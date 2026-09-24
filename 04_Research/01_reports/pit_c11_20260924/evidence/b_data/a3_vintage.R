suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
fs <- c(list.files(root, pattern="^fred_macro[.]parquet[.]bak_", full.names=TRUE), file.path(root,c("fred_macro.parquet","macro_fred.parquet")))
fi <- file.info(fs); o <- order(fi$mtime); fs <- fs[o]; fi <- fi[o,]
snaps <- rbindlist(lapply(seq_along(fs), function(i) {
  x <- tryCatch(as.data.table(read_parquet(fs[i], mmap=FALSE)), error=function(e) NULL); if (is.null(x)) return(NULL)
  x[, Date := as.Date(Date)]
  x[, .(snap=basename(fs[i]), mtime=fi$mtime[i], maxD=max(Date), n=.N), by=Series_ID]
}))
saveRDS(snaps, file.path("C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/b_data","snaps.rds"))
w <- dcast(snaps, snap + mtime ~ Series_ID, value.var="maxD")
setorder(w, mtime)
w[, mtime := format(mtime, "%m-%d %H:%M")]
f <- function(d) format(d, "%m-%d")
keep <- c("snap","mtime","VIXCLS","DGS10","DEXKOUS","WALCL","NFCI","STLFSI4","ICSA","FEDFUNDS","UNRATE","CPIAUCSL","INDPRO","M2SL","PERMIT","UMCSENT","PCOPPUSDM","DRTSCILM","BAMLH0A0HYM2")
ww <- w[, ..keep]
for (c in keep[-(1:2)]) set(ww, j=c, value=format(ww[[c]], "%y%m%d"))
ww[, snap := sub("fred_macro.parquet.bak_","bak_",snap)]
options(width=250); print(ww)
cat("\nBAML n per snap:\n"); print(snaps[Series_ID=="BAMLH0A0HYM2", .(snap=sub("fred_macro.parquet.bak_","",snap), n)][, paste(snap, n, collapse="  ")])
