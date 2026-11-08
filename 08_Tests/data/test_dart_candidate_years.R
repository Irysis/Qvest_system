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
# 2026-11-08 추가 (연간 완결 분모 = 그 해 12월 상장 기업 수):
#   구 분모(직전 마감 연도 커버리지)는 ~600사 유니버스가 자기 자신을 기준으로 완결을
#   선언하게 했다 — FY2021~2024 ratio 0.99~1.07 'complete' 인데 상장 대비 28~30%.
#   G. 상장 분모 — 11-08 실측 상태를 주입해 FY2023~2025 가 due 로 잡히는지(위반 주입),
#      구 규칙이면 due={} 가 재현되는지(차단 실효), 자기 종료 · 경계 · lookback(과거 연도는
#      보충 플래그로만) · 분모 미상 시 수집 쪽 후퇴, 그리고 **돌연변이 통제**(판정부의 상장
#      분기를 구 규칙으로 바꾼 사본은 G1 을 통과하지 못해야 한다 — 검사가 살아 있음을 확인)
#   H. 진행 장부 — 재시도 간격 · 확인된 자료 없음 · 병합 · 상장 집합/해결 집계(집합 밖 기업과
#      마감 전 '자료 없음'은 분자에 넣지 않는다) · 요청 대상 산출
#   I. 배선 — 연간은 listed · 분기는 prior_year 명시 · 수집기·보충 CLI 가 같은 요청 대상 함수를
#      쓰는가 · 보충은 --backfill 플래그 없이 API 를 부르지 않는가 · 체인이 보충을 부르지 않는가
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

# ── 연간(11011) = 분모 '그 해 12월 상장 기업 수'(ref_basis listed · 2026-11-08) ──
# 상장 수 실측 (RAWDATA 12월 종목 ∩ corpcode — 2026-11-08 · 매칭률 100%)
LISTED <- c("2020" = 2248, "2021" = 2310, "2022" = 2357, "2023" = 2443,
            "2024" = 2509, "2025" = 2561)
# P2-01 장면(2026-07-26 · FY2025 원시본 50 corps)을 상장 분모로 옮긴 것 — 과거 연도는 해결 완료로 둔다
RES_P201   <- c("2020" = 2248, "2021" = 2300, "2022" = 2350, "2023" = 2440,
                "2024" = 2500, "2025" = 50, "2026" = 26)
# 보충 뒤 기대 상태 (FY2025 해결 2,550/2,561 = 0.996)
RES_FILLED <- replace(RES_P201, "2025", 2550)
due_a <- function(cov, today = "2026-07-26", ...) due_of(cov, today = today, listed = LISTED, ...)
ver_a <- function(cov, y, today = "2026-07-26", ...) verdict_of(cov, y, today = today, listed = LISTED, ...)

