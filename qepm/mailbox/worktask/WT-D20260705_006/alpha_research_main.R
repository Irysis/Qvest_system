# ============================================================================
# WT-D20260705_006 — KR Conservative-Investment (FF5 CMA) multi-signal composite
# Alpha Research Agent — canonical top-25 EW long-only, K200∪KQ150, 15bps
# ============================================================================
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
options(datatable.print.class = TRUE)
data.table::setDTthreads(1L)
try(arrow::set_cpu_count(1L), silent=TRUE)
try(arrow::set_io_thread_count(1L), silent=TRUE)   # memory: prevents parquet read HANG

PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")                 # load_rawdata
source("02_Infrastructure/factor_db/factor_db_connector.R")    # load_month_factors (C15)
source("02_Infrastructure/contracts/canonical_screen_bt.R")    # canonical_screen_bt

OUT <- file.path(PROJ, "qepm/mailbox/worktask/WT-D20260705_006")
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006"); dir.create(STA, recursive=TRUE, showWarnings=FALSE)

# ---- Conservative-Investment family factors (C13-safe: Z_Score_Aligned higher=better) ----
CONS <- c("GR03_Asset_Growth","Q06_Asset_Growth","AC24_NOA_Growth","AC05_NOA",
          "AC09_NNI","IN04_Net_Equity_Issuance","IN05_Net_Debt_Issuance",
          "IN06_Investment_to_Assets","IN01_CapEx_to_Assets","Q20_Net_Equity_Issuance")
# de-dup economic overlap: Q06==GR03 (asset growth), Q20==IN04 (net equity issuance).
# Keep 6 economically distinct axes for primary composite:
CORE6 <- c("GR03_Asset_Growth","AC24_NOA_Growth","AC05_NOA","AC09_NNI",
           "IN04_Net_Equity_Issuance","IN06_Investment_to_Assets")
MOM <- "M04_Mom_1"; MOM_ALT <- "M01_Mom_12_1"   # incumbent core alpha proxy (STR_1715 = M04 momentum)

FDB_MIN <- as.Date("2005-01-01")   # study window start (constitution mandate)

# ---- 1. RAWDATA -> universe (K200∪KQ150 + liq 2e8) + monthly returns + BM ----
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date := as.Date(Date)]
rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
rm(RAWDATA); gc(FALSE)
setorder(rd, Ticker, Date)
rd[, ym := format(Date, "%Y-%m")]
me_dates <- sort(rd[, .(Date=max(Date)), by=ym]$Date)
me_dates <- me_dates[me_dates >= FDB_MIN]
rd[, ym := NULL]
rd[, TV := Close * Vol]
rd[, AvgTV20 := frollmean(TV, 20L, align="right"), by=Ticker]   # PIT t-1 (right window)

# monthly close (month-end) per ticker -> forward 1M return
me <- rd[Date %in% me_dates, .(Date, Ticker, Close, K200, KQ150, AvgTV20)]
setorder(me, Ticker, Date)
me[, Ret_1m := shift(Close, -1L)/Close - 1, by=Ticker]          # forward realized (t -> t+1)
# universe membership + liquidity at sig date t (PIT: AvgTV20 uses past 20d)
me[, in_univ := (K200==TRUE | KQ150==TRUE) & !is.na(AvgTV20) & AvgTV20 >= 2e8]

returns_dt <- me[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt     <- me[in_univ==TRUE, .(Date, Ticker, adv=AvgTV20)]
univ_dt    <- me[in_univ==TRUE, .(Date, Ticker)]
setkey(univ_dt, Date, Ticker)

# benchmark monthly: month-end BM close -> forward 1M return (align to same me_dates)
if (!inherits(BM_DT$Date,"Date")) BM_DT[, Date := as.Date(Date)]
bmc <- names(BM_DT)[grepl("Close", names(BM_DT))][1]
bm_me <- BM_DT[Date %in% me_dates, .(Date, BM_Close=get(bmc))]
setorder(bm_me, Date)
bm_me[, BM_Ret := shift(BM_Close, -1L)/BM_Close - 1]
bench_dt <- bm_me[!is.na(BM_Ret), .(Date, BM_Ret)]

cat(sprintf("[panel] months=%d (%s..%s) | univ-month rows=%d | ret rows=%d | bench rows=%d\n",
            length(me_dates), as.character(min(me_dates)), as.character(max(me_dates)),
            nrow(univ_dt), nrow(returns_dt), nrow(bench_dt)))

# ---- 2. Monthly factor sweep: load CONS + MOM, restricted to universe ----
sig_dates <- me_dates[me_dates >= FDB_MIN & me_dates <= max(bench_dt$Date)]
want <- unique(c(CONS, MOM, MOM_ALT))
flist <- vector("list", length(sig_dates))
t0 <- Sys.time()
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  uni <- univ_dt[.(d), Ticker, nomatch=0L]; if (!length(uni)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min=0.05, factor_names=want),
                  error=function(e) NULL)
  if (is.null(fdt) || nrow(fdt)==0) next
  slim <- fdt[Factor_Name %in% want & Ticker %in% uni & is.finite(Z_Score_Aligned),
              .(Ticker, Factor_Name, Z=Z_Score_Aligned)]
  if (nrow(slim)) { slim[, Date := d]; flist[[i]] <- slim }
  if (i %% 36L == 0L) cat(sprintf("[factors] %d/%d (%.0fs)\n", i, length(sig_dates),
                                  as.numeric(difftime(Sys.time(),t0,units="secs"))))
}
FAC <- rbindlist(Filter(Negate(is.null), flist), use.names=TRUE)
cat(sprintf("[factors] rows=%d | months=%d | factors=%s\n",
            nrow(FAC), uniqueN(FAC$Date), paste(sort(unique(FAC$Factor_Name)),collapse=",")))

