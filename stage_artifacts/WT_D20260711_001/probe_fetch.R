#==============================================================================
# WT-D20260711_001 — PROBE: 사업보고서(annual report) MD&A section fetch feasibility
# No returns touched. Mechanical fetch test only.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
.HANGUL <- paste0("[", intToUtf8(0xAC00), "-", intToUtf8(0xD7A3), "]")

load_key <- function() {
  lines <- readLines(file.path(ROOT, ".env"), warn = FALSE)
  for (l in lines) if (grepl("^DART_API_KEY=", l)) return(trimws(sub("^DART_API_KEY=", "", l)))
  stop("no key")
}
KEY <- load_key()

cmap <- as.data.table(read_parquet(file.path(ROOT, ".cache/dart/corpcode_map.parquet")))

# --- list.json for annual business report (사업보고서): pblntf_ty=A, pblntf_detail_ty=A001 ---
fetch_annual_list <- function(corp_code, bgn, end) {
  resp <- GET("https://opendart.fss.or.kr/api/list.json", query = list(
    crtfc_key = KEY, corp_code = corp_code, bgn_de = bgn, end_de = end,
    pblntf_ty = "A", pblntf_detail_ty = "A001", page_no = 1, page_count = 100))
  if (status_code(resp) != 200) return(list(ok=FALSE, note=paste0("http_", status_code(resp))))
  p <- fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE)
  if (is.null(p$status) || p$status != "000") return(list(ok=FALSE, note=paste0("status_", p$status %||% "NA")))
  list(ok=TRUE, dt=as.data.table(p$list))
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1 && is.na(a))) b else a

# --- document.xml fetch (reuse insider parser pattern) ---
fetch_doc_text <- function(rcept_no) {
  d <- tryCatch(GET("https://opendart.fss.or.kr/api/document.xml",
                    query = list(crtfc_key = KEY, rcept_no = rcept_no)),
                error=function(e) NULL)
  if (is.null(d) || status_code(d) != 200) return(list(ok=FALSE, note="http"))
  ctype <- headers(d)[["content-type"]] %||% ""
  raw <- content(d, "raw")
  if (length(raw) < 100 || grepl("application/json", ctype, ignore.case=TRUE))
    return(list(ok=FALSE, note="no_zip"))
  z <- tempfile(fileext=".zip"); writeBin(raw, z)
  exdir <- tempfile(); files <- tryCatch(unzip(z, exdir=exdir), error=function(e) NULL)
  if (is.null(files) || length(files)==0) return(list(ok=FALSE, note="unzip"))
  xf <- files[grepl("\\.xml$", files, ignore.case=TRUE)]
  if (length(xf)==0) return(list(ok=FALSE, note="no_xml"))
  main <- xf[which.max(file.info(xf)$size)]
  # encoding-robust read
  rd <- function(enc) tryCatch({ x<-paste(readLines(file(main,encoding=enc),warn=FALSE),collapse="\n"); Encoding(x)<-"UTF-8"; x}, error=function(e) "")
  t_euc <- rd("EUC-KR"); t_utf <- rd("UTF-8")
  txt <- if (grepl(.HANGUL,t_euc) && nchar(t_euc)>=nchar(t_utf)) t_euc else if (grepl(.HANGUL,t_utf)) t_utf else t_euc
  unlink(z); unlink(exdir, recursive=TRUE)
  list(ok=TRUE, txt=txt, nchar=nchar(txt))
}

# strip tags to plain text
strip_all <- function(x) {
  x <- gsub("&cr;", "\n", x, fixed=TRUE)
  x <- gsub("<[^>]+>", " ", x)
  x <- gsub("&#[0-9]+;", " ", x); x <- gsub("&[a-zA-Z]+;", " ", x)
  x <- gsub("[ \t]+", " ", x)
  x <- gsub(" *\n *", "\n", x)
  trimws(x)
}

# Extract MD&A-like section: heading '이사의 경영진단 및 분석의견' (MD&A)
extract_mdna <- function(txt) {
  plain <- strip_all(txt)
  # candidate anchors
  anchors <- c("경영진단 및 분석의견", "경영진의 재무상태 및 영업실적", "이사의 경영진단")
  pos <- NA
  for (a in anchors) { m <- regexpr(a, plain, fixed=TRUE); if (m[1] > 0) { pos <- m[1]; break } }
  if (is.na(pos)) return(list(found=FALSE, excerpt=NA_character_, anchor=NA))
  # take up to 6000 chars from the LAST occurrence (TOC has first occurrence)
  occ <- gregexpr(a, plain, fixed=TRUE)[[1]]
  start <- occ[length(occ)]
  excerpt <- substr(plain, start, start + 6000)
  list(found=TRUE, excerpt=excerpt, anchor=a, plain_nchar=nchar(plain))
}

# ---- RUN PROBE on 3 tickers of varying size ----
probes <- c("A005930", "A035720", "A214150")  # Samsung, Kakao, Classys(mid/small)
res <- list()
for (tk in probes) {
  cc <- cmap[Ticker==tk, corp_code][1]
  if (is.na(cc)) { cat(tk, "no corp_code\n"); next }
  lst <- fetch_annual_list(cc, "20180101", "20191231")
  if (!isTRUE(lst$ok)) { cat(tk, "list fail:", lst$note, "\n"); next }
  cat("\n==== ", tk, cmap[Ticker==tk,corp_name][1], " filings:", nrow(lst$dt), "====\n")
  # FILTER: only 사업보고서 (annual business report) — exclude 분기/반기 & amendments (기재정정)
  ann <- lst$dt[grepl("사업보고서", report_nm) & !grepl("기재정정|첨부정정|첨부추가|정정", report_nm)]
  print(ann[, .(rcept_no, report_nm, rcept_dt)])
  if (nrow(ann)==0) { cat("  no clean 사업보고서\n"); next }
  rc <- ann$rcept_no[1]
  doc <- fetch_doc_text(rc)
  if (!isTRUE(doc$ok)) { cat("  doc fail:", doc$note, "\n"); next }
  cat("  doc nchar(raw):", doc$nchar, "\n")
  md <- extract_mdna(doc$txt)
  cat("  MD&A found:", md$found, " anchor:", md$anchor, "\n")
  if (isTRUE(md$found)) {
    cat("  --- excerpt first 1200 chars ---\n")
    cat(substr(md$excerpt, 1, 1200), "\n")
  }
  res[[tk]] <- list(rcept_no=rc, found=md$found)
  Sys.sleep(0.7)
}
cat("\nPROBE DONE\n")
