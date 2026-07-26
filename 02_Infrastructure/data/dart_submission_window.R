#==============================================================================
# dart_submission_window.R — DART 보고서 제출창 지식 + 수집 후보집합 판정 (순수 함수)
#
# 정체: "지금 시점에 어느 bsns_year 를 요청해야 하는가"의 단일 판정부.
#       입력(coverage, today)만 보고 판정하는 순수 함수 — 파일 I/O·Sys.Date() 암묵
#       참조 없음(today 를 인자로 받는다). 따라서 위반 주입 테스트가 가능하다.
#       I/O 는 아래쪽 dart_coverage_by_year() / dart_due_*_years() 로 분리.
#
# 왜 있나 (2026-07-26, P2-01 수리):
#   구 코드는 후보집합을 **달력**으로 만들었다:
#     daily_refresh.sh:337        dart_run_pipeline(years = format(Sys.Date(), "%Y"))
#     dart_daily_incremental.R:33 current_year = format(Sys.Date(), "%Y")
#   FY2025 사업보고서는 2026-03 에 제출되는데, 2025년 내내는 존재하지 않았고
#   2026년에는 아예 요청되지 않았다 → dart_raw_financials FY2025 = 50 corps
#   (FY2024 = 714, 7.0%). 제출기한(2026-03-31) 경과 4개월, 자동 회복 경로 없음.
#   아이러니: 제출창 지식(.dart_season_bounds)은 이미 저장소에 있었으나
#   **후보집합 생성**이 아니라 재시도 cadence 계산에만 쓰였다.
#
# 계약 — 세 명제는 서로 다르다:
#   (a) 달력 연도      : "지금이 2026년이다"
#   (b) 제출창 개시    : "이 bsns_year 의 보고서가 접수되기 시작했다"  ← 요청 자격
#   (c) 커버리지 도달  : "그 연도가 실제로 차 있다"                    ← 중단 자격
#   (a)로 (b)(c)를 대리 판정하던 것이 P2-01. 존재(연도가 캐시에 있다)로 (c)를
#   대리 판정하는 것도 같은 함정이므로, 완결 판정은 **직전 완결연도 대비 커버리지
#   비율**로 한다(= B형 동형결함 회피).
#
# ★ reprt_code ↔ 분기 매핑 정정 (2026-07-26, 실측 확정)
#   구 .dart_season_bounds 는 11013 을 3분기, 11014 를 1분기로 잡고 있었다 — 반대다.
#   OpenDART 공식 코드: 11013 = 1분기보고서 / 11014 = 3분기보고서.
#   저장 데이터 실측(dart_raw_quarterly, bsns_year 2023·2024 corp 단위 접수월 최빈):
#     11013 → 2024-05 (595 corps) · thstrm_nm "제 N 기 1분기말"   = 1분기
#     11014 → 2024-11 (601 corps) · thstrm_nm "제 N 기 3분기말"   = 3분기
#     11012 → 2024-08 (591 corps) "반기말" / 11011 → 2025-03 (524 corps) 연간
#   ✅ (2026-07-26 R1, 도훈 승인) data_collector_dart_quarterly.R 의 REPRT_MAP·
#     Factor_Date 부여도 정정 완료 + fundamental_dart_quarterly 전량 재생성.
#     구 매핑 실측 피해: 11014 의 Factor_Date − 실접수일 중앙값 −183일,
#     look-ahead 99.8%(5,911/5,923 filing key). 소비처는 생산자 자신뿐이라 실현 피해 0.
#
# 상설 검사: 08_Tests/data/test_dart_candidate_years.R (제출창 후보집합)
#            08_Tests/data/test_dart_reprt_quarter_map.R (코드↔분기 매핑 — 이 파일과
#              REPRT_MAP 의 **교차 합치**를 매 실행 대조: 한쪽만 뒤집혀도 FAIL)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# reprt_code → (라벨, 실제 분기, 제출창) — 12월 결산 기준
#   11013 1분기 (3/31 결산, 마감 5/15)         : bsns_year 4/1  ~ 5/31
#   11012 반기  (6/30 결산, 마감 8/14)          : bsns_year 7/1  ~ 8/31
#   11014 3분기 (9/30 결산, 마감 11/14)         : bsns_year 10/1 ~ 11/30
#   11011 사업보고서 (12/31 결산, 마감 익년 3/31): bsns_year+1 1/1 ~ 4/15
# (비12월 결산사는 창 밖 접수 — grace/커버리지 판정이 흡수)
DART_REPRT_CODES <- c("11013", "11012", "11014", "11011")

