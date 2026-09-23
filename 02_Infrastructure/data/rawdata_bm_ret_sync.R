#==============================================================================
# rawdata_bm_ret_sync.R — RAWDATA.parquet::BM_Ret 단일 writer (W-09 · 2026-09-23 도훈 승인)
#
# ## 정의 (재도출 — rawdata_bm_ret_sync_config.json::_definition_derivation)
#   RAWDATA.BM_Ret(d) := .cache/benchmark.parquet::BM_Ret(d)
#   = 코스피200 종가 대비 단순수익률(소수). 한 날짜의 모든 종목 행에 같은 값.
#   1999-01-04~2026-09-06 공통 구간은 2025-01-02 · 2026-09-02 외 전부 비트 일치였다.
#
# ## 왜 단일 writer 인가 (실사고)
#   BM_Ret 을 RAWDATA 에 쓰는 경로가 여럿이었고 서로 다른 정의를 썼다:
#     · naver_data_collector.R  — 행을 append 하면서 BM_Ret 을 **아예 안 채움**
#                                  → 2026-09-07~ 전량 NA(MA06 소실 · C18 332→110행)
#     · krx_build_rawdata.R     — KRX 지수로 **자체 계산** + NA 면 **0 센티널**(결측 위장)
#     · incremental_update_file.R / rawdata_sanitize.R — 벤치 **전열 재조인**(보호 날짜까지 덮음)
#     · build_index_cache.py --update-rawdata — 전열 재생성 + BM_Ret NA 행 **삭제**
#   경로가 여럿이면 마지막에 쓴 쪽의 정의가 굳는다. 여기가 그 정의의 유일한 구현이다.
#   다른 writer 는 이 파일의 rawdata_bm_ret_sync_dt()(메모리) 또는
#   rawdata_sync_bm_ret()(파일) 를 부른다.
#
# ## 규칙
#   · 채움(fill)      : RAWDATA 결측 ∧ 벤치 유한값 → 벤치 값. 킬스위치 무관(측정값을 바꾸지 않는다).
#   · 덮어쓰기(overwrite): RAWDATA 유한값 ≠ 벤치 → 킬스위치(reinforce_auto_config.json::enabled)가
#                        내려가 있을 때만 · 상한(max_overwrite_per_run) 이하일 때만.
#   · 보호(protect)   : 설정의 보호 구간(1990~98 토요장 계열 · 2024-12-30)은 어떤 경우에도 안 쓴다.
#   · 벤치 지연(bench_lag): RAWDATA 날짜 > 벤치 최신일 → NA 로 두고 경고. **추정 금지.**
#   · 벤치 결손(bench_missing): 벤치 구간 안인데 벤치에 그 날이 없음 → NA 유지 + 위반.
#   · 광기값(refused_insane): |벤치 값| > max_abs_ret → 쓰지 않고 위반.
#   · BM_Ret 외 열·행 순서·행 수는 건드리지 않는다(쓰기 전후 대조로 검증).
#
# ## 사용
#   source("02_Infrastructure/data/rawdata_bm_ret_sync.R")
#   rawdata_sync_bm_ret()                        # dry-run (계획만)
#   rawdata_sync_bm_ret(dry_run = FALSE)         # 결측 채움 + (킬스위치 해제 시) 불일치 정정
#   rawdata_sync_bm_ret(dates = as.Date(c("2025-01-02","2026-09-02")), dry_run = FALSE)
#   CLI: Rscript rawdata_bm_ret_sync.R [--apply] [--allow-overwrite] [--dates 2025-01-02,2026-09-02]
#        덮어쓰기 = --allow-overwrite ∧ 킬스위치 해제 둘 다(수동 정정 전용). 플래그 없으면 채움만.
#        rc 0 = 정합 · 4 = 벤치 지연(NA 유지·경고) · 3 = 위반(거부/결손/광기값/쓰기검증 실패) · 1 = 오류
#   검사: 08_Tests/data/test_rawdata_bm_ret_sync.R
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# 이 파일의 위치 — source() 가 함수 안에서 불려도 찾도록 가장 가까운 ofile 프레임을 쓴다.
.BMS_SELF_DIR <- tryCatch({
  of <- NULL
  for (.f in rev(sys.frames())) if (!is.null(.f$ofile)) { of <- .f$ofile; break }
  if (is.null(of)) {   # Rscript <file> (CLI) — --file= 인자
    .fa <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (length(.fa)) of <- sub("^--file=", "", .fa[1L])
  }
  if (is.null(of)) NA_character_ else {
    of <- gsub("\\\\", "/", of)   # 한글 경로 규약상 경로 정규화 함수는 쓰지 않는다 — 절대화만
    if (!grepl("^([A-Za-z]:|/)", of)) of <- file.path(gsub("\\\\", "/", getwd()), of)
    dirname(of)
  }
}, error = function(e) NA_character_)

