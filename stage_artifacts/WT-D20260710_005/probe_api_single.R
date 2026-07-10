# Single-firm DART list.json probe — confirm API behavior + report_nm taxonomy for restatement/bad-news
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
key <- sub("^DART_API_KEY=","", grep("^DART_API_KEY=", readLines(".env",warn=FALSE), value=TRUE)[1])
cat("key nchar:", nchar(key), "\n")

fetch_corp_all <- function(corp_code, bgn, end, max_pages=30) {
  acc <- list(); pg <- 1
  repeat {
    r <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
             query=list(crtfc_key=key, corp_code=corp_code, bgn_de=bgn, end_de=end,
                        page_no=pg, page_count=100), timeout(30)),
             error=function(e) NULL)
    Sys.sleep(1.2)
    if (is.null(r) || status_code(r)!=200) { cat("HTTP fail pg",pg,"\n"); break }
    p <- fromJSON(content(r,"text",encoding="UTF-8"), flatten=TRUE)
    if (is.null(p$status)) { cat("no status\n"); break }
    if (p$status!="000") { cat("status:", p$status, p$message %||% "", "\n"); break }
    d <- as.data.table(p$list); acc[[length(acc)+1L]] <- d
    tp <- p$total_page %||% 1
    cat(sprintf("  pg %d/%s rows=%d total_count=%s\n", pg, tp, nrow(d), p$total_count %||% "?"))
    if (pg >= tp) break
    pg <- pg + 1; if (pg>max_pages) { cat("hit max_pages\n"); break }
  }
  if (length(acc)==0) return(NULL)
  rbindlist(acc, fill=TRUE)
}

# Samsung Electronics corp_code = 00126380
cc <- "00126380"
cat("=== Samsung 005930 full-history list.json ===\n")
D <- fetch_corp_all(cc, "20050101", "20260710")
if (!is.null(D)) {
  cat("TOTAL rows:", nrow(D), "cols:", paste(names(D), collapse=","), "\n")
  cat("date range:", min(D$rcept_dt), "..", max(D$rcept_dt), "\n")
  # taxonomy of report_nm prefixes/flags
  D[, is_restate := grepl("^\\[?기재정정", report_nm) | grepl("정정", report_nm)]
  D[, is_unfaith := grepl("불성실공시", report_nm)]
  D[, is_lawsuit := grepl("소송|소제기|판결", report_nm)]
  D[, is_capreduce := grepl("감자", report_nm)]
  cat("restate rows:", sum(D$is_restate), " unfaith:", sum(D$is_unfaith),
      " lawsuit:", sum(D$is_lawsuit), " capreduce:", sum(D$is_capreduce), "\n")
  cat("\n=== sample restatement report_nm ===\n")
  print(head(unique(D[is_restate==TRUE, report_nm]), 15))
  cat("\n=== pblntf_ty distribution (top) ===\n")
  print(D[, .N, by=pblntf_ty][order(-N)])
  cat("\n=== yearly disclosure count ===\n")
  D[, yr := substr(rcept_dt,1,4)]
  print(D[, .(n=.N, n_restate=sum(is_restate)), by=yr][order(yr)])
  fwrite(D, "stage_artifacts/WT-D20260710_005/probe_samsung.csv")
}