DART_REPRT_LABEL <- c(
  "11013" = "1분기보고서",
  "11012" = "반기보고서",
  "11014" = "3분기보고서",
  "11011" = "사업보고서(연간)"
)

#' 제출창 경계. 벡터화 (bsns_year, reprt_code 동일 길이 또는 재사용 가능 길이).
#' @return list(start = Date vector, end = Date vector) — 미상 코드는 NA
.dart_season_bounds <- function(bsns_year, reprt_code) {
  bsns_year <- as.integer(bsns_year)
  reprt_code <- as.character(reprt_code)
  start <- as.Date(fcase(
    reprt_code == "11013", sprintf("%d-04-01", bsns_year),
    reprt_code == "11012", sprintf("%d-07-01", bsns_year),
    reprt_code == "11014", sprintf("%d-10-01", bsns_year),
    reprt_code == "11011", sprintf("%d-01-01", bsns_year + 1L),
    default = NA_character_
  ))
  end <- as.Date(fcase(
    reprt_code == "11013", sprintf("%d-05-31", bsns_year),
    reprt_code == "11012", sprintf("%d-08-31", bsns_year),
    reprt_code == "11014", sprintf("%d-11-30", bsns_year),
    reprt_code == "11011", sprintf("%d-04-15", bsns_year + 1L),
    default = NA_character_
  ))
  list(start = start, end = end)
}

#' 제출창이 열렸는가 (= 요청할 자격이 있는가). 미상 코드는 FALSE(fail-closed).
.dart_window_open <- function(bsns_year, reprt_code, today = Sys.Date()) {
  b <- .dart_season_bounds(bsns_year, reprt_code)
  !is.na(b$start) & b$start <= as.Date(today)
}

#' 제출창이 닫혔는가 (grace 포함 시 grace_days 경과까지 '수집 시즌'으로 본다).
.dart_window_closed <- function(bsns_year, reprt_code, today = Sys.Date(), grace_days = 0L) {
  b <- .dart_season_bounds(bsns_year, reprt_code)
  !is.na(b$end) & (b$end + as.integer(grace_days)) < as.Date(today)
}

#' coverage(named vector) 조회 — 이름은 bsns_year 문자열. 없으면 0.
.dart_cov_lookup <- function(coverage, years) {
  out <- rep(0, length(years))
  if (is.null(coverage) || length(coverage) == 0L) return(out)
  nm <- names(coverage)
  if (is.null(nm)) return(out)
  hit <- match(as.character(years), nm)
  out[!is.na(hit)] <- as.numeric(coverage)[hit[!is.na(hit)]]
  out[is.na(out)] <- 0
  out
}

