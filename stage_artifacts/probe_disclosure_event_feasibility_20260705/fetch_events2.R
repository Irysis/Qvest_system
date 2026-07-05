# Robust resumable fetch: supply+earn events, list.json only. Per-month CSV cache.
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
key <- sub("^DART_API_KEY=","", grep("^DART_API_KEY=", readLines(".env",warn=F), value=TRUE)[1])
OUT <- "stage_artifacts/probe_disclosure_event_feasibility_20260705"
MDIR <- file.path(OUT, "months"); if(!dir.exists(MDIR)) dir.create(MDIR, recursive=TRUE)

get_page <- function(bgn,end,pg) {
  for (att in 1:3) {
    r <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
             query=list(crtfc_key=key,bgn_de=bgn,end_de=end,pblntf_ty="I",page_no=pg,page_count=100),timeout(40)),
             error=function(e) NULL)
    if (!is.null(r) && status_code(r)==200) {
      p <- tryCatch(fromJSON(content(r,"text",encoding="UTF-8"),flatten=TRUE), error=function(e) NULL)
      if (!is.null(p) && !is.null(p$status)) return(p)
    }
    Sys.sleep(1.5)  # backoff
  }
  NULL
}
fetch_month <- function(ym) {
  y<-as.integer(substr(ym,1,4)); mo<-as.integer(substr(ym,5,6))
  bgn<-sprintf("%s01",ym); last<-as.integer(format(seq.Date(as.Date(sprintf("%04d-%02d-01",y,mo)),by="month",length.out=2)[2]-1,"%d")); end<-sprintf("%s%02d",ym,last)
  acc<-list(); pg<-1; tp<-1
  repeat {
    p <- get_page(bgn,end,pg); Sys.sleep(0.8)
    if (is.null(p) || p$status!="000") break
    d <- as.data.table(p$list); acc[[length(acc)+1L]]<-d
    tp <- as.integer(p$total_page %||% 1)
    if (pg>=tp || nrow(d)<100) break
    pg<-pg+1
  }
  if (length(acc)==0) return(data.table())
  m <- rbindlist(acc, fill=TRUE)
  m[, is_supply := grepl("단일판매ㆍ공급계약체결", report_nm) & !grepl("정정|해지", report_nm)]
  m[, is_earn   := grepl("잠정", report_nm) & grepl("실적", report_nm) & !grepl("정정|전망", report_nm)]
  keep <- m[is_supply|is_earn, .(rcept_no, corp_code, stock_code, report_nm, rcept_dt, is_supply, is_earn)]
  attr(keep,"npages") <- pg; attr(keep,"tp") <- tp; attr(keep,"nI") <- nrow(m)
  keep
}

yms <- character(0); for(y in 2023:2024) for(mo in 1:12) yms<-c(yms, sprintf("%04d%02d",y,mo))
for (ym in yms) {
  f <- file.path(MDIR, paste0(ym,".csv"))
  if (file.exists(f)) { cat(ym,"cached\n"); next }
  k <- tryCatch(fetch_month(ym), error=function(e){cat(ym,"ERR",conditionMessage(e),"\n"); NULL})
  if (is.null(k)) next
  fwrite(k, f)
  cat(sprintf("%s I=%d pages=%s/%s supply+earn=%d\n", ym, attr(k,"nI")%||%0, attr(k,"npages")%||%NA, attr(k,"tp")%||%NA, nrow(k)))
}
# consolidate
fs <- list.files(MDIR, pattern="\.csv$", full.names=TRUE)
all <- rbindlist(lapply(fs, fread, colClasses=list(character=c("stock_code","corp_code","rcept_dt","rcept_no"))), fill=TRUE)
fwrite(all, file.path(OUT,"events_raw_2023_2024.csv"))
cat("CONSOLIDATED:", nrow(all), "events over", length(fs), "months\n")