.bms_is_root <- function(p) {
  !is.null(p) && length(p) == 1L && !is.na(p) && nzchar(p) &&
    file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))
}

#' 프로젝트 루트 — 인자 > PROJECT_ROOT > QM_ROOT > 이 파일 위치(../..).
.bms_root <- function(root = NULL) {
  cand <- c(root,
            if (exists("PROJECT_ROOT", envir = globalenv())) get("PROJECT_ROOT", envir = globalenv()),
            Sys.getenv("QM_ROOT", unset = ""),
            if (!is.na(.BMS_SELF_DIR)) dirname(dirname(.BMS_SELF_DIR)))
  for (c0 in cand) {
    c0 <- gsub("\\\\", "/", c0)
    if (.bms_is_root(c0)) return(c0)
  }
  stop("[bm_ret_sync] 프로젝트 루트 resolve 실패 — root 인자 또는 QM_ROOT 필요")
}

#' 설정 로드 — 부재 = stop(하드코딩 폴백 없음).
rawdata_bm_ret_sync_config <- function(path = NULL, root = NULL) {
  if (is.null(path)) {
    d <- if (!is.na(.BMS_SELF_DIR)) .BMS_SELF_DIR else file.path(.bms_root(root), "02_Infrastructure/data")
    path <- file.path(d, "rawdata_bm_ret_sync_config.json")
  }
  if (!file.exists(path)) stop("[bm_ret_sync] 설정 부재: ", path)
  cfg <- fromJSON(path, simplifyVector = TRUE)
  need <- c("tolerance", "max_abs_ret", "max_overwrite_per_run", "protect", "killswitch")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[bm_ret_sync] 설정 키 부재: ", paste(miss, collapse = ","))
  pr <- as.data.table(cfg$protect)
  if (nrow(pr)) {
    pr[, `:=`(from = as.Date(from), to = as.Date(to))]
    if (anyNA(pr$from) || anyNA(pr$to)) stop("[bm_ret_sync] 보호 구간 날짜 판독 실패")
  }
  cfg$protect <- pr
  cfg$tolerance <- as.numeric(cfg$tolerance)
  cfg$max_abs_ret <- as.numeric(cfg$max_abs_ret)
  cfg$max_overwrite_per_run <- as.integer(cfg$max_overwrite_per_run)
  cfg$.path <- path
  cfg
}

#' 보호 날짜 판정 (벡터).
bm_ret_protected <- function(dates, cfg) {
  dates <- as.Date(dates)
  out <- rep(FALSE, length(dates))
  pr <- cfg$protect
  if (!is.null(pr) && nrow(pr))
    for (i in seq_len(nrow(pr))) out <- out | (dates >= pr$from[i] & dates <= pr$to[i])
  out
}

#' 킬스위치 판독 — TRUE = 기존 유한값 덮어쓰기 허용.
#' naver_data_collector.R::.naver_assert_write_allowed 와 같은 판정: 파일 부재 = 허용,
#' flag=true = 거부, 판독 실패 = 거부.
bm_ret_overwrite_allowed <- function(cfg, root = NULL, killswitch_path = NULL) {
  p <- killswitch_path
  if (is.null(p)) p <- file.path(.bms_root(root), cfg$killswitch$path)
  if (!file.exists(p)) return(TRUE)
  flag <- cfg$killswitch$flag
  en <- tryCatch(isTRUE(fromJSON(p)[[flag]]), error = function(e) TRUE)
  !en
}

