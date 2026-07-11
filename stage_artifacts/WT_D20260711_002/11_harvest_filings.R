#==============================================================================
# WT-D20260711_002 Phase A — Step 11: harvest 사업보고서 inventory (list.json)
#   ONE list.json call per corp_code (all annual reports 2010..2024) -> rcept_no map.
#   Resumable: appends to filings_inventory.parquet; skips corps already harvested.
#   Throttle >=0.4s; exp backoff on 429/quota; stop after 5 consecutive errors.
#   Does NOT touch insider_backfill/ (different code path + cache dir).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(httr); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1 && is.na(a))) b else a
load_key <- function() { for (l in readLines(file.path(ROOT,".env"),warn=FALSE)) if (grepl("^DART_API_KEY=",l)) return(trimws(sub("^DART_API_KEY=","",l))); stop("no key") }
KEY  <- load_key()

cmap <- as.data.table(read_parquet(file.path(ROOT,".cache/dart/corpcode_map.parquet")))
pool <- as.data.table(read_parquet(file.path(OUT,"candidate_pool_full.parquet")))
tickers <- sort(unique(pool$Ticker))
cmap_p <- cmap[Ticker %in% tickers, .(Ticker, corp_code = corp_code, corp_name)][!is.na(corp_code)]
cmap_p <- unique(cmap_p, by = "Ticker")
cat("[11] pool tickers:", length(tickers), " with corp_code:", nrow(cmap_p),
    " (missing:", length(tickers) - nrow(cmap_p), ")\n")

PARTS_DIR <- file.path(OUT, "inv_parts")   # append-only part files (avoid Windows mmap 1224)
dir.create(PARTS_DIR, showWarnings = FALSE)
DONE_PATH <- file.path(OUT, "harvest_done_corps.txt")
done_corps <- if (file.exists(DONE_PATH)) readLines(DONE_PATH) else character(0)

todo <- cmap_p[!(corp_code %in% done_corps)]
cat("[11] corps to harvest:", nrow(todo), " (already done:", length(done_corps), ")\n")

fetch_annual_list <- function(cc) {
  # one call: all 사업보고서(A/A001) 2010-2024, up to 100 rows (annual = ~14 max)
  resp <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json", query=list(
    crtfc_key=KEY, corp_code=cc, bgn_de="20100101", end_de="20241231",
    pblntf_ty="A", pblntf_detail_ty="A001", page_no=1, page_count=100)),
    error=function(e) NULL)
  if (is.null(resp)) return(list(status="neterr", dt=NULL))
  sc <- status_code(resp)
  if (sc == 429) return(list(status="429", dt=NULL))
  if (sc != 200) return(list(status=paste0("http",sc), dt=NULL))
  p <- tryCatch(fromJSON(content(resp,"text",encoding="UTF-8"),flatten=TRUE), error=function(e) NULL)
  if (is.null(p) || is.null(p$status)) return(list(status="parseerr", dt=NULL))
  if (p$status == "020") return(list(status="quota", dt=NULL))   # usage limit
  if (p$status == "013") return(list(status="nodata", dt=data.table()))  # no matching
  if (p$status != "000") return(list(status=p$status, dt=NULL))
  list(status="000", dt=as.data.table(p$list))
}

new_rows <- list(); consec_err <- 0L; backoff <- 0.4
batch_flush <- function() {
  if (length(new_rows) == 0) return(invisible())
  nr <- rbindlist(new_rows, fill=TRUE)
  part <- file.path(PARTS_DIR, sprintf("part_%s.parquet", format(Sys.time(), "%H%M%S_%OS3")))
  write_parquet(nr, part)   # write-once, never rewrite (mmap 1224 safe)
  new_rows <<- list()
}

for (i in seq_len(nrow(todo))) {
  r <- todo[i]
  res <- fetch_annual_list(r$corp_code)
  Sys.sleep(0.4)
  if (res$status %in% c("429","quota")) {
    backoff <- min(backoff * 2, 30)
    cat(sprintf("  [%d] %s %s -> %s, backoff %.1fs\n", i, r$Ticker, r$corp_code, res$status, backoff))
    Sys.sleep(backoff)
    consec_err <- consec_err + 1L
    if (consec_err >= 5L) { cat("[11] 5 consecutive quota/429 errors — STOP for cooldown.\n"); break }
    next
  }
  if (is.null(res$dt)) {
    consec_err <- consec_err + 1L
    cat(sprintf("  [%d] %s ERR %s (consec %d)\n", i, r$Ticker, res$status, consec_err))
    if (consec_err >= 5L) { cat("[11] 5 consecutive errors — STOP.\n"); break }
    next
  }
  consec_err <- 0L; backoff <- 0.4
  if (nrow(res$dt) > 0) {
    d <- res$dt[grepl("사업보고서", report_nm) & !grepl("정정|첨부", report_nm)]
    if (nrow(d) > 0) {
      d[, `:=`(Ticker = r$Ticker, corp_code = r$corp_code, corp_name_map = r$corp_name)]
      # fiscal year from report_nm "(YYYY.12)"
      fy <- sub(".*\\((\\d{4})\\.12\\).*", "\\1", d$report_nm)
      d[, fy := suppressWarnings(as.integer(fifelse(grepl("^\\d{4}$", fy), fy, NA_character_)))]
      new_rows[[length(new_rows)+1L]] <- d[, .(Ticker, corp_code, corp_name_map, report_nm,
                                               rcept_no, rcept_dt, fy, flr_nm)]
    }
  }
  done_corps <- c(done_corps, r$corp_code)
  if (i %% 25 == 0) {
    batch_flush(); writeLines(done_corps, DONE_PATH)
    cat(sprintf("[11] progress %d/%d corps\n", i, nrow(todo)))
  }
}
batch_flush(); writeLines(done_corps, DONE_PATH)

# combine parts -> filings_inventory.parquet (write-once each run to a fresh name)
parts <- list.files(PARTS_DIR, pattern="\\.parquet$", full.names=TRUE)
if (length(parts) > 0) {
  inv <- rbindlist(lapply(parts, function(p) as.data.table(read_parquet(p))), fill=TRUE)
  inv <- unique(inv, by = c("Ticker","fy","rcept_no"))
  write_parquet(inv, file.path(OUT, "filings_inventory.parquet"))
  cat("[11] inventory rows:", nrow(inv), " unique (Ticker,fy):", uniqueN(inv[,.(Ticker,fy)]), "\n")
}
cat("[11] corps harvested total:", length(done_corps), "/", nrow(cmap_p), "\n")
cat("[11] DONE\n")
