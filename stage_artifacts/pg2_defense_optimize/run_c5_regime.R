## ============================================================================
## run_c5_regime.R — candidate c5_regime pinned recon + recon-vs-recon marginal.
##
## c5_regime (AX-001 v2 conditional tilt):
##   NORMAL, BULL (fallback) = Q07,M08,Q25         (== current defense sleeve)
##   CRISIS, CAUTION         = Q07,D48_VaR_5pct,RE07_Crisis_Beta
## Mechanism: regime-conditional swap of the two non-earnings-stability defense factors
##   (M08 momentum + Q25 Ohlson) for explicit tail factors (VaR + crisis β) during
##   CRISIS/CAUTION only; NORMAL/BULL sleeve unchanged from incumbent.
##
## Judgment = recon-vs-recon marginal on IDENTICAL pinned caches (carrier grid drift cancels).
##   Authoritative denominator = pinned_ic (convention-matched to deployed book: freeze used
##   align_factor_direction IC-sign, min_ic_months=12). regdir carried as robustness cross-check.
##   d_* = candidate(conv) - current_defense_recon(conv), SAME convention per arm.
##
## Harness = eval_defense_grid.R (grid reproduces recon_baseline exactly, validate_grid.R:
##   IC 1.8196/0.2340/5.4658/1.2421, regdir 1.7741/0.2263/5.1902/1.2083). All reads local
##   (OneDrive arrow-mmap segfault avoidance; byte-identical staged copies).
## ============================================================================
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_grid.R"))

CUR_SPEC    <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CRISIS_SPEC <- list(factors=c("Q07_Earnings_Stability","D48_VaR_5pct","RE07_Crisis_Beta"), weights=NULL)
REGIME_MAP  <- list(NORMAL=CUR_SPEC, BULL=CUR_SPEC, CAUTION=CRISIS_SPEC, CRISIS=CRISIS_SPEC)
BASE_SPEC   <- CUR_SPEC   # regime not in map -> current NORMAL sleeve

oos_med <- function(x){ v <- x %||% NA_real_; if (length(v)>1) median(v, na.rm=TRUE) else v }
run_arm <- function(src, spec, rmap, label){
  Sys.setenv(ED_PANEL_SRC=src); .ED$ready <- FALSE; .ED$PANEL_SRC <- src
  cat(sprintf("\n=== %s : pinned + %s ===\n", label, src))
  eval_defense(spec, regime_map=rmap, label=label)
}

## ---- candidate: authoritative (IC) + robustness (regdir) --------------------
c_ic  <- run_arm("ic",    BASE_SPEC, REGIME_MAP, "c5_regime_ic")
c_reg <- run_arm("regdir",BASE_SPEC, REGIME_MAP, "c5_regime_regdir")
## ---- baseline (current defense) recon on SAME grid, both conventions --------
b_ic  <- run_arm("ic",    CUR_SPEC,  NULL,       "recon_cur_ic")
b_reg <- run_arm("regdir",CUR_SPEC,  NULL,       "recon_cur_regdir")

## sanity: baseline recon must match recon_baseline.json
cat(sprintf("\n[baseline check IC]     SR=%.4f (exp 1.8196) PORT_t=%.4f (exp 5.4658) IR=%.4f (exp 1.2421)\n",
            b_ic$SR, b_ic$PORT_t, b_ic$IR))
cat(sprintf("[baseline check regdir] SR=%.4f (exp 1.7741) PORT_t=%.4f (exp 5.1902) IR=%.4f (exp 1.2083)\n",
            b_reg$SR, b_reg$PORT_t, b_reg$IR))

mk <- function(cand, base, conv){
  list(convention=conv,
    SR=round(cand$SR,4), MDD=round(abs(cand$MDD),4), calmar=round(cand$calmar,4),
    CAGR=round(cand$CAGR,4), PORT_t=round(cand$PORT_t,4), IR=round(cand$IR,4),
    oos_retention_median=round(oos_med(cand$oos_retention),4),
    oos_retention_raw=cand$oos_retention, n_periods=cand$n_periods,
    recon_baseline=list(SR=round(base$SR,4), MDD=round(abs(base$MDD),4), calmar=round(base$calmar,4),
                        PORT_t=round(base$PORT_t,4), IR=round(base$IR,4),
                        oos_retention_median=round(oos_med(base$oos_retention),4)),
    d_sr_vs_recon    = round(cand$SR       - base$SR,       4),
    d_mdd_vs_recon   = round(abs(cand$MDD) - abs(base$MDD), 4),
    d_calmar_vs_recon= round(cand$calmar   - base$calmar,   4),
    d_port_t_vs_recon= round(cand$PORT_t   - base$PORT_t,   4),
    d_ir_vs_recon    = round(cand$IR       - base$IR,       4))
}
res_ic  <- mk(c_ic,  b_ic,  "pinned_ic_authoritative")
res_reg <- mk(c_reg, b_reg, "pinned_regdir_robustness")

