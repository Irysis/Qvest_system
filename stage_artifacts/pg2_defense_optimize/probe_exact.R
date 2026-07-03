ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
Sys.setenv(ED_RAW_LOCAL=file.path(SCRATCH,"RAWDATA_pin20260703_local.parquet"))
Sys.setenv(ED_PANEL_SRC="ic")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pinlocal.R"))
cat("ED_RAW_LOCAL=", Sys.getenv("ED_RAW_LOCAL"), " exists=", file.exists(Sys.getenv("ED_RAW_LOCAL")), "\n"); flush.console()
cat("calling ed_init directly...\n"); flush.console()
ed_init()
cat("ED_INIT OK RAW nrow=", nrow(.ED), "\n")