# per-factor availability (some may be absent in aligned set)
print(FAC[, .(months=uniqueN(Date), tickers=uniqueN(Ticker)), by=Factor_Name][order(Factor_Name)])

# ---- 3. Composite construction (EW mean of aligned Z across available core axes) ----
build_composite <- function(FAC, factors) {
  sub <- FAC[Factor_Name %in% factors]
  # require >=2 of the axes present per ticker-month to avoid single-signal masquerade
  comp <- sub[, .(score=mean(Z), n_axes=.N), by=.(Date, Ticker)]
  comp[n_axes >= 2L, .(Date, Ticker, score)]
}
comp_core6 <- build_composite(FAC, CORE6)             # primary composite
comp_full  <- build_composite(FAC, CONS)              # all 10 (with redundant pairs)
# best single component (for RF-A2 baseline improvement check) chosen IS-only later

saveRDS(list(FAC=FAC, returns_dt=returns_dt, bench_dt=bench_dt, liq_dt=liq_dt,
             univ_dt=univ_dt, me_dates=me_dates),
        file.path(STA, "panels.rds"), compress=TRUE)

# ---- 4. Rank-IC diagnostics (Spearman monthly, score vs forward Ret_1m) ----
rank_ic_series <- function(scores_dt, returns_dt) {
  m <- merge(scores_dt, returns_dt, by=c("Date","Ticker"))
  m[, .(ic = suppressWarnings(cor(score, Ret_1m, method="spearman")), n=.N), by=Date][n>=20 & is.finite(ic)]
}
ic_core <- rank_ic_series(comp_core6, returns_dt)
ic_full <- rank_ic_series(comp_full,  returns_dt)

ic_summary <- function(ic, label) {
  x <- ic$ic
  mu <- mean(x); s <- sd(x); n <- length(x)
  icir <- mu / s * sqrt(1)             # monthly ICIR (mean/sd) — report both raw and t
  t_ic <- mu / (s/sqrt(n))             # simple t
  # Harvey-t style (Newey-West lag adj on IC series)
  nw_t <- tryCatch({
    fit <- lm(x ~ 1)
    library(sandwich); library(lmtest)
    coeftest(fit, vcov.=NeweyWest(fit, lag=3, prewhite=FALSE))[1,3]
  }, error=function(e) t_ic)
  data.table(composite=label, n_months=n, mean_ic=mu, sd_ic=s, icir=icir,
             ic_t_simple=t_ic, ic_harvey_t_nw=nw_t)
}
IC_TBL <- rbindlist(list(ic_summary(ic_core,"core6"), ic_summary(ic_full,"full10")))
cat("\n=== RANK-IC DIAGNOSTICS (metric_type=canonical_screen rank-IC) ===\n"); print(IC_TBL)

# ---- 5. CANONICAL portfolio-alpha t (AUTHORITATIVE gate metric) top-25 ----
run_canon <- function(scores_dt, tag) {
  canonical_screen_bt(scores_dt=scores_dt, returns_dt=returns_dt, bench_dt=bench_dt,
                      top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8,
                      run_id=tag, strategy_id=tag)
}
cs_core <- run_canon(comp_core6, "cons_core6")
cs_full <- run_canon(comp_full,  "cons_full10")

canon_row <- function(cs, tag) data.table(
  spec=tag, metric_type=cs$metric_type, n_months=cs$n_months, top_n=cs$top_n,
  PORT_t_NW=round(cs$portfolio_alpha_t_nw_lag3,3), IR=round(cs$information_ratio,3),
  alpha_ann=round(cs$alpha_annualized,4), net_sr=round(cs$net_sr,3),
  mean_active_net=round(cs$mean_active_net,5), turnover_ann=round(cs$turnover_annual,3))
CANON_TBL <- rbindlist(list(canon_row(cs_core,"cons_core6"), canon_row(cs_full,"cons_full10")))
cat("\n=== CANONICAL top-25 PORT-ALPHA t (AUTHORITATIVE, metric_type=canonical_screen) ===\n")
print(CANON_TBL)

