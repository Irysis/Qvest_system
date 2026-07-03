## ============================================================================
## run_c3_swap_D45.R — pinned recon of candidate c3_swap_D45 vs current-defense recon.
##
## Candidate c3_swap_D45: {Q07_Earnings_Stability, M08_Residual_Mom, D45_Downside_Dev} EW
##   (Q25_Ohlson_O -> D45_Downside_Dev swap; mechanism: distress-prob -> downside-dev).
## Current defense (recon denominator): {Q07, M08, Q25} EW.
##
## Marginal = candidate - current, computed on IDENTICAL pinned caches so the carrier
## re-derivation drift (recon SR != frozen 1.898) cancels between the two arms.
## Authoritative arm = IC-panel (convention-matched to deployed freeze which used IC-sign).
## regdir arm retained as robustness cross-check only.
##
## Both arms re-run CUR in the SAME process (not trusting stored JSON) to guarantee the
## exact same vintage/caches for a clean cancellation.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(1L), silent=TRUE))
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))

CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","D45_Downside_Dev"), weights=NULL)

run_arm <- function(src){
  Sys.setenv(ED_PANEL_SRC=src); .ED$ready <- FALSE; .ED$PANEL_SRC <- src
  cat(sprintf("\n########## PANEL_SRC = %s ##########\n", src))
  cat("--- current defense recon (denominator) ---\n")
  r_cur  <- eval_defense(CUR,  label=paste0("cur_",src))
  cat("--- candidate c3_swap_D45 recon ---\n")
  r_cand <- eval_defense(CAND, label=paste0("c3D45_",src))
  list(cur=r_cur, cand=r_cand)
}

ic  <- run_arm("ic")
reg <- run_arm("regdir")

## ---- def_z alignment to stored (vintage-closeness diagnostic) ----------------
dz_close <- function(r){
  d <- r$score_eff[!is.na(def_z) & !is.na(stored_defz)]
  list(cor=cor(d$def_z,d$stored_defz), n=nrow(d))
}

fmt <- function(r) sprintf("SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f n=%d",
  r$SR, abs(r$MDD), r$calmar, r$CAGR, r$PORT_t, r$IR, r$oos_retention %||% NA_real_, r$n_periods)

cat("\n\n===================== ARM: IC (authoritative) =====================\n")
cat("CUR  recon: ", fmt(ic$cur),  "  defz_cor=", round(dz_close(ic$cur)$cor,4),  "\n")
cat("CAND recon: ", fmt(ic$cand), "  defz_cor=", round(dz_close(ic$cand)$cor,4), "\n")
cat("\n===================== ARM: regdir (cross-check) ===================\n")
cat("CUR  recon: ", fmt(reg$cur),  "  defz_cor=", round(dz_close(reg$cur)$cor,4),  "\n")
cat("CAND recon: ", fmt(reg$cand), "  defz_cor=", round(dz_close(reg$cand)$cor,4), "\n")

## ---- marginals (candidate - current) on same pinned caches -------------------
marg <- function(a){
  list(d_ir  = a$cand$IR     - a$cur$IR,
       d_sr  = a$cand$SR     - a$cur$SR,
       d_mdd = abs(a$cand$MDD) - abs(a$cur$MDD),
       d_calmar = a$cand$calmar - a$cur$calmar,
       d_port_t = a$cand$PORT_t - a$cur$PORT_t,
       d_cagr = a$cand$CAGR  - a$cur$CAGR)
}
m_ic  <- marg(ic)
m_reg <- marg(reg)

cat("\n\n===================== MARGINAL (cand - cur) =====================\n")
cat(sprintf("[IC  authoritative] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_calmar=%+.4f d_port_t=%+.4f d_cagr=%+.4f\n",
    m_ic$d_ir, m_ic$d_sr, m_ic$d_mdd, m_ic$d_calmar, m_ic$d_port_t, m_ic$d_cagr))
cat(sprintf("[regdir cross-chk ] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_calmar=%+.4f d_port_t=%+.4f d_cagr=%+.4f\n",
    m_reg$d_ir, m_reg$d_sr, m_reg$d_mdd, m_reg$d_calmar, m_reg$d_port_t, m_reg$d_cagr))

