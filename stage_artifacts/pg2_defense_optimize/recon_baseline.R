## ============================================================================
## recon_baseline.R — pinned recon baseline for the CURRENT defense sleeve
## (Q07/M08/Q25 EW), the standard against which candidate marginals are judged.
##
## Design (도훈 mandate + PARITY_DIAGNOSIS §alternative, made rigorous):
##  - frozen ret_orig verbatim reproduces SR 1.898/MDD 0.233 (parity_stored.R = Gate1).
##  - candidates lack a frozen ret_orig (different factor set) -> recon unavoidable.
##  - Therefore judgment = recon-vs-recon marginal on IDENTICAL pinned caches, so the
##    carrier re-derivation "drift" (recon SR != frozen SR) cancels between arms.
##  - This script produces the CURRENT-defense recon (the marginal denominator) and
##    reports its gap to frozen 1.898, plus the regdir-vs-IC direction-alignment
##    effect (how much closer regdir gets recon to frozen -> marginal reliability).
##
## Caches pinned: RAWDATA_pin20260703 + benchmark_pin20260703 (self-consistent).
## Direction: registry FIXED (regdir panel) — IC-sign vintage instability removed.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))

CUR <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)

## ---- Arm 1: pinned + REGDIR (the authoritative recon baseline) --------------
Sys.setenv(ED_PANEL_SRC="regdir")
.ED$ready <- FALSE; .ED$PANEL_SRC <- "regdir"
cat("\n=== RECON BASELINE: pinned + regdir (Q07/M08/Q25 EW) ===\n")
r_reg <- eval_defense(CUR, label="recon_regdir")

## ---- Arm 2: pinned + IC panel (direction-alignment drift comparison) --------
Sys.setenv(ED_PANEL_SRC="ic")
.ED$ready <- FALSE; .ED$PANEL_SRC <- "ic"
cat("\n=== COMPARISON: pinned + IC-sign panel (Q07/M08/Q25 EW) ===\n")
r_ic <- eval_defense(CUR, label="recon_ic")

## ---- def_z alignment to stored (proxy for vintage closeness) ----------------
dz_close <- function(r){
  d <- r$score_eff[!is.na(def_z) & !is.na(stored_defz)]
  list(maxdiff=max(abs(d$def_z-d$stored_defz)), cor=cor(d$def_z,d$stored_defz), n=nrow(d))
}
c_reg <- dz_close(r_reg); c_ic <- dz_close(r_ic)

FROZEN <- list(SR=1.898, MDD=0.233, PORT_t=6.21, IR=1.416, calmar=NA, oos=NA)
summ <- function(r, arm){
  data.table(arm=arm, SR=round(r$SR,4), MDD=round(abs(r$MDD),4), calmar=round(r$calmar,4),
             CAGR=round(r$CAGR,4), PORT_t=round(r$PORT_t,4), IR=round(r$IR,4),
             oos_retention=round(r$oos_retention %||% NA,4), n=r$n_periods)
}
tbl <- rbind(summ(r_reg,"pinned_regdir"), summ(r_ic,"pinned_ic"))
cat("\n===== RECON METRICS =====\n"); print(tbl)

cat(sprintf("\n[FROZEN GAP] regdir recon vs frozen: dSR=%+.4f dMDD=%+.4f dPORT_t=%+.4f dIR=%+.4f\n",
            r_reg$SR-FROZEN$SR, abs(r_reg$MDD)-FROZEN$MDD, r_reg$PORT_t-FROZEN$PORT_t, r_reg$IR-FROZEN$IR))
cat(sprintf("[FROZEN GAP] ic     recon vs frozen: dSR=%+.4f dMDD=%+.4f dPORT_t=%+.4f dIR=%+.4f\n",
            r_ic$SR-FROZEN$SR, abs(r_ic$MDD)-FROZEN$MDD, r_ic$PORT_t-FROZEN$PORT_t, r_ic$IR-FROZEN$IR))

cat(sprintf("\n[DEF_Z vs STORED] regdir: max|diff|=%.4f cor=%.5f | ic: max|diff|=%.4f cor=%.5f (higher cor = closer to freeze vintage)\n",
            c_reg$maxdiff, c_reg$cor, c_ic$maxdiff, c_ic$cor))

cat("\n[EPISODES] regdir recon book-active over 11 drawdown episodes:\n")
print(r_reg$episodes)

## ---- persist baseline for candidate comparison ------------------------------
baseline <- list(
  arm="pinned_regdir", spec=CUR,
  SR=r_reg$SR, MDD=abs(r_reg$MDD), calmar=r_reg$calmar, CAGR=r_reg$CAGR,
  PORT_t=r_reg$PORT_t, IR=r_reg$IR, oos_retention=r_reg$oos_retention, n_periods=r_reg$n_periods,
  frozen=list(SR=1.898, MDD=0.233, PORT_t=6.21, IR=1.416),
  frozen_gap=list(dSR=r_reg$SR-1.898, dMDD=abs(r_reg$MDD)-0.233,
                  dPORT_t=r_reg$PORT_t-6.21, dIR=r_reg$IR-1.416),
  defz_cor_regdir=c_reg$cor, defz_cor_ic=c_ic$cor,
  episodes=r_reg$episodes,
  ic_recon=list(SR=r_ic$SR, MDD=abs(r_ic$MDD), PORT_t=r_ic$PORT_t, IR=r_ic$IR,
                calmar=r_ic$calmar, oos_retention=r_ic$oos_retention))
saveRDS(baseline, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/recon_baseline.rds"))
write_json(baseline[c("arm","SR","MDD","calmar","CAGR","PORT_t","IR","oos_retention",
                      "n_periods","frozen","frozen_gap","defz_cor_regdir","defz_cor_ic")],
           file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/recon_baseline.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("\n[saved] recon_baseline.rds + recon_baseline.json\n")
