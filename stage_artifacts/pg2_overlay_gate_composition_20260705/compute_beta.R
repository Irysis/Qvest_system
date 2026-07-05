## PIT trailing-252d per-name market beta vs KOSPI200 (pinned benchmark)
## panel Date D 행: Date < D 데이터로만 (strictly past, PIT). min 120 obs.
suppressPackageStartupMessages({library(arrow); library(data.table)})
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
RAW  <- "C:/qm_cache/RAWDATA.parquet"

## panel tickers + sig dates
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
uni_tk <- unique(sp$Ticker); dts <- sort(unique(sp$Date))
PG("[PG] panel tickers=%d sig_dates=%d", length(uni_tk), length(dts))

## RAWDATA (filter to panel tickers), pinned benchmark as market
d <- as.data.table(read_parquet(RAW, col_select=c("Date","Ticker","Ret")))
d <- d[Ticker %in% uni_tk]; d[, Date := as.Date(Date)]
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret), .(Date, mkt=BM_Ret)]
d <- merge(d, bm, by="Date"); d <- d[is.finite(Ret) & is.finite(mkt)]; setkey(d, Date)
PG("[PG] merged daily rows=%d (%s..%s)", nrow(d), as.character(min(d$Date)), as.character(max(d$Date)))

## per sig_date trailing-252d beta
outl <- vector("list", length(dts))
for(k in seq_along(dts)){ D <- dts[k]
  sub <- d[Date < D & Date > (D-400L)]                      ## strictly past, ~252 trading + buffer
  if(nrow(sub)==0) next
  sub <- sub[order(Date), tail(.SD, 252), by=Ticker, .SDcols=c("Ret","mkt")]
  bt <- sub[, .(n=.N, beta = if(.N>=120 && var(mkt)>0) cov(Ret,mkt)/var(mkt) else NA_real_), by=Ticker]
  bt <- bt[is.finite(beta)]; if(nrow(bt)) { bt[, Date := D]; outl[[k]] <- bt[, .(Date, Ticker, beta)] }
  if(k %% 40 == 0) PG("[PG] %d/%d sig_dates, D=%s n_beta=%d", k, length(dts), as.character(D), nrow(bt))
}
pb <- rbindlist(outl)
PG("[PG] beta panel rows=%d, beta range [%.2f,%.2f] mean=%.3f", nrow(pb), quantile(pb$beta,0.01), quantile(pb$beta,0.99), mean(pb$beta))
write_parquet(pb, file.path(WD,"panel_beta.parquet"))
PG("[PG] DONE saved panel_beta.parquet")
