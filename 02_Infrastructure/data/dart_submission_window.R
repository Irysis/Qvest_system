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
#   대리 판정하는 것도 같은 함정이므로, 완결 판정은 커버리지 **비율**로 한다(= B형
#   동형결함 회피).
#
# ★ 완결 분모 정정 (2026-11-08 — 연간 11011, 분기 경로는 종전 유지):
#   종전 분모 = '직전 마감 연도 커버리지'(ref_basis = "prior_year"). 수집 유니버스가
#   K200∪KQ150(~600사)이던 시절엔 맞았으나, 측정 축이 전 종목(epoch all_hyg_*)으로
#   바뀐 뒤엔 **작은 유니버스가 자기 자신을 기준으로 완결을 선언**했다 — 실측
#   2026-11-08: FY2021~2024 비율 0.99~1.07 'complete' 인데 그 해 12월 상장 대비로는
#   28~30%(FY2024 693/2,509), FY2025 = 1,276/2,561. 연 1,300~1,800사가 재무 원천 없이
#   남았다(FY2015~2025 합 17,057 회사·연도).
#   새 분모 = **그 해 12월 상장 기업(corpcode 매칭) 수**(ref_basis = "listed").
#   분자 = 그 상장 집합 안에서 '해결된' 기업 = 자료 수신 ∪ 마감(+grace) 뒤 확인된
#   '자료 없음'(진행 장부 — 아래 §진행 장부). 마감 전 '자료 없음'은 아직 안 낸 것일
#   수 있으므로 해결로 세지 않는다.
#   종전 주석의 우려(과거 연도 전수 재요청 폭주)는 분모를 바꾸지 않는 것으로 막지
#   않고 ① 진행 장부(해결된 키는 다시 묻지 않음 · 실패·자료 없음은 백오프)
#   ② 콜 예산(max_calls · 일일 상한) ③ lookback(평상 3년 — FY2015~ 는 명시 보충
#   플래그로만 연다, dart_annual_backfill.R)으로 다스린다.
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
# 상설 검사: 08_Tests/data/test_dart_candidate_years.R (제출창 후보집합 · G 상장 분모 + 돌연변이 통제 ·
#              H 진행 장부/해결 집계 · I 배선 — 2026-11-08)
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

#' 완결 문턱 기본값 — 분모 종류별.
#'   listed     : 분자가 '해결'(자료 ∪ 마감 뒤 자료 없음 확인)이라 한 바퀴 돌면 1.0 에
#'                닿는다. 남는 것은 실패·미시도뿐 → 0.99(2,561사 기준 미해결 ≤ 25사).
#'                문턱을 높여도 비용은 '미해결 수'에 비례한다(해결된 키는 다시 안 묻는다).
#'   prior_year : 종전 값(분기 경로 — 변경 없음).
DART_COVERAGE_RATIO_DEFAULT <- c(listed = 0.99, prior_year = 0.85)