## ---- episode active comparison (IC arm) --------------------------------------
epi_cmp <- merge(ic$cur$episodes[, .(episode, active_cur=active)],
                 ic$cand$episodes[, .(episode, active_cand=active)], by="episode", sort=FALSE)
epi_cmp[, d_active := active_cand - active_cur]
cat("\n[EPISODES IC] candidate vs current book-active over 11 drawdown episodes:\n")
print(epi_cmp)

## ---- monthly return series (candidate, IC arm) for paired-t ------------------
mser_ic <- ic$cand$monthly[, .(realized_ym, anchor_date, ret_noL4_cand=ret_noL4)]
mser_ic <- merge(mser_ic, ic$cur$monthly[, .(realized_ym, ret_noL4_cur=ret_noL4)], by="realized_ym", sort=FALSE)
setorder(mser_ic, realized_ym)
fwrite(mser_ic, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c3_swap_D45_monthly_ic.csv"))

## paired-t on monthly active-diff (cand - cur), NW-agnostic simple paired-t as a quick read
dt_diff <- mser_ic$ret_noL4_cand - mser_ic$ret_noL4_cur
pt <- tryCatch(t.test(dt_diff)$statistic[[1]], error=function(e) NA_real_)
cat(sprintf("\n[PAIRED-T IC] monthly ret diff (cand-cur): mean=%+.5f t=%+.3f n=%d\n",
    mean(dt_diff), pt, length(dt_diff)))

## ---- persist marginal JSON ---------------------------------------------------
out <- list(
  id="c3_swap_D45",
  candidate_spec=list(factors=CAND$factors, construction="EW (defense=fixed 1/3 each), winsor_z 2.5sigma, x-sec z per sig_date"),
  denominator_spec=list(factors=CUR$factors, note="current defense recon on SAME pinned caches"),
  authoritative_arm="ic",
  caches="RAWDATA_pin20260703 + benchmark_pin20260703 (byte-identical to .cache)",
  candidate_ic=list(SR=ic$cand$SR, MDD=abs(ic$cand$MDD), calmar=ic$cand$calmar, CAGR=ic$cand$CAGR,
                    PORT_t=ic$cand$PORT_t, IR=ic$cand$IR, oos_retention=ic$cand$oos_retention,
                    n_periods=ic$cand$n_periods, defz_cor_to_stored=dz_close(ic$cand)$cor),
  current_recon_ic=list(SR=ic$cur$SR, MDD=abs(ic$cur$MDD), calmar=ic$cur$calmar, CAGR=ic$cur$CAGR,
                    PORT_t=ic$cur$PORT_t, IR=ic$cur$IR, oos_retention=ic$cur$oos_retention,
                    n_periods=ic$cur$n_periods, defz_cor_to_stored=dz_close(ic$cur)$cor),
  candidate_regdir=list(SR=reg$cand$SR, MDD=abs(reg$cand$MDD), calmar=reg$cand$calmar, CAGR=reg$cand$CAGR,
                    PORT_t=reg$cand$PORT_t, IR=reg$cand$IR, oos_retention=reg$cand$oos_retention),
  current_recon_regdir=list(SR=reg$cur$SR, MDD=abs(reg$cur$MDD), calmar=reg$cur$calmar, CAGR=reg$cur$CAGR,
                    PORT_t=reg$cur$PORT_t, IR=reg$cur$IR, oos_retention=reg$cur$oos_retention),
  marginal_ic=m_ic,
  marginal_regdir=m_reg,
  paired_t_ic=list(mean_monthly_diff=mean(dt_diff), t=pt, n=length(dt_diff)),
  episodes_ic=epi_cmp
)
write_json(out, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c3_swap_D45_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("\n[saved] c3_swap_D45_marginal.json + c3_swap_D45_monthly_ic.csv\n")

## echo compact machine-readable line for the parent
cat(sprintf("\n@@RESULT@@ %s\n", toJSON(list(
  candidate_ic=out$candidate_ic, marginal_ic=m_ic, marginal_regdir=m_reg,
  paired_t=out$paired_t_ic), auto_unbox=TRUE, digits=6)))