#' 지금 요청해야 하는 bsns_year 후보집합.
#'
#' 판정 순서 (연도별):
#'   1. 제출창 미개시            → 제외 ("window_not_open")   ← 미래연도 낭비 차단
#'   2. 수집 시즌(창 열림~마감+grace) → 무조건 후보 ("due_in_season")
#'   3. 시즌 종료 후             → 커버리지 도달 여부로 판정
#'        cov == 0                        → "due_missing"
#'        cov <  coverage_ratio * ref(y)  → "due_partial"
#'        그 외                            → "complete"
#'   reference ref(y) = **y 직전의 창-마감 연도** 중 cov>0 인 가장 가까운 해.
#'   전역 max 를 쓰면 유니버스 확장(2026 수집 유니버스 3,433 vs 2023 당시 ~600)이
#'   과거 완결연도를 전부 '미달'로 오판정한다 — 실측으로 적발(11013 due={2023..2026}).
#'   ref 를 구할 수 없으면 판정 불가 → "due_no_reference"(수집 쪽으로 후퇴 —
#'   과수집 비용은 콜, 과소수집 비용은 데이터 결손이므로 비대칭).
#'
#' @param coverage       named numeric/integer — names = bsns_year, value = corps 수
#' @param reprt_code     단일 코드
#' @param today          판정 기준일 (테스트는 명시 주입)
#' @param lookback_years 창이 열린 연도 중 최근 N개만 후보로 (과거 전수 재요청 방지)
#' @param coverage_ratio 완결 문턱 (ref 대비 비율)
#' @param grace_days     제출창 마감 후에도 시즌으로 취급할 일수 (지연·정정 접수)
#' @param min_year       하한 (NULL = 무제한)
#' @return list(due = integer vector, detail = data.table, reference = numeric, today = Date)
.dart_due_bsns_years <- function(coverage = NULL,
                                 reprt_code = "11011",
                                 today = Sys.Date(),
                                 lookback_years = 3L,
                                 coverage_ratio = 0.85,
                                 grace_days = 60L,
                                 min_year = NULL) {
  today <- as.Date(today)
  if (length(today) != 1L || is.na(today)) stop("[dart_window] today 판정 불가")
  reprt_code <- as.character(reprt_code)[1L]
  if (!reprt_code %in% DART_REPRT_CODES) {
    stop(sprintf("[dart_window] 미상 reprt_code: %s (허용: %s)",
                 reprt_code, paste(DART_REPRT_CODES, collapse = ",")))
  }
  lookback_years <- max(1L, as.integer(lookback_years))

  ycal <- as.integer(format(today, "%Y"))
  # 참조(reference) 산정을 위해 후보보다 넉넉히 스캔한다
  scan <- seq.int(ycal - lookback_years - 5L, ycal + 1L)
  rc   <- rep(reprt_code, length(scan))
  bnd  <- .dart_season_bounds(scan, rc)
  open   <- .dart_window_open(scan, rc, today)
  closed <- .dart_window_closed(scan, rc, today, grace_days = 0L)
  in_season <- open & !.dart_window_closed(scan, rc, today, grace_days = grace_days)
  cov  <- .dart_cov_lookup(coverage, scan)

  # 연도별 reference = 직전(older) 창-마감 연도 중 cov>0 인 가장 가까운 해
  ref <- rep(NA_real_, length(scan))
  for (i in seq_along(scan)) {
    prior <- which(scan < scan[i] & closed & cov > 0)
    if (length(prior) > 0L) ref[i] <- cov[max(prior)]
  }

  verdict <- rep(NA_character_, length(scan))
  verdict[!open] <- "window_not_open"
  sel <- open & in_season
  verdict[sel] <- "due_in_season"
  sel <- which(open & !in_season)
  if (length(sel) > 0L) {
    r <- cov[sel] / ref[sel]
    verdict[sel] <- fifelse(is.na(ref[sel]), "due_no_reference",
                     fifelse(cov[sel] <= 0, "due_missing",
                      fifelse(r < coverage_ratio, "due_partial", "complete")))
  }

  detail <- data.table(
    bsns_year    = scan,
    reprt_code   = reprt_code,
    label        = unname(DART_REPRT_LABEL[reprt_code]),
    window_start = bnd$start,
    window_end   = bnd$end,
    window_open  = open,
    in_season    = in_season,
    coverage     = cov,
    reference    = ref,
    ratio        = cov / ref,
    verdict      = verdict
  )

  # 후보 = 창이 열린 연도 중 최근 lookback_years 개, 그 안에서 due_*
  open_years <- scan[open]
  if (length(open_years) == 0L) {
    return(list(due = integer(0), detail = detail, reference = ref, today = today))
  }
  win_lo <- max(open_years) - lookback_years + 1L
  if (!is.null(min_year)) win_lo <- max(win_lo, as.integer(min_year))
  detail[, in_lookback := window_open & bsns_year >= win_lo]
  due <- detail[in_lookback == TRUE & grepl("^due_", verdict), sort(bsns_year)]

  list(due = as.integer(due), detail = detail, today = today)
}

