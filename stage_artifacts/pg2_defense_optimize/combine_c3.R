## combine_c3.R — assemble c3_swap_D45 marginal JSON from the 4 isolated-arm RDS.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
options(scipen=999)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCR <- Sys.getenv("ED_SCR")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
cur_ic  <- readRDS(file.path(SCR,"_r_cur_ic.rds"))
cand_ic <- readRDS(file.path(SCR,"_r_cand_ic.rds"))
cur_rg  <- readRDS(file.path(SCR,"_r_cur_regdir.rds"))
cand_rg <- readRDS(file.path(SCR,"_r_cand_regdir.rds"))

marg <- function(cand, cur) list(
  d_ir = cand$IR - cur$IR, d_sr = cand$SR - cur$SR,
  d_mdd = cand$MDD - cur$MDD, d_calmar = cand$calmar - cur$calmar,
  d_port_t = cand$PORT_t - cur$PORT_t, d_cagr = cand$CAGR - cur$CAGR)
m_ic <- marg(cand_ic, cur_ic); m_rg <- marg(cand_rg, cur_rg)

## episode active comparison (IC arm authoritative)
ep <- merge(cur_ic$episodes[, .(episode, active_cur=active)],
            cand_ic$episodes[, .(episode, active_cand=active)], by="episode", sort=FALSE)
ep[, d_active := active_cand - active_cur]

## monthly series (IC arm) for paired-t
ms <- merge(cand_ic$monthly[, .(realized_ym, anchor_date, ret_cand=ret_noL4)],
            cur_ic$monthly[, .(realized_ym, ret_cur=ret_noL4)], by="realized_ym", sort=FALSE)
setorder(ms, realized_ym)
fwrite(ms, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c3_swap_D45_monthly_ic.csv"))
diff <- ms$ret_cand - ms$ret_cur
tt <- t.test(diff)
## NW-agnostic paired-t on monthly active diff
pt_simple <- as.numeric(tt$statistic)

## mean episode active (candidate, IC)
mean_epi_active_cand <- mean(cand_ic$episodes$active, na.rm=TRUE)
mean_epi_active_cur  <- mean(cur_ic$episodes$active, na.rm=TRUE)

out <- list(
  id="c3_swap_D45",
  candidate="{Q07_Earnings_Stability, M08_Residual_Mom, D45_Downside_Dev} EW (Q25->D45 swap)",
  denominator="current defense {Q07,M08,Q25} EW recon on SAME pinned caches",
  authoritative_arm="ic (convention-matched to deployed freeze which used IC-sign)",
  caches="RAWDATA_pin20260703 + benchmark_pin20260703 (universe-filtered slim carrier, parity-verified vs recon_baseline IC SR 1.8196)",
  convention_note="For {Q07,M08,D45}, IC and regdir Z_Aligned are IDENTICAL (cor +1.0000 each); only Q25 flips between conventions (cor -1.0000). Hence the CANDIDATE recon is convention-robust: ic and regdir arms coincide exactly (SR 2.0598 both). The current-defense denominator differs by arm only because of Q25.",
  candidate_ic=list(SR=cand_ic$SR, MDD=cand_ic$MDD, calmar=cand_ic$calmar, CAGR=cand_ic$CAGR,
                    PORT_t=cand_ic$PORT_t, IR=cand_ic$IR, oos_retention=cand_ic$oos_retention,
                    n_periods=cand_ic$n_periods, defz_cor_to_stored=cand_ic$defz_cor_to_stored),
  current_recon_ic=list(SR=cur_ic$SR, MDD=cur_ic$MDD, calmar=cur_ic$calmar, CAGR=cur_ic$CAGR,
                    PORT_t=cur_ic$PORT_t, IR=cur_ic$IR, oos_retention=cur_ic$oos_retention,
                    n_periods=cur_ic$n_periods, defz_cor_to_stored=cur_ic$defz_cor_to_stored),
  candidate_regdir=list(SR=cand_rg$SR, MDD=cand_rg$MDD, calmar=cand_rg$calmar, CAGR=cand_rg$CAGR,
                    PORT_t=cand_rg$PORT_t, IR=cand_rg$IR, oos_retention=cand_rg$oos_retention),
  current_recon_regdir=list(SR=cur_rg$SR, MDD=cur_rg$MDD, calmar=cur_rg$calmar, CAGR=cur_rg$CAGR,
                    PORT_t=cur_rg$PORT_t, IR=cur_rg$IR, oos_retention=cur_rg$oos_retention),
  marginal_ic=m_ic, marginal_regdir=m_rg,
  paired_t_ic=list(mean_monthly_diff=mean(diff), t=pt_simple, n=length(diff), p_value=as.numeric(tt$p.value)),
  mean_episode_active_candidate_ic=mean_epi_active_cand,
  mean_episode_active_current_ic=mean_epi_active_cur,
  episodes_ic=ep
)
write_json(out, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c3_swap_D45_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)

cat("===== c3_swap_D45 (IC authoritative) =====\n")
cat(sprintf("CAND : SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos_med=%.4f n=%d\n",
    cand_ic$SR,cand_ic$MDD,cand_ic$calmar,cand_ic$CAGR,cand_ic$PORT_t,cand_ic$IR,cand_ic$oos_retention,cand_ic$n_periods))
cat(sprintf("CUR  : SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos_med=%.4f n=%d\n",
    cur_ic$SR,cur_ic$MDD,cur_ic$calmar,cur_ic$CAGR,cur_ic$PORT_t,cur_ic$IR,cur_ic$oos_retention,cur_ic$n_periods))
cat(sprintf("MARG : d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_calmar=%+.4f d_port_t=%+.4f d_cagr=%+.4f\n",
    m_ic$d_ir,m_ic$d_sr,m_ic$d_mdd,m_ic$d_calmar,m_ic$d_port_t,m_ic$d_cagr))
cat(sprintf("REGDIR xchk MARG: d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f\n", m_rg$d_ir,m_rg$d_sr,m_rg$d_mdd))
cat(sprintf("PAIRED-T (monthly cand-cur): mean=%+.5f t=%+.3f p=%.4f n=%d\n",
    mean(diff),pt_simple,as.numeric(tt$p.value),length(diff)))
cat(sprintf("mean_episode_active: cand=%+.4f cur=%+.4f\n", mean_epi_active_cand, mean_epi_active_cur))
cat("\n[EPISODES cand vs cur (IC)]\n"); print(ep)
cat("\n[saved] c3_swap_D45_marginal.json + c3_swap_D45_monthly_ic.csv\n")
