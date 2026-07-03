#==============================================================================
# M36 audit: orthogonality vs INV09/INV01/INV03/INV08/INV10/M01/M08/M24
#            + decile concentration profile (the C23/C24 lesson)
#            + rank-IC / ICIR / Harvey-t (advisory) + oos_retention + calmar
#==============================================================================
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L)
Sys.setenv(OMP_NUM_THREADS = "1", ARROW_NUM_THREADS = "1")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||all(is.na(a))) b else a

ROOT   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(ROOT, "stage_artifacts", "WT-D20260621_007")
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

LOG <- file.path(OUTDIR, "audit_log.txt"); cat("", file = LOG)
logf <- function(...) { cat(..., "\n", file = LOG, append = TRUE); cat(..., "\n") }

P  <- readRDS(file.path(OUTDIR, "_panels.rds"))
sig_dates  <- P$sig_dates
returns_dt <- P$returns_dt
scores <- as.data.table(arrow::read_parquet(file.path(OUTDIR, "alpha_scores.parquet")))  # PRIMARY MAG_RUN
setnames(scores, "score", "m36")

#------------------------------------------------------------------------------
# 1. Orthogonality — load comparator factors at each sig_date, monthly Spearman
#------------------------------------------------------------------------------
comparators <- c("INV09_Flow_Persistence","INV01_Foreign_NetBuy_20d","INV03_Inst_NetBuy_20d",
                 "INV08_Foreign_Inst_Agreement","INV10_Smart_Money_Flow",
                 "M01_Mom_12_1","M08_Residual_Mom","M24_Sector_Rel_Mom")
logf("[1] Orthogonality audit over", length(unique(scores$Date)), "sig_dates ...")

mcorr <- list()  # per (factor, date) spearman
sig_use <- sort(unique(scores$Date))
for (sd_i in sig_use) {
  fac <- tryCatch(load_month_factors(as.Date(sd_i), factor_names = comparators),
                  error = function(e) NULL)
  if (is.null(fac) || nrow(fac) == 0) next
  m36_d <- scores[Date == sd_i, .(Ticker, m36)]
  if (nrow(m36_d) < 30) next
  for (cf in comparators) {
    fc <- fac[Factor_Name == cf, .(Ticker, z = Z_Score_Aligned)]
    if (nrow(fc) < 30) next
    mm <- merge(m36_d, fc, by = "Ticker")
    if (nrow(mm) < 30) next
    rho <- suppressWarnings(cor(mm$m36, mm$z, method = "spearman", use = "complete.obs"))
    mcorr[[length(mcorr)+1]] <- data.table(Date = as.Date(sd_i), factor = cf, rho = rho, n = nrow(mm))
  }
}
mcorr <- rbindlist(mcorr)
ortho <- mcorr[, .(median_spearman = median(rho, na.rm = TRUE),
                   mean_spearman   = mean(rho, na.rm = TRUE),
                   q25 = quantile(rho, .25, na.rm = TRUE),
                   q75 = quantile(rho, .75, na.rm = TRUE),
                   n_months = .N), by = factor]
setorder(ortho, -median_spearman)
logf("[1] Orthogonality (monthly-median Spearman, authoritative):")
for (i in seq_len(nrow(ortho))) {
  logf(sprintf("    %-30s median=%+.3f mean=%+.3f [q25 %+.3f, q75 %+.3f] n=%d",
       ortho$factor[i], ortho$median_spearman[i], ortho$mean_spearman[i],
       ortho$q25[i], ortho$q75[i], ortho$n_months[i]))
}
fwrite(ortho, file.path(OUTDIR, "orthogonality.csv"))

#------------------------------------------------------------------------------
# 2. Decile concentration (C23/C24 lesson) — for PRIMARY MAG_RUN score
#    Decile EW forward return (gross & active vs BM), D10-D9 gap, top-decile t.
#------------------------------------------------------------------------------
logf("[2] Decile concentration profile (PRIMARY MAG_RUN) ...")
dec <- merge(scores, returns_dt, by = c("Date","Ticker"))
bench_dt <- P$bench_dt
dec <- merge(dec, bench_dt, by = "Date", all.x = TRUE)
dec[, active := Ret_1m - BM_Ret]
dec[, decile := {
      r <- frank(m36, ties.method = "first")
      cut(r, breaks = quantile(r, probs = seq(0,1,.1), na.rm=TRUE),
          include.lowest = TRUE, labels = 1:10)
    }, by = Date]
dec <- dec[!is.na(decile)]
dec[, decile := as.integer(as.character(decile))]
# per decile per month mean, then time-series
dmon <- dec[, .(ret = mean(Ret_1m, na.rm=TRUE), act = mean(active, na.rm=TRUE)), by = .(Date, decile)]
dprof <- dmon[, .(mean_ret = mean(ret), mean_active = mean(act),
                  active_t = mean(act)/ (sd(act)/sqrt(.N)),  # naive t (advisory)
                  n = .N), by = decile][order(decile)]
