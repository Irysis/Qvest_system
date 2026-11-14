## 표본 — 2024-11 ~ 2026-11 · 오늘도 상장된 종목 12개(무작위 · 종가 1,000원 이상) · Date,Ticker,Close,Vol,source
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
rd <- as.data.table(open_dataset(file.path(ROOT, ".cache/RAWDATA.parquet")) |> filter(Date >= as.Date("2024-11-01")) |>
  select(Date, Ticker, Close, Vol, source) |> collect())
rd[, Date := as.Date(Date)]
last <- max(rd$Date)
alive <- rd[Date == last & is.finite(Close) & Close >= 1000, Ticker]
old <- rd[Date == as.Date("2024-11-01"), Ticker]
set.seed(7)
tk <- sample(intersect(alive, old), 12)
s <- rd[Ticker %in% tk]
fwrite(s[, .(Date = as.character(Date), Ticker, Close, Vol, source)], file.path(SP, "close_match_sample.csv"))
cat("표본", length(tk), "종목 ·", nrow(s), "행 · 원천 분포:\n"); print(s[, .N, by = .(source, m = format(Date, "%Y-%m"))][order(m)][, .(m, source, N)], nrows = 60)
