# Optimizer walk-forward comparison — WT-D20260706_MIDCAP
# Role: weights ONLY. Uses alpha_hat (tierEmph_B) + score_eff from alpha panel; Sigma from risk snapshot.
# Contract-grade measurement: build_benchmark_compare (NW lag-3), NO self-synthesis.
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
try(arrow::set_cpu_count(1), silent=TRUE)
options(stringsAsFactors=FALSE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
DIR  <- file.path(ROOT, "stage_artifacts/WT_D20260706_MIDCAP")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

# ---- Load alpha panel (full 268-month time series) ----
ap <- as.data.table(arrow::read_parquet(file.path(DIR, "alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
# alpha_hat = tierEmph_B (authoritative alpha signal). score_eff = base.

# ---- Benchmark: pinned IKS200 daily -> monthly compounded, aligned to alpha sig grid ----
bd <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/benchmark_pin20260703.parquet")))
bd[, Date := as.Date(Date)]
bd[, ym := format(Date, "%Y-%m")]
# monthly total return = prod(1+daily)-1 is benchmark aggregation (index construction, allowed:
#   this is the benchmark series itself, not a strategy return synthesis)
bm_m <- bd[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = ym]
# alpha Date is first-of-month sig_date; Ret_1m is forward month(t+1) realized.
# Align benchmark forward month to the alpha sig_date: sig_date t -> benchmark of month t+1.
agrid <- sort(unique(ap$Date))
ym_of <- format(agrid, "%Y-%m")
# forward month ym for each sig grid date
fwd_ym <- format(seq(agrid[1], by="month", length.out=length(agrid)) + 40, "%Y-%m")  # approx next month
# robust: next-month ym = add 1 month
nextmonth <- function(d){ as.Date(format(seq(d, by="month", length.out=2)[2], "%Y-%m-01")) }
fwd_ym <- sapply(agrid, function(d) format(nextmonth(d), "%Y-%m"))
bench_dt <- data.table(Date = agrid, ym_fwd = fwd_ym)
bench_dt <- merge(bench_dt, bm_m, by.x="ym_fwd", by.y="ym", all.x=TRUE)
bench_dt <- bench_dt[, .(Date, BM_Ret)][order(Date)]

# ---- Risk snapshot (as_of covariance, 24 names) ----
cov <- as.data.table(arrow::read_parquet(file.path(DIR, "covariance.parquet")))
cov_names <- cov$Ticker
Sig <- as.matrix(cov[, ..cov_names]); rownames(Sig) <- cov_names

# ---- Helper: measure a weighted schedule via contract (NW lag-3), NO synthesis ----
measure_sched <- function(W, id) {
  # W: data.table(Date, Ticker, w) ; sum(w)=1 per Date
  R <- ap[, .(Date, Ticker, Ret_1m)]
  WR <- merge(W, R, by=c("Date","Ticker"), all.x=TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w*Ret_1m)), by=Date][order(Date)]
  # turnover
  dts <- sort(unique(W$Date)); traded <- setNames(numeric(length(dts)), as.character(dts))
  prev <- data.table(Ticker=character(0), w=numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date==dts[i], .(Ticker,w)]
    m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_c","_p"))
    m[is.na(w_c),w_c:=0]; m[is.na(w_p),w_p:=0]
    traded[i] <- sum(abs(m$w_c-m$w_p)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded*15/1e4]
  port[, ret_net := port_gross - cost]
  pr <- merge(port[,.(date=Date,ret_net)], bench_dt[,.(date=Date,benchmark_ret=BM_Ret)], by="date")
  pr <- pr[!is.na(benchmark_ret)]
  prt <- data.table(date=pr$date, ret_net=pr$ret_net, frequency="monthly")
  brt <- data.table(date=pr$date, benchmark_ret=pr$benchmark_ret, benchmark_id="IKS200")
  bc <- build_benchmark_compare(prt, brt, run_id=id, strategy_id=id, annualization_factor=12)
  gv <- function(nm){v<-bc[metric_name==nm,active_value]; if(length(v))as.numeric(v[1]) else NA_real_}
  active <- pr$ret_net - pr$benchmark_ret
  te <- sd(active)*sqrt(12)
  list(id=id, n=nrow(pr),
       port_t = gv("Portfolio_Alpha_t_NW_lag3"),
       ir = gv("Information_Ratio"),
       alpha_ann = gv("Alpha_Annualized"),
       te = te,
       net_sr = mean(active)/sd(active)*sqrt(12),
       turnover = mean(port$traded,na.rm=TRUE)*12,
       pr = pr)
}

# ---- Build per-period weight schedules from alpha_hat (top-25 by alpha_hat each month) ----
# selection: top-25 by alpha_hat within liquid universe (alpha panel already liquidity-screened upstream)
setorder(ap, Date, -alpha_hat)
top25 <- ap[, .SD[seq_len(min(25,.N))], by=Date]

# Scheme 1: EW (baseline — matches alpha tierEmph_B canonical)
W_ew <- top25[, .(Ticker, w=1/.N), by=Date]

# Scheme 2: alpha-proportional tilt (positive-shifted alpha_hat, capped [0,0.20], normalized)
mk_prop <- function(dt, powr=1){
  dt[, {
    a <- alpha_hat - min(alpha_hat) + 1e-6
    a <- a^powr
    w <- a/sum(a)
    # cap 0.20 with iterative redistribution
    for (it in 1:200){ over <- w>0.20; if(!any(over)) break
      excess <- sum(w[over]-0.20); w[over]<-0.20
      und <- !over & w>0; if(!any(und)) break
      w[und] <- w[und] + excess*w[und]/sum(w[und]) }
    .(Ticker=Ticker, w=w/sum(w))
  }, by=Date]
}
W_prop <- mk_prop(copy(top25), 1)

# Scheme 3: mega-cap anchor (discovered lever): pin top-2 by market cap (lowest size_rank) at 0.20 each,
#   fill remaining 0.60 alpha-proportional among the rest. Tests cap-w bench tracking bridge.
mk_anchor <- function(dt){
  dt[, {
    ord <- order(size_rank)  # size_rank 1 = biggest
    tick <- Ticker; a <- alpha_hat
    n <- length(tick)
    w <- rep(0, n)
    anchor_idx <- ord[seq_len(min(2,n))]
    w[anchor_idx] <- 0.20
    rest <- setdiff(seq_len(n), anchor_idx)
    ar <- a[rest]-min(a[rest])+1e-6; wr <- ar/sum(ar)*0.60
    # cap rest at 0.20
    for (it in 1:200){ over<-wr>0.20; if(!any(over))break; ex<-sum(wr[over]-0.20); wr[over]<-0.20
      und<-!over&wr>0; if(!any(und))break; wr[und]<-wr[und]+ex*wr[und]/sum(wr[und]) }
    w[rest] <- wr
    .(Ticker=tick, w=w/sum(w))
  }, by=Date]
}
W_anchor <- mk_anchor(copy(top25))

# Scheme 4: inverse-vol tilt on selected (uses per-name specific_sd proxy from full-panel vol)
# per-period realized vol not available cross-section cheaply; use alpha panel Ret_1m rolling sd as proxy
vol_tbl <- ap[, .(Date, Ticker, Ret_1m)][order(Ticker, Date)]
vol_tbl[, rv := frollapply(Ret_1m, 24, sd, align="right"), by=Ticker]
top25v <- merge(top25, vol_tbl[,.(Date,Ticker,rv)], by=c("Date","Ticker"), all.x=TRUE)
top25v[is.na(rv)|rv<=0, rv := median(top25v$rv, na.rm=TRUE)]
W_ivol <- top25v[, {
  iv <- 1/rv; w <- iv/sum(iv)
  for (it in 1:200){ over<-w>0.20; if(!any(over))break; ex<-sum(w[over]-0.20); w[over]<-0.20
    und<-!over&w>0; if(!any(und))break; w[und]<-w[und]+ex*w[und]/sum(w[und]) }
  .(Ticker=Ticker, w=w/sum(w))
}, by=Date]

# ---- Measure all schemes ----
res <- list(
  EW      = measure_sched(W_ew,     "EW_top25"),
  PROP    = measure_sched(W_prop,   "alpha_prop"),
  ANCHOR  = measure_sched(W_anchor, "megacap_anchor"),
  IVOL    = measure_sched(W_ivol,   "inv_vol")
)

cat("=== FULL PERIOD (vs cap-w IKS200) ===\n")
cat(sprintf("%-16s %6s %7s %6s %6s %7s %7s\n","method","n","port_t","IR","TE","netSR","turn"))
for (k in names(res)){ r<-res[[k]]
  cat(sprintf("%-16s %6d %7.3f %6.3f %6.3f %7.3f %7.2f\n", r$id, r$n, r$port_t, r$ir, r$te, r$net_sr, r$turnover)) }

# ---- POST-2017 subperiod (the binding cap-tier trap window) ----
cat("\n=== POST-2017 (2017-01+, vs cap-w IKS200) ===\n")
cat(sprintf("%-16s %6s %7s %6s %6s\n","method","n","port_t","IR","netSR"))
post_t <- function(pr){ p<-pr[date>=as.Date("2017-01-01")]; a<-p$ret_net-p$benchmark_ret
  list(n=nrow(p), t=mean(a)/sd(a)*sqrt(length(a)), ir=mean(a)/sd(a)*sqrt(12), sr=mean(a)/sd(a)*sqrt(12)) }
for (k in names(res)){ r<-res[[k]]; pt<-post_t(r$pr)
  cat(sprintf("%-16s %6d %7.3f %6.3f %6.3f\n", r$id, pt$n, pt$t, pt$ir, pt$sr)) }

# ---- oos_v2 retention (anchored 3-split median) on best method ----
oos_v2 <- function(pr){
  a <- pr$ret_net - pr$benchmark_ret; n <- length(a)
  cuts <- floor(n*c(0.55,0.65,0.75))
  rets <- sapply(cuts, function(c){
    is_sr <- mean(a[1:c])/sd(a[1:c])*sqrt(12)
    oos <- a[(c+1):n]; oos_sr <- mean(oos)/sd(oos)*sqrt(12)
    if (abs(is_sr)<1e-9) NA else oos_sr/is_sr })
  median(rets, na.rm=TRUE)
}
cat("\n=== oos_v2 retention (vs cap-w) ===\n")
for (k in names(res)) cat(sprintf("%-16s oos_v2=%.3f\n", res[[k]]$id, oos_v2(res[[k]]$pr)))

saveRDS(res, file.path(DIR, "_opt_wf_res.rds"))
cat("\n[done]\n")
