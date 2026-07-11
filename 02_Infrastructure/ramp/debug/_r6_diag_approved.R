## _r6_diag_approved.R — 승인팩터 102 확인 + fam_of 매핑 + R4 캐시 재사용성 + z==Z_Score_Aligned parity
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

cat("=== approved_factor_library.parquet ===\n")
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
cat("cols:", paste(names(af),collapse=", "), "\n")
cat("nrow:", nrow(af), "\n")
if("status" %in% names(af)) print(af[,.N,by=status])
approved <- af[status=="approved", factor_id]
cat("approved count:", length(approved), "\n")

## fam_of (R4/consolidation과 동일)
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }
fam <- sapply(approved, fam_of)
cat("\n=== fam_of mapping (approved 102) ===\n")
print(sort(table(fam), decreasing=TRUE))
cat("non-Macro approved:", sum(fam!="Macro"), "\n")

cat("\n=== R4 cache reuse ===\n")
r4c <- ".cache/_ramp_r4_20260711.rds"
cat("R4 cache exists:", file.exists(r4c), "\n")
if(file.exists(r4c)){
  r4 <- readRDS(r4c)
  cat("R4 cache PR names:", paste(names(r4$PR),collapse=", "), "\n")
  b <- r4$PR[["base_W36_EW"]]
  cat("base_W36_EW rows:", nrow(b), " cols:", paste(names(b),collapse=","), "\n")
  cat("base_W36_EW date range:", as.character(min(b$date)), "~", as.character(max(b$date)), "\n")
}

cat("\n=== r5 cache ===\n")
r5c <- ".cache/_ramp_r5_20260711.rds"
cat("R5 cache exists:", file.exists(r5c), "\n")

cat("\nAPPROVED_DIAG_DONE\n")
