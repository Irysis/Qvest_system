#!/usr/bin/env Rscript
#==============================================================================
# DART Insider Backfill Driver — resumable, universe-bounded, daily-limit-aware
#
# 2026-06-30 (도훈 mandate "인사이더 백필 → QEPM"):
#   - 버그수리: pblntf_ty="D"(지분공시), 기존 collector 의 "E"(기타공시)는 insider 0건.
#   - 월 50건 cap 제거(전수). 유니버스(K200∪KQ150 corp_code) 한정으로 API 호출 bound.
#   - 월별 CSV 체크포인트 → resumable(완료 월 skip). 일일 예산 가드(DART 10k/일, daily_refresh 여유).
#   - 측정: 월 ~1,500 insider(전체) → 유니버스 한정 ~300-500/월. 2005-2024 ~10-13일(일 7k 예산).
#
# Usage: QM_ROOT=... [BF_START=2005-01 BF_END=2024-02 DART_DAILY_BUDGET=7000] Rscript dart_insider_backfill.R
# 산출: .cache/dart/insider_backfill/<YYYYMM>.csv (consolidate 별도)
#==============================================================================
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

ROOT  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
env   <- readLines(file.path(ROOT, ".env"), warn = FALSE)
KEY   <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
CKDIR <- file.path(ROOT, ".cache/dart/insider_backfill"); dir.create(CKDIR, recursive = TRUE, showWarnings = FALSE)
uni   <- fread(file.path(ROOT, ".cache/dart/universe_corpcodes.csv"), colClasses = "character")
UNI_CC <- unique(uni$corp_code)
# [2026-07-05] document.xml 원문 파서 (elestock.json 최근2년 cap 우회 — 2005~ 역사 전구간).
#   ★encoding="UTF-8" 필수(누락 시 전량 FAIL). parse_insider_doc(rcept_no, KEY)가 GET 자체수행.
source(file.path(ROOT, "02_Infrastructure/data/dart_insider_doc_parser.R"), encoding = "UTF-8")
DELAY <- 0.75
DAILY_BUDGET <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "7000"))
START <- Sys.getenv("BF_START", "2005-01"); END <- Sys.getenv("BF_END", "2024-02")

calls <- 0L; halted <- FALSE
api_get <- function(url, q) { calls <<- calls + 1L; r <- tryCatch(GET(url, query = q), error = function(e) NULL); Sys.sleep(DELAY); r }
parse_resp <- function(r) tryCatch(fromJSON(content(r, "text", encoding = "UTF-8"), flatten = TRUE), error = function(e) NULL)

months <- format(seq(as.Date(paste0(START, "-01")), as.Date(paste0(END, "-01")), by = "month"), "%Y%m")
cat(sprintf("[bf] universe corp_codes=%d | months=%s..%s (%d) | budget=%d/run\n",
            length(UNI_CC), START, END, length(months), DAILY_BUDGET))

