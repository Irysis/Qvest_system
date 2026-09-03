# C14 same-day 릴리스 1건 열거 + 영향 범위 실측 (B1-4)
suppressWarnings(suppressMessages({ library(arrow); library(data.table); library(jsonlite) }))
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- file.path(ROOT, "04_Research/strategies/RF_B1_4_MomRevision")
eb <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus/esbr.parquet")))
eb <- eb[!is.na(esbr)]; eb[, Date := as.Date(Date)]; setorder(eb, Ticker, Date)
eb[, newrun := is.na(shift(esbr)) | Ticker != shift(Ticker) | abs(esbr - shift(esbr)) > 1e-12]
runs <- eb[newrun == TRUE, .(Ticker, Release_Date = Date, esbr)]
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
RD <- load_rawdata(TRUE)$RAWDATA
if (!inherits(RD$Date, "Date")) RD[, Date := as.Date(Date)]
RD[, .ym := format(Date, "%Y-%m")]
sig_dates <- sort(RD[, .(Date = max(Date)), by = .ym]$Date)
hit <- runs[Release_Date %in% sig_dates]
cat("[enum] same-day rows:\n"); print(hit)
# 그 (Ticker, Date) 가 유니버스 안이었나 + 그 달 유니버스 규모
inf <- rbindlist(lapply(seq_len(nrow(hit)), function(i) {
  d <- hit$Release_Date[i]; tk <- hit$Ticker[i]
  sub <- RD[Date == d]
  uni <- sub[(K200 == TRUE | KQ150 == TRUE), .N]
  data.table(Ticker = tk, Date = d, in_univ_that_day = tk %in% sub[(K200==TRUE|KQ150==TRUE), Ticker],
             univ_n = uni, in_backtest_window = d >= as.Date("2005-01-01"))
}))
cat("[enum] impact:\n"); print(inf)
write_json(list(same_day_rows = hit, impact = inf,
  note = "위반 가능 케이스 전수. in_univ_that_day=FALSE 또는 in_backtest_window=FALSE 면 B1-4 스코어에 미도달"),
  file.path(OUT_DIR, "c14_same_day_enum.json"), auto_unbox = TRUE, pretty = TRUE)