#' 벤치 로드 — (Date, BM_Ret). 중복 날짜 = stop.
bm_ret_read_bench <- function(bench_path) {
  if (!file.exists(bench_path)) stop("[bm_ret_sync] 벤치 부재: ", bench_path)
  b <- as.data.table(read_parquet(bench_path, col_select = c("Date", "BM_Ret"), mmap = FALSE))
  b[, Date := as.Date(Date)]
  b[, BM_Ret := as.numeric(BM_Ret)]
  if (anyDuplicated(b$Date)) stop("[bm_ret_sync] 벤치 날짜 중복 — 정본 판독 불가")
  setorder(b, Date)
  b
}

#' 날짜별 현재 상태 요약 — (Date, BM_Ret) 행 테이블에서.
bm_ret_date_summary <- function(dt) {
  x <- dt[, .(Date = as.Date(Date), BM_Ret = as.numeric(BM_Ret))]
  x[, .(n = .N,
        n_na = sum(!is.finite(BM_Ret)),
        n_val = uniqueN(BM_Ret[is.finite(BM_Ret)]),
        cur = if (any(is.finite(BM_Ret))) BM_Ret[is.finite(BM_Ret)][1L] else NA_real_),
    by = Date]
}

#' 계획 — 순수 함수(쓰기 없음).
#' @param cur    bm_ret_date_summary() 결과
#' @param bench  bm_ret_read_bench() 결과
#' @param dates  NULL = 전 날짜 · 벡터 = 그 날짜만 판정(나머지는 계획에서 제외 = 불변)
#' @param allow_overwrite 킬스위치 판정
#' @return data.table(Date, n, n_na, cur, bench, action, reason)
bm_ret_sync_plan <- function(cur, bench, cfg, dates = NULL, allow_overwrite = FALSE) {
  cur <- copy(cur)
  bench_max <- if (nrow(bench)) max(bench$Date) else as.Date(NA)
  absent <- data.table()
  if (!is.null(dates)) {
    dates <- unique(as.Date(dates))
    absent_d <- setdiff(dates, cur$Date)
    if (length(absent_d))
      absent <- data.table(Date = as.Date(absent_d, origin = "1970-01-01"), n = 0L, n_na = 0L,
                           cur = NA_real_, bench = NA_real_, action = "absent_in_rawdata",
                           reason = "요청 날짜가 RAWDATA 에 없음")
    cur <- cur[Date %in% dates]
  }
  bench_dates <- bench$Date
  p <- merge(cur, bench[, .(Date, bench = BM_Ret)], by = "Date", all.x = TRUE)
  p[, in_bench := Date %in% bench_dates]
  tol <- cfg$tolerance
  p[, has_diff := n_val > 1L | (n_val == 1L & is.finite(bench) & abs(cur - bench) > tol)]
  p[, action := NA_character_][, reason := NA_character_]
  p[, prot := bm_ret_protected(Date, cfg)]
  p[prot == TRUE, `:=`(action = "protected", reason = "설정 보호 구간 — 쓰지 않는다")]
  p[is.na(action) & !is.finite(bench) & n_na > 0L & !is.na(bench_max) & Date > bench_max,
    `:=`(action = "bench_lag", reason = "벤치가 이 날짜를 아직 못 덮음 — NA 유지(추정 금지)")]
  p[is.na(action) & !is.finite(bench) & n_na > 0L,
    `:=`(action = "bench_missing", reason = ifelse(in_bench, "벤치 행은 있으나 BM_Ret 결측",
                                                   "벤치 구간 안인데 벤치에 날짜 없음 — 달력 불일치"))]
  p[is.na(action) & !is.finite(bench),
    `:=`(action = "no_bench_keep", reason = "벤치 값 없음 — RAWDATA 기존값 유지(경계일 등)")]
  p[is.na(action) & abs(bench) > cfg$max_abs_ret,
    `:=`(action = "refused_insane", reason = sprintf("|벤치|>%s — 스케일 단절 의심", format(cfg$max_abs_ret)))]
  p[is.na(action) & has_diff == TRUE, action := "overwrite"]
  p[is.na(action) & n_na > 0L, `:=`(action = "fill", reason = "결측 → 벤치 값")]
  p[is.na(action), `:=`(action = "ok", reason = "일치")]
  n_ow <- p[action == "overwrite", .N]
  if (n_ow > 0L) {
    if (!isTRUE(allow_overwrite)) {
      p[action == "overwrite", `:=`(action = "refused_killswitch",
                                    reason = "기존 유한값 변경 불허 — 킬스위치 가동 중 또는 --allow-overwrite 없음(무인 경로)")]
    } else if (n_ow > cfg$max_overwrite_per_run) {
      p[action == "overwrite", `:=`(action = "refused_cap",
                                    reason = sprintf("덮어쓰기 %d일 > 상한 %d — 벤치 축 이동 의심, 전부 거부",
                                                     n_ow, cfg$max_overwrite_per_run))]
    } else {
      p[action == "overwrite", reason := "기존 유한값 ≠ 벤치 → 벤치 값"]
    }
  }
  p[, c("in_bench", "has_diff", "prot", "n_val") := NULL]
  out <- rbind(p[, .(Date, n, n_na, cur, bench, action, reason)], absent, fill = TRUE)
  setorder(out, Date)
  out[]
}