cat("\n=== A. 위반 주입 (미수집/부분수집이 후보로 잡히는가) ===\n")
{
  # A1: 실측 그대로 — FY2025 가 2% 인 상태
  d <- due_a(RES_P201)
  if (2025L %in% d) ok("A1_realized_FY2025_due", sprintf("due={%s}", paste(d, collapse = ","))) else
    bad("A1_realized_FY2025_due", sprintf("FY2025 가 후보에 없음 — 원 결함 재현 (due={%s})", paste(d, collapse = ",")))

  # A2: 완전 미수집 주입 (연도 자체가 캐시에 없음)
  cov <- RES_P201[names(RES_P201) != "2025"]
  d <- due_a(cov)
  if (2025L %in% d && identical(ver_a(cov, 2025L), "due_missing"))
    ok("A2_absent_year_due_missing") else
    bad("A2_absent_year_due_missing", sprintf("verdict=%s due={%s}", ver_a(cov, 2025L), paste(d, collapse = ",")))

  # A3: 존재하지만 부분 — 존재=완비 대리판정(B형 동형결함) 회피 확인
  cov <- replace(RES_P201, "2025", 1800)   # 1800/2561 = 0.70 < 0.99
  if (identical(ver_a(cov, 2025L), "due_partial")) ok("A3_partial_coverage_due", "1800/2561=0.70") else
    bad("A3_partial_coverage_due", sprintf("존재만으로 완결 판정 — verdict=%s", ver_a(cov, 2025L)))

  # A4: 캐시 파일 자체가 없는(=coverage NULL) 최초 부팅 상태에서도 죽지 않고 수집으로 후퇴
  #     (분모를 알 때 = due_missing / 분모도 모를 때 = due_no_reference — 둘 다 후보)
  d1 <- due_a(NULL)
  d2 <- due_of(NULL)
  if (length(d1) > 0L && length(d2) > 0L) ok("A4_null_coverage_falls_back_to_collect",
        sprintf("listed 有 due={%s} · listed 無 due={%s}", paste(d1, collapse = ","), paste(d2, collapse = ","))) else
    bad("A4_null_coverage_falls_back_to_collect", "커버리지 미상인데 후보 0 — 침묵 무수집")

  # A5: 분기 경로 11011(사업보고서 · 분모 prior_year 유지)도 같은 결손을 잡는다 — 실측 103/621
  covq <- c("2023" = 624, "2024" = 621, "2025" = 103)
  if (2025L %in% due_of(covq, ref_basis = "prior_year")) ok("A5_quarterly_11011_FY2025_due", "103/621=0.17") else
    bad("A5_quarterly_11011_FY2025_due", "분기 사업보고서 결손이 후보로 안 잡힘")
}

