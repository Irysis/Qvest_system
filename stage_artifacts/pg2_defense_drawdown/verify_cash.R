# Verify market_fwd = corrected KOSPI200 benchmark (IKS200) + cash dominance test
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
setDTthreads(1); suppressWarnings(arrow::set_io_thread_count(1))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
dd   <- file.path(root,"stage_artifacts/pg2_defense_drawdown")
mkt<- fread(file.path(dd,"market_fwd.csv")); mkt[,ym:=as.character(ym)]

# corrected benchmark
bp <- file.path(root,".cache/benchmark.parquet")
if(file.exists(bp)){
  bm <- as.data.table(read_parquet(bp))
  print(names(bm)); print(head(bm,3))
  # monthly ret from daily BM_Ret
  if("Date" %in% names(bm)){
    bm[, ym := format(as.Date(Date),"%Y-%m")]
    mm <- bm[, .(bm_m = prod(1+BM_Ret)-1), by=ym]
    cmp <- merge(mkt[,.(ym,market_fwd)], mm, by="ym")
    cat("\ncor(market_fwd, benchmark.parquet monthly) =", round(cor(cmp$market_fwd,cmp$bm_m),4),
        " mean|diff| =", round(mean(abs(cmp$market_fwd-cmp$bm_m)),5), "n=",nrow(cmp),"\n")
    # 2026 sanity: KOSPI200 2026-03 approx -20.2%? check cumulative
  }
} else cat("no benchmark.parquet\n")

# CASH dominance: in deep episodes, is any factor's absolute (compounded) episode return > 0 (cash=0)?
epi<- fread(file.path(dd,"episodes.csv"))
cat("\n=== Episode market depth (compounded market_fwd over decline months) ===\n")
ymseq<-function(a,b){ai<-as.integer(substr(a,1,4))*12+as.integer(substr(a,6,7));bi<-as.integer(substr(b,1,4))*12+as.integer(substr(b,6,7))
  sapply(ai:bi,function(x){y<-(x-1)%/%12;m<-(x-1)%%12+1;sprintf("%04d-%02d",y,m)})}
mkv<-setNames(mkt$market_fwd,mkt$ym)
for(i in seq_len(nrow(epi))){
  ms<-ymseq(epi$peak_ym[i],epi$trough_ym[i])[-1]
  cum<-prod(1+mkv[ms])-1
  cat(sprintf("%-20s market_cum=%.3f (n=%d)\n", epi$name[i], cum, length(ms)))
}
cat("\nDONE\n")