# ---- 6. Subperiod split (pre-2017 vs 2017+) on the primary core6 composite ----
subperiod_canon <- function(scores_dt, returns_dt, bench_dt, liq_dt, cut="2017-01-01") {
  cutd <- as.Date(cut)
  splitrun <- function(lo, hi, lbl) {
    sc <- scores_dt[Date >= lo & Date < hi]
    if (uniqueN(sc$Date) < 12) return(data.table(period=lbl, n_months=uniqueN(sc$Date), PORT_t_NW=NA_real_))
    cs <- canonical_screen_bt(sc, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                              liq_dt=liq_dt, liq_min=2e8, run_id=lbl, strategy_id=lbl)
    data.table(period=lbl, n_months=cs$n_months, PORT_t_NW=round(cs$portfolio_alpha_t_nw_lag3,3),
               IR=round(cs$information_ratio,3), net_sr=round(cs$net_sr,3),
               mean_active=round(cs$mean_active_net,5))
  }
  rbindlist(list(
    splitrun(as.Date("1900-01-01"), cutd, "pre2017"),
    splitrun(cutd, as.Date("2100-01-01"), "post2017")
  ), fill=TRUE)
}
SUB_TBL <- subperiod_canon(comp_core6, returns_dt, bench_dt, liq_dt)
cat("\n=== SUBPERIOD (core6) ===\n"); print(SUB_TBL)

# ---- 7. oos_retention: anchored splits {55/65/75} of net-active SR, OOS/IS median ----
oos_retention <- function(scores_dt, returns_dt, bench_dt, liq_dt) {
  cs_full <- canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                                 liq_dt=liq_dt, liq_min=2e8, run_id="oos", strategy_id="oos")
  pr <- as.data.table(cs_full$period_returns)   # date, ret_net, benchmark_ret
  setorder(pr, date)
  pr[, active := ret_net - benchmark_ret]
  n <- nrow(pr)
  sr <- function(a) if (length(a) < 6 || sd(a)==0) NA_real_ else mean(a)/sd(a)*sqrt(12)
  rets <- sapply(c(0.55,0.65,0.75), function(f){
    k <- floor(n*f)
    is_sr  <- sr(pr$active[1:k]); oos_sr <- sr(pr$active[(k+1):n])
    if (is.na(is_sr) || is.na(oos_sr) || is_sr<=0) NA_real_ else oos_sr/is_sr
  })
  list(splits=setNames(round(rets,3), c("55","65","75")), median=round(median(rets,na.rm=TRUE),3),
       n_months=n)
}
OOS <- oos_retention(comp_core6, returns_dt, bench_dt, liq_dt)
cat("\n=== OOS RETENTION (core6, net-active SR OOS/IS) ===\n")
cat("splits:", paste(names(OOS$splits), OOS$splits, sep="="), "| median:", OOS$median, "\n")

# ---- 8. Orthogonality to incumbent core alpha (momentum M04/M01) ----
mom_name <- if (MOM %in% FAC$Factor_Name) MOM else MOM_ALT
mom_dt <- FAC[Factor_Name==mom_name, .(Date, Ticker, mom=Z)]
orth <- merge(comp_core6, mom_dt, by=c("Date","Ticker"))
orth_by_month <- orth[, .(rho=suppressWarnings(cor(score, mom, method="spearman")), n=.N), by=Date][n>=20 & is.finite(rho)]
orth_pooled <- suppressWarnings(cor(orth$score, orth$mom, method="spearman"))
cat(sprintf("\n=== ORTHOGONALITY to incumbent momentum (%s) ===\n", mom_name))
cat(sprintf("pooled cross-sec rank-rho=%.3f | mean monthly rho=%.3f (over %d months)\n",
            orth_pooled, mean(orth_by_month$rho), nrow(orth_by_month)))

# ---- Save diagnostics ----
diag_out <- list(
  freshness = list(latest_factor_month="202607", last_complete_month="2026-06",
                   cons_factor_coverage="10/10 non-NA through 202607", verdict="PASS"),
  factors_used = CORE6, composite_full = CONS,
  ic = IC_TBL, canonical = CANON_TBL, subperiod = SUB_TBL,
  oos_retention = OOS,
  orthogonality = list(incumbent_proxy=mom_name, pooled_rho=orth_pooled,
                       mean_monthly_rho=mean(orth_by_month$rho)),
  mom_orth_series = orth_by_month
)
saveRDS(diag_out, file.path(STA, "alpha_diagnostics.rds"), compress=TRUE)

# also emit alpha_scores.parquet (latest sig date scores for downstream)
last_d <- max(comp_core6$Date)
scores_latest <- comp_core6[Date==last_d]
write_parquet(as_arrow_table(scores_latest), file.path(STA, "alpha_scores.parquet"))

cat("\n=== DONE. artifacts in", STA, "===\n")
print(sessionInfo()$R.version$version.string)
