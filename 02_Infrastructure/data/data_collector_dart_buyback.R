#==============================================================================
# DART Buyback DECISION Collector — tsstkAqDecsn (자기주식취득 결정)
#
# Board resolutions to acquire treasury shares (주요사항보고서). Each = discrete
# EVENT at rcept_dt (PIT). Captures the continuous event stream the quarterly
# stock_buyback.parquet panel lacks. WT-D20260621_010 (C27_Buyback_Decision_Drift).
#
# API: opendart.fss.or.kr/api/tsstkAqDecsn.json?crtfc_key&corp_code&bgn_de&end_de
# Strategy: targeted per-corp_code fetch over K200∪KQ150 universe (efficient vs
#           monthly list.json crawl). 0.7s delay, resume-checkpoint.
# Cache: .cache/dart/buyback_decisions.parquet (temp-rename, arrow mmap 1224 guard)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(httr); library(jsonlite)
})
setDTthreads(1)

DART_CACHE_DIR <- ".cache/dart"
BUYBACK_CACHE  <- file.path(DART_CACHE_DIR, "buyback_decisions.parquet")
CKPT_PATH      <- file.path(DART_CACHE_DIR, "buyback_decisions_ckpt.rds")
if (!dir.exists(DART_CACHE_DIR)) dir.create(DART_CACHE_DIR, recursive = TRUE)

.load_dart_key <- function() {
  lines <- readLines(".env", warn = FALSE)
  k <- sub("^DART_API_KEY=", "", lines[grepl("^DART_API_KEY=", lines)])
  if (length(k) == 0) stop("DART_API_KEY not found in .env")
  k[1]
}

.fetch_buyback_decsn <- function(api_key, corp_code, bgn_de, end_de) {
  url <- "https://opendart.fss.or.kr/api/tsstkAqDecsn.json"
  resp <- tryCatch(GET(url, query = list(crtfc_key = api_key, corp_code = corp_code,
                                         bgn_de = bgn_de, end_de = end_de),
                       timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)
  p <- tryCatch(fromJSON(content(resp, "text", encoding = "UTF-8"), flatten = TRUE),
                error = function(e) NULL)
  if (is.null(p)) return(NULL)
  # status 000 = ok with data; 013 = no data (normal for non-buyback firms)
  if (is.null(p$status) || p$status != "000") return(NULL)
  if (is.null(p$list) || length(p$list) == 0) return(NULL)
  as.data.table(p$list)
}

#' Main collector — iterate K200∪KQ150 corp_codes
dart_fetch_buyback <- function(corpcodes_rds = "/tmp/univ_corpcodes.rds",
                               bgn_de = "20100101", end_de = "20261231",
                               delay = 0.7, resume = TRUE) {
  api_key <- .load_dart_key()
  univ <- as.data.table(readRDS(corpcodes_rds))

  done <- character(0); acc <- list()
  if (resume && file.exists(CKPT_PATH)) {
    ck <- readRDS(CKPT_PATH)
    done <- ck$done; acc <- ck$acc
    cat(sprintf("[buyback] resume: %d corp done\n", length(done)))
  }

  todo <- univ[!corp_code %in% done]
  n <- nrow(todo)
  cat(sprintf("[buyback] fetching %d corps (%s ~ %s)\n", n, bgn_de, end_de))

  for (i in seq_len(n)) {
    cc <- todo$corp_code[i]; tk <- todo$Ticker[i]
    d <- .fetch_buyback_decsn(api_key, cc, bgn_de, end_de)
    Sys.sleep(delay)
    if (!is.null(d) && nrow(d) > 0) {
      d[, Ticker := tk]
      acc[[length(acc) + 1L]] <- d
    }
    done <- c(done, cc)
    if (i %% 50 == 0 || i == n) {
      saveRDS(list(done = done, acc = acc), CKPT_PATH)
      n_ev <- sum(vapply(acc, nrow, 0L))
      cat(sprintf("[buyback] %d/%d corps, %d events so far\n", i, n, n_ev))
    }
  }

  if (length(acc) == 0) { cat("[buyback] no events collected.\n"); return(NULL) }
  res <- rbindlist(acc, fill = TRUE)

  # temp-rename write (Windows arrow mmap 1224 guard)
  tmp <- paste0(BUYBACK_CACHE, ".tmp")
  write_parquet(res, tmp)
  if (file.exists(BUYBACK_CACHE)) file.remove(BUYBACK_CACHE)
  file.rename(tmp, BUYBACK_CACHE)
  cat(sprintf("[buyback] saved %d events -> %s\n", nrow(res), BUYBACK_CACHE))
  res
}

if (sys.nframe() == 0 || identical(environment(), globalenv())) {
  # invoked via Rscript -e source: run collection
  dart_fetch_buyback()
}
