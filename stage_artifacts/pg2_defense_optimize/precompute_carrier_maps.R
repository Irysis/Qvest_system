## precompute_carrier_maps.R — SINGLE-PASS build of per-month forward-return + liquidity
## maps from pinned RAW. Avoids ALL repeated big-DT range subsets (iter-32 segfault locus)
## by tagging every raw row with its window index once via findInterval, then one groupby.
## Spec-INDEPENDENT (depends only on sig calendar + RAW); both CUR/CAND arms reuse.
suppressPackageStartupMessages({library(data.table); library(arrow)})
options(scipen=999); setDTthreads(1L); suppressWarnings(try(arrow::set_io_thread_count(1L),silent=TRUE))
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
S <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
raw <- as.data.table(read_parquet(file.path(S,"RAWDATA_pin.parquet"), col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]
ap <- as.data.table(read_parquet(file.path(R,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date := as.Date(Date)]
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))
TD <- sort(unique(raw$Date))
first_ge <- function(x){ i <- findInterval(as.numeric(x)-1e-9, as.numeric(TD)); if (i>=length(TD)) return(length(TD)); i+1L }  # returns TD index
nb <- length(sig_dates)-1L
## window bounds as TD indices
start_ix <- integer(nb); end_ix <- integer(nb)
for (i in seq_len(nb)){ start_ix[i] <- first_ge(sig_dates[i]); end_ix[i] <- first_ge(sig_dates[i+1L]) }
start_d <- TD[start_ix]; end_d <- TD[end_ix]; liq_lo <- start_d - 30L
cat("windows built nb=",nb,"\n"); flush.console()

## ---- FORWARD RETURN MAP via non-equi join (exact) --------------------------
## Window i covers (start_d[i], end_d[i]]. Non-equi join tags each raw row with idx.
raw2 <- raw[, .(Date, Ticker, Ret, TradingAmt)]
fwin <- data.table(idx=seq_len(nb), lo=start_d, hi=end_d)
tagged <- raw2[fwin, on=.(Date > lo, Date <= hi), allow.cartesian=TRUE, nomatch=NULL,
               .(idx, Ticker, Ret)]
FWD <- tagged[, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by=.(idx, Ticker)]
cat("FWD rows=",nrow(FWD)," distinct idx=",length(unique(FWD$idx)),"\n"); flush.console()
rm(tagged); gc()

## ---- LIQUIDITY MAP via non-equi join: ADV over [start_d[i]-30, start_d[i]) --
lwin <- data.table(idx=seq_len(nb), lo=liq_lo, hi=start_d)
taggedl <- raw2[lwin, on=.(Date >= lo, Date < hi), allow.cartesian=TRUE, nomatch=NULL,
                .(idx, Ticker, TradingAmt)]
LIQ <- taggedl[, .(ADV = mean(TradingAmt, na.rm=TRUE)), by=.(idx, Ticker)]
cat("LIQ rows=",nrow(LIQ)," distinct idx=",length(unique(LIQ$idx)),"\n"); flush.console()
rm(taggedl); gc()

win_out <- data.table(idx=seq_len(nb), sig_label=sig_dates[seq_len(nb)], next_sig=sig_dates[seq_len(nb)+1L],
                      start_d=start_d, end_d=end_d)
saveRDS(list(win=win_out, FWD=FWD, LIQ=LIQ, nb=nb), file.path(S,"carrier_maps.rds"))
cat(sprintf("[precompute DONE] nb=%d FWD_rows=%d LIQ_rows=%d\n", nb, nrow(FWD), nrow(LIQ)))
