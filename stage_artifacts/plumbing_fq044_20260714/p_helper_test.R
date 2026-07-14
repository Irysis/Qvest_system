## p_helper_test.R — align_signal_return_ym.R functional test (FQ-043)
## cases: (1) realized_month off+1 full coverage -> PASS
##        (2) coverage breach (92/255-style month loss) -> STOP
##        (3) realized_month off=0 (same-month look-ahead) -> STOP
##        (4) signal_anchor off=0 -> PASS ; (5) signal_anchor off=+1 -> STOP
suppressPackageStartupMessages({library(data.table)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/align_signal_return_ym.R")

## synthetic: 24 signal months (calendar month-end), 50 tickers
mes <- as.Date(sapply(seq(as.Date("2020-01-01"), by="month", length.out=24),
        function(d) as.character(seq(d, by="month", length.out=2)[2]-1)))
tk <- sprintf("T%03d", 1:50)
sig <- CJ(signal_date=mes, Ticker=tk); sig[, z := rnorm(.N)]
## realized-month returns: dated by the month the return was earned (= signal month + 1)
ret_re <- CJ(Date=as.Date(sapply(mes, function(d) as.character(seq(d+1, by="month", length.out=2)[2]-1))), Ticker=tk)
ret_re[, Ret_1m := rnorm(.N, 0, 0.05)]
## signal-anchor returns: dated by signal month-end (forward return embedded), TRADING month-end (2 days earlier -> ym same)
ret_an <- CJ(Date=mes-2, Ticker=tk); ret_an[, Ret_1m := rnorm(.N, 0, 0.05)]

ok <- function(tag, expr){ r <- tryCatch({expr; "PASS"}, error=function(e) paste0("STOP: ", substr(conditionMessage(e),1,80)))
  cat(sprintf("  [%s] %s\n", tag, r)); r }

cat("case1: realized_month off=+1 (expected PASS)\n")
r1 <- ok("c1", { m <- align_signal_return_ym(sig, ret_re, off=+1, return_dating="realized_month")
  stopifnot(attr(m,"align_coverage_month") == 1, "vintage_label" %in% names(m)) })

cat("case2: month-loss coverage breach (expected STOP <0.95)\n")
ret_holey <- ret_re[!format(Date,"%Y-%m") %in% format(as.Date(sapply(mes[seq(2,24,by=3)], function(d) as.character(seq(d+1,by="month",length.out=2)[2]-1)) ),"%Y-%m")]
r2 <- ok("c2", align_signal_return_ym(sig, ret_holey, off=+1, return_dating="realized_month"))

cat("case3: realized_month off=0 same-month look-ahead (expected STOP)\n")
r3 <- ok("c3", align_signal_return_ym(sig, ret_re, off=0, return_dating="realized_month"))

cat("case4: signal_anchor off=0, trading-vs-calendar month-end date mismatch (expected PASS — ym key absorbs; exact-Date would lose all)\n")
r4 <- ok("c4", { m <- align_signal_return_ym(sig, ret_an, off=0, return_dating="signal_anchor")
  stopifnot(attr(m,"align_coverage_month") == 1) })

cat("case5: signal_anchor off=+1 forward-anchor look-ahead (expected STOP)\n")
r5 <- ok("c5", align_signal_return_ym(sig, ret_an, off=+1, return_dating="signal_anchor"))

cat("case6: off missing (expected STOP — explicit off is mandatory)\n")
r6 <- ok("c6", align_signal_return_ym(sig, ret_re, return_dating="realized_month"))

verdict <- c(c1=r1, c2=r2, c3=r3, c4=r4, c5=r5, c6=r6)
expect_stop <- c(FALSE, TRUE, TRUE, FALSE, TRUE, TRUE)
got_stop <- grepl("^STOP", verdict)
cat(sprintf("\nHELPER_TEST %s (%d/6 as expected)\n",
    if(all(got_stop==expect_stop)) "ALL_PASS" else "MISMATCH", sum(got_stop==expect_stop)))
