#==============================================================================
# R47 STEP 04: 백업 + APPEND-ONLY 병합 + 가드 5종 (가드 실패 시 write 안 함·롤백)
#   ★4월 사고 방어: 구멍만 채움·유니버스 보호·행수 추이·collision 0·temp-rename
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RAWDATA_CACHE <- file.path(ROOT, ".cache", "RAWDATA.parquet")
BACKUP <- file.path(ROOT, ".cache", "rawdata_pre_r47_backup_20260715.parquet")
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
log <- function(...) cat(sprintf(...), "\n")
abort <- function(msg) { log("\n[ABORT] %s — rawdata write 안 함(무변경).", msg); quit(status=1) }

# ── 0. 백업 (리빌드 전 필수) ────────────────────────────────────────────────
if (!file.exists(BACKUP)) {
  file.copy(RAWDATA_CACHE, BACKUP, overwrite=FALSE)
  log("[backup] created: %s (%.0f MB)", basename(BACKUP), file.info(BACKUP)$size/1e6)
} else {
  log("[backup] already exists: %s (%.0f MB) — 재사용", basename(BACKUP), file.info(BACKUP)$size/1e6)
}
if (abs(file.info(BACKUP)$size - file.info(RAWDATA_CACHE)$size) > 1e6)
  abort(sprintf("backup size mismatch (backup=%.0fMB live=%.0fMB)",
                file.info(BACKUP)$size/1e6, file.info(RAWDATA_CACHE)$size/1e6))

# ── 1. load ─────────────────────────────────────────────────────────────────
old <- as.data.table(read_parquet(RAWDATA_CACHE))
fill <- as.data.table(read_parquet(file.path(WT, "r47_fill_rows.parquet")))
old[, Date := as.Date(Date)]; fill[, Date := as.Date(Date)]
# fill 내부 중복 방어 (stk/ksq 동일티커 방지 — 없어야 정상)
ndup_fill <- sum(duplicated(fill, by=c("Date","Ticker")))
if (ndup_fill > 0) { log("[fill] 내부 중복 %d행 dedup", ndup_fill); fill <- unique(fill, by=c("Date","Ticker")) }
# book 14보유 overlap 확인 (있으면 abort — book은 유니버스, fill은 non-universe라 0이어야)
book <- c("A005930","A000660","A319660","A034730","A095610","A011070","A007340","A023530",
          "A004170","A402340","A222800","A003030","A290650","A189300")
book_overlap <- intersect(unique(fill$Ticker), book)
log("[book] fill∩book14 overlap = %d (MUST be 0)", length(book_overlap))
if (length(book_overlap) > 0) abort(sprintf("book overlap: %s", paste(book_overlap, collapse=",")))
rows_pre <- nrow(old); maxd_pre <- max(old$Date); mind_pre <- min(old$Date)
nuniv_pre <- nrow(old[K200 %in% 1 | KQ150 %in% 1])
ntick_pre <- uniqueN(old$Ticker)
log("[pre] rows=%d | dates %s~%s | universe_rows=%d | tickers=%d",
    rows_pre, as.character(mind_pre), as.character(maxd_pre), nuniv_pre, ntick_pre)
log("[fill] rows=%d | tickers=%d", nrow(fill), uniqueN(fill$Ticker))

# ── 2. APPEND-ONLY collision 게이트 (fill (Date,Ticker) 전량 rawdata 부재?) ──
coll <- merge(fill[, .(Date, Ticker)], old[, .(Date, Ticker, .exists=TRUE)],
              by=c("Date","Ticker"), all.x=TRUE)
n_coll <- sum(!is.na(coll$.exists))
log("[gate-collision] fill∩existing = %d (MUST be 0)", n_coll)
if (n_coll != 0) abort(sprintf("collision %d행 — 기존 데이터 덮어쓸 위험", n_coll))

# ── 3. schema 정합 확인 ─────────────────────────────────────────────────────
if (!identical(sort(names(old)), sort(names(fill))))
  abort(sprintf("schema mismatch: old=%s fill=%s",
                paste(setdiff(names(old),names(fill)),collapse=","),
                paste(setdiff(names(fill),names(old)),collapse=",")))
setcolorder(fill, names(old))

# ── 4. 병합 (append-only; unique는 belt-and-suspenders, old 우선) ────────────
combined <- rbind(old, fill, fill=TRUE, ignore.attr=TRUE)
combined <- unique(combined, by=c("Date","Ticker"))   # collision 0이므로 순수 append
setorder(combined, Date, Ticker)
rows_post <- nrow(combined)
nuniv_post <- nrow(combined[K200 %in% 1 | KQ150 %in% 1])
maxd_post <- max(combined$Date); mind_post <- min(combined$Date)
log("[post] rows=%d | dates %s~%s | universe_rows=%d | tickers=%d",
    rows_post, as.character(mind_post), as.character(maxd_post), nuniv_post, uniqueN(combined$Ticker))

# ── 5. 가드 5종 (전부 PASS해야 write) ───────────────────────────────────────
G <- list()
G$g1_rowcount_exact <- (rows_post == rows_pre + nrow(fill))
G$g2_no_decrease    <- (rows_post > rows_pre)
G$g3_universe_prot  <- (nuniv_post == nuniv_pre)      # 유니버스 행 불변 (fill 전량 non-universe)
G$g4_maxdate_same   <- (maxd_post == maxd_pre)        # 최신일 불변 (interior만 추가)
G$g5_mindate_same   <- (mind_post == mind_pre)        # 시작일 불변 (꼬리 소실 없음)
log("\n[guards]")
for (nm in names(G)) log("  %-20s : %s", nm, ifelse(G[[nm]], "PASS", "***FAIL***"))
if (!all(unlist(G))) abort(sprintf("가드 실패: %s", paste(names(G)[!unlist(G)], collapse=", ")))
log("[guards] ALL PASS — write 진행")

# ── 6. write (temp-rename, mmap 1224 회피) ──────────────────────────────────
rm(old); gc(verbose=FALSE)
tmp <- paste0(RAWDATA_CACHE, ".tmp")
write_parquet(combined, tmp)
if (file.exists(RAWDATA_CACHE)) file.remove(RAWDATA_CACHE)
file.rename(tmp, RAWDATA_CACHE)
log("[write] RAWDATA.parquet updated: +%d rows | %d total | %s ~ %s",
    nrow(fill), rows_post, as.character(mind_post), as.character(maxd_post))

writeLines(jsonlite::toJSON(list(
  backup=basename(BACKUP), rows_pre=rows_pre, rows_post=rows_post, fill_rows=nrow(fill),
  rowcount_delta=rows_post-rows_pre, universe_rows_pre=nuniv_pre, universe_rows_post=nuniv_post,
  maxdate_pre=as.character(maxd_pre), maxdate_post=as.character(maxd_post),
  mindate_pre=as.character(mind_pre), mindate_post=as.character(mind_post),
  collision=n_coll, guards=G, all_guards_pass=all(unlist(G))
), auto_unbox=TRUE, pretty=TRUE), file.path(WT, "r47_merge_guards.json"))
log("[done] merge + guards written.")
