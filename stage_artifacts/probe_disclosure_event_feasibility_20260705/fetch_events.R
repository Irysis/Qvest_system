# Cheap-kill: fetch supply-contract + earnings events (list.json only, no doc parse) 2022-2024
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)) b else a
key <- sub("^DART_API_KEY=","", grep("^DART_API_KEY=", readLines(".env",warn=F), value=TRUE)[1])
OUT <- "stage_artifacts/probe_disclosure_event_feasibility_20260705"

fetch_month_I <- function(bgn, end) {
  acc <- list(); pg <- 1
  repeat {
    r <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
             query=list(crtfc_key=key, bgn_de=bgn, end_de=end, pblntf_ty="I", page_no=pg, page_count=100), timeout(30)),
             error=function(e) NULL)
    Sys.sleep(0.75)
    if (is.null(r) || status_code(r)!=200) break
    p <- fromJSON(content(r,"text",encoding="UTF-8"), flatten=TRUE)
    if (is.null(p$status) || p$status!="000") break
    d <- as.data.table(p$list); acc[[length(acc)+1L]] <- d
    tp <- p$total_page %||% 1
    if (pg >= tp || nrow(d)<100) break
    pg <- pg + 1; if (pg>40) break
  }
  if (length(acc)==0) return(NULL)
  rbindlist(acc, fill=TRUE)
}

yms <- character(0)
for (y in 2022:2024) for (mo in 1:12) yms <- c(yms, sprintf("%04d%02d", y, mo))
all <- list()
for (ym in yms) {
  y <- as.integer(substr(ym,1,4)); mo <- as.integer(substr(ym,5,6))
  bgn <- sprintf("%s01", ym)
  last <- as.integer(format(seq.Date(as.Date(sprintf("%04d-%02d-01",y,mo)), by="month", length.out=2)[2]-1, "%d"))
  end <- sprintf("%s%02d", ym, last)
  m <- fetch_month_I(bgn, end)
  if (is.null(m)) { cat(ym,"NULL\n"); next }
  m[, is_supply := grepl("단일판매ㆍ공급계약체결", report_nm) & !grepl("정정|해지", report_nm)]
  m[, is_earn   := grepl("잠정", report_nm) & grepl("실적", report_nm) & !grepl("정정|전망", report_nm)]
  keep <- m[is_supply|is_earn, .(rcept_no, corp_code, stock_code, report_nm, rcept_dt, is_supply, is_earn)]
  all[[ym]] <- keep
  cat(ym, "I=", nrow(m), "supply+earn=", nrow(keep), "\n")
}
res <- rbindlist(all, fill=TRUE)
fwrite(res, file.path(OUT,"events_raw_2022_2024.csv"))
cat("TOTAL events saved:", nrow(res), "\n")
