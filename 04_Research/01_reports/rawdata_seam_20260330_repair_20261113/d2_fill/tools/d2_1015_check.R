## A250030 10-15 종가 불일치(퀀티 14,940 vs 거래소 14,350) — 그 종목 앞뒤 날짜 + 같은 날 무작위 30종목을 공식 종가와 대조
##   + A012170 1997-12-26 → 1998-01-05 네이버 수정주가 비율(같은 구간)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr); library(jsonlite) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
setwd(file.path(ROOT, "02_Infrastructure")); suppressMessages(source("config.R"))
invisible(capture.output(source("data/naver_data_collector.R")))
rd <- as.data.table(open_dataset(file.path(ROOT, ".cache/RAWDATA.parquet")) |> filter(Date >= as.Date("2026-10-08"), Date <= as.Date("2026-10-21")) |>
  select(Date, Ticker, Close, Vol, Ret, source) |> collect())
rd[, Date := as.Date(Date)]
api <- function(code, n = 30) {
  u <- sprintf("https://m.stock.naver.com/api/stock/%s/price?pageSize=%d&page=1", code, n)
  d <- tryCatch(fromJSON(u), error = function(e) NULL); Sys.sleep(0.12)
  if (is.null(d) || !length(d)) return(NULL)
  data.table(Date = as.Date(d$localTradedAt), off_close = as.numeric(gsub(",", "", d$closePrice)), off_vol = as.numeric(d$accumulatedTradingVolume))
}
a <- api("250030", 40)
x <- merge(rd[Ticker == "A250030", .(Date, Close, Vol, Ret, source)], a, by = "Date", all.x = TRUE)
options(width = 220); cat("## A250030 퀀티 vs 거래소\n"); print(x)
set.seed(20261114)
tk <- sample(unique(rd[Date == as.Date("2026-10-15") & is.finite(Close) & Close >= 1000]$Ticker), 30)
cmp <- rbindlist(lapply(tk, function(t) { z <- api(sub("^A", "", t), 30); if (is.null(z)) return(NULL)
  merge(rd[Ticker == t & Date %in% as.Date(c("2026-10-14", "2026-10-15", "2026-10-16")), .(Date, Ticker, Close, Vol)], z, by = "Date") }))
cmp[, same := abs(Close - off_close) < 0.5]
cat("\n## 무작위 30종목 · 날짜별 종가 일치\n"); print(cmp[, .(n = .N, same = sum(same)), by = Date])
if (any(!cmp$same)) print(cmp[same == FALSE])
## A012170 — 수정주가 비율(같은 구간 1997-12-26 → 1998-01-05)
d <- as.data.table(naver_daily_adjusted("012170", "19971215", "19980110"))
setnames(d, tolower(names(d))); dc <- intersect(c("date", "dt"), names(d))[1]; cc <- intersect(c("close", "clpr"), names(d))[1]
d[, dd := as.Date(get(dc))]
cat("\n## A012170 네이버 수정주가 1997-12-15 ~ 1998-01-10\n"); print(d[, .(dd, close = get(cc))])
p0 <- d[dd == as.Date("1997-12-26"), get(cc)]; p1 <- d[dd == as.Date("1998-01-05"), get(cc)]
cat(sprintf("12-26 → 01-05 수정주가 비율 = %.2f%% (시총 기준 채움 +0.88%%)\n", 100 * (p1 / p0 - 1)))
