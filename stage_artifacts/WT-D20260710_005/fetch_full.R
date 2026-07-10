# Full corp-scoped list.json fetch (2005-2026), compact rows for disclosure-quality signals.
# Checkpointed per-firm (resume). Quota-abort on repeated 020/429 (yields to insider backfill = 무간섭).
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
key <- sub("^DART_API_KEY=","", grep("^DART_API_KEY=", readLines(".env",warn=FALSE), value=TRUE)[1])
U <- fread(".cache/dart/universe_corpcodes.csv", colClasses="character")
CKDIR <- "stage_artifacts/WT-D20260710_005/disc_ck"
dir.create(CKDIR, showWarnings=FALSE, recursive=TRUE)

fetch_corp <- function(corp_code, bgn="20050101", end="20260710", max_pages=400) {
  acc <- list(); pg <- 1; quota_err <- 0L
  repeat {
    r <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
             query=list(crtfc_key=key, corp_code=corp_code, bgn_de=bgn, end_de=end,
                        page_no=pg, page_count=100), timeout(30)),
             error=function(e) NULL)
    Sys.sleep(1.0)
    if (is.null(r)) { quota_err<-quota_err+1L; if(quota_err>=2) return(list(d=NULL,q=TRUE)); next }
    sc <- status_code(r)
    if (sc!=200) { quota_err<-quota_err+1L; if(quota_err>=2) return(list(d=NULL,q=TRUE)); next }
    p <- tryCatch(fromJSON(content(r,"text",encoding="UTF-8"), flatten=TRUE), error=function(e) NULL)
    if (is.null(p)||is.null(p$status)) { quota_err<-quota_err+1L; if(quota_err>=2) return(list(d=NULL,q=TRUE)); next }
    if (p$status=="013") return(list(d=data.table(), q=FALSE))    # no data (valid)
    if (p$status %in% c("020","021")) return(list(d=NULL, q=TRUE)) # quota / rate limit -> abort
    if (p$status!="000") return(list(d=data.table(), q=FALSE))
    d <- as.data.table(p$list)
    if (nrow(d)) acc[[length(acc)+1L]] <- d[, .(rcept_no, stock_code, report_nm, rcept_dt, corp_cls)]
    tp <- as.integer(p$total_page %||% 1)
    if (pg >= tp) break
    pg <- pg + 1L; if (pg > max_pages) break
  }
  list(d=if(length(acc)) rbindlist(acc, fill=TRUE) else data.table(), q=FALSE)
}

done <- sub("\\.csv$","", list.files(CKDIR, pattern="\\.csv$"))
todo <- U[!(corp_code %in% done)]
cat(sprintf("[fetch_full] resume: %d done, %d todo (of %d)\n", length(done), nrow(todo), nrow(U)))
qhit <- 0L; t0 <- Sys.time()
for (i in seq_len(nrow(todo))) {
  cc <- todo$corp_code[i]
  o <- fetch_corp(cc)
  if (isTRUE(o$q)) {
    qhit <- qhit + 1L
    cat(sprintf("[QUOTA] firm %s quota/rate error (qhit=%d). Pausing 60s to yield to insider.\n", cc, qhit))
    Sys.sleep(60)
    if (qhit >= 4L) { cat("[ABORT] repeated quota errors — yielding fully. Resume later.\n"); break }
    next
  }
  d <- o$d
  if (is.null(d)) d <- data.table()
  fwrite(d, file.path(CKDIR, paste0(cc, ".csv")))
  if (i %% 25 == 0) {
    el <- as.numeric(difftime(Sys.time(), t0, units="mins"))
    cat(sprintf("[fetch_full] %d/%d (%.1f min elapsed, %d rows last firm)\n", i, nrow(todo), el, nrow(d)))
  }
}
cat(sprintf("[fetch_full] DONE loop. checkpoints=%d\n", length(list.files(CKDIR, pattern='\\.csv$'))))
