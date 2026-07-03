## ============================================================================
## c4_augment4_run.R — candidate c4_augment4 vs CURRENT-defense recon marginal.
##
## Candidate: Q07/M08/Q25 + RE07_Crisis_Beta, EW 1/4 (augment, no removal).
## Baseline (marginal denominator): CURRENT defense Q07/M08/Q25 EW, SAME pinned
##   cache, SAME panel convention. Per recon_baseline block:
##   authoritative_marginal_denominator = "pinned_ic" (IC-sign, convention-matched
##   to the deployed frozen alpha_scores). regdir retained as robustness cross-check.
## Marginal = candidate - recon_baseline (drift cancels: identical caches/convention).
##
## Pinned caches: RAWDATA_pin20260703 + benchmark_pin20260703 (self-consistent).
## Self-synth 금지: carrier prod(1+Ret)-1 + contract build_metrics/build_benchmark_compare.
## Segfault guard: setDTthreads(1), arrow io=1, taskkill pre-run, col_select.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(1L), silent=TRUE))
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))

CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O","RE07_Crisis_Beta"), weights=NULL)

run_arm <- function(src){
  Sys.setenv(ED_PANEL_SRC=src); .ED$ready <- FALSE; .ED$PANEL_SRC <- src
  cat(sprintf("\n=== BASELINE recon (Q07/M08/Q25 EW) [%s] ===\n", src))
  base <- eval_defense(CUR,  label=paste0("recon_base_",src))
  Sys.setenv(ED_PANEL_SRC=src); .ED$ready <- FALSE; .ED$PANEL_SRC <- src
  cat(sprintf("\n=== CANDIDATE c4_augment4 (+RE07_Crisis_Beta EW 1/4) [%s] ===\n", src))
  cand <- eval_defense(CAND, label=paste0("c4_augment4_",src))
  list(base=base, cand=cand)
}

## Arm A: IC panel (authoritative, convention-matched to deployed book)
A <- run_arm("ic")
## Arm B: regdir panel (robustness cross-check)
B <- run_arm("regdir")

fmt <- function(r) data.table(
  SR=round(r$SR,4), MDD=round(abs(r$MDD),4), calmar=round(r$calmar,4),
  CAGR=round(r$CAGR,4), PORT_t=round(r$PORT_t,4), IR=round(r$IR,4),
  oos=round(r$oos_retention %||% NA,4), n=r$n_periods)

cat("\n\n===== METRICS TABLE =====\n")
tbl <- rbind(
  cbind(arm="ic",     who="baseline", fmt(A$base)),
  cbind(arm="ic",     who="candidate",fmt(A$cand)),
  cbind(arm="regdir", who="baseline", fmt(B$base)),
  cbind(arm="regdir", who="candidate",fmt(B$cand)))
print(tbl)

## ---- marginal = candidate - baseline (authoritative arm = IC) ---------------
marg <- function(P){
  list(d_ir = P$cand$IR - P$base$IR,
       d_sr = P$cand$SR - P$base$SR,
       d_mdd= abs(P$cand$MDD) - abs(P$base$MDD),
       d_port_t = P$cand$PORT_t - P$base$PORT_t,
       d_calmar = P$cand$calmar - P$base$calmar,
       d_cagr   = P$cand$CAGR - P$base$CAGR,
       d_oos    = (P$cand$oos_retention %||% NA) - (P$base$oos_retention %||% NA))
}
mA <- marg(A); mB <- marg(B)
cat(sprintf("\n[MARGINAL ic (authoritative)]    d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f d_calmar=%+.4f d_oos=%+.4f\n",
            mA$d_ir, mA$d_sr, mA$d_mdd, mA$d_port_t, mA$d_calmar, mA$d_oos))
cat(sprintf("[MARGINAL regdir (cross-check)]  d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f d_calmar=%+.4f d_oos=%+.4f\n",
            mB$d_ir, mB$d_sr, mB$d_mdd, mB$d_port_t, mB$d_calmar, mB$d_oos))

## ---- episode active table (candidate, ic arm) -------------------------------
cat("\n[EPISODES] candidate (ic) book-active over 11 drawdown episodes:\n")
print(A$cand$episodes)
cat("\n[EPISODES] baseline (ic) book-active over 11 drawdown episodes:\n")
print(A$base$episodes)

