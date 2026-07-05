# PATH B v3: try the exact short-selling menu referer + sanity-check a KNOWN-WORKING bld
# to isolate whether "LOGOUT" is a session issue or a bld/param issue.
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

h <- handle("http://data.krx.co.kr")
UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
GET("http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020101",
    add_headers(`User-Agent` = UA), handle = h, timeout(25))

MDC_URL <- "http://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd"
post_bld <- function(params, label, referer) {
  cat(sprintf("\n=== %s ===\n", label))
  resp <- tryCatch(POST(MDC_URL, body = params, encode = "form", handle = h,
    add_headers(`User-Agent`=UA, `Referer`=referer, `Origin`="http://data.krx.co.kr",
                `X-Requested-With`="XMLHttpRequest",
                `Accept`="application/json, text/javascript, */*; q=0.01"), timeout(25)),
    error=function(e){cat("[ERR]",conditionMessage(e),"\n");NULL})
  if (is.null(resp)) return(invisible(NULL))
  sc <- status_code(resp); txt <- content(resp,"text",encoding="UTF-8")
  cat(sprintf("  HTTP %d bytes=%d head=%s\n", sc, nchar(txt), substr(gsub("\n"," ",txt),1,120)))
  if (sc==200 && !grepl("^LOGOUT", txt)) {
    p <- tryCatch(fromJSON(txt), error=function(e)NULL)
    if(!is.null(p)) for(k in names(p)) if(is.data.frame(p[[k]]) && nrow(p[[k]])>0){
      cat("  block",k,"rows",nrow(p[[k]]),"cols:",paste(names(p[[k]]),collapse=","),"\n")
      print(head(as.data.table(p[[k]]),2)); return(invisible(as.data.table(p[[k]])))
    }
  }
  invisible(NULL)
}

# (1) KNOWN-WORKING sanity: 전종목시세 MDCSTAT01501 (daily all-stock quote) — proves session works
post_bld(list(bld="dbms/MDC/STAT/standard/MDCSTAT01501", locale="ko_KR",
  mktId="STK", trdDd="20260630", share="1", money="1", csvxls_isNo="false"),
  "SANITY MDCSTAT01501 all-stock quote",
  "http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020101")

# (2) short-balance with the specific short-selling menu referer
SREF <- "http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020506"
post_bld(list(bld="dbms/MDC/STAT/srt/MDCSTAT30501", locale="ko_KR",
  mktId="STK", trdDd="20260630", share="1", money="1", csvxls_isNo="false"),
  "30501 balance (short menu referer)", SREF)

# (3) short-trade with secugrpId param variant
post_bld(list(bld="dbms/MDC/STAT/srt/MDCSTAT30101", locale="ko_KR",
  secugrpId="STMFRTSCIFDRFS", mktId="STK", trdDd="20260630",
  inqTpCd="1", share="1", money="1", csvxls_isNo="false"),
  "30101 trade (secugrpId variant)", SREF)

cat("\nDONE v3\n")