#' 후보집합 판정 요약 (로그용)
.dart_due_report <- function(res) {
  d <- res$detail[window_open == TRUE][order(-bsns_year)][seq_len(min(5L, .N))]
  paste0(
    sprintf("[dart_window] %s | today=%s | due={%s}\n",
            unname(DART_REPRT_LABEL[d$reprt_code[1]]), format(res$today),
            paste(res$due, collapse = ",")),
    paste(sprintf("    FY%d 창 %s~%s cov=%s ref=%s ratio=%s → %s",
                  d$bsns_year, format(d$window_start), format(d$window_end),
                  format(d$coverage),
                  ifelse(is.na(d$reference), "NA", format(d$reference)),
                  ifelse(is.na(d$ratio), "NA", sprintf("%.2f", d$ratio)),
                  d$verdict), collapse = "\n")
  )
}

#' (corp_code, bsns_year, reprt_code) task 에서 제출창 미개시분 제거.
#' reprt_code 열이 없으면 default_reprt 로 간주한다.
.dart_filter_tasks_by_window <- function(tasks, today = Sys.Date(), default_reprt = "11011",
                                         verbose = TRUE) {
  if (is.null(tasks) || nrow(tasks) == 0L) return(tasks)
  rc <- if ("reprt_code" %in% names(tasks)) tasks$reprt_code else rep(default_reprt, nrow(tasks))
  keep <- .dart_window_open(tasks$bsns_year, rc, today)
  n_drop <- sum(!keep)
  if (verbose && n_drop > 0L) {
    dropped <- unique(data.table(bsns_year = tasks$bsns_year, reprt_code = rc)[!keep])
    cat(sprintf("[dart_window] 제출창 미개시 task %s건 제외 (%s)\n",
                format(n_drop, big.mark = ","),
                paste(sprintf("FY%d/%s", dropped$bsns_year, dropped$reprt_code), collapse = ", ")))
  }
  tasks[keep]
}


#==============================================================================
# I/O 계층 — 캐시에서 커버리지 실측 → 후보집합
#==============================================================================

.dart_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure", "config.R"))]
  if (length(hit) == 0L) return(cands[1])
  hit[1]
}

.dart_cache_dir <- function() {
  cd <- get0("CACHE_DIR", ifnotfound = NULL)
  if (is.null(cd)) cd <- file.path(.dart_root(), ".cache")
  file.path(cd, "dart")
}

#' 캐시 parquet 에서 bsns_year 별 고유 corp 수 실측.
#' @return named numeric (names = bsns_year) 또는 NULL(파일 부재)
dart_coverage_by_year <- function(path, reprt_code = NULL, id_col = "corp_code") {
  if (!file.exists(path)) return(NULL)
  # ★ data.table i-표현식 안에서 인자명과 열명이 같으면 **열이 이긴다**
  #   (reprt_code == reprt_code → 항상 TRUE = 필터 무력화, 무에러 침묵).
  #   실측으로 적발(4코드 커버리지가 전부 동일값) → 인자를 별도 이름으로 고정한다.
  .rc_want <- if (is.null(reprt_code)) NULL else as.character(reprt_code)[1L]
  cols <- c("bsns_year", id_col)
  if (!is.null(.rc_want)) cols <- c(cols, "reprt_code")
  # col_select 는 문자벡터 허용 (data.table::fread 의 select 와 동일 규약).
  # tidyselect all_of() 를 쓰면 arrow 버전에 따라 미해결 심볼이 되므로 쓰지 않는다.
  dt <- tryCatch(
    as.data.table(arrow::read_parquet(path, col_select = unique(cols), mmap = FALSE)),
    error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0L) return(NULL)
  if (!is.null(.rc_want) && "reprt_code" %in% names(dt)) {
    dt <- dt[reprt_code == .rc_want]
  }
  if (nrow(dt) == 0L) return(NULL)
  agg <- dt[, .(n = uniqueN(get(id_col))), by = bsns_year]
  setNames(as.numeric(agg$n), as.character(agg$bsns_year))
}