BM_RET_WRITE_ACTIONS     <- c("fill", "overwrite")
BM_RET_VIOLATION_ACTIONS <- c("refused_insane", "refused_killswitch", "refused_cap",
                              "bench_missing", "absent_in_rawdata")

#' 판정 코드 — 0 정합 · 4 벤치 지연 · 3 위반.
bm_ret_plan_rc <- function(plan) {
  if (any(plan$action %in% BM_RET_VIOLATION_ACTIONS)) return(3L)
  if (any(plan$action == "bench_lag")) return(4L)
  0L
}

#' 메모리 적용 — raw 의 BM_Ret 만 계획대로 바꾼다(제자리 set · 행 순서 불변).
bm_ret_apply_dt <- function(raw, plan) {
  w <- plan[action %in% BM_RET_WRITE_ACTIONS]
  if (!nrow(w)) return(invisible(list(dt = raw, n_rows = 0L)))
  if (!inherits(raw$Date, "Date")) stop("[bm_ret_sync] raw$Date 가 Date 형이 아니다 — 조인 전 as.Date 필요")
  idx <- which(raw$Date %in% w$Date)
  val <- w$bench[match(raw$Date[idx], w$Date)]
  set(raw, i = idx, j = "BM_Ret", value = as.numeric(val))
  invisible(list(dt = raw, n_rows = length(idx)))
}

.bms_say_plan <- function(plan, tag = "bm_ret_sync", tol = 1e-12) {
  tb <- plan[, .N, by = action]
  cat(sprintf("[%s] 계획: %s\n", tag, paste(sprintf("%s=%d", tb$action, tb$N), collapse = " · ")))
  show <- plan[!action %in% c("ok", "protected", "no_bench_keep")]
  if (nrow(show)) {
    for (i in seq_len(min(nrow(show), 40L)))
      cat(sprintf("   %s  %-18s cur=%s bench=%s  (%s)\n", format(show$Date[i]), show$action[i],
                  ifelse(is.finite(show$cur[i]), sprintf("%+.10f", show$cur[i]), "NA"),
                  ifelse(is.finite(show$bench[i]), sprintf("%+.10f", show$bench[i]), "NA"),
                  show$reason[i]))
    if (nrow(show) > 40L) cat(sprintf("   ... 외 %d일\n", nrow(show) - 40L))
  }
  np <- plan[action == "protected" & (n_na > 0L | (is.finite(cur) & is.finite(bench) & abs(cur - bench) > tol)), .N]
  if (np) cat(sprintf("[%s] 보호 구간 불일치 %d일 — 결정 대기로 미처리(설정 protect)\n", tag, np))
}

#' 다른 writer 용 메모리 경로 — 이미 raw 를 들고 있는 writer 가 쓰기 직전에 부른다.
#' ★전열 재조인(raw[, BM_Ret := NULL]; merge(...)) 대신 이 함수를 쓴다.
#' @param raw   data.table (Date, BM_Ret 포함). BM_Ret 부재면 NA 열을 만든다.
#' @param allow_overwrite NULL = 킬스위치 판독
#' @return list(dt, plan, rc)
rawdata_bm_ret_sync_dt <- function(raw, bench = NULL, cfg = NULL, dates = NULL,
                                   allow_overwrite = NULL, root = NULL, tag = "bm_ret_sync_dt") {
  stopifnot(is.data.table(raw))
  if (is.null(cfg)) cfg <- rawdata_bm_ret_sync_config(root = root)
  if (is.null(bench)) bench <- bm_ret_read_bench(file.path(.bms_root(root), ".cache", "benchmark.parquet"))
  if (!inherits(raw$Date, "Date")) raw[, Date := as.Date(Date)]
  if (!"BM_Ret" %in% names(raw)) raw[, BM_Ret := NA_real_]
  if (!is.double(raw$BM_Ret)) raw[, BM_Ret := as.numeric(BM_Ret)]
  if (is.null(allow_overwrite)) allow_overwrite <- bm_ret_overwrite_allowed(cfg, root = root)
  plan <- bm_ret_sync_plan(bm_ret_date_summary(raw[, .(Date, BM_Ret)]), bench, cfg,
                           dates = dates, allow_overwrite = allow_overwrite)
  .bms_say_plan(plan, tag, cfg$tolerance)
  bm_ret_apply_dt(raw, plan)
  list(dt = raw, plan = plan, rc = bm_ret_plan_rc(plan))
}

