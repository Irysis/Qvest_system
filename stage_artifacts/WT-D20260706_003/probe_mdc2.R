# PATH B v2: KRX MDC with proper session handshake
# Step 1: GET loader page -> establishes JSESSIONID cookie in handle
# Step 2: POST getJsonData.cmd with same handle (cookie carried) + Referer
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

h <- handle("http://data.krx.co.kr")
UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

# Step 1: warm up session by loading the short-selling stat page
warm <- tryCatch(
  GET("http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020506",
      add_headers(`User-Agent` = UA), handle = h, timeout(25)),
  error = function(e) { cat("[warm ERR]", conditionMessage(e), "\n"); NULL })
if (!is.null(warm)) cat("Warm-up GET status:", status_code(warm), "\n")

# Also try the getJsonData with full browser-like headers using SAME handle
MDC_URL <- "http://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd"

mdc_post <- function(params, label, referer) {
  cat(sprintf("\n=== %s ===\n", label))
  resp <- tryCatch(
    POST(MDC_URL, body = params, encode = "form", handle = h,
         add_headers(
           `User-Agent` = UA,
           `Referer` = referer,
           `Origin` = "http://data.krx.co.kr",
           `X-Requested-With` = "XMLHttpRequest",
           `Accept` = "application/json, text/javascript, */*; q=0.01",
           `Accept-Language` = "ko-KR,ko;q=0.9,en;q=0.8"
         ), timeout(25)),
    error = function(e) { cat("  [ERR]", conditionMessage(e), "\n"); NULL })
  if (is.null(resp)) return(NULL)
  sc <- status_code(resp)
  txt <- content(resp, "text", encoding = "UTF-8")
  cat(sprintf("  HTTP %d  bytes=%d\n", sc, nchar(txt)))
  if (sc == 200 && nchar(txt) > 2 && !grepl("^LOGOUT", txt)) {
    parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
    if (!is.null(parsed)) {
      cat("  keys:", paste(names(parsed), collapse=", "), "\n")
      for (k in names(parsed)) {
        if (is.data.frame(parsed[[k]]) && nrow(parsed[[k]]) > 0) {
          blk <- as.data.table(parsed[[k]])
          cat("  data block:", k, "rows:", nrow(blk), " cols:", paste(names(blk), collapse=","), "\n")
          print(head(blk, 3)); return(blk)
        }
      }
      cat("  no non-empty block. head:", substr(txt,1,400), "\n")
    }
  } else {
    cat("  head:", substr(txt, 1, 200), "\n")
  }
  NULL
}

REF <- "http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020506"
d <- "20260630"

# 공매도 잔고 종목별 (balance) - MDCSTAT30501 : requires trdDd + mktId
mdc_post(list(
  bld = "dbms/MDC/STAT/srt/MDCSTAT30501",
  locale = "ko_KR", mktId = "STK", trdDd = d,
  share = "1", money = "1", csvxls_isNo = "false"
), "30501 balance mktId=STK", REF)

# 공매도 거래 종목별 - MDCSTAT30101
mdc_post(list(
  bld = "dbms/MDC/STAT/srt/MDCSTAT30101",
  locale = "ko_KR", mktId = "STK", trdDd = d, inqCondTpCd = "1",
  share = "1", money = "1", csvxls_isNo = "false"
), "30101 trade mktId=STK", REF)

# save cookies for inspection
cat("\n--- cookies ---\n")
print(cookies(h))
cat("\nDONE\n")
