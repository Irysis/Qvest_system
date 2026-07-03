## eval_one.R — run ONE eval_defense in an isolated process, write result RDS+JSON.
## Args: <src: ic|regdir>  <spec: cur|cand>  <out_rds>
## Segfault isolation: single eval per process, RAW forced-materialized (break ALTREP).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
args <- commandArgs(trailingOnly=TRUE)
SRC <- args[1]; SPEC <- args[2]; OUT <- args[3]
Sys.setenv(ED_PANEL_SRC=SRC)
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))
ed_init()
## Override .ED$RAW with slim LOCAL-scratchpad pinned parquet (2003-06+, off OneDrive)
## — same pin20260703 vintage, filtered to carrier-needed range, native materialized.
## Segfault guard: removes OneDrive paging + 1990-2003 dead rows.
SCR <- Sys.getenv("ED_SCR")
rawp <- read_parquet(file.path(SCR,"RAW_pin_slim.parquet"))
raw <- data.table(Date=as.Date(rawp$Date), Ticker=as.character(rawp$Ticker),
                  Close=as.numeric(rawp$Close), Vol=as.numeric(rawp$Vol), Ret=as.numeric(rawp$Ret))
rm(rawp); raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker)
.ED$RAW <- raw
gc()
cat(sprintf("[eval_one] RAW override: %d rows, range %s..%s\n", nrow(raw),
    as.character(min(raw$Date)), as.character(max(raw$Date))))
CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","D45_Downside_Dev"), weights=NULL)
spec <- if (SPEC=="cand") CAND else CUR
r <- eval_defense(spec, label=paste0(SPEC,"_",SRC))
dz <- r$score_eff[!is.na(def_z) & !is.na(stored_defz)]
defz_cor <- cor(dz$def_z, dz$stored_defz)
res <- list(src=SRC, spec=SPEC, factors=spec$factors,
            SR=r$SR, MDD=abs(r$MDD), calmar=r$calmar, CAGR=r$CAGR,
            PORT_t=r$PORT_t, IR=r$IR, oos_retention=r$oos_retention,
            n_periods=r$n_periods, defz_cor_to_stored=defz_cor,
            episodes=r$episodes,
            monthly=r$monthly[, .(realized_ym, anchor_date, ret_noL4)])
saveRDS(res, OUT)
cat(sprintf("[eval_one DONE] src=%s spec=%s SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f defz_cor=%.4f n=%d\n",
   SRC, SPEC, r$SR, abs(r$MDD), r$calmar, r$CAGR, r$PORT_t, r$IR, r$oos_retention %||% NA_real_, defz_cor, r$n_periods))