#' 지금 요청해야 하는 bsns_year 후보집합.
#'
#' 판정 순서 (연도별):
#'   1. 제출창 미개시            → 제외 ("window_not_open")   ← 미래연도 낭비 차단
#'   2. 수집 시즌(창 열림~마감+grace) → 무조건 후보 ("due_in_season")
#'   3. 시즌 종료 후             → 커버리지 도달 여부로 판정
#'        cov == 0                        → "due_missing"
#'        cov <  coverage_ratio * ref(y)  → "due_partial"
#'        그 외                            → "complete"
#'   reference ref(y) 는 ref_basis 로 정한다:
#'   ★ "listed" (연간 11011 기본 · 2026-11-08): ref(y) = listed[y] = **그 해 12월 상장
#'     기업(corpcode 매칭) 수**. coverage 는 그 상장 집합 안의 '해결' 기업 수여야 한다
#'     (dart_annual_resolution 이 만든다 — 집합 밖 기업을 세면 비율이 부풀어 결손이
#'     가려진다). listed[y] 를 모르면 ref = NA.
#'   "prior_year" (분기 경로 — 종전 규칙 유지): ref(y) = **y 직전의 창-마감 연도** 중
#'     cov>0 인 가장 가까운 해. 전역 max 를 쓰면 유니버스 확장이 과거 완결연도를 전부
#'     '미달'로 오판정한다(11013 실측 적발). ★이 규칙은 작은 유니버스가 자기 자신을
#'     기준으로 완결을 선언하는 결함이 있다 — 연간은 2026-11-08 listed 로 옮겼다.
#'   ref 를 구할 수 없으면 판정 불가 → "due_no_reference"(수집 쪽으로 후퇴 —
#'   과수집 비용은 콜, 과소수집 비용은 데이터 결손이므로 비대칭).
#'
#' @param coverage       named numeric/integer — names = bsns_year, value = corps 수
#'                       (listed 기준이면 '상장 집합 안 해결 수')
#' @param reprt_code     단일 코드
#' @param today          판정 기준일 (테스트는 명시 주입)
#' @param lookback_years 창이 열린 연도 중 최근 N개만 후보로 (평상 3 — 과거 연도는
#'                       보충 플래그로만 연다)
#' @param coverage_ratio 완결 문턱 (ref 대비 비율 · NULL = DART_COVERAGE_RATIO_DEFAULT[ref_basis])
#' @param grace_days     제출창 마감 후에도 시즌으로 취급할 일수 (지연·정정 접수)
#' @param min_year       하한 (NULL = 무제한)
#' @param listed         named numeric — names = bsns_year, value = 그 해 12월 상장 corp 수
#' @param ref_basis      "listed" | "prior_year"
#' @return list(due = integer vector, detail = data.table, today = Date, ref_basis = chr)
.dart_due_bsns_years <- function(coverage = NULL,
                                 reprt_code = "11011",
                                 today = Sys.Date(),
                                 lookback_years = 3L,
                                 coverage_ratio = NULL,
                                 grace_days = 60L,
                                 min_year = NULL,
                                 listed = NULL,
                                 ref_basis = c("listed", "prior_year")) {
  ref_basis <- match.arg(ref_basis)
  if (is.null(coverage_ratio)) coverage_ratio <- unname(DART_COVERAGE_RATIO_DEFAULT[[ref_basis]])
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

  ref <- rep(NA_real_, length(scan))
  if (identical(ref_basis, "listed")) {
    # 연도별 reference = 그 해 상장 기업 수 (모르면 NA → due_no_reference)
    lst <- .dart_cov_lookup(listed, scan)
    ref[lst > 0] <- lst[lst > 0]
  } else {
    # 연도별 reference = 직전(older) 창-마감 연도 중 cov>0 인 가장 가까운 해
    for (i in seq_along(scan)) {
      prior <- which(scan < scan[i] & closed & cov > 0)
      if (length(prior) > 0L) ref[i] <- cov[max(prior)]
    }
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
    ref_basis    = ref_basis,
    verdict      = verdict
  )

  # 후보 = 창이 열린 연도 중 최근 lookback_years 개, 그 안에서 due_*
  open_years <- scan[open]
  if (length(open_years) == 0L) {
    return(list(due = integer(0), detail = detail, today = today, ref_basis = ref_basis))
  }
  win_lo <- max(open_years) - lookback_years + 1L
  if (!is.null(min_year)) win_lo <- max(win_lo, as.integer(min_year))
  detail[, in_lookback := window_open & bsns_year >= win_lo]
  due <- detail[in_lookback == TRUE & grepl("^due_", verdict), sort(bsns_year)]

  list(due = as.integer(due), detail = detail, today = today, ref_basis = ref_basis)
}

