## D2 재검 ③ — 측정 축 4행(네이버 없음) + A214610 · A037030: 네이버 첫 날짜 · DART 법인명 · 전 공시 제목(창 −400~+30일) — 키는 출력하지 않는다
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(httr) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
setwd(file.path(ROOT, "02_Infrastructure")); suppressMessages(source("config.R"))
invisible(capture.output(source("data/naver_data_collector.R")))
key <- NULL
for (ln in readLines(file.path(ROOT, ".env"), warn = FALSE)) if (grepl("^DART_API_KEY=", ln)) key <- sub("^DART_API_KEY=", "", trimws(ln))
stopifnot(!is.null(key), nchar(key) >= 10)
cm <- as.data.table(read_parquet(file.path(ROOT, ".cache/dart/corpcode_map.parquet")))
sc <- intersect(c("stock_code", "Ticker", "ticker"), names(cm))[1]; cc <- intersect(c("corp_code", "corpcode"), names(cm))[1]
nm <- intersect(c("corp_name", "name"), names(cm))[1]
rows <- data.table(Date = as.Date(c("2010-06-15", "2018-02-08", "2019-01-25", "2019-12-26", "2020-10-22", "2018-06-07")),
                   Ticker = c("A046120", "A042000", "A053580", "A062970", "A214610", "A037030"))
pat_skip <- "대량보유|임원ㆍ주요주주|임원·주요주주|특정증권등소유|최대주주등소유|기업설명회|공정공시|자기주식|분기보고서|반기보고서|사업보고서|감사보고서|정기주주총회|주주총회소집"
for (i in seq_len(nrow(rows))) {
  r <- rows[i]; code <- sub("^A", "", r$Ticker)
  d <- tryCatch(as.data.table(naver_daily_adjusted(code, format(r$Date - 400, "%Y%m%d"), format(r$Date + 10, "%Y%m%d"))), error = function(e) NULL)
  nv_first <- NA; nv_n <- 0L; nv_win <- NULL
  if (!is.null(d) && nrow(d)) {
    setnames(d, tolower(names(d))); dc <- intersect(c("date", "dt"), names(d))[1]; ccl <- intersect(c("close", "clpr"), names(d))[1]
    d[, dd := as.Date(get(dc))]; setorder(d, dd); nv_first <- as.character(min(d$dd)); nv_n <- nrow(d)
    nv_win <- d[dd >= r$Date - 7 & dd <= r$Date + 3, .(dd, close = get(ccl))]
  }
  m <- cm[get(sc) == code | get(sc) == r$Ticker]
  corp <- m[[cc]][1]; cname <- if (!is.na(nm)) m[[nm]][1] else NA
  cat(sprintf("\n## %s %s · DART 법인 %s · 네이버 창 %d행 첫 날 %s\n", r$Date, r$Ticker, cname, nv_n, nv_first))
  if (!is.null(nv_win) && nrow(nv_win)) print(nv_win)
  if (is.na(corp)) next
  res <- list(); page <- 1L
  repeat {
    rr <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
                       query = list(crtfc_key = key, corp_code = corp, bgn_de = format(r$Date - 400, "%Y%m%d"), end_de = format(r$Date + 30, "%Y%m%d"),
                                    page_no = page, page_count = 100), timeout(30)), error = function(e) NULL)
    Sys.sleep(0.5)
    if (is.null(rr)) break
    j <- tryCatch(fromJSON(content(rr, "text", encoding = "UTF-8"), flatten = TRUE), error = function(e) NULL)
    if (is.null(j) || !identical(j$status, "000") || !length(j$list)) break
    res[[length(res) + 1L]] <- as.data.table(j$list)
    if (page >= as.integer(j$total_page)) break
    page <- page + 1L
  }
  if (!length(res)) { cat("   DART 공시 없음\n"); next }
  L <- rbindlist(res, fill = TRUE)
  L[, t := gsub("\\s+", " ", trimws(report_nm))]
  L <- L[!grepl(pat_skip, t)]
  cat(sprintf("   DART %s 공시(정기 · 지분 보고 뺌) %d건:\n", L$corp_name[1], nrow(L)))
  print(L[order(rcept_dt), .(rcept_dt, t = substr(t, 1, 90))], nrows = 80)
}
