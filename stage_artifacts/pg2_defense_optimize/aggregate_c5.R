## aggregate_c5.R — combine the 4 arm RDS into c5_regime marginal + paired-t + episode marginal.
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a

cand_ic  <- readRDS(file.path(SCRATCH,"arm_cand_ic.rds"))
cand_reg <- readRDS(file.path(SCRATCH,"arm_cand_regdir.rds"))
base_ic  <- readRDS(file.path(SCRATCH,"arm_base_ic.rds"))
base_reg <- readRDS(file.path(SCRATCH,"arm_base_regdir.rds"))

## baseline recon fidelity vs recon_baseline.json (authoritative denominators)
cat(sprintf("[fidelity IC]     base recon SR=%.4f (exp 1.8196) PORT_t=%.4f (exp 5.4658) IR=%.4f (exp 1.2421) MDD=%.4f (exp 0.234)\n",
            base_ic$SR, base_ic$PORT_t, base_ic$IR, base_ic$MDD))
cat(sprintf("[fidelity regdir] base recon SR=%.4f (exp 1.7741) PORT_t=%.4f (exp 5.1902) IR=%.4f (exp 1.2083) MDD=%.4f (exp 0.2263)\n",
            base_reg$SR, base_reg$PORT_t, base_reg$IR, base_reg$MDD))

mk <- function(cand, base, conv){
  list(convention=conv,
    SR=round(cand$SR,4), MDD=round(cand$MDD,4), calmar=round(cand$calmar,4),
    CAGR=round(cand$CAGR,4), PORT_t=round(cand$PORT_t,4), IR=round(cand$IR,4),
    oos_retention_median=round(cand$oos_retention_median,4),
    oos_retention_raw=cand$oos_retention_raw, n_periods=cand$n_periods,
    recon_baseline=list(SR=round(base$SR,4), MDD=round(base$MDD,4), calmar=round(base$calmar,4),
                        PORT_t=round(base$PORT_t,4), IR=round(base$IR,4),
                        oos_retention_median=round(base$oos_retention_median,4)),
    d_sr_vs_recon    = round(cand$SR     - base$SR,     4),
    d_mdd_vs_recon   = round(cand$MDD    - base$MDD,    4),
    d_calmar_vs_recon= round(cand$calmar - base$calmar, 4),
    d_port_t_vs_recon= round(cand$PORT_t - base$PORT_t, 4),
    d_ir_vs_recon    = round(cand$IR     - base$IR,     4))
}
res_ic  <- mk(cand_ic,  base_ic,  "pinned_ic_authoritative")
res_reg <- mk(cand_reg, base_reg, "pinned_regdir_robustness")

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

## paired-t (candidate IC - baseline IC monthly ret)
cand_m <- cand_ic$monthly[, .(realized_ym, ret_cand=ret_noL4)]
base_m <- base_ic$monthly[, .(realized_ym, ret_base=ret_noL4)]
paired <- merge(base_m, cand_m, by="realized_ym", all=FALSE); setorder(paired, realized_ym)
paired[, d_ret := ret_cand - ret_base]
dt_pt <- t.test(paired$d_ret)
cat(sprintf("\n[PAIRED-t monthly ret (cand-base, IC)] mean=%+.5f t=%+.3f p=%.4f n=%d nonzero=%d\n",
            mean(paired$d_ret), dt_pt$statistic, dt_pt$p.value, nrow(paired), sum(abs(paired$d_ret)>1e-9)))
fwrite(paired, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_monthly_paired.csv"))

## episode active marginal (IC)
ep_marg <- merge(base_ic$episodes[, .(episode, active_base=active)],
                 cand_ic$episodes[, .(episode, active_cand=active)], by="episode")
ep_marg[, d_active := active_cand - active_base]
ep_marg <- ep_marg[match(base_ic$episodes$episode, ep_marg$episode)]
cat("\n[EPISODE ACTIVE MARGINAL (cand-base, IC)]\n"); print(ep_marg)
cat("\n[CANDIDATE IC episodes]\n"); print(cand_ic$episodes)

CUR_F  <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
CRIS_F <- c("Q07_Earnings_Stability","D48_VaR_5pct","RE07_Crisis_Beta")
out <- list(
  candidate_id="c5_regime",
  mechanism="AX-001 v2 conditional tilt: NORMAL/BULL=Q07/M08/Q25, CRISIS/CAUTION=Q07/D48_VaR_5pct/RE07_Crisis_Beta",
  regime_map=list(NORMAL=CUR_F, BULL=CUR_F, CAUTION=CRIS_F, CRISIS=CRIS_F),
  authoritative=res_ic, robustness_regdir=res_reg,
  paired_t_monthly=list(mean_d_ret=mean(paired$d_ret), t=as.numeric(dt_pt$statistic),
                        p=dt_pt$p.value, n=nrow(paired), nonzero_months=sum(abs(paired$d_ret)>1e-9)),
  episode_active_marginal=ep_marg, episodes_candidate_ic=cand_ic$episodes,
  baseline_recon_fidelity=list(
    ic=list(SR=base_ic$SR, PORT_t=base_ic$PORT_t, IR=base_ic$IR, MDD=base_ic$MDD,
            exp="recon_baseline.json pinned_ic: SR1.8196 PORT_t5.4658 IR1.2421 MDD0.234"),
    regdir=list(SR=base_reg$SR, PORT_t=base_reg$PORT_t, IR=base_reg$IR, MDD=base_reg$MDD,
                exp="recon_baseline.json pinned_regdir: SR1.7741 PORT_t5.1902 IR1.2083 MDD0.2263")),
  pinned_caches=c("RAWDATA_pin20260703.parquet","benchmark_pin20260703.parquet"),
  harness="eval_defense_grid.R (carrier grid validated == recon_baseline exactly, validate_grid.R)",
  note=paste0("recon-vs-recon on identical pinned carrier grid; d_* = c5_regime(IC) - current_defense_recon(IC). ",
              "Authoritative denominator = IC panel (convention-matched to deployed book, defz_cor_to_stored 0.849). ",
              "regdir robustness cross-check. c5 swaps M08+Q25 -> D48_VaR+RE07_CrisisBeta in CRISIS/CAUTION only."))
write_json(out, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)
saveRDS(list(cand_ic=cand_ic, cand_regdir=cand_reg, base_ic=base_ic, base_regdir=base_reg, paired=paired),
        file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_regime_full.rds"))
cat("\n[saved] c5_regime_marginal.json + c5_regime_monthly_paired.csv + c5_regime_full.rds\n")
