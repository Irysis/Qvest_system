##=============================================================================
## run_fdb_rebuild.R -- fdb_daily full rebuild runner (phase6+7+8, hours)
##
## Why this file exists (2026-07-17):
##   phase6/7/8 + incremental resolve their own location via
##   dirname(sys.frame(1)$ofile). sys.frame(1) is the OUTERMOST call frame,
##   so ofile only exists when the top-level call is source() of a file, and
##   the resolved dir is that file's dir. Calling update_daily_fdb_current()
##   directly from Rscript -e (as daily_refresh.sh [6b] does) leaves frame 1
##   without ofile -> tryCatch fallback to a dead /mnt/c WSL path -> abort at
##   config.R load (before any file deletion; verified 2026-07-17).
##   Sourcing THIS file (which lives in factor_db/) from cwd=02_Infrastructure
##   keeps ofile="factor_db/..." so .SELF_DIR/INFRA_DIR resolve correctly for
##   every nested phase script.
##
## Usage:
##   cd 02_Infrastructure
##   Rscript -e 'source("factor_db/run_fdb_rebuild.R")'
##
## WARNING: phase6 step [0/8] deletes ALL fdb_daily parquet before rebuild.
##   Run only on AC power, no sleep; take a backup first; must run to end.
##=============================================================================
Sys.setenv(QVEST_FDB_DAILY_AUTOREBUILD = "1")
cat(sprintf("[run_fdb_rebuild] start %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
source("factor_db/factor_db_daily_incremental.R")
update_daily_fdb_current()
cat(sprintf("[run_fdb_rebuild] ALL PHASES DONE %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
