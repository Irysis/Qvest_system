#==============================================================================
# dart_annual_backfill.R — DART 연간(사업보고서 11011) 과거 연도 보충 · 명시 플래그 전용
#
# 왜 있나 (2026-11-08):
#   연간 재무 원시본(dart_raw_financials)이 FY2015~2024 상장 종목의 28~30% 에서 굳어
#   있었다(FY2024 693/2,509 · FY2025 1,276/2,561 — 12월 상장 대비). 원인 3가지:
#   ① 완결 분모 = 직전 마감 연도 커버리지(작은 유니버스의 자기 기준 완결) → 분모를 그 해
#      상장 기업 수로 정정(dart_submission_window.R §완결 분모 정정)
#   ② lookback 3년 → FY2015~2022 는 미달이어도 후보가 아니다 → 이 스크립트(명시 플래그)로만 연다
#   ③ 진행 장부 부재 · 직전 연도 제출사 우선 → 예산 안에서 신규사가 밀렸다 → 장부 + 순서 정정
#   빠진 회사·연도 = 17,057건(FY2015~2025 · 2026-11-08 실측) · 1건 = 1~2콜(CFS → OFS).
#
# 같은 API 키를 쓰는 00:03 체인([5a] 연간 월 1회 · [5b] 분기+내부자 매일)과 겹치지 않게:
#   - 시간 창: 기본 04:00 이후 시작 · 23:30 마감(진행분 저장 후 중단 — 체인은 00:03)
#   - 체인 실행 중이면 시작 안 함(리프레시 잠금 %TEMP%/qm_daily_refresh.lock 또는 로그상
#     오늘 시작 표식 뒤에 '[lock] 데이터 갱신 완료'·'Done' 이 없음)
#   - 원시 캐시 잠금(.cache/dart/dart_raw_financials.lock — dart_fetch_all 이 잡는다)
#   - 예산 = min(--max-calls, 일일 상한 − 오늘 쓴 콜(사용량 로그) − 예비 − 아직 안 돈
#     [5b]·[5a] 예정분). 사용량 로그에 안 남는 호출(내부자 증분 ~400콜/일)은 예비가 덮는다.
#
# 사용:
#   Rscript 02_Infrastructure/data/dart_annual_backfill.R              # 계획만(API 0콜) — 상태 표 + 남은 콜 추정
#   Rscript 02_Infrastructure/data/dart_annual_backfill.R --backfill   # 오늘 예산만큼 수집
#   옵션: --from=2015 --to=<마지막 제출창 열린 연도> --max-calls=N --daily-cap=10000 --reserve=1000
#         --window-start=04:00 --deadline=23:30 --ignore-chain --compute=auto|always|never
#   --compute=auto(기본): 범위 안 요청 대상이 0 이 되면(보충 완료) fundamental_dart 재계산
#     (dart_compute_factors) + fundamental_merged 재생성(build_fundamental_derived.R).
#     ★병합 우선순위 · 팩터 DB 재빌드는 이 스크립트 소관이 아니다(도훈 확인 사항).
# 산출: .cache/dart/annual_backfill_status.json (연도별 상장·해결·시가총액 커버리지 · 남은 콜 추정)
# 종료 코드: 0 = 정상(수집 또는 계획) · 3 = 가드로 시작 안 함(체인 실행 중 · 시간 창 · 예산 없음)
#==============================================================================

.args <- commandArgs(trailingOnly = TRUE)
.arg <- function(name, default = NULL) {
  hit <- grep(sprintf("^--%s=", name), .args, value = TRUE)
  if (length(hit) == 0L) return(default)
  sub(sprintf("^--%s=", name), "", hit[length(hit)])
}
.flag <- function(name) any(.args == sprintf("--%s", name))

.resolve_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure", "config.R"))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1L]
}
ROOT <- .resolve_root()
setwd(file.path(ROOT, "02_Infrastructure"))
source("config.R")
source("data/data_collector_dart.R")
suppressPackageStartupMessages(library(jsonlite))

DO_BACKFILL  <- .flag("backfill")
TODAY        <- Sys.Date()
NOW          <- Sys.time()
DAILY_CAP    <- as.integer(.arg("daily-cap", "10000"))
RESERVE      <- as.integer(.arg("reserve", "1000"))
MAX_CALLS    <- suppressWarnings(as.numeric(.arg("max-calls", "Inf")))
FROM_FY      <- as.integer(.arg("from", "2015"))
COMPUTE      <- match.arg(.arg("compute", "auto"), c("auto", "always", "never"))
WINDOW_START <- .arg("window-start", "04:00")
DEADLINE_HM  <- .arg("deadline", "23:30")
IGNORE_CHAIN <- .flag("ignore-chain")
STATUS_PATH  <- file.path(DART_CACHE_DIR, "annual_backfill_status.json")
PEND_5B_CALLS <- 3000L   # [5b] 분기 예산(dart_daily_incremental quarterly_max_calls)
PEND_5A_CALLS <- 3000L   # [5a] 연간 예산(daily_refresh.sh dart_run_pipeline(max_calls = 3000))