## mean episode active (candidate, ic)
mean_epi_cand <- mean(A$cand$episodes$active, na.rm=TRUE)
mean_epi_base <- mean(A$base$episodes$active, na.rm=TRUE)
cat(sprintf("\n[MEAN EPISODE ACTIVE] candidate=%+.4f baseline=%+.4f delta=%+.4f\n",
            mean_epi_cand, mean_epi_base, mean_epi_cand-mean_epi_base))

## ---- def_z alignment to stored (vintage closeness diagnostic) ---------------
dz_close <- function(r){
  d <- r$score_eff[!is.na(def_z) & !is.na(stored_defz)]
  cor(d$def_z, d$stored_defz)
}
cat(sprintf("\n[DEF_Z cor to stored] ic: base=%.4f cand=%.4f | regdir: base=%.4f cand=%.4f\n",
            dz_close(A$base), dz_close(A$cand), dz_close(B$base), dz_close(B$cand)))

## ---- write monthly return series (paired-t) ---------------------------------
mo_cand <- A$cand$monthly[, .(realized_ym, anchor_date, ret_noL4_cand=ret_noL4)]
mo_base <- A$base$monthly[, .(realized_ym, ret_noL4_base=ret_noL4)]
mo <- merge(mo_cand, mo_base, by="realized_ym", all=TRUE); setorder(mo, realized_ym)
fwrite(mo, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c4_augment4_monthly.csv"))

## paired-t on paired monthly diffs (informational)
pd <- mo[is.finite(ret_noL4_cand) & is.finite(ret_noL4_base)]
dv <- pd$ret_noL4_cand - pd$ret_noL4_base
pt <- tryCatch(t.test(dv), error=function(e) NULL)
paired_t <- if(!is.null(pt)) as.numeric(pt$statistic) else NA_real_
cat(sprintf("[PAIRED-t monthly diff cand-base (ic)] mean=%+.6f t=%+.3f n=%d\n",
            mean(dv), paired_t, length(dv)))

## ---- persist JSON -----------------------------------------------------------
out <- list(
  candidate="c4_augment4",
  candidate_factors=CAND$factors,
  candidate_construction="Q07/M08/Q25/RE07_Crisis_Beta EW 1/4 (augment, no removal)",
  authoritative_arm="ic",
  pinned_cache=c("RAWDATA_pin20260703.parquet","benchmark_pin20260703.parquet"),
  candidate_ic=list(SR=A$cand$SR, MDD=abs(A$cand$MDD), calmar=A$cand$calmar, CAGR=A$cand$CAGR,
                    PORT_t=A$cand$PORT_t, IR=A$cand$IR, oos_retention=A$cand$oos_retention,
                    n_periods=A$cand$n_periods, mean_episode_active=mean_epi_cand),
  recon_baseline_ic=list(SR=A$base$SR, MDD=abs(A$base$MDD), calmar=A$base$calmar, CAGR=A$base$CAGR,
                    PORT_t=A$base$PORT_t, IR=A$base$IR, oos_retention=A$base$oos_retention,
                    n_periods=A$base$n_periods, mean_episode_active=mean_epi_base),
  marginal_ic=mA,
  candidate_regdir=list(SR=B$cand$SR, MDD=abs(B$cand$MDD), calmar=B$cand$calmar, CAGR=B$cand$CAGR,
                    PORT_t=B$cand$PORT_t, IR=B$cand$IR, oos_retention=B$cand$oos_retention,
                    n_periods=B$cand$n_periods),
  recon_baseline_regdir=list(SR=B$base$SR, MDD=abs(B$base$MDD), calmar=B$base$calmar, CAGR=B$base$CAGR,
                    PORT_t=B$base$PORT_t, IR=B$base$IR, oos_retention=B$base$oos_retention,
                    n_periods=B$base$n_periods),
  marginal_regdir=mB,
  episodes_candidate_ic=A$cand$episodes,
  episodes_baseline_ic=A$base$episodes,
  paired_t_monthly=list(mean_diff=mean(dv), t=paired_t, n=length(dv)),
  defz_cor_to_stored=list(ic_base=dz_close(A$base), ic_cand=dz_close(A$cand),
                          regdir_base=dz_close(B$base), regdir_cand=dz_close(B$cand))
)
write_json(out, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c4_augment4_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("\n[saved] c4_augment4_marginal.json + c4_augment4_monthly.csv\n")
saveRDS(list(A=A,B=B,marg_ic=mA,marg_regdir=mB), file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c4_augment4_run.rds"))
