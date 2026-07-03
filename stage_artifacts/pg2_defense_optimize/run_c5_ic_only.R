## Isolate: single IC-arm c5_regime candidate run (matches working probe_srcd order).
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
Sys.setenv(ED_RAW_LOCAL=file.path(SCRATCH,"RAWDATA_pin20260703_local.parquet"))
Sys.setenv(ED_PANEL_SRC="ic")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pinlocal.R"))

CUR_SPEC <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CRISIS_SPEC <- list(factors=c("Q07_Earnings_Stability","D48_VaR_5pct","RE07_Crisis_Beta"), weights=NULL)
REGIME_MAP <- list(NORMAL=CUR_SPEC, BULL=CUR_SPEC, CAUTION=CRISIS_SPEC, CRISIS=CRISIS_SPEC)

cat("START ic candidate — priming ed_init()\n"); flush.console()
ed_init()   ## prime cache in direct-call context (RAW read stable here)
cat("ed_init primed; running eval_defense (will early-return ed_init)\n"); flush.console()
c_ic <- eval_defense(CUR_SPEC, regime_map=REGIME_MAP, label="c5_regime_ic")
cat("DONE ic candidate\n")
saveRDS(c_ic, file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/c5_ic_cand.rds"))
oos_med <- function(x){ v <- x %||% NA_real_; if (length(v)>1) median(v, na.rm=TRUE) else v }
cat(sprintf("CAND_IC SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f n=%d\n",
            c_ic$SR, abs(c_ic$MDD), c_ic$calmar, c_ic$CAGR, c_ic$PORT_t, c_ic$IR,
            oos_med(c_ic$oos_retention), c_ic$n_periods))
cat("oos_raw:", paste(round(c_ic$oos_retention,4),collapse=","), "\n")
print(c_ic$episodes)