for (ym in months) {
  ck <- file.path(CKDIR, paste0(ym, ".csv"))
  if (file.exists(ck)) next
  if (calls >= DAILY_BUDGET) { cat(sprintf("[bf] budget reached before %s — stop (resume next run)\n", ym)); break }

  yr <- substr(ym, 1, 4); mo <- substr(ym, 5, 6)
  bgn <- paste0(ym, "01")
  last <- format(seq(as.Date(paste0(yr, "-", mo, "-01")), by = "month", length.out = 2)[2] - 1, "%d")
  end <- paste0(ym, last)

  # paginate 지분공시 list
  page <- 1L; disc <- list(); list_ok <- TRUE
  repeat {
    p  <- api_get("https://opendart.fss.or.kr/api/list.json",
                  list(crtfc_key = KEY, bgn_de = bgn, end_de = end, pblntf_ty = "D", page_no = page, page_count = 100))
    pp <- parse_resp(p)
    if (is.null(pp)) { list_ok <- FALSE; break }
    if (!is.null(pp$status) && pp$status == "020") { cat("[bf] DART status 020 (rate limit) — halt\n"); halted <- TRUE; break }
    if (is.null(pp$status) || pp$status != "000" || is.null(pp$list) || length(pp$list) == 0) break
    disc[[length(disc) + 1L]] <- as.data.table(pp$list)
    tp <- if (!is.null(pp$total_page)) as.integer(pp$total_page) else page
    if (page >= tp) break
    page <- page + 1L
    if (calls >= DAILY_BUDGET) { list_ok <- FALSE; break }
  }
  if (halted) break
  if (!list_ok) { cat(sprintf("[bf] list incomplete for %s — skip checkpoint, redo next run\n", ym)); break }

  if (!length(disc)) { fwrite(data.table(ym = ym, note = "no_disclosures"), ck); next }
  dd  <- rbindlist(disc, fill = TRUE)
  ins <- dd[grepl("임원.{0,2}주요주주.{0,4}특정증권", report_nm) & corp_code %in% UNI_CC]
  if (!nrow(ins)) { fwrite(data.table(ym = ym, note = "no_universe_insider"), ck);
                    cat(sprintf("[bf] %s: 0 universe insider (calls=%d)\n", ym, calls)); next }

  # [2026-07-13 수리] 단발 429/503에 즉시 halt하던 fail-fast가 대형 월(202001+ 600건대)에서
  # "partial → 체크포인트 스킵 → 재시도" 무한루프 유발(201912 정체 실사고, 3h 스케줄 반복 공전).
  # 일시 오류 = 백오프 재시도 2회 → 소진 시 해당 문서만 note 행 기록 후 계속(월당 실패율 2% 초과면 partial).
  # 진짜 일한도(status 020)만 즉시 halt.
  .is_rate  <- function(pr) !is.null(pr) && "note" %in% names(pr) &&
    any(grepl("020|rate|http_fail_(429|503)", as.character(pr$note)), na.rm = TRUE)
  .is_quota <- function(pr) !is.null(pr) && "note" %in% names(pr) &&
    any(grepl("\\b020\\b", as.character(pr$note)), na.rm = TRUE)
  rows <- list(); partial <- FALSE; fail_n <- 0L
  for (i in seq_len(nrow(ins))) {
    if (calls >= DAILY_BUDGET) { partial <- TRUE; break }
    calls <- calls + 1L
    # elestock.json(최근2년 cap) → document.xml 원문 파서(역사 전구간). parse_insider_doc가 GET 자체수행.
    pr <- tryCatch(parse_insider_doc(ins$rcept_no[i], KEY), error = function(e) NULL)
    Sys.sleep(DELAY)
    retry <- 0L
    while (.is_rate(pr) && !.is_quota(pr) && retry < 2L && calls < DAILY_BUDGET) {
      retry <- retry + 1L; Sys.sleep(5 * retry)
      calls <- calls + 1L
      pr <- tryCatch(parse_insider_doc(ins$rcept_no[i], KEY), error = function(e) NULL)
      Sys.sleep(DELAY)
    }
    if (.is_quota(pr)) { cat("[bf] DART status 020 (일한도) — halt\n"); halted <- TRUE; partial <- TRUE; break }
    if (.is_rate(pr)) {
      fail_n <- fail_n + 1L
      rows[[length(rows) + 1L]] <- data.table(ym = ym, rcept_dt = ins$rcept_dt[i],
                                              note = sprintf("doc_fail_after_retry:%s", ins$rcept_no[i]))
      next
    }
    if (!is.null(pr) && nrow(pr) > 0) {
      pr[, rcept_dt := ins$rcept_dt[i]]; pr[, ym := ym]
      rows[[length(rows) + 1L]] <- pr
    }
  }
  if (!partial && fail_n > max(2L, as.integer(0.02 * nrow(ins)))) {
    cat(sprintf("[bf] %s doc 실패 과다(fail_n=%d/%d) — skip checkpoint, redo next run\n", ym, fail_n, nrow(ins)))
    partial <- TRUE
  }
  if (partial) { cat(sprintf("[bf] %s partial (budget/halt at report %d/%d, fail_n=%d) — skip checkpoint, redo next run\n", ym, i, nrow(ins), fail_n)); break }

  out <- if (length(rows)) rbindlist(rows, fill = TRUE) else data.table(ym = ym, note = "no_insider_trades")
  fwrite(out, ck)
  cat(sprintf("[bf] %s done: %d reports, %d rows (calls=%d)\n", ym, nrow(ins), if (length(rows)) nrow(out) else 0L, calls))
}

done <- sum(file.exists(file.path(CKDIR, paste0(months, ".csv"))))
cat(sprintf("[bf] RUN END. calls=%d halted=%s done=%d/%d months. 다음 run 이 이어서 수집.\n",
            calls, halted, done, length(months)))
