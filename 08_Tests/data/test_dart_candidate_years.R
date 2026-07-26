#==============================================================================
# test_dart_candidate_years.R — DART 수집 후보집합 판정 상설 검사 (위반 주입)
#
# 대상: 02_Infrastructure/data/dart_submission_window.R
#         .dart_season_bounds / .dart_due_bsns_years / .dart_filter_tasks_by_window
#         dart_coverage_by_year
#       + 실제 호출부 배선 (data_collector_dart.R / _quarterly.R /
#         dart_daily_incremental.R / daily_refresh.sh)
#
# 왜 있나 (2026-07-26, P2-01 수리):
#   구 코드는 후보집합을 **달력**으로 만들었다 — years = format(Sys.Date(), "%Y").
#   FY2025 사업보고서는 2026-03 에 제출되므로 2025년 내내는 존재하지 않았고
#   2026년에는 아예 요청되지 않았다 → dart_raw_financials FY2025 = 50 corps
#   (FY2024 = 714 → 7.0%). 제출기한 경과 4개월, 자동 회복 경로 없음.
#   판정 로직(.dart_season_bounds)은 이미 옳았다 — 결함은 **후보집합 생성**이었다.
#
# 구조 6축:
#   A. 위반 주입 — FY2025 를 미수집/부분수집 상태로 주입해 due 로 잡히는지
#   B. 오탐 통제 — 완결 연도가 due 로 잡히지 않는지 (오탐 0). 유니버스가 5배
#                  커진 상황에서 과거 완결연도가 전부 '미달'로 뒤집히지 않는지
#   C. 미래 차단 — 제출창 미개시 연도를 요청하지 않는지 (콜 낭비 + 무의미)
#   D. 차단 실효 — **구 규칙(달력 현재연도)** 을 같은 케이스에 적용하면 A 가
#                  통과해버리는 것을 실증. 케이스가 공허하지 않음을 보인다.
#   E. 배선     — 호출부가 실제로 달력연도를 넘기지 않는지. 판정부만 고치고
#                 호출부가 years 를 덮어쓰면 수리는 무력화된다(원 결함 그대로).
#   F. 매핑 회귀 — 11013=1분기 / 11014=3분기 (OpenDART 공식 + 저장데이터 실측).
#                  종전 중복 정의는 이 둘이 뒤집혀 있었다.
#
# 단독 실행: Rscript 08_Tests/data/test_dart_candidate_years.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/data/dart_submission_window.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

SRC <- "02_Infrastructure/data/dart_submission_window.R"
source(SRC)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

due_of <- function(cov, rc = "11011", today = "2026-07-26", ...) {
  r <- tryCatch(.dart_due_bsns_years(cov, reprt_code = rc, today = today, ...),
                error = function(e) list(due = NA_integer_, err = conditionMessage(e)))
  r$due
}
verdict_of <- function(cov, y, rc = "11011", today = "2026-07-26", ...) {
  r <- .dart_due_bsns_years(cov, reprt_code = rc, today = today, ...)
  r$detail[bsns_year == y, verdict]
}

# 실측 커버리지 (2026-07-26, dart_raw_financials.parquet corp_code nunique)
COV_REAL <- c("2021" = 656, "2022" = 666, "2023" = 713, "2024" = 714,
              "2025" = 50, "2026" = 26)
# 백필 후 기대 상태 (FY2025 가 직전연도 수준으로 찬 상태)
COV_FILLED <- replace(COV_REAL, "2025", 700)

cat("\n=== A. 위반 주입 (미수집/부분수집이 후보로 잡히는가) ===\n")
{
  # A1: 실측 그대로 — FY2025 가 7% 인 상태
  d <- due_of(COV_REAL)
  if (2025L %in% d) ok("A1_realized_FY2025_due", sprintf("due={%s}", paste(d, collapse = ","))) else
    bad("A1_realized_FY2025_due", sprintf("FY2025 가 후보에 없음 — 원 결함 재현 (due={%s})", paste(d, collapse = ",")))

  # A2: 완전 미수집 주입 (연도 자체가 캐시에 없음)
  cov <- COV_REAL[names(COV_REAL) != "2025"]
  d <- due_of(cov)
  if (2025L %in% d && identical(verdict_of(cov, 2025L), "due_missing"))
    ok("A2_absent_year_due_missing") else
    bad("A2_absent_year_due_missing", sprintf("verdict=%s due={%s}", verdict_of(cov, 2025L), paste(d, collapse = ",")))

  # A3: 존재하지만 부분 — 존재=완비 대리판정(B형 동형결함) 회피 확인
  cov <- replace(COV_REAL, "2025", 500)   # 500/714 = 0.70 < 0.85
  if (identical(verdict_of(cov, 2025L), "due_partial")) ok("A3_partial_coverage_due", "500/714=0.70") else
    bad("A3_partial_coverage_due", sprintf("존재만으로 완결 판정 — verdict=%s", verdict_of(cov, 2025L)))

  # A4: 캐시 파일 자체가 없는(=coverage NULL) 최초 부팅 상태에서도 죽지 않고 수집으로 후퇴
  d <- due_of(NULL)
  if (length(d) > 0L) ok("A4_null_coverage_falls_back_to_collect", sprintf("due={%s}", paste(d, collapse = ","))) else
    bad("A4_null_coverage_falls_back_to_collect", "커버리지 미상인데 후보 0 — 침묵 무수집")

  # A5: 분기 11011(사업보고서)도 같은 결함 — 실측 103/621
  covq <- c("2023" = 624, "2024" = 621, "2025" = 103)
  if (2025L %in% due_of(covq)) ok("A5_quarterly_11011_FY2025_due", "103/621=0.17") else
    bad("A5_quarterly_11011_FY2025_due", "분기 사업보고서 결손이 후보로 안 잡힘")
}

