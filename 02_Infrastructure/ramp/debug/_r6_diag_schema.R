## _r6_diag_schema.R — R6 착수 진단: 승인팩터 목록·pure_factor_scores 스키마·재사용 후보
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "outputs/ramp"

cat("=== factor_validation_metrics.parquet ===\n")
fvm <- as.data.table(read_parquet(file.path(OUT,"factor_validation_metrics.parquet")))
cat("cols:", paste(names(fvm),collapse=", "), "\n")
cat("nrow:", nrow(fvm), "\n")
if("status" %in% names(fvm)) print(fvm[,.N,by=status])
cat("\n-- sample rows --\n"); print(head(fvm, 3))

cat("\n=== factor_group_map.parquet ===\n")
fgm <- as.data.table(read_parquet(file.path(OUT,"factor_group_map.parquet")))
cat("cols:", paste(names(fgm),collapse=", "), "\n")
cat("nrow:", nrow(fgm), "\n")
print(head(fgm, 5))
if("family" %in% names(fgm)) print(fgm[,.N,by=family][order(-N)])

cat("\n=== factor_group_scores.parquet (schema only) ===\n")
fgs_sch <- arrow::open_dataset(file.path(OUT,"factor_group_scores.parquet"))
cat("cols:", paste(names(fgs_sch),collapse=", "), "\n")

cat("\n=== pure_factor_scores.parquet (schema only, no full load) ===\n")
pfs_sch <- arrow::open_dataset(file.path(OUT,"pure_factor_scores.parquet"))
cat("cols:", paste(names(pfs_sch),collapse=", "), "\n")
## unique factor_id count via light column read
pf_fid <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
                                      col_select=c("factor_id")))
cat("pure_factor_scores nrow:", nrow(pf_fid), "\n")
cat("unique factor_id count:", length(unique(pf_fid$factor_id)), "\n")
cat("factor_ids:\n"); print(sort(unique(pf_fid$factor_id)))

cat("\nDIAG_DONE\n")
