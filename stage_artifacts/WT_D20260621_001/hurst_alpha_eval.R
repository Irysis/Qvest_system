#==============================================================================
# WT-D20260621_001 — Stage 2: A/B/C operationalization eval + orthogonality
#   + canonical_screen_bt (real-computation) + IC/ICIR/Harvey-t
#==============================================================================
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
           R_DATATABLE_NUM_THREADS="1")
suppressMessages({ library(data.table); library(jsonlite) })
setDTthreads(1L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A <- file.path(ROOT, "stage_artifacts", "WT_D20260621_001")
LOG <- function(...) cat(sprintf("[%s] ", format(Sys.time(),"%H:%M:%S")), ..., "\n")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

panel    <- readRDS(file.path(OUT_A, "panel_raw.rds"))
bench_dt <- readRDS(file.path(OUT_A, "bench_fwd.rds"))
LOG("panel:", nrow(panel), " bench:", nrow(bench_dt))

# cross-sectional z within each Date (winsor 3std then z). higher = better orientation handled per-signal.
zc <- function(v) {
  m <- mean(v, na.rm=TRUE); s <- sd(v, na.rm=TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(v)))
  z <- (v - m)/s; z <- pmax(pmin(z, 3), -3); z
}
panel[, z_M01 := zc(M01), by=Date]
panel[, z_M08 := zc(M08), by=Date]
panel[, z_M13 := zc(M13), by=Date]
panel[, z_H252 := zc(H252), by=Date]
panel[, z_H126 := zc(H126), by=Date]
panel[, z_H504 := zc(H504), by=Date]
panel[, z_HRS  := zc(HRS252), by=Date]

#==============================================================================
# Hurst sanity: distribution + DFA vs R/S agreement
#==============================================================================
hsum <- panel[is.finite(H252), .(mean_H=mean(H252), med_H=median(H252),
                                  sd_H=sd(H252), q10=quantile(H252,.1), q90=quantile(H252,.9),
                                  frac_persistent=mean(H252>0.5), n=.N)]
dfa_rs_cor <- panel[is.finite(H252) & is.finite(HRS252), cor(H252, HRS252, method="pearson")]
LOG("Hurst H252 summary:"); print(hsum)
LOG("DFA-252 vs R/S-252 cross-estimator cor:", round(dfa_rs_cor,3))

#==============================================================================
# Orthogonality: cross-sectional corr (per-date Spearman avg) of H vs momentum cluster
#==============================================================================
xcorr <- function(a, b) {
  d <- panel[is.finite(get(a)) & is.finite(get(b))]
  cs <- d[, .(c = if (.N>=10) cor(get(a), get(b), method="spearman") else NA_real_), by=Date]
  mean(cs$c, na.rm=TRUE)
}
orth <- list(
  H252_vs_M01 = xcorr("H252","M01"),
  H252_vs_M08 = xcorr("H252","M08"),
  H252_vs_M13 = xcorr("H252","M13"),
  H126_vs_M01 = xcorr("H126","M01"),
  H504_vs_M01 = xcorr("H504","M01")
)
LOG("Orthogonality (avg cross-sectional Spearman, H vs momentum cluster):"); print(orth)

#==============================================================================
# Operationalizations
#  (a) H-scaled momentum: signal = z_M01 * g(H), g amplifies high-H damps low-H
#       g(H) = exp(beta*(H-0.5)) bounded; use g = 1 + clamp((H-0.5)/0.5, -1, 1)  → range [0,2]
#  (b) H-gated regime split: high-H names -> +z_M01; low-H names -> -z_M01 (reversal)
#       BUT long-only: we just rank; reversal in low-H = take -momentum ordering for those names.
#       Implement as composite score where low-H momentum is sign-flipped before z.
#  (c) pure cross-sectional H factor (baseline): score = z_H252
#  Plus baseline (d) pure momentum z_M01 for reference.
#==============================================================================
gH <- function(H) {
  g <- 1 + pmax(pmin((H - 0.5)/0.5, 1), -1)   # H=0.5 ->1 ; H>=1 ->2 ; H<=0 ->0
  g
}
panel[, sig_a := z_M01 * gH(H252)]                       # H-scaled momentum
# (b) gated split: per name, if H>=0.5 use +M01 else use -M01 (anti-persistent -> reversal)
panel[, mom_gated := fifelse(H252 >= 0.5, M01, -M01)]
panel[, sig_b := zc(mom_gated), by=Date]
panel[, sig_c := z_H252]                                 # pure H
panel[, sig_d := z_M01]                                  # baseline momentum
# (a2) variant lookbacks
panel[, sig_a126 := z_M01 * gH(H126)]
panel[, sig_a504 := z_M01 * gH(H504)]
# (e) additive composite: 0.7*z_M01 + 0.3*z_H252 (incremental-signal form)
panel[, sig_e := 0.7*z_M01 + 0.3*z_H252]

