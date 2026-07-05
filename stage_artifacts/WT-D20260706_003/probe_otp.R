suppressPackageStartupMessages({ library(httr); library(jsonlite) })
h <- handle("http://data.krx.co.kr")
UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36"
# GenerateOTP for CSV download (historically login-free for some reports)
otp_url <- "http://data.krx.co.kr/comm/fileDn/GenerateOTP.cmd"
r <- tryCatch(POST(otp_url, body=list(
  locale="ko_KR", mktId="STK", trdDd="20260630",
  share="1", money="1", csvxls_isNo="false",
  name="fileDown", url="dbms/MDC/STAT/srt/MDCSTAT30501"),
  encode="form", handle=h,
  add_headers(`User-Agent`=UA, `Referer`="http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=MDC0201020506",
  `X-Requested-With`="XMLHttpRequest"), timeout(25)),
  error=function(e){cat("[ERR]",conditionMessage(e),"\n");NULL})
if(!is.null(r)){
  txt <- content(r,"text",encoding="UTF-8")
  cat("GenerateOTP HTTP", status_code(r), "bytes", nchar(txt), "\n")
  cat("head:", substr(gsub("\n"," ",txt),1,150), "\n")
}