cat("\n===== c5_regime AUTHORITATIVE (IC) recon-vs-recon marginal =====\n")
cat(sprintf("candidate:  SR=%.4f MDD=%.4f calmar=%.4f PORT_t=%.4f IR=%.4f oos=%.4f\n",
            res_ic$SR,res_ic$MDD,res_ic$calmar,res_ic$PORT_t,res_ic$IR,res_ic$oos_retention_median))
cat(sprintf("baseline:   SR=%.4f MDD=%.4f calmar=%.4f PORT_t=%.4f IR=%.4f oos=%.4f\n",
            res_ic$recon_baseline$SR,res_ic$recon_baseline$MDD,res_ic$recon_baseline$calmar,
            res_ic$recon_baseline$PORT_t,res_ic$recon_baseline$IR,res_ic$recon_baseline$oos_retention_median))
cat(sprintf("MARGINAL:   d_sr=%+.4f d_mdd=%+.4f d_calmar=%+.4f d_port_t=%+.4f d_ir=%+.4f\n",
            res_ic$d_sr_vs_recon,res_ic$d_mdd_vs_recon,res_ic$d_calmar_vs_recon,
            res_ic$d_port_t_vs_recon,res_ic$d_ir_vs_recon))
cat(sprintf("[robustness regdir] d_sr=%+.4f d_mdd=%+.4f d_ir=%+.4f d_port_t=%+.4f\n",
            res_reg$d_sr_vs_recon,res_reg$d_mdd_vs_recon,res_reg$d_ir_vs_recon,res_reg$d_port_t_vs_recon))

## ---- paired-t on monthly return diff (candidate IC - baseline IC) -----------
cand_m <- c_ic$monthly[, .(realized_ym, ret_cand=ret_noL4)]
base_m <- b_ic$monthly[, .(realized_ym, ret_base=ret_noL4)]
paired <- merge(base_m, cand_m, by="realized_ym", all=FALSE); setorder(paired, realized_ym)
paired[, d_ret := ret_cand - ret_base]
dt_pt <- t.test(paired$d_ret)
cat(sprintf("\n[PAIRED-t monthly ret (cand-base, IC)] mean=%+.5f t=%+.3f p=%.4f n=%d nonzero_months=%d\n",
            mean(paired$d_ret), dt_pt$statistic, dt_pt$p.value, nrow(paired), sum(abs(paired$d_ret)>1e-9)))
fwrite(paired, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_monthly_paired.csv"))

## ---- episode active marginal (candidate IC - baseline IC) -------------------
ep_marg <- merge(b_ic$episodes[, .(episode, active_base=active)],
                 c_ic$episodes[, .(episode, active_cand=active)], by="episode")
ep_marg[, d_active := active_cand - active_base]
ep_marg <- ep_marg[match(b_ic$episodes$episode, ep_marg$episode)]
cat("\n[EPISODE ACTIVE MARGINAL (cand-base, IC)]\n"); print(ep_marg)
cat("\n[CANDIDATE IC episodes]\n"); print(c_ic$episodes)

## ---- persist ----------------------------------------------------------------
out <- list(
  candidate_id="c5_regime",
  mechanism="AX-001 v2 conditional tilt: NORMAL/BULL=Q07/M08/Q25, CRISIS/CAUTION=Q07/D48_VaR_5pct/RE07_Crisis_Beta",
  regime_map=list(NORMAL=CUR_SPEC$factors, BULL=CUR_SPEC$factors,
                  CAUTION=CRISIS_SPEC$factors, CRISIS=CRISIS_SPEC$factors),
  authoritative=res_ic, robustness_regdir=res_reg,
  paired_t_monthly=list(mean_d_ret=mean(paired$d_ret), t=as.numeric(dt_pt$statistic),
                        p=dt_pt$p.value, n=nrow(paired), nonzero_months=sum(abs(paired$d_ret)>1e-9)),
  episode_active_marginal=ep_marg, episodes_candidate_ic=c_ic$episodes,
  baseline_recon_check=list(ic=list(SR=b_ic$SR, PORT_t=b_ic$PORT_t, IR=b_ic$IR),
                            regdir=list(SR=b_reg$SR, PORT_t=b_reg$PORT_t, IR=b_reg$IR)),
  pinned_caches=c("RAWDATA_pin20260703.parquet","benchmark_pin20260703.parquet"),
  harness="eval_defense_grid.R (grid validated == recon_baseline: validate_grid.R)",
  note=paste0("recon-vs-recon on identical pinned carrier grid; d_* = c5_regime(IC) - current_defense_recon(IC). ",
              "Authoritative denominator = IC panel (convention-matched to deployed book). ",
              "regdir robustness cross-check only. c5 swaps M08+Q25 -> D48_VaR+RE07_CrisisBeta in CRISIS/CAUTION."))
write_json(out, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)
saveRDS(list(cand_ic=c_ic, cand_regdir=c_reg, base_ic=b_ic, base_regdir=b_reg, paired=paired),
        file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_full.rds"))
cat("\n[saved] c5_regime_marginal.json + c5_regime_monthly_paired.csv + c5_regime_full.rds\n")