#' 파일 경로 단일 writer.
#' @param dates     NULL = 전 날짜 판정 · 벡터 = 그 날짜만
#' @param dry_run   TRUE = 계획만(파일·로그 쓰기 0)
#' @param backup_path 지정 시 쓰기 전 원본 복사(존재하면 stop — 덮지 않는다)
#' @param log_dir   기본 = raw_path 디렉터리 (검사가 운영 로그에 쓰지 않도록)
#' @return list(plan, rc, n_rows_written, written)
rawdata_sync_bm_ret <- function(dates = NULL, dry_run = TRUE, raw_path = NULL, bench_path = NULL,
                                cfg = NULL, root = NULL, killswitch_path = NULL,
                                allow_overwrite = NULL, log_dir = NULL, backup_path = NULL) {
  if (is.null(raw_path) || is.null(bench_path)) {
    rt <- .bms_root(root)
    if (is.null(raw_path))   raw_path   <- file.path(rt, ".cache", "RAWDATA.parquet")
    if (is.null(bench_path)) bench_path <- file.path(rt, ".cache", "benchmark.parquet")
  }
  if (is.null(cfg)) cfg <- rawdata_bm_ret_sync_config(root = root)
  if (is.null(allow_overwrite))
    allow_overwrite <- bm_ret_overwrite_allowed(cfg, root = root, killswitch_path = killswitch_path)
  if (is.null(log_dir)) log_dir <- dirname(raw_path)
  if (!file.exists(raw_path)) stop("[bm_ret_sync] RAWDATA 부재: ", raw_path)

  bench <- bm_ret_read_bench(bench_path)
  # 동시 writer 가드 — 계획 시점의 파일 지문. 쓰기 직전에 다시 재서 다르면 쓰지 않는다
  #   (다른 writer 가 그 사이 RAWDATA 를 바꿨다면 그 변경을 덮어 지우게 된다).
  .fp <- function() { fi <- file.info(raw_path); paste(fi$size, format(fi$mtime, "%Y-%m-%d %H:%M:%OS6")) }
  fp0 <- .fp()
  slim <- as.data.table(read_parquet(raw_path, col_select = c("Date", "BM_Ret"), mmap = FALSE))
  slim[, Date := as.Date(Date)]
  plan <- bm_ret_sync_plan(bm_ret_date_summary(slim), bench, cfg, dates = dates,
                           allow_overwrite = allow_overwrite)
  rm(slim); gc(verbose = FALSE)
  cat(sprintf("[bm_ret_sync] mode=%s · 벤치 최신 %s · 덮어쓰기 %s\n",
              if (dry_run) "DRY-RUN" else "APPLY", format(max(bench$Date)),
              if (allow_overwrite) "허용(--allow-overwrite ∧ 킬스위치 해제)" else "거부(킬스위치 가동 또는 플래그 없음)"))
  .bms_say_plan(plan, tol = cfg$tolerance)
  rc <- bm_ret_plan_rc(plan)
  w <- plan[action %in% BM_RET_WRITE_ACTIONS]
  res <- list(plan = plan, rc = rc, n_rows_written = 0L, written = FALSE)
  if (dry_run || !nrow(w)) {
    if (!dry_run) .bms_write_log(plan, res, log_dir, raw_path)
    return(invisible(res))
  }

  # ── 쓰기: 전 열 로드 → BM_Ret 만 set → 원자 교체 ─────────────────────────
  gc(verbose = FALSE)
  raw <- as.data.table(read_parquet(raw_path, mmap = FALSE))
  cols0 <- names(raw); n0 <- nrow(raw)
  types0 <- vapply(raw, function(v) class(v)[1L], character(1))
  if (!inherits(raw$Date, "Date")) stop("[bm_ret_sync] RAWDATA Date 형이 Date 가 아니다 — 스키마 이탈")
  old_bm <- copy(raw$BM_Ret)
  # 다른 열 불변 가드 — BM_Ret 외 전 열의 내용 해시를 적용 전후로 대조한다(열 복사 없이).
  .col_hash <- function(dt) vapply(setdiff(names(dt), "BM_Ret"),
                                   function(cc) digest::digest(dt[[cc]], algo = "xxhash64"), character(1))
  h0 <- .col_hash(raw)
  ap <- bm_ret_apply_dt(raw, plan)
  h1 <- .col_hash(raw)
  if (!identical(h0, h1))
    stop("[bm_ret_sync] ★BM_Ret 외 열이 바뀌었다 — 쓰지 않는다: ",
         paste(names(h0)[h0 != h1[names(h0)]], collapse = ","))
  chg <- which(xor(is.na(old_bm), is.na(raw$BM_Ret)) |
               (!is.na(old_bm) & !is.na(raw$BM_Ret) & old_bm != raw$BM_Ret))
  stray <- setdiff(unique(raw$Date[chg]), w$Date)
  if (length(stray)) stop("[bm_ret_sync] ★계획 밖 날짜 변경 감지 — 쓰지 않는다: ",
                          paste(format(head(stray, 5)), collapse = ","))
  if (nrow(raw) != n0 || !identical(names(raw), cols0) ||
      !identical(vapply(raw, function(v) class(v)[1L], character(1)), types0))
    stop("[bm_ret_sync] ★행 수·열 구성·형이 바뀌었다 — 쓰지 않는다")

  if (!is.null(backup_path)) {
    if (file.exists(backup_path)) stop("[bm_ret_sync] 백업 경로가 이미 존재 — 덮지 않는다: ", backup_path)
    if (!file.copy(raw_path, backup_path)) stop("[bm_ret_sync] 백업 실패: ", backup_path)
    cat(sprintf("[bm_ret_sync] 백업: %s\n", backup_path))
  }
  if (!exists("qvest_atomic_write_parquet")) {
    ap_src <- if (!is.na(.BMS_SELF_DIR)) file.path(dirname(.BMS_SELF_DIR), "utils", "atomic_parquet.R") else
      file.path(.bms_root(root), "02_Infrastructure/utils/atomic_parquet.R")
    source(ap_src)
  }
  gc(verbose = FALSE)
  if (!identical(.fp(), fp0))
    stop("[bm_ret_sync] ★RAWDATA 가 계획 이후 다른 writer 에 의해 바뀌었다 — 쓰지 않는다(재실행 필요)")
  qvest_atomic_write_parquet(raw, raw_path, tag = "bm_ret_sync/rawdata")
  new_bm_expected <- raw$BM_Ret
  rm(raw); gc(verbose = FALSE)

  # ── 사후 검증: 다시 읽어 BM_Ret 기대값·행 수 대조 ─────────────────────────
  post <- as.data.table(read_parquet(raw_path, col_select = c("Date", "BM_Ret"), mmap = FALSE))
  ok_n  <- nrow(post) == n0
  ok_bm <- ok_n && identical(is.na(post$BM_Ret), is.na(new_bm_expected)) &&
    isTRUE(all(post$BM_Ret == new_bm_expected, na.rm = TRUE))
  rm(post); gc(verbose = FALSE)
  res$n_rows_written <- ap$n_rows
  res$written <- TRUE
  if (!(ok_n && ok_bm)) {
    cat("[bm_ret_sync] ★사후 검증 실패 — 기록된 파일의 BM_Ret/행 수가 기대와 다르다\n")
    res$rc <- 3L
  }
  cat(sprintf("[bm_ret_sync] 기록: %d일 · %s행 (채움 %d · 덮어쓰기 %d) · 사후검증 %s\n",
              nrow(w), format(ap$n_rows, big.mark = ","), sum(w$action == "fill"),
              sum(w$action == "overwrite"), if (ok_n && ok_bm) "PASS" else "FAIL"))
  .bms_write_log(plan, res, log_dir, raw_path)
  invisible(res)
}

