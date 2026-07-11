#==============================================================================
# WT-D20260711_002 Phase A — Step 12: fetch document.xml + compute FROZEN metrics
#   For each (Ticker, fiscal_year) in pool with a matching 사업보고서 rcept_no:
#     document.xml -> strip -> extract_mdna_full -> compute_metrics -> append part.
#   Resumable: skips rcept_no already in text_cache. Throttle>=0.4s; exp backoff
#   on 429/quota; stop after 5 consecutive errors. Never touches insider_backfill/.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(httr); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
CACHE <- file.path(OUT, "text_cache")
dir.create(CACHE, showWarnings = FALSE)
source(file.path(OUT, "metrics_lib.R"))
.HANGUL_CLS <- .HANGUL
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1 && is.na(a))) b else a
load_key <- function() { for (l in readLines(file.path(ROOT,".env"),warn=FALSE)) if (grepl("^DART_API_KEY=",l)) return(trimws(sub("^DART_API_KEY=","",l))); stop("no key") }
KEY <- load_key()

pool <- as.data.table(read_parquet(file.path(OUT,"candidate_pool_full.parquet")))
inv  <- as.data.table(read_parquet(file.path(OUT,"filings_inventory.parquet")))
inv  <- inv[!is.na(fy)]
# match pool (Ticker, fiscal_year) -> inventory (Ticker, fy). earliest rcept per (Ticker,fy).
setorder(inv, Ticker, fy, rcept_dt)
inv1 <- inv[, .SD[1], by = .(Ticker, fy)]
todo <- merge(pool[, .(Ticker, fiscal_year)], inv1,
              by.x = c("Ticker","fiscal_year"), by.y = c("Ticker","fy"))
todo <- unique(todo, by = "rcept_no")
cat("[12] fetch targets (pool∩inventory, unique rcept):", nrow(todo),
    " of pool", nrow(pool), "\n")

# resume: already-cached rcept_no
done_rcept <- character(0)
parts <- list.files(CACHE, pattern="^metrics_part_.*\\.parquet$", full.names=TRUE)
if (length(parts) > 0) {
  ex <- rbindlist(lapply(parts, function(p) tryCatch(as.data.table(read_parquet(p)),
                                                     error=function(e) NULL)), fill=TRUE)
  if (!is.null(ex) && nrow(ex) > 0) done_rcept <- unique(ex$rcept_no)
}
todo <- todo[!(rcept_no %in% done_rcept)]
cat("[12] remaining to fetch:", nrow(todo), " (cached:", length(done_rcept), ")\n")

fetch_doc_text <- function(rcept_no) {
  d <- tryCatch(GET("https://opendart.fss.or.kr/api/document.xml",
                    query=list(crtfc_key=KEY, rcept_no=rcept_no), timeout(60)),
                error=function(e) NULL)
  if (is.null(d)) return(list(status="neterr", txt=NULL))
  sc <- status_code(d)
  if (sc == 429) return(list(status="429", txt=NULL))
  if (sc != 200) return(list(status=paste0("http",sc), txt=NULL))
  ct <- headers(d)[["content-type"]] %||% ""
  if (grepl("application/json", ct, ignore.case=TRUE)) {
    p <- tryCatch(fromJSON(content(d,"text",encoding="UTF-8")), error=function(e) NULL)
    st <- if (!is.null(p$status)) p$status else "json"
    return(list(status=paste0("json_",st), txt=NULL))   # 020=quota
  }
  raw <- content(d,"raw"); if (length(raw)<100) return(list(status="empty", txt=NULL))
  z <- tempfile(fileext=".zip"); writeBin(raw,z)
  exdir <- tempfile(); files <- tryCatch(unzip(z,exdir=exdir), error=function(e) NULL)
  if (is.null(files)||length(files)==0) { unlink(z); return(list(status="unzip", txt=NULL)) }
  xf <- files[grepl("\\.xml$",files,ignore.case=TRUE)]
  if (length(xf)==0) { unlink(z); unlink(exdir,recursive=TRUE); return(list(status="noxml", txt=NULL)) }
  main <- xf[which.max(file.info(xf)$size)]
  rd <- function(enc) tryCatch({ x<-paste(readLines(file(main,encoding=enc),warn=FALSE),collapse="\n"); Encoding(x)<-"UTF-8"; x}, error=function(e) "")
  t_euc <- rd("EUC-KR"); t_utf <- rd("UTF-8")
  txt <- if (grepl(.HANGUL_CLS,t_euc) && nchar(t_euc)>=nchar(t_utf)) t_euc else if (grepl(.HANGUL_CLS,t_utf)) t_utf else t_euc
  unlink(z); unlink(exdir,recursive=TRUE)
  list(status="000", txt=txt)
}