#' 후보집합 판정 요약 (로그용) — n = 보여줄 연도 수(창 열린 연도 최근순)
.dart_due_report <- function(res, n = 5L) {
  d <- res$detail[window_open == TRUE][order(-bsns_year)][seq_len(min(as.integer(n), .N))]
  ref_lab <- if (identical(res$ref_basis, "listed")) "listed" else "ref"
  cov_lab <- if (identical(res$ref_basis, "listed")) "resolved" else "cov"
  paste0(
    sprintf("[dart_window] %s | today=%s | basis=%s | due={%s}\n",
            unname(DART_REPRT_LABEL[d$reprt_code[1]]), format(res$today),
            if (is.null(res$ref_basis)) "prior_year" else res$ref_basis,
            paste(res$due, collapse = ",")),
    paste(sprintf("    FY%d 창 %s~%s %s=%s %s=%s ratio=%s → %s",
                  d$bsns_year, format(d$window_start), format(d$window_end),
                  cov_lab, format(d$coverage), ref_lab,
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

#==============================================================================
# 연간(11011) 완결 분모 · 진행 장부 · 해결 집계 (2026-11-08)
#==============================================================================

#' 그 해 상장 기업(corpcode 매칭) 집합.
#'   분모(in_denominator = TRUE) = RAWDATA 에 **그 해 12월** 행이 있는 종목.
#'   추가 요청 대상(in_denominator = FALSE) = 12월엔 없고 익년 1/1~4/15(사업보고서
#'   제출창)에 처음 보이는 종목 — 상장 뒤 처음 오는 제출기한부터 사업보고서를 내므로
#'   1분기 신규 상장사도 그 해 보고서가 있을 수 있다. 완결 분모에는 넣지 않는다.
#'   mcap = 그 해 12월 마지막 거래일 Size(시가총액 가중 커버리지 · 요청 순서용).
#' @param raw  (검사용) Date · Ticker · Size 를 가진 data.table — 주면 파일을 읽지 않는다
#' @param corpmap (검사용) Ticker · corp_code 를 가진 data.table
#' @return data.table(bsns_year, Ticker, corp_code, corp_name, mcap, in_denominator)
#'         attr "unmatched" = data.table(bsns_year, n) — corpcode 미매칭 상장 종목 수
dart_listed_corps_by_year <- function(rawdata_path = NULL, corpmap_path = NULL,
                                      years = NULL, raw = NULL, corpmap = NULL) {
  if (is.null(raw)) {
    if (is.null(rawdata_path)) {
      rawdata_path <- get0("RAWDATA_CACHE", ifnotfound = file.path(.dart_root(), ".cache", "RAWDATA.parquet"))
    }
    if (!file.exists(rawdata_path)) stop("[dart_listed] RAWDATA 없음: ", rawdata_path)
    raw <- as.data.table(arrow::read_parquet(rawdata_path, col_select = c("Date", "Ticker", "Size"),
                                             mmap = FALSE))
  } else raw <- as.data.table(raw)[, .(Date, Ticker, Size)]
  if (is.null(corpmap)) {
    if (is.null(corpmap_path)) corpmap_path <- file.path(.dart_cache_dir(), "corpcode_map.parquet")
    if (!file.exists(corpmap_path)) stop("[dart_listed] corpcode_map 없음: ", corpmap_path)
    corpmap <- as.data.table(arrow::read_parquet(corpmap_path, mmap = FALSE))
  } else corpmap <- as.data.table(corpmap)
  if (!"corp_name" %in% names(corpmap)) corpmap[, corp_name := NA_character_]

  raw[, Date := as.Date(Date)]
  raw[, `:=`(yr_ = data.table::year(Date), mo_ = data.table::month(Date),
             dd_ = data.table::mday(Date))]
  dec <- raw[mo_ == 12L]
  last_dec <- dec[, .(d_last = max(Date)), by = yr_]
  mc <- dec[last_dec, on = c("yr_", Date = "d_last"), nomatch = 0L][
    , .(bsns_year = yr_, Ticker, mcap = as.numeric(Size))]
  mc <- mc[, .(mcap = mcap[1L]), by = .(bsns_year, Ticker)]
  den <- unique(dec[, .(bsns_year = yr_, Ticker)])
  den <- merge(den, mc, by = c("bsns_year", "Ticker"), all.x = TRUE)
  den[, in_denominator := TRUE]
  # 익년 1/1~4/15 에 처음 보이는 종목 (사업보고서 제출창 안 신규 상장)
  q1 <- unique(raw[mo_ < 4L | (mo_ == 4L & dd_ <= 15L), .(bsns_year = yr_ - 1L, Ticker)])
  q1 <- q1[!den, on = c("bsns_year", "Ticker")]
  q1[, `:=`(mcap = NA_real_, in_denominator = FALSE)]
  L <- rbindlist(list(den, q1), use.names = TRUE)
  if (!is.null(years)) L <- L[bsns_year %in% as.integer(years)]

  cm <- unique(corpmap[, .(Ticker, corp_code, corp_name)], by = "Ticker")
  M <- merge(L, cm, by = "Ticker", all.x = TRUE)
  unmatched <- M[is.na(corp_code) & in_denominator == TRUE, .(n = .N), keyby = bsns_year]
  M <- M[!is.na(corp_code)]
  setcolorder(M, c("bsns_year", "Ticker", "corp_code", "corp_name", "mcap", "in_denominator"))
  setorder(M, bsns_year, -mcap, Ticker, na.last = TRUE)
  setattr(M, "unmatched", unmatched)
  M
}

#' 연간 원시 캐시의 자료 수신 키 (corp_code, bsns_year)
dart_annual_keys <- function(path = NULL) {
  if (is.null(path)) path <- file.path(.dart_cache_dir(), "dart_raw_financials.parquet")
  if (!file.exists(path)) return(data.table(corp_code = character(0), bsns_year = integer(0)))
  dt <- tryCatch(as.data.table(arrow::read_parquet(path, col_select = c("corp_code", "bsns_year"),
                                                    mmap = FALSE)),
                 error = function(e) NULL)
  if (is.null(dt)) stop("[dart_window] 연간 원시 캐시 판독 실패: ", path)
  unique(dt[, .(corp_code = as.character(corp_code), bsns_year = as.integer(bsns_year))])
}

#------------------------------------------------------------------------------
# 진행 장부 (연간 11011) — 자료를 못 받은 시도만 적는다(자료 수신 = 원시 캐시가 장부).
#   status "empty" : CFS·OFS 모두 status 013/빈 목록 (자료 없음) · 또는 응답이 요청 연도가 아닌 해의
#                    보고서(last_code year_mismatch_<응답 연도> · 2026-11-09 — data_collector_dart.R)
#   status "fail"  : HTTP·파싱·기타 status (일시 실패 — 재시도 대상)
#   '자료 없음'이 **마감(창 끝) + grace 뒤에 관측**됐으면 확인된 자료 없음(해결)으로 센다.
#   마감 전 관측분은 아직 안 낸 것일 수 있다 → 미해결 · 마감+grace 가 지나면 한 번 더 묻는다.
#   재시도 간격(백오프):
#     fail                : 1일 (시도 5회 이상이면 30일)
#     empty · 미확인(시즌) : 7일 · 단 확인 시점(마감+grace)이 지나면 즉시 1회
#     empty · 확인됨       : 180일 (아주 늦은 지각 제출만 건진다 — 해결로 세므로 완결 판정엔 무영향)
#------------------------------------------------------------------------------
DART_ANNUAL_LEDGER_RETRY <- list(fail_days = 1L, fail_slow_after = 5L, fail_slow_days = 30L,
                                 empty_season_days = 7L, empty_confirmed_days = 180L)

DART_ANNUAL_LEDGER <- function() file.path(.dart_cache_dir(), "dart_annual_ledger.parquet")

.dart_annual_ledger_empty <- function() {
  data.table(corp_code = character(0), bsns_year = integer(0), reprt_code = character(0),
             Ticker = character(0), status = character(0), last_code = character(0),
             first_attempt_date = as.Date(character(0)), last_attempt_date = as.Date(character(0)),
             n_attempts = integer(0))
}

dart_annual_load_ledger <- function(path = DART_ANNUAL_LEDGER()) {
  if (!file.exists(path)) return(.dart_annual_ledger_empty())
  # mmap = FALSE: 같은 실행 안에서 같은 경로에 다시 쓴다(Windows error 1224 회피)
  lg <- tryCatch(as.data.table(arrow::read_parquet(path, mmap = FALSE)), error = function(e) NULL)
  if (is.null(lg)) stop("[dart_ledger] 진행 장부 판독 실패 — 덮어쓰지 않는다: ", path)
  if (nrow(lg) == 0L) return(.dart_annual_ledger_empty())
  lg[, `:=`(bsns_year = as.integer(bsns_year), reprt_code = as.character(reprt_code),
            first_attempt_date = as.Date(first_attempt_date),
            last_attempt_date = as.Date(last_attempt_date), n_attempts = as.integer(n_attempts))]
  lg
}

#' 장부 병합: 기존 + 이번 시도(같은 키 = 최신 상태 · 횟수 합산), 자료를 받은 키(ok_keys)는 제거
.dart_annual_ledger_merge <- function(ledger, attempts, ok_keys = NULL) {
  if (is.null(ledger)) ledger <- .dart_annual_ledger_empty()
  if (!is.null(attempts) && nrow(attempts) > 0L) {
    a <- copy(as.data.table(attempts))
    a[, `:=`(bsns_year = as.integer(bsns_year), first_attempt_date = as.Date(last_attempt_date),
             last_attempt_date = as.Date(last_attempt_date), n_attempts = as.integer(n_attempts))]
    m <- rbindlist(list(ledger, a), use.names = TRUE, fill = TRUE)
    setorder(m, corp_code, bsns_year, reprt_code, last_attempt_date)
    ledger <- m[, .(Ticker = Ticker[.N], status = status[.N], last_code = last_code[.N],
                    first_attempt_date = min(first_attempt_date),
                    last_attempt_date = max(last_attempt_date),
                    n_attempts = sum(n_attempts)),
                by = .(corp_code, bsns_year, reprt_code)]
  }
  if (!is.null(ok_keys) && nrow(ok_keys) > 0L && nrow(ledger) > 0L) {
    ok <- unique(as.data.table(ok_keys)[, .(corp_code, bsns_year = as.integer(bsns_year))])
    ledger <- ledger[!ok, on = c("corp_code", "bsns_year")]
  }
  ledger[]
}

dart_annual_save_ledger <- function(ledger, path = DART_ANNUAL_LEDGER()) {
  if (is.null(ledger)) return(invisible(NULL))
  if (!dir.exists(dirname(path))) dir.create(dirname(path), recursive = TRUE)
  tmp <- paste0(path, ".tmp")
  arrow::write_parquet(ledger, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("[dart_ledger] 장부 저장 실패: ", path)
  invisible(ledger)
}

#' 장부 판정(순수): 확인된 자료 없음 여부 + 오늘 재시도 차례 여부
#' @return ledger + confirm_at(Date) · confirmed(lgl) · retry_due(lgl)
.dart_annual_ledger_eval <- function(ledger, today = Sys.Date(), grace_days = 60L,
                                     retry = DART_ANNUAL_LEDGER_RETRY) {
  today <- as.Date(today)
  if (is.null(ledger) || nrow(ledger) == 0L) {
    out <- .dart_annual_ledger_empty()
    out[, `:=`(confirm_at = as.Date(character(0)), confirmed = logical(0), retry_due = logical(0))]
    return(out)
  }
  ev <- copy(as.data.table(ledger))
  rc <- if ("reprt_code" %in% names(ev)) ev$reprt_code else rep("11011", nrow(ev))
  b <- .dart_season_bounds(ev$bsns_year, rc)
  ev[, confirm_at := b$end + as.integer(grace_days)]
  ev[, confirmed := status == "empty" & !is.na(confirm_at) & last_attempt_date > confirm_at]
  age <- as.integer(today - ev$last_attempt_date)
  fail_iv <- ifelse(ev$n_attempts >= retry$fail_slow_after, retry$fail_slow_days, retry$fail_days)
  ev[, retry_due := fcase(
    status == "fail", age >= fail_iv,
    status == "empty" & confirmed, age >= retry$empty_confirmed_days,
    status == "empty" & !confirmed, (today > confirm_at) | (age >= retry$empty_season_days),
    default = TRUE)]
  ev[is.na(retry_due), retry_due := TRUE]
  ev[]
}

#' 연도별 해결 집계 — 분모 = 그 해 12월 상장(corpcode 매칭) · 분자 = 그 집합 안의 해결.
#'   ok              : 원시 캐시에 자료 있음
#'   empty_confirmed : 자료 없음 · 마감+grace 뒤 관측(해결)
#'   empty_season    : 자료 없음 · 마감+grace 전 관측(미해결 — 아직 안 냈을 수 있음)
#'   fail            : 일시 실패(미해결)
#'   untried         : 시도 기록 없음(미해결)
#' @return data.table(bsns_year, listed, ok, empty_confirmed, empty_season, fail, untried,
#'                    resolved, unresolved, ratio, mcap_ok_share)
dart_annual_resolution <- function(keys, ledger, listed_tbl, today = Sys.Date(), grace_days = 60L) {
  if (is.null(listed_tbl) || nrow(listed_tbl) == 0L) return(NULL)
  den <- unique(as.data.table(listed_tbl)[in_denominator == TRUE,
                .(corp_code, bsns_year = as.integer(bsns_year), mcap)], by = c("corp_code", "bsns_year"))
  den[, `:=`(ok = FALSE, st = "untried")]
  if (!is.null(keys) && nrow(keys) > 0L) {
    den[unique(as.data.table(keys)[, .(corp_code, bsns_year = as.integer(bsns_year))]),
        ok := TRUE, on = c("corp_code", "bsns_year")]
  }
  ev <- .dart_annual_ledger_eval(ledger, today = today, grace_days = grace_days)
  if (nrow(ev) > 0L) {
    ev[, st := fifelse(status == "fail", "fail",
                fifelse(confirmed, "empty_confirmed", "empty_season"))]
    den[ev, st := i.st, on = c("corp_code", "bsns_year")]
  }
  den[ok == TRUE, st := "ok"]
  out <- den[, .(listed = .N, ok = sum(st == "ok"), empty_confirmed = sum(st == "empty_confirmed"),
                 empty_season = sum(st == "empty_season"), fail = sum(st == "fail"),
                 untried = sum(st == "untried"),
                 mcap_ok_share = if (any(!is.na(mcap))) sum(mcap[st == "ok"], na.rm = TRUE) /
                   sum(mcap, na.rm = TRUE) else NA_real_),
             keyby = bsns_year]
  out[, `:=`(resolved = ok + empty_confirmed, unresolved = listed - ok - empty_confirmed)]
  out[, ratio := resolved / listed]
  setcolorder(out, c("bsns_year", "listed", "ok", "empty_confirmed", "empty_season", "fail",
                     "untried", "resolved", "unresolved", "ratio", "mcap_ok_share"))
  out[]
}

#' 연간 요청 대상 = 후보 중 (제출창 열림) − (자료 보유) − (장부 백오프 중).
#' dart_fetch_all 과 보충 계획(dart_annual_backfill.R)이 같은 함수를 쓴다(두 셈이 갈라지지 않게).
#' @param candidates data.table(corp_code, bsns_year, ...) — 보통 dart_listed_corps_by_year 의 행
#' @param keys       data.table(corp_code, bsns_year) — 자료 보유 키(dart_annual_keys)
#' @return candidates 의 부분집합 · attr "counts" = c(candidates, window_open, after_data, after_backoff)
dart_annual_pending_tasks <- function(candidates, keys = NULL, ledger = NULL, today = Sys.Date(),
                                      grace_days = 60L, reprt_code = "11011") {
  tk <- unique(as.data.table(candidates), by = c("corp_code", "bsns_year"))
  tk[, bsns_year := as.integer(bsns_year)]
  n_c <- nrow(tk)
  tk <- .dart_filter_tasks_by_window(tk, today = today, default_reprt = reprt_code, verbose = FALSE)
  n_w <- nrow(tk)
  if (!is.null(keys) && nrow(keys) > 0L) {
    kk <- unique(as.data.table(keys)[, .(corp_code, bsns_year = as.integer(bsns_year))])
    tk <- tk[!kk, on = c("corp_code", "bsns_year")]
  }
  n_d <- nrow(tk)
  ev <- .dart_annual_ledger_eval(ledger, today = today, grace_days = grace_days)
  if (nrow(ev) > 0L) {
    skip <- ev[retry_due == FALSE, .(corp_code, bsns_year)]
    if (nrow(skip) > 0L) tk <- tk[!skip, on = c("corp_code", "bsns_year")]
  }
  setattr(tk, "counts", c(candidates = n_c, window_open = n_w, after_data = n_d, after_backoff = nrow(tk)))
  tk
}

#' 연간(11011, dart_raw_financials) 후보 연도 — 분모 = 그 해 상장 기업 수(ref_basis "listed").
#' 상장 집합을 만들 수 없으면(RAWDATA·corpcode 부재) listed = NULL → 열린 연도는
#' due_no_reference(수집 쪽 후퇴). 종전 규칙(prior_year)으로 조용히 되돌아가지 않는다.
#' @return due (integer) — attr "resolution" = dart_annual_resolution 표, attr "detail"
dart_due_annual_years <- function(today = Sys.Date(), path = NULL, verbose = TRUE,
                                  listed_tbl = NULL, ledger = NULL, grace_days = 60L, ...) {
  if (is.null(path)) path <- file.path(.dart_cache_dir(), "dart_raw_financials.parquet")
  if (is.null(listed_tbl)) {
    listed_tbl <- tryCatch(dart_listed_corps_by_year(), error = function(e) {
      cat(sprintf("[dart_window] ⚠ 상장 집합 산출 실패(%s) — 분모 미상 → 수집 쪽 후퇴\n",
                  conditionMessage(e)))
      NULL
    })
  }
  if (is.null(ledger)) ledger <- dart_annual_load_ledger()
  keys <- dart_annual_keys(path)
  rt <- dart_annual_resolution(keys, ledger, listed_tbl, today = today, grace_days = grace_days)
  cov <- if (is.null(rt)) NULL else setNames(as.numeric(rt$resolved), rt$bsns_year)
  lst <- if (is.null(rt)) NULL else setNames(as.numeric(rt$listed), rt$bsns_year)
  res <- .dart_due_bsns_years(cov, reprt_code = "11011", today = today, listed = lst,
                              ref_basis = "listed", grace_days = grace_days, ...)
  if (verbose) cat(.dart_due_report(res), "\n")
  out <- res$due
  setattr(out, "resolution", rt)
  setattr(out, "detail", res$detail)
  out
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
    # ★분기 경로는 종전 분모(직전 마감 연도) 유지 — 2026-11-08 연간만 listed 로 옮겼다.
    #   같은 결함(작은 유니버스의 자기 기준 완결)이 남아 있다 → 후속 과제(분기 원시본 소비처 0).
    res <- .dart_due_bsns_years(cov, reprt_code = rc, today = today, ref_basis = "prior_year", ...)
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