.bms_write_log <- function(plan, res, log_dir, raw_path) {
  w <- plan[action %in% BM_RET_WRITE_ACTIONS]
  summ <- list(
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    raw_path = raw_path,
    rc = res$rc,
    written = res$written,
    n_rows_written = res$n_rows_written,
    counts = as.list(setNames(plan[, .N, by = action]$N, plan[, .N, by = action]$action)),
    changes = if (nrow(w)) lapply(seq_len(nrow(w)), function(i)
      list(date = format(w$Date[i]), action = w$action[i],
           old = if (is.finite(w$cur[i])) w$cur[i] else NULL, new = w$bench[i])) else list(),
    lag_dates = format(plan[action == "bench_lag"]$Date),
    violations = if (any(plan$action %in% BM_RET_VIOLATION_ACTIONS))
      lapply(which(plan$action %in% BM_RET_VIOLATION_ACTIONS), function(i)
        list(date = format(plan$Date[i]), action = plan$action[i], reason = plan$reason[i])) else list()
  )
  tryCatch({
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    last <- file.path(log_dir, "rawdata_bm_ret_sync_last.json")
    tmp <- paste0(last, ".tmp", Sys.getpid())
    writeLines(toJSON(summ, auto_unbox = TRUE, digits = NA, pretty = TRUE, null = "null"), tmp, useBytes = TRUE)
    file.rename(tmp, last)
    if (nrow(w))
      cat(toJSON(summ[c("at", "raw_path", "changes")], auto_unbox = TRUE, digits = NA), "\n",
          file = file.path(log_dir, "rawdata_bm_ret_sync_log.jsonl"), append = TRUE, sep = "")
  }, error = function(e) cat(sprintf("[bm_ret_sync] 로그 기록 실패(판정 불변): %s\n", conditionMessage(e))))
  invisible(summ)
}