cat("\n=== B. 오탐 통제 (완결 연도를 건드리지 않는가) ===\n")
{
  # B1: FY2025 를 채운 뒤엔 스스로 후보에서 빠져야 한다 (자기 종료)
  d <- due_a(RES_FILLED)
  if (!(2025L %in% d)) ok("B1_filled_year_not_due", sprintf("2550/2561=0.996 → due={%s}", paste(d, collapse = ","))) else
    bad("B1_filled_year_not_due", "채워도 계속 재수집 — 매일 수천 콜 낭비")

  # B2: 과거 완결 연도 오탐 0 (2021~2024 — 해결 ≥ 0.99)
  d <- due_a(RES_FILLED)
  fp <- intersect(d, c(2021L, 2022L, 2023L, 2024L))
  if (length(fp) == 0L) ok("B2_no_false_positive_past_years") else
    bad("B2_no_false_positive_past_years", sprintf("완결 연도 오탐: %s", paste(fp, collapse = ",")))

  # B3: (분기 경로 · prior_year) 유니버스 확장 함정 — reference 를 전역 max 로 잡으면 과거가
  #     전부 미달이 된다. (2026 수집 유니버스 3,433 vs 2019 당시 ~580 — 실측 적발 사례)
  cov <- c("2019" = 580, "2020" = 587, "2021" = 586, "2022" = 583,
           "2023" = 584, "2024" = 621, "2025" = 618)
  d <- due_of(cov, rc = "11013", ref_basis = "prior_year")
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
  v <- ver_a(RES_P201, 2026L)
  if (identical(v, "window_not_open")) ok("C1_future_year_window_not_open") else
    bad("C1_future_year_window_not_open", sprintf("verdict=%s — 미개시 연도 요청", v))

  d <- due_a(RES_P201)
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
  new_due <- due_a(RES_P201)
  if (!(2025L %in% old_due) && (2025L %in% new_due))
    ok("D1_old_rule_misses_FY2025", sprintf("구={%s} vs 신={%s}", paste(old_due, collapse=","), paste(new_due, collapse=","))) else
    bad("D1_old_rule_misses_FY2025", "구 규칙과 신 규칙이 구분되지 않음 — 케이스가 공허함")

  # 구 규칙은 제출창 미개시 연도(2026 사업보고서)를 요청한다 = 낭비 축도 구분
  if (2026L %in% old_due && !(2026L %in% new_due))
    ok("D2_old_rule_wastes_on_unopened") else
    bad("D2_old_rule_wastes_on_unopened", "미개시 요청 축이 구분되지 않음")

  # 존재=완비 대리판정(B형)로 되돌리면 A3 가 통과해버리는가
  naive_present <- function(cov, y) as.character(y) %in% names(cov)
  cov <- replace(RES_P201, "2025", 1800)
  if (naive_present(cov, 2025) && identical(ver_a(cov, 2025L), "due_partial"))
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

cat("\n=== G. 상장 분모 (2026-11-08 — 작은 유니버스의 자기 기준 완결) ===\n")
{
  # 2026-11-08 실측 — 상장 집합 안 자료 보유 수 / 12월 상장 수 / 원시본 corp 수(집합 밖 포함)
  RES_1108  <- c("2015" = 563, "2016" = 571, "2017" = 602, "2018" = 615, "2019" = 630, "2020" = 639,
                 "2021" = 652, "2022" = 660, "2023" = 693, "2024" = 693, "2025" = 1276)
  LIST_1108 <- c("2015" = 1901, "2016" = 1971, "2017" = 2039, "2018" = 2115, "2019" = 2197,
                 "2020" = 2248, "2021" = 2310, "2022" = 2357, "2023" = 2443, "2024" = 2509,
                 "2025" = 2561)
  COV_1108  <- c("2015" = 565, "2016" = 576, "2017" = 605, "2018" = 620, "2019" = 633, "2020" = 646,
                 "2021" = 656, "2022" = 666, "2023" = 713, "2024" = 714, "2025" = 1327, "2026" = 26)
  T1108 <- "2026-11-08"
  g1_check <- function(fn) {
    r <- fn(RES_1108, reprt_code = "11011", today = T1108, listed = LIST_1108)
    all(c(2023L, 2024L, 2025L) %in% r$due) &&
      all(r$detail[bsns_year %in% 2023:2025, verdict] == "due_partial")
  }

  # G1: 위반 주입 — 11-08 실측 상태에서 lookback 3년(FY2023~2025)이 전부 due_partial
  r <- .dart_due_bsns_years(RES_1108, today = T1108, listed = LIST_1108)
  if (g1_check(.dart_due_bsns_years))
    ok("G1_listed_basis_flags_partial_years",
       sprintf("due={%s} · FY2024 ratio=%.3f", paste(r$due, collapse = ","),
               r$detail[bsns_year == 2024, ratio])) else
    bad("G1_listed_basis_flags_partial_years",
        sprintf("due={%s} — 상장 대비 28%%인 연도를 완결로 판정", paste(r$due, collapse = ",")))

  # G2: 차단 실효 — 구 규칙(prior_year)은 같은 날 원시본 커버리지로 due={} 를 낸다(11-08 로그 재현)
  old <- .dart_due_bsns_years(COV_1108, today = T1108, ref_basis = "prior_year")
  if (length(old$due) == 0L && length(r$due) > 0L)
    ok("G2_old_rule_declares_complete",
       sprintf("구 due={} · 구 ratio FY2024=%.2f FY2025=%.2f",
               old$detail[bsns_year == 2024, ratio], old$detail[bsns_year == 2025, ratio])) else
    bad("G2_old_rule_declares_complete",
        sprintf("구 규칙이 결함을 재현하지 않음(구 due={%s}) — 케이스가 공허함", paste(old$due, collapse = ",")))

  # G3: 자기 종료 — 해결 ≥ 0.99 면 후보 0 (보충이 끝나면 스스로 멈춘다)
  d <- due_of(round(LIST_1108 * 0.995), today = T1108, listed = LIST_1108)
  if (length(d) == 0L) ok("G3_resolved_years_not_due") else
    bad("G3_resolved_years_not_due", sprintf("해결해도 due={%s}", paste(d, collapse = ",")))

  # G4: 경계 — 문턱 0.99 바로 아래는 due_partial, 0.99 는 complete
  lst <- c("2024" = 1000, "2025" = 1000)
  v_lo <- verdict_of(c("2024" = 1000, "2025" = 989), 2025L, today = T1108, listed = lst)
  v_eq <- verdict_of(c("2024" = 1000, "2025" = 990), 2025L, today = T1108, listed = lst)
  if (identical(v_lo, "due_partial") && identical(v_eq, "complete"))
    ok("G4_threshold_boundary", "989/1000 → due_partial · 990/1000 → complete") else
    bad("G4_threshold_boundary", sprintf("989 → %s · 990 → %s", v_lo, v_eq))

  # G5: lookback — 평상(3년)은 FY2015~2022 를 열지 않는다(과거 전수 재요청 방지) /
  #     보충 설정(min_year 2015 · lookback 11)은 FY2015~2025 를 전부 연다
  d_norm <- due_of(RES_1108, today = T1108, listed = LIST_1108)
  d_bf   <- due_of(RES_1108, today = T1108, listed = LIST_1108, lookback_years = 11L, min_year = 2015L)
  if (!any(2015:2022 %in% d_norm) && all(2015:2025 %in% d_bf))
    ok("G5_past_years_only_by_backfill",
       sprintf("평상 due={%s} · 보충 due={%s}", paste(d_norm, collapse = ","), paste(range(d_bf), collapse = "~"))) else
    bad("G5_past_years_only_by_backfill",
        sprintf("평상 due={%s} · 보충 due={%s}", paste(d_norm, collapse = ","), paste(d_bf, collapse = ",")))

  # G6: 분모 미상(그 해 상장 집합 없음) → complete 가 아니라 due_no_reference(수집 쪽 후퇴)
  v <- verdict_of(c("2025" = 2600), 2025L, today = T1108, listed = LIST_1108[names(LIST_1108) != "2025"])
  if (identical(v, "due_no_reference")) ok("G6_unknown_denominator_collects") else
    bad("G6_unknown_denominator_collects", sprintf("verdict=%s — 분모를 모르는데 완결/제외", v))

  # G7: 돌연변이 통제 — 판정부의 상장 분기를 끈 사본(= 구 규칙)은 G1 을 통과하지 못해야 한다.
  #     소스 텍스트 치환(deparse 치환은 줄바꿈된 호출을 조용히 빗나간다) · 치환 성사 · 사본 파싱을 단정.
  src <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
  pat <- 'if (identical(ref_basis, "listed")) {'
  hit <- which(trimws(src) == pat)
  mut <- src
  if (length(hit) == 1L) mut[hit] <- sub(pat, "if (FALSE) {", mut[hit], fixed = TRUE)
  applied <- length(hit) == 1L && !identical(mut, src)
  menv <- new.env(parent = globalenv())
  parsed <- applied && isTRUE(tryCatch({
    invisible(capture.output(eval(parse(text = mut, encoding = "UTF-8"), envir = menv)))
    is.function(menv$.dart_due_bsns_years)
  }, error = function(e) FALSE))
  mutant_caught <- parsed && !isTRUE(tryCatch(g1_check(menv$.dart_due_bsns_years), error = function(e) TRUE))
  if (applied && parsed && mutant_caught && g1_check(.dart_due_bsns_years))
    ok("G7_mutation_old_rule_fails_G1", "치환 1곳 · 사본 파싱 · 사본 = G1 FAIL · 원본 = G1 PASS") else
    bad("G7_mutation_old_rule_fails_G1",
        sprintf("applied=%s parsed=%s mutant_caught=%s — 검사가 구 규칙을 못 가린다", applied, parsed, mutant_caught))
}

cat("\n=== H. 진행 장부 · 상장 집합 · 해결 집계 ===\n")
{
  mk <- function(cc, y, st, d, n = 1L) data.table(
    corp_code = cc, bsns_year = as.integer(y), reprt_code = "11011", Ticker = paste0("A", cc),
    status = st, last_code = if (st == "empty") "013" else "800",
    first_attempt_date = as.Date(d), last_attempt_date = as.Date(d), n_attempts = as.integer(n))
  lg <- rbindlist(list(
    mk("F1", 2020, "fail",  "2026-11-07"),           # 실패 · 1일 경과 → 재시도
    mk("F2", 2020, "fail",  "2026-11-08"),           # 실패 · 당일 → 대기
    mk("F3", 2020, "fail",  "2026-10-30", n = 5L),   # 실패 5회 · 9일 → 30일 간격 → 대기
    mk("E1", 2020, "empty", "2026-11-01"),           # 마감 뒤 관측 = 확인됨 · 7일 → 180일 간격 → 대기
    mk("E2", 2026, "empty", "2027-02-01"),           # FY2026 시즌 중 관측 = 미확인
    mk("E3", 2019, "empty", "2026-05-02")))          # 확인됨 · 190일 → 재시도
  ev <- .dart_annual_ledger_eval(lg, today = "2026-11-08", grace_days = 60L)
  rd_ <- setNames(ev$retry_due, ev$corp_code); cf <- setNames(ev$confirmed, ev$corp_code)

  # H1: 실패 백오프 — 1일 / 5회 이상 30일
  if (isTRUE(rd_[["F1"]]) && isFALSE(rd_[["F2"]]) && isFALSE(rd_[["F3"]]))
    ok("H1_fail_backoff", "1일 경과 재시도 · 당일 대기 · 5회 이상 30일") else
    bad("H1_fail_backoff", sprintf("F1=%s F2=%s F3=%s", rd_[["F1"]], rd_[["F2"]], rd_[["F3"]]))

  # H2: 마감+grace 뒤 '자료 없음' = 확인됨(해결) · 180일 간격
  if (isTRUE(cf[["E1"]]) && isTRUE(cf[["E3"]]) && isFALSE(rd_[["E1"]]) && isTRUE(rd_[["E3"]]))
    ok("H2_confirmed_empty_cadence") else
    bad("H2_confirmed_empty_cadence", sprintf("cf E1=%s E3=%s · retry E1=%s E3=%s",
                                              cf[["E1"]], cf[["E3"]], rd_[["E1"]], rd_[["E3"]]))

  # H3: 시즌 중 '자료 없음' = 미확인 · 7일 간격 · 마감+grace 가 지나면 즉시 한 번 더(확인용)
  e2 <- lg[corp_code == "E2"]
  r1 <- .dart_annual_ledger_eval(e2, today = "2027-02-05")
  r2 <- .dart_annual_ledger_eval(e2, today = "2027-02-09")
  r3 <- .dart_annual_ledger_eval(e2, today = "2027-06-20")   # confirm_at = 2027-04-15 + 60 = 06-14
  if (isFALSE(r1$retry_due) && isTRUE(r2$retry_due) && isTRUE(r3$retry_due) &&
      isFALSE(r1$confirmed) && isFALSE(r3$confirmed))
    ok("H3_season_empty_not_resolved", "시즌 중 관측은 해결로 세지 않고, 시즌 뒤 한 번 더 묻는다") else
    bad("H3_season_empty_not_resolved",
        sprintf("retry 02-05=%s 02-09=%s 06-20=%s · confirmed=%s", r1$retry_due, r2$retry_due,
                r3$retry_due, r3$confirmed))

  # H4: 병합 — 같은 키는 최신 상태 · 횟수 합산 · 최초 시도일 보존 / 자료를 받은 키는 제거
  att <- mk("F1", 2020, "empty", "2026-11-08")[, .(corp_code, bsns_year, reprt_code, Ticker, status,
                                                    last_code, last_attempt_date, n_attempts)]
  m <- .dart_annual_ledger_merge(lg, att, ok_keys = data.table(corp_code = "F2", bsns_year = 2020L))
  f1 <- m[corp_code == "F1"]
  if (nrow(f1) == 1L && f1$status == "empty" && f1$n_attempts == 2L &&
      f1$first_attempt_date == as.Date("2026-11-07") && !("F2" %in% m$corp_code) && nrow(m) == nrow(lg) - 1L)
    ok("H4_ledger_merge") else
    bad("H4_ledger_merge", sprintf("F1 status=%s n=%s first=%s · F2 남음=%s",
                                   f1$status, f1$n_attempts, f1$first_attempt_date, "F2" %in% m$corp_code))

  # H5: 상장 집합 — 분모 = 12월 상장 · 익년 1/1~4/15 첫 등장 = 요청만(분모 밖) · 미매칭 집계
  raw <- data.table(
    Date = as.Date(c("2020-12-30", "2021-12-29", "2021-12-30", "2021-12-30", "2022-02-10",
                     "2022-05-02", "2021-12-30")),
    Ticker = c("A001", "A001", "A001", "B002", "C003", "D004", "E005"),
    Size = c(10, 11, 12, 5, 7, 9, 3))
  cmap <- data.table(Ticker = c("A001", "B002", "C003", "D004"),
                     corp_code = c("c1", "c2", "c3", "c4"), corp_name = c("a", "b", "c", "d"))
  lt <- dart_listed_corps_by_year(raw = raw, corpmap = cmap)
  den21 <- sort(lt[bsns_year == 2021 & in_denominator == TRUE, corp_code])
  ext21 <- sort(lt[bsns_year == 2021 & in_denominator == FALSE, corp_code])
  um <- attr(lt, "unmatched")
  mc_a <- lt[bsns_year == 2021 & corp_code == "c1", mcap]
  if (identical(den21, c("c1", "c2")) && identical(ext21, "c3") && !("c4" %in% lt[bsns_year == 2021, corp_code]) &&
      identical(um[bsns_year == 2021, n], 1L) && identical(mc_a, 12))
    ok("H5_listed_set", "FY2021 분모 {c1,c2} · 1분기 신규 {c3} · 5월 상장 제외 · 미매칭 1 · 시총 = 12월 말일") else
    bad("H5_listed_set", sprintf("den=%s ext=%s um=%s mcap=%s", paste(den21, collapse = ","),
                                 paste(ext21, collapse = ","), paste(um$n, collapse = ","), mc_a))

  # H6: 해결 집계 — 분자는 상장 집합 안만 · 시즌 중 '자료 없음'은 미해결 · 확인된 것은 해결
  lt2 <- data.table(bsns_year = 2021L, corp_code = c("k1", "k2", "k3", "k4"), Ticker = "x",
                    corp_name = "x", mcap = c(100, 50, 30, 20), in_denominator = c(TRUE, TRUE, TRUE, FALSE))
  keys <- data.table(corp_code = c("k1", "zz", "k4"), bsns_year = 2021L)      # zz = 집합 밖 · k4 = 분모 밖
  lg2 <- rbindlist(list(mk("k2", 2021, "empty", "2022-03-01"),              # 시즌 중 관측
                        mk("k3", 2021, "empty", "2026-11-01")))             # 마감 뒤 관측
  rt <- dart_annual_resolution(keys, lg2, lt2, today = "2026-11-08")
  naive <- nrow(keys) + nrow(lg2)                                            # 구분 없이 센 분자
  if (nrow(rt) == 1L && rt$listed == 3L && rt$ok == 1L && rt$empty_confirmed == 1L &&
      rt$empty_season == 1L && rt$resolved == 2L && abs(rt$mcap_ok_share - 100 / 180) < 1e-9 &&
      naive > rt$listed)
    ok("H6_resolution_counts_only_listed",
       sprintf("listed 3 · ok 1 · 확인 1 · 시즌 1 → 해결 2 (구분 없는 분자 %d > 분모)", naive)) else
    bad("H6_resolution_counts_only_listed", paste(capture.output(print(rt)), collapse = " | "))

  # H7: 요청 대상 — 자료 보유 · 백오프 중 제외, 재시도 차례 · 분모 밖 신규사는 포함
  cand <- lt2[, .(corp_code, bsns_year, Ticker, corp_name, mcap)]
  pt <- dart_annual_pending_tasks(cand, keys = keys, ledger = lg2, today = "2026-11-08")
  cn <- attr(pt, "counts")
  # k1 = 자료 보유 · k4 = 자료 보유(키에 있음) · k2 = 시즌 관측 → 마감+grace 지남 → 재시도 · k3 = 확인됨 7일 → 대기
  if (identical(sort(pt$corp_code), "k2") && cn[["after_data"]] == 2L && cn[["after_backoff"]] == 1L)
    ok("H7_pending_tasks", "자료 보유·백오프 제외 → {k2}") else
    bad("H7_pending_tasks", sprintf("pending={%s} counts=%s", paste(pt$corp_code, collapse = ","),
                                    paste(cn, collapse = "/")))
}

cat("\n=== I. 배선 ===\n")
{
  rd2 <- function(p) if (file.exists(p)) readLines(p, warn = FALSE, encoding = "UTF-8") else character(0)
  # deparse 는 긴 호출을 줄바꿈한다 → 공백을 정규화한 한 줄로 대조
  body_txt <- function(f) gsub("\\s+", " ", paste(deparse(body(f), width.cutoff = 500L), collapse = " "))
  # I1: 연간 판정 = listed · 분기 판정 = prior_year 명시(분기는 이번 수리 범위 밖 — 동작 불변)
  if (grepl('ref_basis = "listed"', body_txt(dart_due_annual_years), fixed = TRUE) &&
      grepl('ref_basis = "prior_year"', body_txt(dart_due_quarterly_pairs), fixed = TRUE))
    ok("I1_annual_listed_quarterly_prior_year") else
    bad("I1_annual_listed_quarterly_prior_year", "연간/분기 판정 분모 배선이 다름")

  # I2: 평상 lookback 3 · 문턱 기본값 (listed 0.99 · prior_year 0.85)
  if (identical(formals(.dart_due_bsns_years)$lookback_years, 3L) &&
      identical(unname(DART_COVERAGE_RATIO_DEFAULT[c("listed", "prior_year")]), c(0.99, 0.85)))
    ok("I2_defaults_lookback3_ratio") else
    bad("I2_defaults_lookback3_ratio", "평상 lookback 또는 문턱 기본값이 바뀜")

  # I3: 수집기와 보충 계획이 같은 요청 대상 함수를 쓴다 + 수집기는 상장 집합을 판정에 넘긴다
  C <- rd2("02_Infrastructure/data/data_collector_dart.R")
  B <- rd2("02_Infrastructure/data/dart_annual_backfill.R")
  nc <- function(L) L[!grepl("^\\s*#", L)]
  if (any(grepl("dart_annual_pending_tasks\\(", nc(C))) && any(grepl("dart_annual_pending_tasks\\(", nc(B))) &&
      any(grepl("listed_tbl = listed_tbl", nc(C), fixed = TRUE)))
    ok("I3_shared_pending_tasks") else
    bad("I3_shared_pending_tasks", "수집기·보충 계획의 요청 대상 산출이 갈라질 수 있음")

  # I4: 보충은 --backfill 없이는 API 를 부르지 않는다(계획만) · backfill=TRUE 는 years 명시 필수
  Bn <- nc(B)
  i_gate <- grep("^if \\(!DO_BACKFILL\\)", Bn)
  i_call <- grep("dart_fetch_all\\(", Bn)
  flag_def <- any(grepl('DO_BACKFILL\\s*<-\\s*\\.flag\\("backfill"\\)', Bn))
  gate_quits <- length(i_gate) == 1L && any(grepl("quit\\(status = 0\\)", Bn[i_gate + 0:3]))
  years_req <- any(grepl("if \\(isTRUE\\(backfill\\) && is.null\\(years\\)\\)", nc(C)))
  if (flag_def && gate_quits && length(i_call) >= 1L && min(i_call) > i_gate && years_req)
    ok("I4_backfill_requires_flag", "--backfill 없으면 quit(0) 이 API 호출보다 앞 · years 없는 backfill 은 오류") else
    bad("I4_backfill_requires_flag", sprintf("flag=%s gate=%s call=%s years_req=%s", flag_def,
                                             paste(i_gate, collapse = ","), paste(i_call, collapse = ","), years_req))

  # I5: 00:03 체인은 보충을 부르지 않는다(과거 연도는 명시 실행으로만)
  R <- nc(rd2("02_Infrastructure/data/daily_refresh.sh"))
  if (!any(grepl("dart_annual_backfill|backfill\\s*=\\s*TRUE", R)))
    ok("I5_chain_does_not_backfill") else
    bad("I5_chain_does_not_backfill", "daily_refresh.sh 가 보충을 부른다 — 체인 콜 예산 침범")
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "dart_candidate_years", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