new_rows <- list(); consec_err <- 0L; backoff <- 0.4; n_ok <- 0L; n_nosec <- 0L
flush <- function() {
  if (length(new_rows)==0) return(invisible())
  nr <- rbindlist(new_rows, fill=TRUE)
  part <- file.path(CACHE, sprintf("metrics_part_%s.parquet", format(Sys.time(), "%H%M%S_%OS3")))
  write_parquet(nr, part); new_rows <<- list()
}

t0 <- Sys.time()
for (i in seq_len(nrow(todo))) {
  r <- todo[i]
  res <- fetch_doc_text(r$rcept_no)
  Sys.sleep(0.4)
  if (res$status == "429" || res$status == "json_020") {
    backoff <- min(backoff*2, 30); consec_err <- consec_err + 1L
    cat(sprintf("  [%d] %s QUOTA/%s backoff %.1fs (consec %d)\n", i, r$Ticker, res$status, backoff, consec_err))
    Sys.sleep(backoff)
    if (consec_err >= 5L) { cat("[12] 5 consecutive quota errors — STOP for cooldown.\n"); break }
    next
  }
  if (is.null(res$txt)) {
    consec_err <- consec_err + 1L
    if (consec_err >= 5L) { cat("[12] 5 consecutive errors — STOP.\n"); break }
    next
  }
  consec_err <- 0L; backoff <- 0.4
  plain <- strip_all(res$txt)
  sec <- tryCatch(extract_mdna_full(plain), error=function(e) NULL)
  if (is.null(sec) || nchar(sec) < 300) { n_nosec <- n_nosec + 1L;
    new_rows[[length(new_rows)+1L]] <- data.table(rcept_no=r$rcept_no, Ticker=r$Ticker,
      fy=r$fiscal_year, rcept_dt=r$rcept_dt, status="no_section",
      m1_avg_sentence_len_chars=NA_real_, m2_fog_kr=NA_real_, m3_hanja_latin_density=NA_real_,
      m4_numeric_table_density=NA_real_, m5_section_nchar=NA_integer_, n_content=NA_integer_,
      n_sent=NA_integer_, n_words=NA_integer_, section_head=NA_character_)
    next }
  m <- compute_metrics(sec)
  new_rows[[length(new_rows)+1L]] <- data.table(
    rcept_no=r$rcept_no, Ticker=r$Ticker, fy=r$fiscal_year, rcept_dt=r$rcept_dt, status="ok",
    m1_avg_sentence_len_chars=m$m1_avg_sentence_len_chars, m2_fog_kr=m$m2_fog_kr,
    m3_hanja_latin_density=m$m3_hanja_latin_density, m4_numeric_table_density=m$m4_numeric_table_density,
    m5_section_nchar=m$m5_section_nchar, n_content=m$n_content_chars, n_sent=m$n_sentences,
    n_words=m$n_words, section_head=substr(sec, 1, 8000))
  n_ok <- n_ok + 1L
  if (i %% 50 == 0) {
    flush()
    el <- as.numeric(difftime(Sys.time(), t0, units="mins"))
    cat(sprintf("[12] %d/%d done ok=%d nosec=%d  %.1fmin  (%.2fs/doc)\n",
                i, nrow(todo), n_ok, n_nosec, el, el*60/i))
  }
}
flush()
cat(sprintf("[12] DONE this run: ok=%d no_section=%d\n", n_ok, n_nosec))
