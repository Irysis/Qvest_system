#==============================================================================
# WT-D20260711_001 — Step 2: fetch 사업보고서 + extract MD&A excerpt (FROZEN rule)
# BLIND: no returns touched. Output = excerpts.json (doc_id, meta, excerpt) only.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(httr); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_001")
.HANGUL <- paste0("[", intToUtf8(0xAC00), "-", intToUtf8(0xD7A3), "]")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1 && is.na(a))) b else a

load_key <- function() { for (l in readLines(file.path(ROOT,".env"),warn=FALSE)) if (grepl("^DART_API_KEY=",l)) return(trimws(sub("^DART_API_KEY=","",l))); stop("no key") }
KEY  <- load_key()
cmap <- as.data.table(read_parquet(file.path(ROOT,".cache/dart/corpcode_map.parquet")))
sel  <- as.data.table(read_parquet(file.path(OUT,"selection.parquet")))

fetch_annual_list <- function(cc, Yfile) {
  resp <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json", query=list(
    crtfc_key=KEY, corp_code=cc, bgn_de=paste0(Yfile,"0101"), end_de=paste0(Yfile,"1231"),
    pblntf_ty="A", pblntf_detail_ty="A001", page_no=1, page_count=100)), error=function(e) NULL)
  if (is.null(resp) || status_code(resp)!=200) return(NULL)
  p <- tryCatch(fromJSON(content(resp,"text",encoding="UTF-8"),flatten=TRUE), error=function(e) NULL)
  if (is.null(p) || is.null(p$status) || p$status!="000") return(NULL)
  as.data.table(p$list)
}
fetch_doc_text <- function(rcept_no) {
  d <- tryCatch(GET("https://opendart.fss.or.kr/api/document.xml", query=list(crtfc_key=KEY, rcept_no=rcept_no)), error=function(e) NULL)
  if (is.null(d) || status_code(d)!=200) return(NULL)
  if (grepl("application/json", headers(d)[["content-type"]] %||% "", ignore.case=TRUE)) return(NULL)
  raw <- content(d,"raw"); if (length(raw)<100) return(NULL)
  z <- tempfile(fileext=".zip"); writeBin(raw,z)
  exdir <- tempfile(); files <- tryCatch(unzip(z,exdir=exdir), error=function(e) NULL)
  if (is.null(files)||length(files)==0) { unlink(z); return(NULL) }
  xf <- files[grepl("\\.xml$",files,ignore.case=TRUE)]; if (length(xf)==0) { unlink(z); unlink(exdir,recursive=TRUE); return(NULL) }
  main <- xf[which.max(file.info(xf)$size)]
  rd <- function(enc) tryCatch({ x<-paste(readLines(file(main,encoding=enc),warn=FALSE),collapse="\n"); Encoding(x)<-"UTF-8"; x}, error=function(e) "")
  t_euc <- rd("EUC-KR"); t_utf <- rd("UTF-8")
  txt <- if (grepl(.HANGUL,t_euc) && nchar(t_euc)>=nchar(t_utf)) t_euc else if (grepl(.HANGUL,t_utf)) t_utf else t_euc
  unlink(z); unlink(exdir,recursive=TRUE); txt
}
strip_all <- function(x) {
  x <- gsub("&cr;","\n",x,fixed=TRUE); x <- gsub("<[^>]+>"," ",x)
  x <- gsub("&#[0-9]+;"," ",x); x <- gsub("&[a-zA-Z]+;"," ",x)
  x <- gsub("[ \t]+"," ",x); x <- gsub(" *\n *","\n",x); trimws(x)
}
# FROZEN extraction rule
extract_mdna <- function(txt) {
  plain <- strip_all(txt)
  anc <- "경영진단 및 분석의견"
  occ <- gregexpr(anc, plain, fixed=TRUE)[[1]]
  if (occ[1] < 0) return(NULL)
  start <- occ[length(occ)]                      # last occurrence = body
  window <- substr(plain, start, start + 2500)
  gi <- regexpr("개요", window, fixed=TRUE)
  begin <- if (gi[1] > 0) start + gi[1] - 1 else start + 400
  substr(plain, begin, begin + 2800 - 1)
}

cap_order  <- c("LARGE","MID","SMALL")
ybin_order <- c("FILE_2015_2017","FILE_2018_2020","FILE_2021_2023")
CELL_TARGET <- 5L
results <- list()
for (ct in cap_order) for (yb in ybin_order) {
  cellname <- paste(ct, yb, sep="|")
  cand <- sel[cell==cellname][order(seeded_rank)]
  got <- 0L
  for (i in seq_len(nrow(cand))) {
    if (got >= CELL_TARGET) break
    r <- cand[i]
    cc <- cmap[Ticker==r$Ticker, corp_code][1]
    if (is.na(cc)) next
    Yfile <- r$file_year; fy <- r$fiscal_year
    lst <- fetch_annual_list(cc, Yfile); Sys.sleep(0.5)
    if (is.null(lst) || nrow(lst)==0) next
    ann <- lst[grepl("사업보고서", report_nm) & !grepl("정정|첨부", report_nm) &
                 grepl(sprintf("\\(%d\\.12\\)", fy), report_nm)]
    if (nrow(ann)==0) ann <- lst[grepl("사업보고서", report_nm) & !grepl("정정|첨부", report_nm)]
    if (nrow(ann)==0) next
    rc <- ann$rcept_no[1]; rcept_dt <- ann$rcept_dt[1]
    txt <- fetch_doc_text(rc); Sys.sleep(0.5)
    if (is.null(txt) || !grepl(.HANGUL, txt)) next
    ex <- tryCatch(extract_mdna(txt), error=function(e) NULL)
    if (is.null(ex) || nchar(ex) < 400) next     # need substantive MD&A
    got <- got + 1L
    results[[length(results)+1L]] <- list(
      doc_id = r$doc_id, cell = cellname, cap_tier = ct, year_bin = yb,
      Ticker = r$Ticker, corp_name = cmap[Ticker==r$Ticker,corp_name][1],
      fiscal_year = fy, file_year = Yfile, rcept_no = rc, rcept_dt = rcept_dt,
      seeded_rank = r$seeded_rank, excerpt_nchar = nchar(ex), excerpt = ex)
    cat(sprintf("  [%s] %s %s fy%d rcept %s (%d chars)\n", cellname, r$Ticker,
                cmap[Ticker==r$Ticker,corp_name][1], fy, rcept_dt, nchar(ex)))
  }
  cat(sprintf("== cell %s: %d/%d fetched ==\n", cellname, got, CELL_TARGET))
}
cat("\n[2] total docs:", length(results), "\n")
write_json(results, file.path(OUT,"excerpts.json"), pretty=TRUE, auto_unbox=TRUE)
# also a compact meta table (no excerpt) for audit
meta <- rbindlist(lapply(results, function(x) as.data.table(x[c("doc_id","cell","cap_tier","year_bin","Ticker","corp_name","fiscal_year","rcept_no","rcept_dt","excerpt_nchar")])))
write_parquet(meta, file.path(OUT,"excerpts_meta.parquet"))
cat("[2] DONE — excerpts.json + excerpts_meta.parquet written\n")
