# diag_tail.R — B2-6 vs B1-5 월말 그리드 말단 6개월 차이 원인 규명 (진단 전용)
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressPackageStartupMessages(library(data.table))
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

r <- load_rawdata(use_cache = TRUE); RAWDATA <- r$RAWDATA; rm(r); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]
me <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date); RAWDATA[, .ym := NULL]
me <- me[me >= as.Date("2004-11-01")]
cat("month_ends total:", length(me), "| last:", format(tail(me, 8)), "\n")

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
mem <- RAWDATA[Date %in% me & (K200 == TRUE | KQ150 == TRUE) &
                 is.finite(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
mom_all <- RAWDATA[Date %in% me & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
setkey(mom_all, Date, Ticker)

for (d in tail(me, 8)) {
  d <- as.Date(d, origin = "1970-01-01")
  uni <- mem[.(d), Ticker, nomatch = 0L]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = "L01_Amihud"),
                  error = function(e) NULL)
  nilq <- if (is.null(fdt)) 0L else nrow(fdt[Factor_Name == "L01_Amihud" & is.finite(Z_Score_Aligned)])
  nmom <- nrow(mom_all[.(d), nomatch = 0L])
  ncmb <- if (nilq == 0L) 0L else {
    ilq <- fdt[Factor_Name == "L01_Amihud" & is.finite(Z_Score_Aligned), .(Ticker, Ilq = Z_Score_Aligned)][Ticker %in% uni]
    mm <- mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni]
    nrow(merge(ilq, mm, by = "Ticker"))
  }
  cat(sprintf("%s | uni=%d | ilq=%d | mom=%d | cmb=%d %s\n",
              format(d), length(uni), nilq, nmom, ncmb,
              if (ncmb < 30L) "<-- DROP (cmb<30)" else ""))
}