# 마지막으로 제출창이 열린 연도 (오늘 기준) — 기본 상한
.last_open_fy <- function(today) {
  y <- as.integer(format(today, "%Y")) + 1L
  while (!.dart_window_open(y, "11011", today)) y <- y - 1L
  y
}
TO_FY <- as.integer(.arg("to", as.character(.last_open_fy(TODAY))))
YEARS <- seq.int(FROM_FY, TO_FY)

.hm_today <- function(hm, day = TODAY) as.POSIXct(paste(format(day), hm), format = "%Y-%m-%d %H:%M")

# ── 사용량 · 예정분 ───────────────────────────────────────────────────────────
.usage_today <- function(day = TODAY) {
  p <- DART_USAGE_LOG()
  if (!file.exists(p)) return(data.table(caller = character(0), calls = integer(0), note = character(0)))
  ln <- readLines(p, warn = FALSE)
  ln <- ln[grepl(sprintf('"date":"%s"', format(day)), ln, fixed = TRUE)]
  if (!length(ln)) return(data.table(caller = character(0), calls = integer(0), note = character(0)))
  rbindlist(lapply(ln, function(x) {
    j <- tryCatch(fromJSON(x), error = function(e) NULL)
    if (is.null(j)) return(NULL)
    data.table(caller = as.character(j$caller), calls = as.integer(j$calls),
               note = if (is.null(j$note)) "" else as.character(j$note))
  }), fill = TRUE)
}

# 보충 실행 이력에서 1건당 콜 수 실측 (없으면 NA)
.calls_per_task_measured <- function() {
  p <- DART_USAGE_LOG()
  if (!file.exists(p)) return(NA_real_)
  ln <- readLines(p, warn = FALSE)
  ln <- ln[grepl('"caller":"dart_fetch_all[backfill]"', ln, fixed = TRUE) & grepl("calls_total=", ln, fixed = TRUE)]
  if (!length(ln)) return(NA_real_)
  ct <- suppressWarnings(as.numeric(sub(".*calls_total=([0-9]+).*", "\\1", ln)))
  td <- suppressWarnings(as.numeric(sub(".*tasks=([0-9]+)/.*", "\\1", ln)))
  ok <- is.finite(ct) & is.finite(td) & td > 0
  if (!any(ok)) return(NA_real_)
  sum(ct[ok]) / sum(td[ok])
}

