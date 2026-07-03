## run_arm.R — evaluate ONE arm in a fresh process, save result RDS.
## args: <src ic|regdir> <spec cand|cur> <out_rds>
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
args <- commandArgs(trailingOnly=TRUE)
src <- args[1]; spec_kind <- args[2]; out_rds <- args[3]
suppressPackageStartupMessages({library(data.table)})
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_grid.R"))

CUR_SPEC    <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CRISIS_SPEC <- list(factors=c("Q07_Earnings_Stability","D48_VaR_5pct","RE07_Crisis_Beta"), weights=NULL)
REGIME_MAP  <- list(NORMAL=CUR_SPEC, BULL=CUR_SPEC, CAUTION=CRISIS_SPEC, CRISIS=CRISIS_SPEC)

if (spec_kind=="cand"){ spec <- CUR_SPEC; rmap <- REGIME_MAP; lab <- paste0("c5_regime_",src)
} else { spec <- CUR_SPEC; rmap <- NULL; lab <- paste0("recon_cur_",src) }

Sys.setenv(ED_PANEL_SRC=src); .ED$ready <- FALSE; .ED$PANEL_SRC <- src
r <- eval_defense(spec, regime_map=rmap, label=lab)
oos_med <- function(x){ v <- x %||% NA_real_; if (length(v)>1) median(v, na.rm=TRUE) else v }
saveRDS(list(
  label=lab, src=src, spec_kind=spec_kind,
  SR=r$SR, MDD=abs(r$MDD), calmar=r$calmar, CAGR=r$CAGR, PORT_t=r$PORT_t, IR=r$IR,
  oos_retention_raw=r$oos_retention, oos_retention_median=oos_med(r$oos_retention),
  n_periods=r$n_periods, monthly=r$monthly, episodes=r$episodes,
  benchmark=r$benchmark), out_rds)
cat(sprintf("[run_arm DONE] %s SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f n=%d\n",
            lab, r$SR, abs(r$MDD), r$calmar, r$CAGR, r$PORT_t, r$IR, oos_med(r$oos_retention), r$n_periods))
