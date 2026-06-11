# Lens 4c — rebuild value sleeve month realized 2026-05 + reconcile SR/IR window gap
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
})
setDTthreads(1)
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE <- file.path(PROJECT_ROOT, ".cache")
VS_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_WT-D20260611_001_value_sleeve")
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")
TOP_N <- 20L; COST_BPS <- 15; LIQ_MIN <- 2e8

scores <- as.data.table(read_parquet(file.path(VS_DIR, "scores_cache.parquet")))
raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2026-01-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)
me_dates <- raw[, .(eom = max(Date)), by = ym]; setorder(me_dates, ym)

# May 2026 per-ticker monthly return
mret_may <- raw[ym == "202605" & !is.na(Ret), .(mret = prod(1+Ret)-1, nd=.N), by=Ticker][nd>=5]
# liquidity + flags at 2026-04 month-end
raw[, tv := Vol*Close]; raw[, adv20 := frollmean(tv,20,align="right"), by=Ticker]
eom_apr <- me_dates[ym=="202604", eom]
liq_apr <- raw[Date == eom_apr, .(Ticker, adv20,
  bad=(AdminStock %in% 1)|(TradingHalt %in% 1)|(UnfaithfulDisc %in% 1))]
liq_apr[is.na(bad), bad := FALSE]

pick <- function(ymtag, liq) {
  s <- scores[ym==ymtag & !is.na(score)]
  s <- merge(s, liq[bad==FALSE, .(Ticker, adv=adv20)], by="Ticker", all.x=TRUE)
  s <- s[is.na(adv) | adv >= LIQ_MIN]
  setorder(s, -score)
  s[seq_len(min(TOP_N,.N)), Ticker]
}
# holdings for sig 202604 (earn May) and sig 202603 (earn Apr; for turnover cost)
eom_mar <- me_dates[ym=="202603", eom]
liq_mar <- raw[Date == eom_mar, .(Ticker, adv20,
  bad=(AdminStock %in% 1)|(TradingHalt %in% 1)|(UnfaithfulDisc %in% 1))]
liq_mar[is.na(bad), bad := FALSE]
h_apr <- pick("202604", liq_apr)   # held during May 2026
h_mar <- pick("202603", liq_mar)   # held during Apr 2026
w_cur <- data.table(Ticker=h_apr, w=1/length(h_apr))
w_prev <- data.table(Ticker=h_mar, w=1/length(h_mar))
mm <- merge(w_cur, w_prev, by="Ticker", all=TRUE)
mm[is.na(w.x), w.x:=0]; mm[is.na(w.y), w.y:=0]
to <- sum(abs(mm$w.x - mm$w.y))
wr <- merge(w_cur, mret_may[, .(Ticker, mret)], by="Ticker", all.x=TRUE)
wr[is.na(mret), mret := 0]
gross <- sum(wr$w * wr$mret)
net_may <- gross - to*COST_BPS/1e4
cat(sprintf("value realized 2026-05: gross=%.4f TO=%.3f net=%.4f\n", gross, to, net_may))

bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y%m")]
bm_may <- bm[ym=="202605" & !is.na(BM_Ret), prod(1+BM_Ret)-1]
cat(sprintf("bench  realized 2026-05: %.4f\n", bm_may))

# reconcile: append to 248m aligned window -> 249m abs SR + IR
M <- as.data.table(readRDS(file.path(OUTDIR, "aligned_series.rds")))
v249 <- c(M$value_ret, net_may); b249 <- c(M$bench_ret, bm_may)
d249 <- c(as.Date(paste0(M$realized_ym,"-01")), as.Date("2026-05-01"))
vx <- xts(v249, order.by=d249)
cat(sprintf("value abs SR 249m=%.4f (json claim 0.4804)  248m=0.5308\n",
  as.numeric(SharpeRatio.annualized(vx, Rf=0))))
act <- v249 - b249
cat(sprintf("value IR 249m=%.4f (alpha_validation net_sr 0.375339)\n",
  mean(act)/sd(act)*sqrt(12)))
cat("DONE\n")