# ── 체인 실행 중 판정 ─────────────────────────────────────────────────────────
.chain_running <- function() {
  lock_dir <- file.path(Sys.getenv("TEMP", unset = tempdir()), "qm_daily_refresh.lock")
  if (dir.exists(lock_dir)) {
    age_h <- as.numeric(difftime(Sys.time(), file.mtime(lock_dir), units = "hours"))
    if (is.finite(age_h) && age_h < 8) return(sprintf("refresh_lock(%.1fh)", age_h))
  }
  lp <- file.path(CACHE_DIR, "scheduler_logs", "daily_refresh.log")
  if (!file.exists(lp)) return("")
  age_h <- as.numeric(difftime(Sys.time(), file.mtime(lp), units = "hours"))
  if (!is.finite(age_h) || age_h > 8) return("")          # 8시간 동안 아무것도 안 쓴 로그 = 실행 중 아님
  sz <- file.info(lp)$size
  con <- file(lp, "rb"); on.exit(close(con))
  n <- min(sz, 8e6)
  seek(con, sz - n)
  rb <- readBin(con, "raw", n)
  rb <- rb[rb != as.raw(0L)]                               # NUL 이 섞이면 rawToChar 가 죽는다
  tail_txt <- rawToChar(rb, multiple = FALSE)
  Encoding(tail_txt) <- "bytes"
  L <- strsplit(tail_txt, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  s <- grep("^=== Daily Refresh v2 @", L, useBytes = TRUE)
  if (!length(s)) return(if (age_h < 0.25) "log_active_no_marker" else "")
  after <- L[seq.int(max(s), length(L))]
  done_pat <- enc2utf8("^\\[lock\\] 데이터 갱신 완료|^=== Daily Refresh v2 Done")
  if (any(grepl(done_pat, after, useBytes = TRUE))) return("")
  return("log_open(start_without_done)")
}

# ── 상태 집계 ─────────────────────────────────────────────────────────────────
.status <- function(listed_tbl) {
  keys <- dart_annual_keys(DART_RAW_CACHE)
  ledger <- dart_annual_load_ledger()
  rt <- dart_annual_resolution(keys, ledger, listed_tbl, today = TODAY)
  cand <- listed_tbl[bsns_year %in% YEARS, .(corp_code, bsns_year, Ticker, corp_name, mcap)]
  pend <- dart_annual_pending_tasks(cand, keys = keys, ledger = ledger, today = TODAY)
  list(rt = rt[bsns_year %in% YEARS], pending = pend, ledger = ledger)
}

.print_table <- function(rt) {
  cat(sprintf("  %-6s %6s %6s %6s %6s %5s %5s %7s %6s %8s\n", "FY", "listed", "ok", "empty", "season",
              "fail", "untry", "unres", "ratio", "mcap_ok"))
  for (i in seq_len(nrow(rt))) {
    r <- rt[i]
    cat(sprintf("  FY%-4d %6d %6d %6d %6d %5d %5d %7d %6.3f %8.3f\n", r$bsns_year, r$listed, r$ok,
                r$empty_confirmed, r$empty_season, r$fail, r$untried, r$unresolved, r$ratio, r$mcap_ok_share))
  }
}

cat(sprintf("\n=== DART 연간 보충 %s @ %s | FY%d~FY%d ===\n",
            if (DO_BACKFILL) "실행" else "계획(API 0콜)", format(NOW, "%Y-%m-%d %H:%M:%S"), FROM_FY, TO_FY))
listed_tbl <- dart_listed_corps_by_year(rawdata_path = RAWDATA_CACHE)
st0 <- .status(listed_tbl)
cat("[보충 전]\n"); .print_table(st0$rt)

ut <- .usage_today()
used <- if (nrow(ut)) sum(ut$calls, na.rm = TRUE) else 0L
pend_5b <- !any(ut$caller == "dart_fetch_quarterly")
stamp <- file.path(DART_CACHE_DIR, ".annual_last_run_ym")
pend_5a <- !identical(trimws(tryCatch(readLines(stamp, warn = FALSE)[1L], error = function(e) "")),
                      format(TODAY, "%Y%m"))
pending_reserve <- (if (pend_5b) PEND_5B_CALLS else 0L) + (if (pend_5a) PEND_5A_CALLS else 0L)
budget <- min(MAX_CALLS, DAILY_CAP - used - RESERVE - pending_reserve)
cpt <- .calls_per_task_measured()
cpt_used <- if (is.finite(cpt)) cpt else 1.5
n_pend <- nrow(st0$pending)
per_day <- max(1, DAILY_CAP - RESERVE - PEND_5B_CALLS - 400L)   # 평일 기준(내부자 ~400 · [5a] 는 월 1회라 제외)
cat(sprintf("[예산] 일일 상한 %d − 오늘 사용 %d(로그) − 예비 %d − 예정 %d([5b] %s · [5a] %s) = %s콜\n",
            DAILY_CAP, used, RESERVE, pending_reserve, if (pend_5b) "미실행" else "완료",
            if (pend_5a) "이번 달 미실행" else "이번 달 완료", format(budget)))
cat(sprintf("[남은 일] 요청 대상 %d건 · 1건당 %.2f콜(%s) → 약 %s콜 · 하루 %d콜이면 약 %.1f일\n",
            n_pend, cpt_used, if (is.finite(cpt)) "보충 실측" else "가정", format(round(n_pend * cpt_used)),
            per_day, n_pend * cpt_used / per_day))

# compute_done = 보충 완료 뒤 fundamental_dart · merged 재생성을 마쳤는가(새 자료가 들어오면 FALSE)
PREV_STATUS <- tryCatch(fromJSON(STATUS_PATH), error = function(e) NULL)
COMPUTE_DONE <- isTRUE(PREV_STATUS$compute_done)

.write_status <- function(st, phase, fr = NULL, guard = "") {
  rt <- st$rt
  out <- list(
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), phase = phase, guard = guard,
    compute_done = COMPUTE_DONE,
    range = c(FROM_FY, TO_FY), today = format(TODAY),
    budget = list(daily_cap = DAILY_CAP, used_logged = used, reserve = RESERVE,
                  pending_reserve = pending_reserve, budget = if (is.finite(budget)) budget else NULL),
    result = fr,
    pending_tasks = nrow(st$pending),
    calls_per_task = list(value = cpt_used, measured = is.finite(cpt)),
    est_calls_remaining = round(nrow(st$pending) * cpt_used),
    est_days_remaining = round(nrow(st$pending) * cpt_used / per_day, 2),
    complete = nrow(st$pending) == 0L,
    coverage = rt[, .(bsns_year, listed, ok, empty_confirmed, empty_season, fail, untried,
                      resolved, unresolved, ratio = round(ratio, 4), mcap_ok_share = round(mcap_ok_share, 4))])
  writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), STATUS_PATH,
             useBytes = TRUE)
  cat(sprintf("[상태] %s\n", STATUS_PATH))
}

