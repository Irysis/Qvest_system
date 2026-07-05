# PATH B: KRX MDC public data portal (data.krx.co.kr) — no auth
# Two-step pattern: (1) POST to generate.cmd to register a query -> returns a code
#                   (2) POST to download.cmd / getJsonData.cmd with that code
# The modern portal uses: http://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd
# with a 'bld' parameter selecting the report template.
#
# Short-selling reports (공매도종합포털 bld codes, MDC):
#   dbms/MDC/STAT/srt/MDCSTAT30101  (공매도 거래현황 - 종목별)
#   dbms/MDC/STAT/srt/MDCSTAT30501  (공매도 잔고 - 종목별, 2016-06~)
#   dbms/MDC/STAT/srt/MDCSTAT30401  (공매도 잔고 상위 50)
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

MDC_URL <- "http://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd"
REFERER <- "http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020506"

mdc_probe <- function(params, label) {
  cat(sprintf("\n=== MDC probe: %s ===\n", label))
  resp <- tryCatch(
    POST(MDC_URL,
         body = params, encode = "form",
         add_headers(
           `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
           `Referer` = REFERER,
           `X-Requested-With` = "XMLHttpRequest",
           `Accept` = "application/json, text/javascript, */*; q=0.01"
         ), timeout(25)),
    error = function(e) { cat("  [ERR]", conditionMessage(e), "\n"); NULL })
  if (is.null(resp)) return(NULL)
  sc <- status_code(resp)
  txt <- content(resp, "text", encoding = "UTF-8")
  cat(sprintf("  HTTP %d  bytes=%d\n", sc, nchar(txt)))
  if (sc == 200 && nchar(txt) > 2) {
    parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
    if (!is.null(parsed)) {
      cat("  top-level keys:", paste(names(parsed), collapse=", "), "\n")
      blk <- NULL
      for (k in names(parsed)) {
        if (is.data.frame(parsed[[k]]) && nrow(parsed[[k]]) > 0) { blk <- parsed[[k]]; cat("  data block:", k, "rows:", nrow(blk), "\n"); break }
      }
      if (!is.null(blk)) {
        cat("  cols:", paste(names(blk), collapse=","), "\n")
        print(head(as.data.table(blk), 3))
        return(as.data.table(blk))
      } else {
        cat("  no non-empty data.frame block. raw head:", substr(txt, 1, 400), "\n")
      }
    } else {
      cat("  JSON parse fail. raw head:", substr(txt, 1, 400), "\n")
    }
  } else {
    cat("  raw head:", substr(txt, 1, 300), "\n")
  }
  NULL
}

# Probe date: a settled recent business day
d <- "20260630"

# 30501: 개별종목 공매도 잔고 (balance, per stock) — needs isuCd usually OR mktId for aggregate.
# First try the "전종목" style via mktId. Samsung 005930 as single-stock fallback.
mdc_probe(list(
  bld = "dbms/MDC/STAT/srt/MDCSTAT30501",
  locale = "ko_KR",
  searchType = "1",
  mktTpCd = "1",
  trdDd = d,
  strtDd = d, endDd = d,
  share = "1", money = "1", csvxls_isNo = "false"
), "MDCSTAT30501 balance mktTp=KOSPI single-day")

# 30101: 공매도 거래현황 per-stock by market on a day
mdc_probe(list(
  bld = "dbms/MDC/STAT/srt/MDCSTAT30101",
  locale = "ko_KR",
  mktTpCd = "1",
  trdDd = d,
  inqCond = "STR",
  share = "1", money = "1", csvxls_isNo = "false"
), "MDCSTAT30101 trade mktTp=KOSPI single-day")

# Balance top list 30401 (aggregate, no isu needed)
mdc_probe(list(
  bld = "dbms/MDC/STAT/srt/MDCSTAT30401",
  locale = "ko_KR",
  mktTpCd = "1",
  trdDd = d,
  share = "1", money = "1", csvxls_isNo = "false"
), "MDCSTAT30401 balance-top mktTp=KOSPI single-day")

cat("\nDONE PATH B\n")
