## run_one_arm_generic.R — evaluate ONE defense spec on ONE panel, in a fresh process.
## Args: SRC(ic|regdir)  SPEC(cur|cand)  OUTTAG
## Writes <OUTTAG>.rds with the eval_defense() result (metrics + monthly + episodes).
## Fresh-process isolation avoids accumulated arrow-mmap/memory segfault on this box.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(1L), silent=TRUE))
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R")); setDTthreads(1L)
OUT <- file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize")
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
RAW_PIN_LOCAL <- file.path(SCRATCH,"RAWDATA_pin.parquet")
BM_PIN_LOCAL  <- file.path(SCRATCH,"benchmark_pin.parquet")

args <- commandArgs(trailingOnly=TRUE)
SRC <- args[1]; SPEC_ID <- args[2]; OUTTAG <- args[3]
stopifnot(SRC %in% c("ic","regdir"), SPEC_ID %in% c("cur","cand"))

CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","RE07_Crisis_Beta"), weights=NULL)
spec <- if (SPEC_ID=="cur") CUR else CAND

## manual ed_init (local pinned caches; byte-identical to .cache pins)
.ED$PANEL_SRC <- SRC
panel_file <- if (identical(SRC,"ic")) "defense_factor_panel.parquet" else "defense_factor_panel_regdir.parquet"
.ED$PANEL <- as.data.table(read_parquet(file.path(OUT,panel_file))); .ED$PANEL[, sig_date := as.Date(sig_date)]
ap <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date := as.Date(Date)]
.ED$AP <- ap[, .(Date, Ticker, score_core_z, score_defense_z, score_eff, regime_state)]
raw <- as.data.table(read_parquet(RAW_PIN_LOCAL, col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker); .ED$RAW <- raw
p5 <- fread(file.path(ED_ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p5[, anchor_date := as.Date(anchor_date)]; setorder(p5, realized_ym)
.ED$P5 <- p5[, .(realized_ym, anchor_date, regime5=regime, beta_R05, m4, ret_orig_book=ret_orig)]
bm <- as.data.table(read_parquet(BM_PIN_LOCAL)); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date); .ED$BM_X <- xts(bm$BM_Ret, order.by=bm$Date)
.ED$EPI <- fread(file.path(ED_ROOT,"stage_artifacts/pg2_defense_drawdown/episodes.csv")); .ED$ready <- TRUE
cat(sprintf("[ed] SRC=%s SPEC=%s panel=%s\n", SRC, SPEC_ID, panel_file)); flush.console()

r <- eval_defense(spec, label=OUTTAG)
out <- list(
  SRC=SRC, SPEC_ID=SPEC_ID, spec=spec$factors,
  SR=r$SR, MDD=abs(r$MDD), calmar=r$calmar, CAGR=r$CAGR, PORT_t=r$PORT_t, IR=r$IR,
  oos_retention=r$oos_retention, n_periods=r$n_periods,
  monthly=r$monthly, episodes=r$episodes)
saveRDS(out, file.path(OUT, paste0(OUTTAG,".rds")))
cat(sprintf("[DONE %s] SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%s n=%d\n",
    OUTTAG, r$SR, abs(r$MDD), r$calmar, r$CAGR, r$PORT_t, r$IR,
    paste(round(r$oos_retention,4),collapse=","), r$n_periods))
