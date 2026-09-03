PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressMessages(library(arrow)); suppressMessages(library(data.table))
d <- as.data.table(read_parquet(".cache/rawdata.parquet"))
last <- max(d$Date)
tk <- d[, .(first = min(Date), last = max(Date)), by = Ticker]
cat("total tickers:", nrow(tk), " | last date:", format(last), "\n")
cat("tickers whose last obs < last-30d (delisted-ish):", sum(tk$last < last - 30), "\n")
cat("tickers delisted after 2005:", sum(tk$last < last - 30 & tk$last >= as.Date("2005-01-01")), "\n")

# month-end grid
d[, .ym := format(Date, "%Y-%m")]
me <- sort(d[, .(Date = max(Date)), by = .ym]$Date)
me <- me[me >= as.Date("2005-01-01")]
d[, .ym := NULL]
setorder(d, Ticker, Date)
d[, .TV := Close * Vol]
d[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]

probe_dates <- me[seq(1, length(me), by = 48)]
for (dd in as.list(probe_dates)) {
  x <- d[Date == dd & is.finite(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(Size) & Size > 0]
  n <- nrow(x)
  thr <- if (n > 0) quantile(x$Size, 1/3, na.rm = TRUE) else NA
  sm <- x[Size <= thr]
  memx <- d[Date == dd & (K200 == TRUE | KQ150 == TRUE) & is.finite(.AvgTV20) & .AvgTV20 >= 2e8]
  cat(sprintf("%s | adv20-pass n=%4d | bottom1/3 n=%4d medSize=%.1f억 | B1-5 univ n=%3d medSize=%.1f억\n",
              format(dd), n, nrow(sm), median(sm$Size)/1e8,
              nrow(memx), if (nrow(memx)) median(memx$Size, na.rm=TRUE)/1e8 else NA))
}
