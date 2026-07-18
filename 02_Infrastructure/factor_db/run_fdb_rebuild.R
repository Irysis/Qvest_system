##=============================================================================
## run_fdb_rebuild.R -- DO NOT source phases 6/7/8 in ONE R process.
##
## 2026-07-18 postmortem: the 2026-07-17 run sourced phase6 -> phase7 in a
##   single Rscript session and died at phase7 [5/6] first read with
##   [Windows error 1224] (arrow mmap section from phase6's write_parquet of
##   the same file still open in-process). The historically successful
##   2026-06-08 build ran each phase as its own Rscript process.
##
## Correct full-rebuild entrypoint (separate process per phase):
##   bash 02_Infrastructure/factor_db/run_fdb_rebuild.sh
## or equivalently:
##   cd 02_Infrastructure
##   Rscript -e 'source("factor_db/factor_db_daily_phase6.R")'
##   Rscript -e 'source("factor_db/factor_db_daily_phase7.R")'
##   Rscript -e 'source("factor_db/factor_db_daily_phase8.R")'
##
## WARNING: phase6 step [0/8] deletes ALL fdb_daily parquet before rebuild.
##   AC power + no sleep + backup + run-to-completion required.
##=============================================================================
stop(paste0(
  "run_fdb_rebuild.R is a guard stub (Windows 1224 arrow-mmap: phases must run ",
  "in separate R processes). Use: bash 02_Infrastructure/factor_db/run_fdb_rebuild.sh"))
