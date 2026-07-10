# measure_dual_basis.R — WT-D20260710_002
# Dual-basis re-measurement of 8 cap-w-rejected standard factors.
# For each factor: canonical_screen_bt(top_n=25, 2e8, 15bps, diag_dual_basis=TRUE, size_dt)
#   -> cap-w PORT_t (HARD-basis authoritative screen) + EW-universe PORT_t/post2017_t/oos_approx (diag)
#      + cap-tier weight-share decomposition (MEGA/MID/OTHER).
# Selection authority = canonical PORT_t (cap-w). EW-basis is diagnostic (re-routing label, not capital).

suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite) })
setDTthreads(1)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
PROJECT_ROOT <- ROOT; CACHE_DIR <- file.path(ROOT, ".cache"); FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P   <- file.path(ROOT, "stage_artifacts/WT-D20260710_002/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_002")

feat  <- as.data.table(read_parquet(file.path(P, "features_monthly.parquet")))
ret   <- as.data.table(read_parquet(file.path(P, "returns_monthly.parquet")))[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench <- as.data.table(read_parquet(file.path(P, "benchmark_monthly.parquet")))[, .(Date=as.Date(Date), BM_Ret)]
uf    <- as.data.table(read_parquet(file.path(P, "universe_flags.parquet")))
size  <- as.data.table(read_parquet(file.path(P, "size_monthly.parquet")))[, .(Date=as.Date(Date), Ticker, Size)]
feat[, Date := as.Date(Date)]; uf[, Date := as.Date(Date)]
liq_dt <- uf[, .(Date, Ticker, adv = adv20)]

# ── CRITICAL universe restriction (measurement-integrity fix) ──────────────────
# features_monthly = full factor-DB universe (~1772 names/mo, whole KR market).
# Mandate universe = KOSPI200 U KOSDAQ150 (in_univ) = ~350 names/mo (returns_monthly).
# Without restriction, canonical top-25 draws micro-caps outside universe whose
# forward Ret_1m is 0-filled -> artificial negative drag (uniform spurious PORT_t ~ -2.5,
# cap-tier UNRANKED ~0.9). Restrict scores to tradable in-universe names (present in
# returns_monthly = in_univ & has forward return). This is the mandate universe anyway.
univ_keys <- ret[, .(Date, Ticker)]
feat <- merge(feat, univ_keys, by = c("Date","Ticker"))
cat(sprintf("[measure] features restricted to K200uKQ150 universe: %d rows / %d months\n",
    nrow(feat), uniqueN(feat$Date)))

FEATURES <- c("V02_EP","V12_Composite_Value","V10_FCF_Yield",
              "Q01_GPA","Q08_Composite_Quality",
              "M08_Residual_Mom","M09_Composite_Mom","R12_Idiosyncratic_Risk")

# NW lag-3 t of a monthly active series (subperiod helper)
nw_t <- function(a, dates, from=NULL, to=NULL, lag=3L) {
  dd <- data.table(d=as.Date(dates), a=a)
  if (!is.null(from)) dd <- dd[d >= as.Date(from)]
  if (!is.null(to))   dd <- dd[d <  as.Date(to)]
  dd <- dd[is.finite(a)]
  if (nrow(dd) < 12L) return(NA_real_)
  f <- lm(a ~ 1, data=dd)
  as.numeric(lmtest::coeftest(f, vcov=sandwich::NeweyWest(f, lag=lag, prewhite=FALSE))[1,3])
}
sr12 <- function(a) { a <- a[is.finite(a)]; if (length(a)<6) return(NA_real_); s<-sd(a); if (!is.finite(s)||s<=0) return(NA_real_); mean(a)/s*sqrt(12) }

res <- list()
for (fac in FEATURES) {
  cat("=== ", fac, " ===\n")
  sc <- feat[!is.na(get(fac)), .(Date, Ticker, score = get(fac))]
  cs <- canonical_screen_bt(scores_dt = sc, returns_dt = ret, bench_dt = bench,
                            top_n = 25L, cost_bps_oneway = 15,
                            liq_dt = liq_dt, liq_min = 2e8,
                            run_id = paste0("WT002_", fac), strategy_id = fac,
                            periods_per_year = 12L,
                            diag_dual_basis = TRUE, size_dt = size)
  pr <- as.data.table(cs$period_returns); pr[, date := as.Date(date)]; setorder(pr, date)
  capw_act <- pr$ret_net - pr$benchmark_ret
  capw_post2017_t <- nw_t(capw_act, pr$date, from="2017-01-01")
  capw_pre2017_t  <- nw_t(capw_act, pr$date, to="2017-01-01")

  d  <- cs$diag_ew_universe
  ct <- cs$diag_cap_tier
  ws <- if (!is.null(ct$available) && isTRUE(ct$available)) ct$weight_share_avg else list()
  cg <- if (!is.null(ct$available) && isTRUE(ct$available)) ct$contrib_gross_annualized else list()

  res[[fac]] <- list(
    factor = fac,
    n_months = cs$n_months,
    # cap-w HARD-basis (authoritative screen)
    capw_port_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
    capw_port_t_pvalue  = cs$portfolio_alpha_t_pvalue,
    capw_IR             = cs$information_ratio,
    capw_alpha_annual   = cs$alpha_annualized,
    capw_net_sr         = cs$net_sr,
    capw_mean_active_net= cs$mean_active_net,
    capw_turnover_annual= cs$turnover_annual,
    capw_pre2017_t      = capw_pre2017_t,
    capw_post2017_t     = capw_post2017_t,
    # EW-universe basis (diagnostic — re-routing label, non-binding)
    ew_port_t_nw_lag3   = d$portfolio_alpha_t_nw_lag3,
    ew_port_t_pvalue    = d$portfolio_alpha_t_pvalue,
    ew_IR               = d$information_ratio,
    ew_net_sr           = d$net_sr,
    ew_post2017_t       = d$post2017_t_nw_lag3,
    ew_oos_retention_approx = d$oos_retention_approx,
    ew_n_months         = d$n_months,
    # cap-tier weight share (avg) + annualized gross contribution
    tier_wshare_MEGA = ws$MEGA %||% NA_real_,
    tier_wshare_MID  = ws$MID  %||% NA_real_,
    tier_wshare_OTHER= ws$OTHER%||% NA_real_,
    tier_wshare_UNRANKED = ws$UNRANKED %||% NA_real_,
    tier_contrib_ann_MEGA = cg$MEGA %||% NA_real_,
    tier_contrib_ann_MID  = cg$MID  %||% NA_real_,
    tier_contrib_ann_OTHER= cg$OTHER%||% NA_real_
  )
  cat(sprintf("  cap-w PORT_t=%+.2f (pre17 %+.2f / post17 %+.2f) | EW PORT_t=%+.2f (post17 %+.2f, oos~%.2f) | tierW MEGA/MID/OTH=%.2f/%.2f/%.2f\n",
    res[[fac]]$capw_port_t_nw_lag3 %||% NA, capw_pre2017_t %||% NA, capw_post2017_t %||% NA,
    res[[fac]]$ew_port_t_nw_lag3 %||% NA, res[[fac]]$ew_post2017_t %||% NA, res[[fac]]$ew_oos_retention_approx %||% NA,
    res[[fac]]$tier_wshare_MEGA %||% NA, res[[fac]]$tier_wshare_MID %||% NA, res[[fac]]$tier_wshare_OTHER %||% NA))
}

tab <- rbindlist(lapply(res, function(x) as.data.table(x)), fill = TRUE)
fwrite(tab, file.path(OUT, "dual_basis_table.csv"))
write_json(res, file.path(OUT, "dual_basis_raw.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("\nDUAL_BASIS_DONE — rows:", nrow(tab), "\n")
