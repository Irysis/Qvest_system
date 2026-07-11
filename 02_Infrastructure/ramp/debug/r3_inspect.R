## r3_inspect.R — RAMP R3 데이터 구조 조사 (단일스레드, 스키마-우선)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
cat("=== factor_group_scores schema ===\n")
sg<-arrow::open_dataset("outputs/ramp/factor_group_scores.parquet")
print(names(sg))
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"))
cat("families:\n"); print(sort(unique(g$family)))
cat("n rows", nrow(g), " date range", as.character(range(as.Date(g$signal_date))),"\n\n")

cat("=== factor_group_map ===\n")
fm<-as.data.table(read_parquet("outputs/ramp/factor_group_map.parquet"))
print(names(fm)); print(fm)

cat("\n=== approved_factor_library (family/factor listing) ===\n")
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
print(names(af))
cat("n approved factors:", nrow(af), "\n")
# find tail/VaR/CVaR/EP factors
idcol <- intersect(c("factor_id","factor","factor_name","id","name"),names(af))[1]
cat("id col:", idcol, "\n")
if(!is.na(idcol)){
  ids <- af[[idcol]]
  cat("-- D47/D48/VaR/CVaR/tail matches --\n")
  print(ids[grepl("D47|D48|VaR|CVaR|[Tt]ail|ES_|Expected.?Short", ids)])
  cat("-- EP / V02 matches --\n")
  print(ids[grepl("V02|_EP$|EP_|EarningsYield|Earnings.?Yield|E_P", ids, ignore.case=TRUE)])
  cat("-- all ids (first 130) --\n")
  print(head(ids,130))
}
