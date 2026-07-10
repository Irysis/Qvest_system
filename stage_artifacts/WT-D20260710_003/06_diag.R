# 06_diag.R — adversarial: is OOS collapse a cap-w mega-cap benchmark artifact or a genuine wall?
# Uses sanctioned canonical_screen_bt(diag_dual_basis=TRUE, size_dt) => diag_ew_universe + diag_cap_tier.
# Winner H3g ~= flat baseline (regime near-inert), so flat-EW composite is representative for this diag.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "stage_artifacts/WT-D20260710_003/02_harness.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_003")
bundle <- readRDS(file.path(OUT, "panel_bundle.rds"))

cfg0 <- list(id="flatEW", H="BASE", factor_design="all_ew", exposure_ctrl="full",
             universe_strat="flat", weighting="EW", regime_dyn="static", top_n=25L)
S_all <- build_score(bundle$features, bundle$size, cfg0)[, .(Date, Ticker, score)]
liq_dt <- bundle$univ[, .(Date, Ticker, adv=adv20)]
size_dt <- bundle$size[, .(Date, Ticker, Size)]

run_basis <- function(lbl, dfilter) {
  sc <- S_all[dfilter(Date)]
  cs <- canonical_screen_bt(sc, bundle$returns, bundle$bench, top_n=25L, cost_bps_oneway=15,
                            liq_dt=liq_dt, liq_min=2e8, diag_dual_basis=TRUE, size_dt=size_dt,
                            run_id=lbl, strategy_id=lbl)
  ew <- cs$diag_ew_universe; ct <- cs$diag_cap_tier
  cat(sprintf("\n== %s (n=%d) ==\n", lbl, cs$n_months))
  cat(sprintf("  CAP-W basis : port_t=%6.3f  ir=%6.3f  net_sr=%6.3f\n",
      cs$portfolio_alpha_t_nw_lag3, cs$information_ratio, cs$net_sr))
  cat(sprintf("  EW-UNIV diag: port_t=%6.3f  ir=%6.3f  net_sr=%6.3f  post2017_t=%6.3f  oos_ret~=%.2f\n",
      ew$portfolio_alpha_t_nw_lag3, ew$information_ratio, ew$net_sr,
      ew$post2017_t_nw_lag3 %||% NA, ew$oos_retention_approx %||% NA))
  if (isTRUE(ct$available)) {
    wa <- ct$weight_share_avg; ca <- ct$contrib_gross_annualized
    cat(sprintf("  CAP-TIER    : wshare MEGA=%.2f MID=%.2f OTHER=%.2f | gross-ann MEGA=%.3f MID=%.3f OTHER=%.3f\n",
        wa$MEGA, wa$MID, wa$OTHER, ca$MEGA, ca$MID, ca$OTHER))
  }
  list(label=lbl, n=cs$n_months, capw_port_t=cs$portfolio_alpha_t_nw_lag3,
       ew_port_t=ew$portfolio_alpha_t_nw_lag3, ew_post2017_t=ew$post2017_t_nw_lag3,
       tier_wshare=if(isTRUE(ct$available)) ct$weight_share_avg else NULL,
       tier_gross_ann=if(isTRUE(ct$available)) ct$contrib_gross_annualized else NULL)
}

res <- list(
  full = run_basis("flatEW_FULL", function(d) rep(TRUE, length(d))),
  is   = run_basis("flatEW_IS",   function(d) d <= as.Date("2018-12-01")),
  oos  = run_basis("flatEW_OOS",  function(d) d >= as.Date("2019-01-01"))
)
write_json(res, file.path(OUT, "dual_basis_captier_diag.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[diag] dual_basis_captier_diag.json written. DONE\n")