#' 한 줄 판정(daily_refresh 판독용).
bm_ret_status_line <- function(res) {
  p <- res$plan
  sprintf("BM_RET_SYNC rc=%d filled=%d overwritten=%d lag=%d violations=%d lag_dates=%s viol=%s",
          res$rc, sum(p$action == "fill"), sum(p$action == "overwrite"), sum(p$action == "bench_lag"),
          sum(p$action %in% BM_RET_VIOLATION_ACTIONS),
          paste(format(p[action == "bench_lag"]$Date), collapse = ",") %|na|% "-",
          paste(sprintf("%s:%s", format(p[action %in% BM_RET_VIOLATION_ACTIONS]$Date),
                        p[action %in% BM_RET_VIOLATION_ACTIONS]$action), collapse = ",") %|na|% "-")
}
`%|na|%` <- function(a, b) if (length(a) == 0L || !nzchar(a)) b else a

# ── CLI ─────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  .args <- commandArgs(trailingOnly = TRUE)
  .apply <- "--apply" %in% .args
  # ★덮어쓰기는 명시 플래그 + 킬스위치 해제 두 조건이 모두 있어야 한다(2026-09-23 적대 검증 발견 3).
  #   구판은 킬스위치만 봤다 — 루프가 어떤 이유로든 꺼진 밤이면 무인 [3b] 가 과거 유한값을
  #   사람 확인 없이 덮었다('루프 정지 = 과거 정정 승인' 결합). 무인 경로([3b])는 채움만 한다.
  .allow_ow <- if ("--allow-overwrite" %in% .args) NULL else FALSE   # NULL = 킬스위치 판독
  .dates <- NULL
  .i <- which(.args == "--dates")
  if (length(.i) && length(.args) > .i[1]) .dates <- as.Date(strsplit(.args[.i[1] + 1L], ",")[[1]])
  .rc <- tryCatch({
    .res <- rawdata_sync_bm_ret(dates = .dates, dry_run = !.apply, allow_overwrite = .allow_ow)
    cat(bm_ret_status_line(.res), "\n")
    .res$rc
  }, error = function(e) {
    cat(sprintf("[bm_ret_sync] ★오류: %s\n", conditionMessage(e)))
    cat("BM_RET_SYNC rc=1 error\n")
    1L
  })
  quit(save = "no", status = .rc)
}
