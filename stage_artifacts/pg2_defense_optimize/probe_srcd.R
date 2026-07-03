ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(ED_RAW_LOCAL="C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad/RAWDATA_pin20260703_local.parquet")
Sys.setenv(ED_PANEL_SRC="ic")
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pinlocal.R"))
cat("sourced. calling ed_init...\n"); flush.console()
ed_init()
cat("ed_init DONE. RAW nrow=", nrow(.ED), "\n")