#' 연간(11011, dart_raw_financials) 후보 연도
dart_due_annual_years <- function(today = Sys.Date(), path = NULL, verbose = TRUE, ...) {
  if (is.null(path)) path <- file.path(.dart_cache_dir(), "dart_raw_financials.parquet")
  cov <- dart_coverage_by_year(path)
  res <- .dart_due_bsns_years(cov, reprt_code = "11011", today = today, ...)
  if (verbose) cat(.dart_due_report(res), "\n")
  res$due
}

#' 분기(dart_raw_quarterly) 후보 **(bsns_year, reprt_code) 쌍**.
#' ★ 연도 합집합만 쓰면 안 된다: CJ(years x reprt_codes) 가 due 아닌 조합까지
#'   되살린다(예: FY2025 x 11013 은 이미 complete 인데 연도 합집합에 2025 가
#'   들어가면 3,300 task 부활). 쌍 단위로 걸러야 한다.
dart_due_quarterly_pairs <- function(reprt_codes = DART_REPRT_CODES,
                                     today = Sys.Date(), path = NULL, verbose = TRUE, ...) {
  if (is.null(path)) path <- file.path(.dart_cache_dir(), "dart_raw_quarterly.parquet")
  out <- list()
  for (rc in reprt_codes) {
    cov <- dart_coverage_by_year(path, reprt_code = rc)
    res <- .dart_due_bsns_years(cov, reprt_code = rc, today = today, ...)
    if (verbose) cat(.dart_due_report(res), "\n")
    if (length(res$due) > 0L) {
      out[[length(out) + 1L]] <- data.table(bsns_year = as.integer(res$due), reprt_code = rc)
    }
  }
  if (length(out) == 0L) return(data.table(bsns_year = integer(0), reprt_code = character(0)))
  unique(rbindlist(out))
}

#' 분기 후보 연도 합집합 (task 생성용 CJ 축 — 쌍 필터와 병용 필수)
dart_due_quarterly_years <- function(...) {
  p <- dart_due_quarterly_pairs(...)
  sort(unique(as.integer(p$bsns_year)))
}


#==============================================================================
# API 사용량 로그 (일 10,000콜 한도 — 가드레일 "사용량 로그" 요구)
#==============================================================================

DART_USAGE_LOG <- function() file.path(.dart_cache_dir(), "dart_api_usage.jsonl")

#' 1 실행의 콜 사용량 append (fail-soft — 로깅 실패가 수집을 죽이지 않는다)
.dart_log_api_usage <- function(caller, calls, ok = NA_integer_, empty = NA_integer_,
                                fail = NA_integer_, halted = "", note = "") {
  rec <- sprintf(
    '{"ts":"%s","date":"%s","caller":"%s","calls":%d,"ok":%s,"empty":%s,"fail":%s,"halted":"%s","note":"%s"}',
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), format(Sys.Date()), caller,
    as.integer(calls),
    ifelse(is.na(ok), "null", as.character(as.integer(ok))),
    ifelse(is.na(empty), "null", as.character(as.integer(empty))),
    ifelse(is.na(fail), "null", as.character(as.integer(fail))),
    halted, gsub('"', "'", note))
  tryCatch({
    p <- DART_USAGE_LOG()
    if (!dir.exists(dirname(p))) dir.create(dirname(p), recursive = TRUE)
    cat(rec, "\n", file = p, sep = "", append = TRUE)
  }, error = function(e) invisible(NULL))
  invisible(rec)
}

#' 오늘 이미 쓴 콜 수 (로그 기준 — 하한 추정치이지 권위값 아님)
dart_calls_used_today <- function(day = Sys.Date()) {
  p <- DART_USAGE_LOG()
  if (!file.exists(p)) return(0L)
  ln <- tryCatch(readLines(p, warn = FALSE), error = function(e) character(0))
  ln <- ln[grepl(sprintf('"date":"%s"', format(as.Date(day))), ln, fixed = TRUE)]
  if (length(ln) == 0L) return(0L)
  v <- suppressWarnings(as.integer(sub('.*"calls":([0-9]+).*', "\\1", ln)))
  sum(v, na.rm = TRUE)
}

cat("[dart_submission_window] Loaded.\n")