cat("\n=== B. 오탐 통제 (완결 연도를 건드리지 않는가) ===\n")
{
  # B1: FY2025 를 채운 뒤엔 스스로 후보에서 빠져야 한다 (자기 종료)
  d <- due_of(COV_FILLED)
  if (!(2025L %in% d)) ok("B1_filled_year_not_due", sprintf("700/714=0.98 → due={%s}", paste(d, collapse = ","))) else
    bad("B1_filled_year_not_due", "채워도 계속 재수집 — 매일 수천 콜 낭비")

  # B2: 과거 완결 연도 오탐 0 (2021~2024)
  d <- due_of(COV_FILLED)
  fp <- intersect(d, c(2021L, 2022L, 2023L, 2024L))
  if (length(fp) == 0L) ok("B2_no_false_positive_past_years") else
    bad("B2_no_false_positive_past_years", sprintf("완결 연도 오탐: %s", paste(fp, collapse = ",")))

  # B3: 유니버스 확장 함정 — reference 를 전역 max 로 잡으면 과거가 전부 미달이 된다.
  #     (2026 수집 유니버스 3,433 vs 2019 당시 ~580 — 실측 적발 사례)
  cov <- c("2019" = 580, "2020" = 587, "2021" = 586, "2022" = 583,
           "2023" = 584, "2024" = 621, "2025" = 618)
  d <- due_of(cov, rc = "11013")
  fp <- intersect(d, c(2019L, 2020L, 2021L, 2022L, 2023L))
  if (length(fp) == 0L) ok("B3_expanding_universe_no_false_positive", sprintf("due={%s}", paste(d, collapse = ","))) else
    bad("B3_expanding_universe_no_false_positive",
        sprintf("전역 max 기준 오판정 재현 — 오탐 %s", paste(fp, collapse = ",")))

  # B4: 시즌 중에는 커버리지와 무관하게 후보 (지연·정정 접수 수집)
  #     11014(3분기) 창 = 10/1~11/30 → 2026-11-01 은 시즌 중
  v <- verdict_of(c("2025" = 617, "2026" = 617), 2026L, rc = "11014", today = "2026-11-01")
  if (identical(v, "due_in_season")) ok("B4_in_season_always_due") else
    bad("B4_in_season_always_due", sprintf("verdict=%s", v))
}

cat("\n=== C. 미래 차단 (제출창 미개시분을 요청하지 않는가) ===\n")
{
  # C1: FY2026 사업보고서 창은 2027-01-01 개시 → 2026-07-26 에 요청 금지
  v <- verdict_of(COV_REAL, 2026L)
  if (identical(v, "window_not_open")) ok("C1_future_year_window_not_open") else
    bad("C1_future_year_window_not_open", sprintf("verdict=%s — 미개시 연도 요청", v))

  d <- due_of(COV_REAL)
  if (!(2026L %in% d)) ok("C1b_future_year_not_due") else
    bad("C1b_future_year_not_due", "미개시 연도가 후보에 포함 — 콜 낭비")

  # C2: task 필터가 실제로 미개시 조합을 제거하는가
  tasks <- data.table(corp_code = rep("00126380", 4),
                      bsns_year = c(2024L, 2025L, 2026L, 2027L),
                      reprt_code = "11011")
  kept <- .dart_filter_tasks_by_window(tasks, today = as.Date("2026-07-26"), verbose = FALSE)
  if (identical(sort(kept$bsns_year), c(2024L, 2025L))) ok("C2_task_filter_drops_unopened",
        sprintf("kept={%s}", paste(sort(kept$bsns_year), collapse = ","))) else
    bad("C2_task_filter_drops_unopened", sprintf("kept={%s}", paste(sort(kept$bsns_year), collapse = ",")))

  # C3: 미상 reprt_code 는 fail-closed (창 열림 FALSE) — 무지를 '허용'으로 바꾸지 않는다
  if (isFALSE(.dart_window_open(2025L, "99999", as.Date("2026-07-26"))))
    ok("C3_unknown_reprt_fail_closed") else
    bad("C3_unknown_reprt_fail_closed", "미상 코드가 창 열림으로 통과")
}

