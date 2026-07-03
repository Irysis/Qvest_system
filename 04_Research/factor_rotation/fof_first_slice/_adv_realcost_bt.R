suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/backtest_result_contract.R")  # for build_benchmark_compare + .nw
DIR <- "04_Research/factor_rotation/fof_first_slice"
rp <- function(f) as.data.table(read_parquet(file.path(DIR, f)))
bench <- rp("kns_master_bench.parquet")[is.finite(BM_Ret)]

# Rebuild the book with per-name, AUM-dependent realistic cost, then route net-active series
# through build_benchmark_compare (contract, NW lag-3) for port_t. Not flat bps -> name-specific.
run_real <- function(univ, AUM, half_spread_bps=20, k_impact=10, exec_days=3) {
  sc  <- rp(sprintf("kns_scores_L2_%s.parquet", univ))
  ret <- rp(sprintf("kns_ret_%s.parquet", univ))[is.finite(Ret_1m)]
  liq <- rp(sprintf("kns_liq_%s.parquet", univ))
  sc  <- sc[Date <= max(ret$Date)]
  S <- merge(sc, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv)|adv>=2e8]
  setorder(S, Date, -score)
  W <- S[, {n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
  W <- merge(W, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  W <- merge(W, ret[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"), all.x=TRUE)
  W[is.na(Ret_1m), Ret_1m := 0]
  dts <- sort(unique(W$Date))
  gross <- numeric(length(dts)); costv <- numeric(length(dts))
  prev <- data.table(Ticker=character(0), wp=numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date==dts[i]]
    gross[i] <- sum(cur$w * cur$Ret_1m)
    m <- merge(cur[,.(Ticker,w,adv)], prev, by="Ticker", all=TRUE)
    m[is.na(w),w:=0]; m[is.na(wp),wp:=0]; m[, dw:=abs(w-wp)]
    # adv for names being sold that left the book (in prev but not cur): use prev-known adv? approx: skip impact (spread only)
    m[is.na(adv), impact_bps := half_spread_bps]  # no adv -> spread only (conservative low)
    m[!is.na(adv), part := (AUM*dw)/(adv*exec_days)]
    m[!is.na(adv), impact_bps := half_spread_bps + k_impact*sqrt(part)]
    costv[i] <- sum(m$dw * m$impact_bps/1e4)
    prev <- cur[,.(Ticker,wp=w)]
  }
  port <- data.table(date=dts, ret_net = gross - costv)
  pr <- merge(port, bench[,.(date=Date, benchmark_ret=BM_Ret)], by="date")
  prt <- data.table(date=pr$date, ret_net=pr$ret_net, frequency="monthly")
  brt <- data.table(date=pr$date, benchmark_ret=pr$benchmark_ret, benchmark_id="KOSPI200")
  bc <- build_benchmark_compare(prt, brt, run_id="real", strategy_id="real", annualization_factor=12)
  pt <- as.numeric(bc[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value][1])
  active <- pr$ret_net - pr$benchmark_ret
  sr <- mean(active)/sd(active)*sqrt(12)
  nav <- cumprod(1+pr$ret_net); n<-nrow(pr); cagr<-nav[n]^(12/n)-1
  mdd <- -min(nav/cummax(nav)-1); cal <- cagr/mdd
  data.table(universe=univ, AUM=AUM, port_t=round(pt,3), net_SR=round(sr,3),
             CAGR=round(cagr,4), MDD=round(mdd,4), calmar=round(cal,3))
}
res <- rbindlist(lapply(c(1e9,5e9,1e10,3e10), function(a) run_real("allliq", a)))
res <- rbind(res, rbindlist(lapply(c(1e9,5e9,1e10), function(a) run_real("allclean", a))))
print(res)
saveRDS(res, file.path(DIR,"_adv_realcost_bt.rds"))
cat("REALCOST_BT_DONE\n")
