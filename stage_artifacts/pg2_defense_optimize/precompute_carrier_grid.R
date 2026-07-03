## ============================================================================
## precompute_carrier_grid.R — precompute arm-INVARIANT walk-forward grid in ONE pass.
##
## Forward returns + liquidity depend ONLY on the sig_date grid (alpha AP dates), not on
## the defense spec. Precompute once -> removes the 270 repeated `raw[Date>a & Date<=b]`
## full-column scans (each a 13.9M-row logical alloc) that segfault under fragmentation.
## Window assignment uses base findInterval (fast, low-alloc), then ONE grouped aggregation.
##
## Window convention (verbatim from eval_defense_pinlocal .carrier_book):
##   start_d(i) = first trade date >= sig_date(i);  end_d(i) = start_d(i+1)
##   forward return over (start_d(i), end_d(i)] ; liquidity ADV over [start_d(i)-30, start_d(i))
## Segfault guards: setDTthreads(1), local col_select read, single grouped pass, no per-iter alloc.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
RAWL <- file.path(SCRATCH,"RAWDATA_pin20260703_local.parquet")

cat("[precompute] reading RAW (col_select, local)...\n"); flush.console()
raw <- as.data.table(read_parquet(RAWL, col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]
cat("[precompute] RAW rows=", nrow(raw), "\n"); flush.console()

ap <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
sig_dates <- sort(unique(ap$Date))
trade_dates <- sort(unique(raw$Date))

## start_d(i) = first trade date >= sig_date(i)
idx <- findInterval(as.numeric(sig_dates) - 1e-9, as.numeric(trade_dates)) + 1L  # first td >= sig
idx[idx > length(trade_dates)] <- NA_integer_
starts <- trade_dates[idx]
keep <- !is.na(starts)
sig_dates2 <- sig_dates[keep]; starts <- starts[keep]
ord <- order(starts); sig_dates2 <- sig_dates2[ord]; starts <- starts[ord]
## dedupe (two sig_dates could map to same start)
dup <- duplicated(starts); sig_dates2 <- sig_dates2[!dup]; starts <- starts[!dup]
ends <- c(starts[-1L], max(trade_dates))
map_start <- data.table(sig_label=sig_dates2, start_d=starts, end_d=ends)
cat("[precompute] windows=", nrow(map_start), " range", as.character(min(starts)),
    "-", as.character(max(starts)), "\n"); flush.console()

## ---- forward returns: window index of each raw Date = findInterval on starts, using
## the (start_d, end_d] convention: a Date D belongs to window i s.t. start_d(i) < D <= start_d(i+1).
## findInterval(D, starts) gives j = #{starts <= D}. For D>start(j) that's window j; for D==start(j)
## it must go to window j-1 (D is the eval boundary of the prior window). Adjust exact matches.
rawD <- as.numeric(raw$Date); startsN <- as.numeric(starts)
j <- findInterval(rawD, startsN)                      # #{start <= D}
onstart <- rawD %in% startsN & (match(rawD, startsN) == j)  # D exactly equals start(j)
j[onstart] <- j[onstart] - 1L                          # boundary row -> prior window
raw[, widx := j]
rr <- raw[widx >= 1L & widx <= nrow(map_start), .(widx, Ticker, Ret)]
rr[, sig_label := map_start$sig_label[widx]]
fwd <- rr[, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by=.(sig_label, Ticker)]
cat("[precompute] fwd rows=", nrow(fwd), "\n"); flush.console()

## ---- liquidity ADV over [start_d-30, start_d) via ONE non-equi join
liq_win <- map_start[, .(sig_label, lo=start_d-30L, hi=start_d)]
rl <- raw[, .(Date, Ticker, TradingAmt)]
adv_join <- liq_win[rl, on=.(lo <= Date, hi > Date), nomatch=NULL,
                    .(sig_label=x.sig_label, Ticker=i.Ticker, TradingAmt=i.TradingAmt)]
adv <- adv_join[, .(ADV = mean(TradingAmt, na.rm=TRUE)), by=.(sig_label, Ticker)]
cat("[precompute] adv rows=", nrow(adv), "\n"); flush.console()

grid <- list(window=map_start, fwd=fwd, adv=adv,
             sig_dates=sig_dates, max_trade_date=max(trade_dates))
setkey(grid$fwd, sig_label, Ticker); setkey(grid$adv, sig_label, Ticker)
saveRDS(grid, file.path(SCRATCH,"carrier_grid.rds"))
cat(sprintf("[precompute] DONE. window=%d fwd=%d adv=%d. saved carrier_grid.rds\n",
            nrow(grid$window), nrow(grid$fwd), nrow(grid$adv)))
