## PIT size + 12-1 momentum panel at panel sig_dates (large-cap leadership cycle)
## size = market cap (RAWDATA Size) at last date < D. mom = prod(1+Ret) [D-252d, D-21d).
suppressPackageStartupMessages({library(arrow); library(data.table)})
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]; uni_tk <- unique(sp$Ticker); dts <- sort(unique(sp$Date))

d <- as.data.table(read_parquet("C:/qm_cache/RAWDATA.parquet", col_select=c("Date","Ticker","Ret","Size")))
d <- d[Ticker %in% uni_tk]; d[, Date := as.Date(Date)]; setkey(d, Ticker, Date)
d <- d[is.finite(Ret)]
PG("[PG] RAWDATA filtered rows=%d", nrow(d))

outl <- vector("list", length(dts))
for(k in seq_along(dts)){ D <- dts[k]
  win <- d[Date < D & Date > (D-400L)]
  if(nrow(win)==0) next
  ## size = last Size < D ; mom = prod(1+Ret) over [D-252d, D-21d)
  info <- win[order(Date), {
    n <- .N
    sz <- if(n>=1) Size[n] else NA_real_
    mm <- if(n>=180){ idx <- Date < (D-21L); if(sum(idx)>=120) prod(1+Ret[idx], na.rm=TRUE)-1 else NA_real_ } else NA_real_
    .(size=sz, mom=mm, nobs=n)
  }, by=Ticker]
  info <- info[is.finite(size) | is.finite(mom)]; if(nrow(info)){ info[, Date := D]; outl[[k]] <- info[, .(Date, Ticker, size, mom, nobs)] }
  if(k %% 40 == 0) PG("[PG] %d/%d D=%s n=%d", k, length(dts), as.character(D), nrow(info))
}
pm <- rbindlist(outl)
PG("[PG] size_mom panel rows=%d  size finite=%.3f mom finite=%.3f", nrow(pm), mean(is.finite(pm$size)), mean(is.finite(pm$mom)))
write_parquet(pm, file.path(WD,"panel_size_mom.parquet"))
PG("[PG] DONE saved panel_size_mom.parquet")
