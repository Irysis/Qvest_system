suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/backtest_result_contract.R")
DIR <- "04_Research/factor_rotation/fof_first_slice"
rp <- function(f) as.data.table(read_parquet(file.path(DIR, f)))
bench <- rp("kns_master_bench.parquet")[is.finite(BM_Ret)]

# flat one-way cost sweep, finer grid, both universes, to pin exact 2.95 breakeven
build_book <- function(univ) {
  sc  <- rp(sprintf("kns_scores_L2_%s.parquet", univ))
  ret <- rp(sprintf("kns_ret_%s.parquet", univ))[is.finite(Ret_1m)]
  liq <- rp(sprintf("kns_liq_%s.parquet", univ))
  sc  <- sc[Date <= max(ret$Date)]
  S <- merge(sc, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv)|adv>=2e8]; setorder(S, Date, -score)
  W <- S[, {n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
  W <- merge(W, ret[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"), all.x=TRUE)
  W[is.na(Ret_1m),Ret_1m:=0]
  dts <- sort(unique(W$Date))
  gross <- numeric(length(dts)); traded <- numeric(length(dts))
  prev <- data.table(Ticker=character(0), wp=numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date==dts[i]]; gross[i] <- sum(cur$w*cur$Ret_1m)
    m <- merge(cur[,.(Ticker,w)], prev, by="Ticker", all=TRUE)
    m[is.na(w),w:=0]; m[is.na(wp),wp:=0]; traded[i] <- sum(abs(m$w-m$wp))
    prev <- cur[,.(Ticker,wp=w)]
  }
  list(dts=dts, gross=gross, traded=traded)
}
pt_at <- function(bk, cb) {
  port <- data.table(date=bk$dts, ret_net = bk$gross - bk$traded*cb/1e4)
  pr <- merge(port, bench[,.(date=Date,benchmark_ret=BM_Ret)], by="date")
  bc <- build_benchmark_compare(data.table(date=pr$date,ret_net=pr$ret_net,frequency="monthly"),
        data.table(date=pr$date,benchmark_ret=pr$benchmark_ret,benchmark_id="B"),
        run_id="x",strategy_id="x",annualization_factor=12)
  as.numeric(bc[metric_name=="Portfolio_Alpha_t_NW_lag3",active_value][1])
}
for (u in c("allliq","allclean")) {
  bk <- build_book(u)
  grid <- seq(15,90,by=5)
  pts <- sapply(grid, function(c) pt_at(bk,c))
  # exact breakeven for 2.95 via linear interp
  be <- approx(pts, grid, xout=2.95)$y
  cat(sprintf("[%s] port_t vs oneway-bps:\n", u))
  print(data.table(bps=grid, port_t=round(pts,3)))
  cat(sprintf("  >> port_t=2.95 breakeven one-way cost = %.1f bps\n\n", be))
}
cat("SPREAD_BREAK_DONE\n")
