## D2 재검 ② — 시총 기준으로 채운 원천 내부 87행 중 A008080 밖 행 + A250030: 네이버 수정주가 비율(독립 수정 계수) vs 퀀티 수정주가 비율(old) vs 시총(new)
##   네이버(KRX 수정계수)는 무상 · 분할 · 병합 · 권리락을 수정하고 제3자 신주(공모 · 전환)는 수정하지 않는다 → 보유자 수익의 독립 계기
## + A008080 반올림 행: 시총 값이 표시 가격(정수 원) 반올림 구간 안인가
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
setwd(file.path(ROOT, "02_Infrastructure")); suppressMessages(source("config.R"))
invisible(capture.output(source("data/naver_data_collector.R")))
ch <- fread(file.path(SP, "d2_changed_rows.csv")); ch[, Date := as.Date(Date)]
tg <- ch[(Date < as.Date("2026-01-01") & Ticker != "A008080") | (Ticker == "A250030")]
cat("대상", nrow(tg), "행\n")
rd <- as.data.table(open_dataset(file.path(ROOT, ".cache/RAWDATA.parquet")) |> filter(Ticker %in% unique(c(tg$Ticker, "A008080"))) |>
  select(Date, Ticker, Close, Size, Ret) |> collect())
rd[, Date := as.Date(Date)]; setorder(rd, Ticker, Date)
rd[, `:=`(pDate = shift(Date), pClose = shift(Close), raw = Close / shift(Close) - 1, mc = Size / shift(Size) - 1), by = Ticker]
nv <- rbindlist(lapply(seq_len(nrow(tg)), function(i) {
  r <- tg[i]; code <- sub("^A", "", r$Ticker)
  d <- tryCatch(as.data.table(naver_daily_adjusted(code, format(r$Date - 25, "%Y%m%d"), format(r$Date + 5, "%Y%m%d"))), error = function(e) NULL)
  Sys.sleep(0.3)
  if (is.null(d) || !nrow(d)) return(data.table(Date = r$Date, Ticker = r$Ticker, nv_ret = NA_real_, nv_prev = as.Date(NA), nv_p0 = NA_real_, nv_p1 = NA_real_, nv_note = "자료 없음"))
  setnames(d, tolower(names(d))); dc <- intersect(c("date", "dt"), names(d))[1]; cc <- intersect(c("close", "clpr"), names(d))[1]
  d[, dd := as.Date(get(dc))]; setorder(d, dd); k <- which(d$dd == r$Date)
  if (!length(k) || k == 1L) return(data.table(Date = r$Date, Ticker = r$Ticker, nv_ret = NA_real_, nv_prev = as.Date(NA), nv_p0 = NA_real_, nv_p1 = NA_real_, nv_note = "그날 행 없음"))
  data.table(Date = r$Date, Ticker = r$Ticker, nv_ret = d[[cc]][k] / d[[cc]][k - 1L] - 1, nv_prev = d$dd[k - 1L],
             nv_p0 = d[[cc]][k - 1L], nv_p1 = d[[cc]][k], nv_note = "ok")
}))
x <- merge(merge(tg, rd[, .(Date, Ticker, pDate, pClose, Close, raw, mc)], by = c("Date", "Ticker")), nv, by = c("Date", "Ticker"))
x[, verdict := fifelse(nv_note != "ok", "네이버 없음",
                 fifelse(nv_prev != pDate, "전 거래일 다름",
                   fifelse(abs(nv_ret - mc) <= 0.01, "네이버 = 시총(무상 · 분할류 → 시총 채움 확인)",
                     fifelse(abs(nv_ret - raw) <= 0.01, "네이버 = 생비율(두 원천 같은 단절)", "셋 다 다름"))))]
options(width = 250)
print(x[order(Date), .(Date, Ticker, pDate, nv_prev, qw_p0 = pClose, qw_p1 = Close, nv_p0, nv_p1, old = round(100 * raw, 2), mc = round(100 * mc, 2), naver = round(100 * nv_ret, 2), verdict)])
fwrite(x, file.path(SP, "d2_verify_naver.csv"))
## A008080 — 반올림 구간 검사
a8 <- merge(ch[Ticker == "A008080"], rd[Ticker == "A008080", .(Date, pClose, Close, mc)], by = "Date")
a8[, `:=`(lo = (Close - 0.5) / (pClose + 0.5) - 1, hi = (Close + 0.5) / pmax(pClose - 0.5, 1e-9) - 1)]
a8[, inside := is.finite(mc) & mc >= lo & mc <= hi]
cat(sprintf("\nA008080 %d행 · 표시 가격 범위 %s~%s원 · 시총 값이 반올림 구간 안 %d행 · 밖 %d행\n", nrow(a8), min(a8$pClose, a8$Close), max(a8$pClose, a8$Close), sum(a8$inside), sum(!a8$inside)))
if (any(!a8$inside)) print(a8[inside == FALSE, .(Date, pClose, Close, mc = round(100 * mc, 2), lo = round(100 * lo, 1), hi = round(100 * hi, 1))])
fwrite(a8, file.path(SP, "d2_verify_a008080.csv"))