logf("[2] Decile forward-return profile (gross mean, active mean, active t):")
for (i in seq_len(nrow(dprof))) {
  logf(sprintf("    D%-2d  ret=%+.4f  active=%+.4f  active_t=%+.2f", dprof$decile[i],
       dprof$mean_ret[i], dprof$mean_active[i], dprof$active_t[i]))
}
d10 <- dprof[decile==10]; d9 <- dprof[decile==9]; d1 <- dprof[decile==1]
logf(sprintf("[2] D10-D9 active gap = %+.4f ; D10-D1 spread = %+.4f ; top-decile active_t = %+.2f",
     d10$mean_active - d9$mean_active, d10$mean_active - d1$mean_active, d10$active_t))
fwrite(dprof, file.path(OUTDIR, "decile_profile.csv"))

#------------------------------------------------------------------------------
# 3. rank-IC / ICIR / Harvey-t (advisory) on PRIMARY
#------------------------------------------------------------------------------
ic_mon <- dec[, .(ic = suppressWarnings(cor(m36, Ret_1m, method="spearman", use="complete.obs"))), by = Date]
ic_mon <- ic_mon[!is.na(ic)]
rank_ic <- mean(ic_mon$ic); ic_sd <- sd(ic_mon$ic); icir <- rank_ic / ic_sd
nmo <- nrow(ic_mon)
# Newey-West Harvey-t (lag 3) on the IC series
nw_t <- function(x, lag=3) {
  x <- x[!is.na(x)]; n <- length(x); mu <- mean(x); e <- x - mu
  g0 <- sum(e^2)/n; v <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*w*gl }
  se <- sqrt(v/n); mu/se
}
harvey_t <- nw_t(ic_mon$ic, 3)
logf(sprintf("[3] rank-IC=%.4f  ICIR=%.3f  Harvey-t(NW3)=%.2f  n_months=%d (ADVISORY per measurement-graduation §3)",
     rank_ic, icir, harvey_t, nmo))

#------------------------------------------------------------------------------
# 4. oos_retention (anchored 3-split median) + calmar — on PRIMARY net active series
#    (canonical_screen period_returns net active)
#------------------------------------------------------------------------------
R <- readRDS(file.path(OUTDIR, "_screen_results.rds"))
prim <- R[["MAG_cap10_eps1e8_z_n20_PRIMARY"]]
pr <- as.data.table(prim$period_returns)  # date, ret_net, benchmark_ret
pr[, active := ret_net - benchmark_ret]
sr_of <- function(a) if (length(a) < 6 || sd(a)==0) NA_real_ else mean(a)/sd(a)*sqrt(12)
# anchored splits 55/65/75
splits <- c(.55,.65,.75); rets <- numeric(0)
n <- nrow(pr)
oos_vals <- sapply(splits, function(p){
  k <- floor(n*p); is_sr <- sr_of(pr$active[1:k]); oos_sr <- sr_of(pr$active[(k+1):n])
  if (is.na(is_sr)||is.na(oos_sr)||is_sr<=0) return(NA_real_)
  oos_sr/is_sr
})
oos_retention <- median(oos_vals, na.rm=TRUE)
# calmar on NET nav (not active): use ret_net cumulative
nav <- cumprod(1 + pr$ret_net)
peak <- cummax(nav); dd <- nav/peak - 1; mdd <- -min(dd)
cagr <- nav[length(nav)]^(12/n) - 1
calmar <- cagr / mdd
net_sr_active <- sr_of(pr$active)
logf(sprintf("[4] PRIMARY net active SR=%.3f  oos_retention(median 55/65/75)=%.3f  calmar=%.3f (CAGR %.3f / MDD %.3f)",
     net_sr_active, oos_retention, calmar, cagr, mdd))
logf(sprintf("    PORT_t_NW3=%.2f  IR=%.3f  turnover_annual=%.2f",
     prim$portfolio_alpha_t_nw_lag3 %||% NA, prim$information_ratio %||% NA, prim$turnover_annual %||% NA))

#------------------------------------------------------------------------------
# 5. Save audit summary
#------------------------------------------------------------------------------
audit <- list(
  orthogonality = ortho,
  inv09_median_spearman = ortho[factor=="INV09_Flow_Persistence", median_spearman],
  decile_profile = dprof,
  d10_d9_active_gap = d10$mean_active - d9$mean_active,
  top_decile_active_t = d10$active_t,
  rank_ic = rank_ic, icir = icir, harvey_t = harvey_t, n_months = nmo,
  primary_port_t = prim$portfolio_alpha_t_nw_lag3,
  primary_ir = prim$information_ratio,
  primary_net_sr_active = net_sr_active,
  primary_turnover_annual = prim$turnover_annual,
  oos_retention = oos_retention, calmar = calmar, cagr = cagr, mdd = mdd
)
saveRDS(audit, file.path(OUTDIR, "_audit.rds"))
logf("[5] Audit complete.")
