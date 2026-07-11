## r3_inspect3.R — tail/EP 팩터 aligned 방향 + approved 통계 + regime 분포
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
tgt<-c("D47_CVaR_5pct","D48_VaR_5pct","D49_VaR_1pct","R01_VaR_95","R02_VaR_99",
       "R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk","D25_Left_Tail_Beta","V02_EP","V15_NetDebt_Adj_EP")
cols<-intersect(c("factor_id","metric_type","rank_ic_mean","rank_ic_ir","net_sr",
                  "portfolio_alpha_t_nw","information_ratio","turnover_annual","status","reject_reason"),names(af))
print(af[factor_id %in% tgt, ..cols])

cat("\n=== regime distribution (alpha_scores WT_D20260425_010) ===\n")
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
cat("regime states:\n"); print(reg[,.N,by=regime][order(-N)])
cat("date range of regime map:", as.character(range(as.Date(paste0(reg$ym,"-01")))),"\n")

cat("\n=== pin_cache availability ===\n")
cat("pin_cache.R exists:", file.exists("02_Infrastructure/data/pin_cache.R"),"\n")
cat("rawdata.parquet exists:", file.exists(".cache/rawdata.parquet"),"\n")
if(file.exists("02_Infrastructure/data/pin_cache.R")){
  src<-readLines("02_Infrastructure/data/pin_cache.R",warn=FALSE)
  cat("pin_cache functions:\n"); print(grep("<-\\s*function|^[a-zA-Z_.]+ ?<- ?function", src, value=TRUE))
}
