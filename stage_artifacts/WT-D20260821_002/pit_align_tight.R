## 유니버스 정합 후 재검 — 같은 (Ticker, 월) 짝만 대조하면 정렬이 맞을 때 상관 ~1 이어야 한다
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd); frd[, ym := format(Date, "%Y-%m")]
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Ret")))
rd[, ym := format(Date, "%Y-%m")]
mo <- rd[is.finite(Ret), .(mret = prod(1+Ret)-1, nd=.N), by=.(Ticker, ym)][nd>=15]
shift_ym <- function(v,k) format(seq(as.Date(paste0(v,"-01")), by=paste(k,"month"), length.out=2)[2], "%Y-%m")
tab <- data.table()
for (k in -1:1) {
  a <- copy(frd); a[, ym_join := if (k==0) ym else sapply(ym, shift_ym, k=k)]
  j <- merge(a[, .(Ticker, ym_join, Ret_1m)], mo[, .(Ticker, ym_join=ym, mret)],
             by=c("Ticker","ym_join"))
  tab <- rbind(tab, data.table(shift=k, n_pairs=nrow(j),
                               cor=cor(j$Ret_1m, j$mret, use="complete.obs"),
                               med_abs_diff=median(abs(j$Ret_1m-j$mret), na.rm=TRUE)))
}
cat("=== 종목-월 짝 단위 대조 (shift=0 에서 cor~1 이어야 정렬 확정) ===\n"); print(tab)
write_json(tab, "stage_artifacts/WT-D20260821_002/pit_align_tight.json", auto_unbox=TRUE, pretty=TRUE, digits=8)
