## D2 로 시총 기준 값을 채운 원천 내부 단절 87행(+ 측정 축 6행 표시) — DART 공시로 사건 종류 분류(키 출력 없음)
##   시총 기준이 맞는 사건 = 무상증자 · 주식분할 · 주식병합 · 감자(현금 환급 없음) / 생비율이 맞는 사건 = 이전상장 · 일반공모 · 합병
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(httr) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
key <- NULL
for (ln in readLines(file.path(ROOT, ".env"), warn = FALSE)) if (grepl("^DART_API_KEY=", ln)) key <- sub("^DART_API_KEY=", "", trimws(ln))
stopifnot(!is.null(key), nchar(key) >= 10)
cm <- as.data.table(read_parquet(file.path(ROOT, ".cache/dart/corpcode_map.parquet")))
sc <- intersect(c("stock_code", "Ticker", "ticker"), names(cm))[1]; cc <- intersect(c("corp_code", "corpcode"), names(cm))[1]
ch <- fread(file.path(SP, "d2_changed_rows.csv")); ch[, Date := as.Date(Date)]
ch <- ch[Date < as.Date("2026-01-01")]                 # 원천 내부 87행(2026 72행 = 03-30 이음매 71 + A250030)
axis6 <- paste(c("2010-06-15", "2018-02-08", "2019-01-25", "2019-12-26", "2020-10-22", "2024-06-24"),
               c("A046120", "A042000", "A053580", "A062970", "A214610", "A107640"))
ch[, in_axis := paste(Date, Ticker) %in% axis6]
cat("rows", nrow(ch), "· in axis", sum(ch$in_axis), "\n")
pat <- "증자|감자|분할|병합|합병|이전상장|상장|권리락|소각|전환|교환"
q <- function(corp, d) {
  res <- list(); page <- 1L
  repeat {
    rr <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
                       query = list(crtfc_key = key, corp_code = corp, bgn_de = format(d - 150, "%Y%m%d"), end_de = format(d + 5, "%Y%m%d"),
                                    page_no = page, page_count = 100), timeout(30)), error = function(e) NULL)
    Sys.sleep(0.4)
    if (is.null(rr)) return(NULL)
    j <- tryCatch(fromJSON(content(rr, "text", encoding = "UTF-8"), flatten = TRUE), error = function(e) NULL)
    if (is.null(j)) return(NULL)
    if (identical(j$status, "013")) break
    if (!identical(j$status, "000") || !length(j$list)) return(NULL)
    res[[length(res) + 1L]] <- as.data.table(j$list)
    if (page >= as.integer(j$total_page)) break
    page <- page + 1L
  }
  if (!length(res)) return(data.table(report_nm = character(0)))
  rbindlist(res, fill = TRUE)
}
out <- rbindlist(lapply(seq_len(nrow(ch)), function(i) {
  r <- ch[i]; code <- sub("^A", "", r$Ticker)
  corp <- cm[get(sc) == code | get(sc) == r$Ticker, get(cc)][1]
  if (is.null(corp) || is.na(corp)) return(data.table(Date = r$Date, Ticker = r$Ticker, in_axis = r$in_axis, old = r$old, new = r$new, n_disc = NA_integer_, events = "법인코드 없음"))
  L <- q(corp, r$Date)
  if (is.null(L)) return(data.table(Date = r$Date, Ticker = r$Ticker, in_axis = r$in_axis, old = r$old, new = r$new, n_disc = NA_integer_, events = "조회 실패"))
  ev <- unique(gsub("\\s+", "", gsub("^\\[[^]]*\\]", "", L[grepl(pat, report_nm)]$report_nm)))
  data.table(Date = r$Date, Ticker = r$Ticker, in_axis = r$in_axis, old = r$old, new = r$new, n_disc = nrow(L), events = paste(ev, collapse = " | "))
}))
out[, cls := fifelse(grepl("이전상장|합병", events), "생비율(이전상장·합병)",
               fifelse(grepl("유상증자", events) & !grepl("무상증자|분할|병합|감자", events), "생비율 후보(유상증자)",
                 fifelse(grepl("무상증자|주식분할|액면분할|주식병합|감자", events), "시총(무상·분할·병합·감자)",
                   fifelse(events %in% c("", NA), "공시 없음(2001 전 등)", "기타"))))]
options(width = 250)
print(out[, .N, by = cls])
print(out[in_axis == TRUE, .(Date, Ticker, old = round(old, 4), new = round(new, 4), cls, events = substr(events, 1, 120))])
fwrite(out, file.path(SP, "d2_dart_classify87.csv"))