#==============================================================================
# IC / ICIR / Harvey-t (rank-IC) per signal — screening evidence (labeled)
#==============================================================================
nw_t <- function(x, lag=3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < lag+2L) return(NA_real_)
  mu <- mean(x); e <- x-mu; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*w*g }
  if (s<=0) return(NA_real_); mu/sqrt(s/n)
}
ic_diag <- function(sigcol) {
  d <- panel[is.finite(get(sigcol)) & is.finite(Ret_1m)]
  ics <- d[, .(ic = if (.N>=10) cor(get(sigcol), Ret_1m, method="spearman") else NA_real_), by=Date]
  ics <- ics[is.finite(ic)]
  n <- nrow(ics); mic <- mean(ics$ic); sic <- sd(ics$ic)
  icir_m <- mic/sic
  list(rank_ic=mic, ic_sd=sic, icir_monthly=icir_m, icir_annualized=icir_m*sqrt(12),
       n_months=n, ic_t_plain=mic/sic*sqrt(n), harvey_t_nw3=nw_t(ics$ic, 3L),
       frac_pos=mean(ics$ic>0), ic_series=ics)
}
signals <- c(a="sig_a", b="sig_b", c="sig_c", d_baseline="sig_d",
             a126="sig_a126", a504="sig_a504", e_additive="sig_e")
diag_all <- lapply(signals, ic_diag)
LOG("IC diagnostics (rank-IC, ICIR, Harvey-t NW3):")
for (nm in names(diag_all)) {
  x <- diag_all[[nm]]
  LOG(sprintf("  %-12s ic=%.4f icir_m=%.3f icir_ann=%.3f harvey_t=%.2f n=%d frac_pos=%.2f",
              nm, x$rank_ic, x$icir_monthly, x$icir_annualized, x$harvey_t_nw3, x$n_months, x$frac_pos))
}

#==============================================================================
# canonical_screen_bt — REAL computation. top_n=25, 15bps, liquidity 2e8.
# scores_dt(Date,Ticker,score), returns_dt(Date,Ticker,Ret_1m), bench_dt(Date,BM_Ret)
# liq_dt(Date,Ticker,adv)
#==============================================================================
ret_dt <- panel[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt <- panel[is.finite(adv), .(Date, Ticker, adv)]
run_screen <- function(sigcol) {
  sc <- panel[is.finite(get(sigcol)), .(Date, Ticker, score=get(sigcol))]
  res <- canonical_screen_bt(sc, ret_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                             liq_dt=liq_dt, liq_min=2e8,
                             run_id=paste0("hurst_",sigcol), strategy_id=paste0("hurst_",sigcol))
  res
}
screen_all <- list()
for (nm in names(signals)) {
  LOG("canonical_screen:", nm, "(", signals[[nm]], ")")
  screen_all[[nm]] <- tryCatch(run_screen(signals[[nm]]), error=function(e){ LOG("  ERR:", conditionMessage(e)); NULL })
}
LOG("Canonical screen results (top25 EW long-only, 15bps, liq 2e8):")
scr_tab <- rbindlist(lapply(names(screen_all), function(nm){
  r <- screen_all[[nm]]; if (is.null(r)) return(NULL)
  data.table(signal=nm, n_months=r$n_months,
             port_alpha_t_nw3=r$portfolio_alpha_t_nw_lag3,
             IR=r$information_ratio, alpha_ann=r$alpha_annualized,
             net_sr=r$net_sr, mean_active_net=r$mean_active_net,
             turnover_ann=r$turnover_annual)
}), fill=TRUE)
print(scr_tab)

#==============================================================================
# Subperiod stability (rank-IC sign across 3 eras) for chosen signal — done later
#==============================================================================
subperiod_stab <- function(sigcol) {
  ics <- ic_diag(sigcol)$ic_series
  ics[, era := fifelse(Date < as.Date("2013-01-01"), "e1",
                fifelse(Date < as.Date("2019-01-01"), "e2", "e3"))]
  era_ic <- ics[, .(ic=mean(ic), n=.N), by=era][order(era)]
  list(era_ic=era_ic, sign_stability=mean(sign(era_ic$ic)==sign(mean(ics$ic))))
}

#==============================================================================
# Save eval results
#==============================================================================
saveRDS(list(hsum=hsum, dfa_rs_cor=dfa_rs_cor, orth=orth,
             diag_all=lapply(diag_all, function(x){x$ic_series<-NULL; x}),
             screen_tab=scr_tab,
             subperiod=lapply(signals, subperiod_stab)),
        file.path(OUT_A, "eval_results.rds"))
# alpha scores parquet for the chosen signal — write all candidate scores at last sig_date
LOG("Saving eval_results.rds")
# dump JSON-friendly summary
summ <- list(
  hurst_summary = as.list(hsum),
  dfa_rs_estimator_cor = dfa_rs_cor,
  orthogonality_xsec_spearman = orth,
  ic_diagnostics = lapply(diag_all, function(x){ x$ic_series<-NULL; x }),
  canonical_screen = scr_tab
)
write_json(summ, file.path(OUT_A, "eval_summary.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
LOG("DONE stage 2.")
