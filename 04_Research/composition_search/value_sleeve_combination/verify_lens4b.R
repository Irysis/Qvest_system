# Lens 4b — off-by-one event evidence + correctly-aligned blend counterfactual
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})
setDTthreads(1)
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

M <- as.data.table(readRDS(file.path(OUTDIR, "aligned_series.rds")))

cat("==== [I] event evidence: known crash months ====\n")
ev <- M[realized_ym %in% c("2008-08","2008-09","2008-10","2008-11","2008-12",
                            "2020-01","2020-02","2020-03","2020-04","2020-05")]
print(ev[, .(realized_ym, book_ret = round(book_ret,4), value_ret = round(value_ret,4),
             bench_ret = round(bench_ret,4))])

cat("\n==== [J] corrected alignment: book row m+1 <-> value/bench row m ====\n")
n <- nrow(M)
C <- data.table(realized_ym = M$realized_ym[1:(n-1)],
                book_true   = M$book_ret[2:n],      # book label m+1 = true month m
                value_ret   = M$value_ret[1:(n-1)],
                bench_ret   = M$bench_ret[1:(n-1)])
cat(sprintf("n=%d  cor(value, book_true)=%.4f  (misaligned claim -0.0455)\n",
  nrow(C), cor(C$value_ret, C$book_true)))
cat(sprintf("cor(book_true, bench)=%.4f  (misaligned -0.0044)\n",
  cor(C$book_true, C$bench_ret)))

dts <- as.Date(paste0(C$realized_ym, "-01"))
bdt <- data.table(date = dts, benchmark_ret = C$bench_ret, benchmark_id = "BM")
mk <- function(x, tag) {
  xx <- xts(x, order.by = dts)
  sr <- as.numeric(SharpeRatio.annualized(xx, Rf=0))
  a <- table.AnnualizedReturns(xx, Rf=0, scale=12)
  cg <- as.numeric(a["Annualized Return",1]); md <- as.numeric(maxDrawdown(xx))
  pr <- data.table(date = dts, ret_net = x, frequency="monthly")
  bc <- build_benchmark_compare(pr, bdt, run_id="v", strategy_id=tag, annualization_factor=12)
  c(SR=sr, CAGR=cg, MDD=md, Calmar=cg/md,
    IR=bc[metric_name=="Information_Ratio", active_value][1],
    PORT_t=bc[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value][1])
}
bk_c <- mk(C$book_true, "book_true")
cat(sprintf("book(correct align): SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f IR=%.4f PORT_t=%.3f\n",
  bk_c["SR"], bk_c["CAGR"], bk_c["MDD"], bk_c["Calmar"], bk_c["IR"], bk_c["PORT_t"]))

ret_mat <- xts(cbind(book = C$book_true, value = C$value_ret), order.by = dts)
for (wv in c(0.05,0.10,0.15,0.20,0.30)) {
  rp <- Return.portfolio(ret_mat, weights = c(book=1-wv, value=wv),
                         rebalance_on="months", verbose=TRUE)
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  net <- rp$returns - xts(to*15/1e4, order.by=index(rp$returns))
  m <- mk(as.numeric(net), sprintf("cw%02d", wv*100))
  cat(sprintf("w=%.2f (correct): SR=%.4f dSR=%+.4f MDD=%.4f dMDD=%+.4f Calmar=%.4f IR=%.4f dIR=%+.4f\n",
    wv, m["SR"], m["SR"]-bk_c["SR"], m["MDD"], m["MDD"]-bk_c["MDD"],
    m["Calmar"], m["IR"], m["IR"]-bk_c["IR"]))
}
cat("DONE\n")