cat("\n=== D. 차단 실효 (구 규칙이면 A 가 통과해버리는가) ===\n")
{
  # 구 규칙 재현: years = as.integer(format(Sys.Date(), "%Y"))
  old_rule <- function(today) as.integer(format(as.Date(today), "%Y"))

  old_due <- old_rule("2026-07-26")
  new_due <- due_of(COV_REAL)
  if (!(2025L %in% old_due) && (2025L %in% new_due))
    ok("D1_old_rule_misses_FY2025", sprintf("구={%s} vs 신={%s}", paste(old_due, collapse=","), paste(new_due, collapse=","))) else
    bad("D1_old_rule_misses_FY2025", "구 규칙과 신 규칙이 구분되지 않음 — 케이스가 공허함")

  # 구 규칙은 제출창 미개시 연도(2026 사업보고서)를 요청한다 = 낭비 축도 구분
  if (2026L %in% old_due && !(2026L %in% new_due))
    ok("D2_old_rule_wastes_on_unopened") else
    bad("D2_old_rule_wastes_on_unopened", "미개시 요청 축이 구분되지 않음")

  # 존재=완비 대리판정(B형)로 되돌리면 A3 가 통과해버리는가
  naive_present <- function(cov, y) as.character(y) %in% names(cov)
  cov <- replace(COV_REAL, "2025", 500)
  if (naive_present(cov, 2025) && identical(verdict_of(cov, 2025L), "due_partial"))
    ok("D3_presence_check_would_miss_partial", "존재-검사는 통과 / 커버리지-검사는 적발") else
    bad("D3_presence_check_would_miss_partial", "부분수집 축이 구분되지 않음")
}

cat("\n=== E. 배선 (호출부가 달력연도를 넘기지 않는가) ===\n")
{
  rd <- function(p) if (file.exists(p)) readLines(p, warn = FALSE) else character(0)

  # E1: 후보집합 판정을 우회하는 달력연도 인자 잔재 — 데이터 계층 전수
  files <- list.files("02_Infrastructure/data", pattern = "\\.(R|sh)$", full.names = TRUE)
  files <- files[!grepl("_old_|_running", files)]        # 아카이브 사본 제외
  offenders <- character(0)
  for (f in files) {
    L <- rd(f)
    hit <- grep("(years|bsns_year)\\s*=\\s*(as\\.integer\\()?\\s*format\\(Sys\\.(Date|time)\\(\\)", L)
    # 주석 줄은 제외 (수리 경위 서술에 구 코드가 인용된다)
    hit <- hit[!grepl("^\\s*#", L[hit])]
    if (length(hit) > 0L) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(hit, collapse = ",")))
  }
  if (length(offenders) == 0L) ok("E1_no_calendar_year_candidate_set") else
    bad("E1_no_calendar_year_candidate_set", sprintf("달력연도 후보집합 잔재: %s", paste(offenders, collapse = " | ")))

  # E2: 진입점 기본값이 NULL(=자동 판정) 인가
  chk_default <- function(file, fn) {
    L <- rd(file)
    i <- grep(sprintf("^%s\\s*<-\\s*function\\(", fn), L)
    if (length(i) == 0L) return(NA)
    grepl("years\\s*=\\s*NULL", L[i[1]])
  }
  for (spec in list(c("02_Infrastructure/data/data_collector_dart.R", "dart_fetch_all"),
                    c("02_Infrastructure/data/data_collector_dart.R", "dart_run_pipeline"),
                    c("02_Infrastructure/data/data_collector_dart_quarterly.R", "dart_fetch_quarterly"))) {
    r <- chk_default(spec[1], spec[2])
    if (isTRUE(r)) ok(sprintf("E2_default_null_%s", spec[2])) else
      bad(sprintf("E2_default_null_%s", spec[2]), sprintf("years 기본값이 NULL 이 아님 (%s)", r))
  }

  # E3: daily_refresh.sh 가 years 를 명시로 덮어쓰지 않는가
  L <- rd("02_Infrastructure/data/daily_refresh.sh")
  i <- grep("dart_run_pipeline\\(", L); i <- i[!grepl("^\\s*#", L[i])]
  if (length(i) > 0L && !any(grepl("years\\s*=", L[i]))) ok("E3_daily_refresh_no_explicit_years") else
    bad("E3_daily_refresh_no_explicit_years",
        sprintf("호출부가 years 를 덮어씀: %s", paste(trimws(L[i]), collapse = " / ")))

  # E4: dart_daily_incremental 이 current_year 를 quarterly 로 넘기지 않는가
  L <- rd("02_Infrastructure/data/dart_daily_incremental.R")
  i <- grep("dart_fetch_quarterly\\(", L); i <- i[!grepl("^\\s*#", L[i])]
  if (length(i) > 0L && !any(grepl("years\\s*=\\s*current_year", L[i]))) ok("E4_incremental_no_current_year") else
    bad("E4_incremental_no_current_year", "quarterly 에 달력 현재연도 주입")

  # E5: 판정부가 실제로 소비되는가 (호출 0이면 함수만 남고 무력화)
  used <- any(grepl("dart_due_annual_years", rd("02_Infrastructure/data/data_collector_dart.R"))) &&
          any(grepl("dart_due_quarterly_pairs", rd("02_Infrastructure/data/data_collector_dart_quarterly.R")))
  if (used) ok("E5_judgment_consumed_by_collectors") else
    bad("E5_judgment_consumed_by_collectors", "후보집합 판정부가 수집기에서 호출되지 않음")

  # E6: 쿼터 가드가 선언만 있고 구현이 없지 않은가 (일 10,000콜 한도)
  for (f in c("02_Infrastructure/data/data_collector_dart.R",
              "02_Infrastructure/data/data_collector_dart_quarterly.R")) {
    L <- rd(f)
    declared <- any(grepl("max_calls\\s*=\\s*Inf", L))
    enforced <- any(grepl("n_calls\\s*\\+\\s*2L\\s*>\\s*max_calls", L)) &&
                any(grepl("n_calls\\s*<-\\s*n_calls\\s*\\+\\s*1L", L))
    if (declared && enforced) ok(sprintf("E6_max_calls_enforced_%s", basename(f))) else
      bad(sprintf("E6_max_calls_enforced_%s", basename(f)),
          sprintf("declared=%s enforced=%s — 선언만 있고 강제 없음", declared, enforced))
  }
}

