# .chk_data.R — 산출물 아님 (읽기 전용 데이터 커버리지 프로브 · 삭제해도 무방)
#   2026-09-06 재구현 세션에서 R 실행이 차단돼 돌리지 못했다. 수동 실행:
#     Rscript -e 'source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/strategies/RP_AUTO_2404_08129/.chk_data.R")'
#   보는 것: RAWDATA 열·기간·멤버십 시작, KR_CD91 커버리지(→ 엔진의 첫 형성일을 정한다: FIDELITY.json changed(4)).
suppressMessages({ library(arrow); library(data.table) })
p <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/RAWDATA.parquet"
cat("cols:", paste(names(read_parquet(p, as_data_frame = FALSE)), collapse = ","), "\n")
d <- as.data.table(read_parquet(p, col_select = c("Date", "Ticker", "K200", "KQ150", "Close", "Vol")))
d[, Date := as.Date(Date)]
cat("rows", nrow(d), "range", format(min(d$Date)), format(max(d$Date)), "tickers", uniqueN(d$Ticker), "\n")
cat("K200 first TRUE:", format(min(d[K200 == TRUE, Date])), " KQ150 first TRUE:", format(min(d[KQ150 == TRUE, Date])), "\n")
cat("class K200:", class(d$K200), " class Vol:", class(d$Vol), " Close:", class(d$Close), "\n")
m <- d[, .(n = uniqueN(Ticker), nk = uniqueN(Ticker[K200 == TRUE]), nq = uniqueN(Ticker[KQ150 == TRUE]),
           medTV = median(Close * Vol, na.rm = TRUE)), by = .(y = year(Date))][order(y)]
print(m, nrows = 60)
e <- as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/ecos_bond_rates.parquet"))
cat("ecos cols:", paste(names(e), collapse = ","), "\n")
print(e[, .(n = .N, from = format(min(as.Date(Date))), to = format(max(as.Date(Date))), na = sum(is.na(Value))), by = Series])
print(head(e[Series == "KR_CD91"], 3)); print(tail(e[Series == "KR_CD91"], 3))
bm <- as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/benchmark.parquet"))
cat("BM cols:", paste(names(bm), collapse = ","), " range:", format(min(as.Date(bm$Date))), format(max(as.Date(bm$Date))), "\n")
