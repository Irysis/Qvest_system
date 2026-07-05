# Confirm the login wall is UNIVERSAL: hit the loader page for a plain public report
# and check whether it redirects to login for ALL, or only short-selling.
suppressPackageStartupMessages({ library(httr) })
UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36"
for (mid in c("MDC0201020101","MDC0201020506")) {
  r <- GET(sprintf("http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/index.cmd?menuId=%s", mid),
           add_headers(`User-Agent`=UA), timeout(20))
  txt <- content(r,"text",encoding="UTF-8")
  login_wall <- grepl("로그인|회원가입|MDCCOMS001", txt)
  cat(sprintf("menuId=%s  HTTP=%d  bytes=%d  login_wall=%s\n", mid, status_code(r), nchar(txt), login_wall))
}