if (!DO_BACKFILL) {
  .write_status(st0, "plan")
  cat("[계획] --backfill 플래그가 없어 API 를 부르지 않았다.\n")
  quit(status = 0)
}

# ── 가드 ──────────────────────────────────────────────────────────────────────
guard <- ""
deadline <- .hm_today(DEADLINE_HM)
if (NOW < .hm_today(WINDOW_START) || NOW >= deadline) {
  guard <- sprintf("time_window(%s~%s 밖)", WINDOW_START, DEADLINE_HM)
}
if (!nzchar(guard) && !IGNORE_CHAIN) {
  cr <- .chain_running()
  if (nzchar(cr)) guard <- sprintf("chain_running(%s)", cr)
}
if (!nzchar(guard) && (!is.finite(budget) || budget < 50)) guard <- sprintf("no_budget(%s)", format(budget))
if (!nzchar(guard) && n_pend == 0L) guard <- "nothing_pending"
if (nzchar(guard) && guard != "nothing_pending") {
  cat(sprintf("[가드] 시작 안 함 — %s\n", guard))
  .write_status(st0, "guarded", guard = guard)
  quit(status = 3)
}

fr <- NULL
if (n_pend > 0L) {
  fr <- dart_fetch_all(years = YEARS, backfill = TRUE, max_calls = budget, deadline = deadline,
                       today = TODAY)
}
st1 <- .status(listed_tbl)
cat("[보충 뒤]\n"); .print_table(st1$rt)
cpt <- .calls_per_task_measured(); if (is.finite(cpt)) cpt_used <- cpt

# ── 보충 완료 시 fundamental_dart · fundamental_merged 재생성 ───────────────────
#   auto: 범위 안 요청 대상 0 ∧ 잠금으로 건너뛰지 않음 ∧ (이번에 새 자료 ∨ 완료 후 재생성 전)
fetched_new <- !is.null(fr) && isTRUE(fr$ok > 0)
if (fetched_new) COMPUTE_DONE <- FALSE
do_compute <- identical(COMPUTE, "always") ||
  (identical(COMPUTE, "auto") && nrow(st1$pending) == 0L && !identical(fr$skipped, "locked") &&
     !COMPUTE_DONE)
if (do_compute) {
  # 덮어쓰기 전 사본(build_fundamental_derived.R 의 BACKUP_PATH 는 선언만 있고 쓰이지 않는다)
  bdir <- file.path(DART_CACHE_DIR, "backfill_backup")
  dir.create(bdir, showWarnings = FALSE, recursive = TRUE)
  for (f in c(DART_FACTOR_CACHE, file.path(CACHE_DIR, "fundamental_merged.parquet"))) {
    if (file.exists(f)) {
      dst <- file.path(bdir, sub("\\.parquet$", sprintf("_%s.parquet", format(Sys.time(), "%Y%m%d_%H%M")), basename(f)))
      if (!file.copy(f, dst, overwrite = FALSE)) stop("[compute] 사본 실패 — 덮어쓰지 않는다: ", f)
      cat(sprintf("[compute] 사본: %s\n", dst))
    }
  }
  cat("\n[compute] fundamental_dart 재계산 (dart_compute_factors)...\n")
  dart_compute_factors()
  rs <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  cat("[compute] fundamental_merged 재생성 (build_fundamental_derived.R)...\n")
  rc <- system2(rs, c("--no-save", shQuote(file.path(ROOT, "02_Infrastructure", "data", "build_fundamental_derived.R"))))
  cat(sprintf("[compute] build_fundamental_derived rc=%s\n", rc))
  if (!identical(as.integer(rc), 0L)) {
    .write_status(st1, "done_compute_failed", fr = fr)
    quit(status = 1)
  }
  COMPUTE_DONE <- nrow(st1$pending) == 0L
} else {
  cat(sprintf("[compute] 건너뜀 (compute=%s · 남은 요청 %d)\n", COMPUTE, nrow(st1$pending)))
}
.write_status(st1, if (nrow(st1$pending) == 0L) "complete" else "partial", fr = fr)
quit(status = 0)