cat("\n=== F. 매핑 회귀 (11013=1Q / 11014=3Q) + 중복 정의 부재 ===\n")
{
  b13 <- .dart_season_bounds(2025L, "11013")
  b14 <- .dart_season_bounds(2025L, "11014")
  b11 <- .dart_season_bounds(2025L, "11011")
  if (identical(b13$start, as.Date("2025-04-01")) && identical(b14$start, as.Date("2025-10-01")))
    ok("F1_reprt_quarter_mapping", "11013 창 4/1 (1분기) · 11014 창 10/1 (3분기)") else
    bad("F1_reprt_quarter_mapping",
        sprintf("11013 start=%s / 11014 start=%s — 뒤집힘", b13$start, b14$start))

  if (identical(b11$start, as.Date("2026-01-01")) && identical(b11$end, as.Date("2026-04-15")))
    ok("F2_annual_window_next_year") else
    bad("F2_annual_window_next_year", sprintf("11011 창 %s~%s", b11$start, b11$end))

  # F3: .dart_season_bounds 가 저장소에 단 하나인가 (중복 = 한쪽만 고쳐지는 사고)
  defs <- character(0)
  for (f in list.files("02_Infrastructure", pattern = "\\.R$", recursive = TRUE, full.names = TRUE)) {
    L <- readLines(f, warn = FALSE)
    if (any(grepl("^\\.dart_season_bounds\\s*<-\\s*function", L))) defs <- c(defs, f)
  }
  if (length(defs) == 1L) ok("F3_single_definition", basename(defs)) else
    bad("F3_single_definition", sprintf("정의 %d곳: %s", length(defs), paste(basename(defs), collapse = ", ")))

  # F4: coverage 집계의 인자/열 이름 shadowing 회귀.
  #     data.table i-표현식에서 인자명과 열명이 같으면 열이 이겨 필터가 무력화된다
  #     (reprt_code == reprt_code → 항상 TRUE, 무에러 침묵).
  tf <- tempfile(fileext = ".parquet")
  dt <- data.table(bsns_year = c(2024L, 2024L, 2024L, 2025L),
                   reprt_code = c("11011", "11013", "11013", "11011"),
                   corp_code = c("A", "B", "C", "D"))
  arrow::write_parquet(dt, tf)
  c11 <- dart_coverage_by_year(tf, reprt_code = "11011")
  c13 <- dart_coverage_by_year(tf, reprt_code = "11013")
  unlink(tf)
  if (identical(as.numeric(c11[["2024"]]), 1) && identical(as.numeric(c13[["2024"]]), 2))
    ok("F4_coverage_reprt_filter_effective", "11011→1 / 11013→2") else
    bad("F4_coverage_reprt_filter_effective",
        sprintf("필터 무력화 — 11011=%s 11013=%s (기대 1 / 2)",
                c11[["2024"]], c13[["2024"]]))
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "dart_candidate_years", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
