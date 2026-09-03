PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressMessages(library(arrow)); suppressMessages(library(data.table))
source("02_Infrastructure/factor_db/factor_db_connector.R")

d <- as.data.table(read_parquet(".cache/rawdata.parquet"))
d[, .ym := format(Date, "%Y-%m")]
me <- sort(d[, .(Date = max(Date)), by = .ym]$Date)
me <- me[me >= as.Date("2005-01-01")]
d[, .ym := NULL]
setorder(d, Ticker, Date)
d[, .TV := Close * Vol]
d[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]

for (dd in as.list(me[seq(1, length(me), by = 60)])) {
  x <- d[Date == dd & is.finite(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(Size) & Size > 0]
  thr <- quantile(x$Size, 1/3, na.rm = TRUE)
  sm <- x[Size <= thr]
  f <- tryCatch(load_month_factors(dd, coverage_min = 0.05, factor_names = "L01_Amihud"),
                error = function(e) NULL)
  if (is.null(f) || !nrow(f)) { cat(format(dd), " NO FACTOR\n"); next }
  fz <- f[Factor_Name == "L01_Amihud" & is.finite(Z_Score_Aligned)]
  cat(sprintf("%s | smallcap n=%4d | factorDB n=%4d | overlap=%4d (%.0f%%)\n",
              format(dd), nrow(sm), nrow(fz), sum(sm$Ticker %in% fz$Ticker),
              100 * mean(sm$Ticker %in% fz$Ticker)))
}
