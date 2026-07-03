ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(ED_RAW_LOCAL="C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet", ED_PANEL_SRC="ic")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pinlocal.R"))
ed_init()
cat("ed_init OK. building defz...\n"); flush.console()
CUR_SPEC <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CRISIS_SPEC <- list(factors=c("Q07_Earnings_Stability","D48_VaR_5pct","RE07_Crisis_Beta"), weights=NULL)
REGIME_MAP <- list(NORMAL=CUR_SPEC, BULL=CUR_SPEC, CAUTION=CRISIS_SPEC, CRISIS=CRISIS_SPEC)
defz <- .build_defz(CUR_SPEC, REGIME_MAP)
cat("defz OK nrow=", nrow(defz), "\n"); flush.console()
sc <- merge(.ED$AP[, .(Date, Ticker, score_core_z, regime_state)],
            defz[, .(Date=sig_date, Ticker, def_z)], by=c("Date","Ticker"), all.x=TRUE)
sc[, score_eff := 0.65*score_core_z + 0.35*def_z]
cat("score_eff built. running carrier_book...\n"); flush.console()
cb <- .carrier_book(sc[, .(Date, Ticker, score_eff, regime_state)])
cat("carrier_book OK nrow=", nrow(cb), "\n")
saveRDS(cb, "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/probe_cb.rds")
