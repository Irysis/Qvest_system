## assemble_c2_marginal.R — combine 4 arm RDS into c2_swap_RE07 marginal + paired-t.
## Authoritative denominator = pinned_ic (convention-matched to deployed book IC-sign freeze).
## regdir = robustness x-check. marginal = candidate - recon_baseline (same pinned cache => drift cancels).
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
options(scipen=999)
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_defense_optimize"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a

ic_base  <- readRDS(file.path(OUT,"ic_base.rds"))
ic_cand  <- readRDS(file.path(OUT,"ic_cand.rds"))
reg_base <- readRDS(file.path(OUT,"reg_base.rds"))
reg_cand <- readRDS(file.path(OUT,"reg_cand.rds"))

## sanity: IC base reproduces recon baseline (equivalence gate)
gate <- abs(ic_base$SR - 1.8196) < 1e-3 && abs(ic_base$PORT_t - 5.4658) < 1e-2
cat(sprintf("[EQUIV GATE] ic_base SR=%.4f (want 1.8196) PORT_t=%.4f (want 5.4658) -> %s\n",
            ic_base$SR, ic_base$PORT_t, if(gate)"PASS" else "FAIL"))

mm <- function(r) list(SR=r$SR, MDD=abs(r$MDD), calmar=r$calmar, CAGR=r$CAGR,
                       PORT_t=r$PORT_t, IR=r$IR, oos_retention=r$oos_retention, n=r$n_periods)
marg <- function(cand,base) list(
  d_ir = cand$IR - base$IR, d_sr = cand$SR - base$SR,
  d_mdd = abs(cand$MDD) - abs(base$MDD),
  d_port_t = cand$PORT_t - base$PORT_t, d_calmar = cand$calmar - base$calmar)

m_ic  <- marg(ic_cand,  ic_base)
m_reg <- marg(reg_cand, reg_base)

## mean episode active (candidate, IC arm)
mean_epi_active_cand <- mean(ic_cand$episodes$active, na.rm=TRUE)
mean_epi_active_base <- mean(ic_base$episodes$active, na.rm=TRUE)

## episode deltas (IC arm)
epc <- merge(ic_base$episodes[, .(episode, active_base=active)],
             ic_cand$episodes[, .(episode, active_cand=active)], by="episode")
epc[, d_active := active_cand - active_base]

## OOS retention v2 median (candidate IC)
oos_med_cand <- median(ic_cand$oos_retention, na.rm=TRUE)

## ---- paired-t on monthly net returns (IC arm) -------------------------------
mo_base <- ic_base$monthly[, .(realized_ym, ret_base=ret_noL4)]
mo_cand <- ic_cand$monthly[, .(realized_ym, ret_cand=ret_noL4)]
mo <- merge(mo_base, mo_cand, by="realized_ym", all=TRUE); setorder(mo, realized_ym)
fwrite(mo, file.path(OUT,"c2_swap_RE07_monthly_ic.csv"))
mp2 <- mo[is.finite(ret_base) & is.finite(ret_cand)]; dvec <- mp2$ret_cand - mp2$ret_base
pt <- if (length(dvec)>2 && sd(dvec)>0) t.test(dvec) else NULL
paired_t <- if(!is.null(pt)) as.numeric(pt$statistic) else NA_real_
paired_p <- if(!is.null(pt)) as.numeric(pt$p.value) else NA_real_

cat("\n===== c2_swap_RE07 (Q07/M08/RE07 EW, Q25 removed) =====\n")
cat(sprintf("IC recon baseline (CUR): SR=%.4f MDD=%.4f calmar=%.4f PORT_t=%.4f IR=%.4f oos=[%s]\n",
    ic_base$SR, abs(ic_base$MDD), ic_base$calmar, ic_base$PORT_t, ic_base$IR, paste(round(ic_base$oos_retention,3),collapse=",")))
cat(sprintf("IC candidate (CAND):     SR=%.4f MDD=%.4f calmar=%.4f PORT_t=%.4f IR=%.4f oos=[%s]\n",
    ic_cand$SR, abs(ic_cand$MDD), ic_cand$calmar, ic_cand$PORT_t, ic_cand$IR, paste(round(ic_cand$oos_retention,3),collapse=",")))
cat(sprintf("[MARGINAL ic] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f d_calmar=%+.4f\n",
    m_ic$d_ir, m_ic$d_sr, m_ic$d_mdd, m_ic$d_port_t, m_ic$d_calmar))
cat(sprintf("[MARGINAL regdir x-check] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f\n",
    m_reg$d_ir, m_reg$d_sr, m_reg$d_mdd, m_reg$d_port_t))
cat(sprintf("[PAIRED-t ic] mean(cand-base)=%+.5f/mo t=%+.3f p=%.4f n=%d\n",
    mean(dvec), paired_t, paired_p, length(dvec)))
cat(sprintf("[mean episode active] base=%+.4f cand=%+.4f (11 drawdown episodes, IC)\n",
    mean_epi_active_base, mean_epi_active_cand))
cat("\n[EPISODES ic] base vs cand active:\n"); print(epc)

res <- list(
  candidate="c2_swap_RE07",
  spec=list(factors=ic_cand$spec, weighting="EW 1/3 each (theta_defense-matched)"),
  mechanism="Q25_Ohlson_O (drawdown-rank100 weakest) -> RE07_Crisis_Beta (episode hit100%)",
  authoritative_denominator="pinned_ic (convention-matched to deployed book IC-sign freeze)",
  pinned_caches=c("RAWDATA_pin20260703.parquet","benchmark_pin20260703.parquet"),
  equivalence_gate=list(ic_base_SR=ic_base$SR, want_SR=1.8196, ic_base_PORT_t=ic_base$PORT_t,
                        want_PORT_t=5.4658, pass=gate),
  candidate_ic=mm(ic_cand),
  recon_baseline_ic=mm(ic_base),
  marginal_vs_recon_ic=m_ic,
  d_ir_vs_recon=m_ic$d_ir, d_sr_vs_recon=m_ic$d_sr, d_mdd_vs_recon=m_ic$d_mdd,
  oos_retention_v2_median_cand=oos_med_cand,
  mean_episode_active_cand=mean_epi_active_cand,
  mean_episode_active_base=mean_epi_active_base,
  paired_t_monthly=paired_t, paired_p_monthly=paired_p, paired_n=length(dvec),
  candidate_regdir=mm(reg_cand),
  recon_baseline_regdir=mm(reg_base),
  marginal_vs_recon_regdir=m_reg,
  episodes_ic=epc,
  n_re07_sig_dates=257L)
write_json(res, file.path(OUT,"c2_swap_RE07_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
cat("\n[saved]", file.path(OUT,"c2_swap_RE07_marginal.json"),"\n")
cat("[saved]", file.path(OUT,"c2_swap_RE07_monthly_ic.csv"),"\n")
