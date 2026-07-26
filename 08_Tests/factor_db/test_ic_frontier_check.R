#==============================================================================
# test_ic_frontier_check.R — 월별 IC 프론티어 감시 상설 검사 (P3, 2026-07-26)
#
# 대상: 02_Infrastructure/data/ic_frontier_check.R 의 ic_frontier_check()
#       (소비처 = 02_Infrastructure/data/cache_freshness_audit.R 1c → registry 엔트리
#        .cache/factor_db/factor_ic_monthly.parquet 의 "::frontier" 결과 1건,
#        그리고 bootstrap.sh 가 그 결과를 check=='ic_month_frontier' 로 읽는다)
#
# 왜 있나:
#   ic_frontier_check() 는 2026-07-26 신설되며 `ic_max_date_override` 를 "위반 주입
#   테스트용"으로 노출해 놨는데, 정작 08_Tests 에 케이스가 없고 SUITES 에도 없었다.
#   4트랙 중 유일하게 상설 검사가 없던 갭 — 검사 없는 가드는 조용히 무력화돼도
#   아무 신호를 내지 않는다(그때 보이는 것은 "경보 0건"뿐이다).
#
# 구조 5축:
#   A. 위반 주입 — 프론티어가 뒤처진 상태를 주입해 실제로 경보가 나는가
#   B. 회귀     — 정상 상태(당월 진행 중 = 전월 IC 가 최신)를 경보로 오탐하지 않는가
#   C. 크래시   — IC 파일 부재/파손/0행, RAWDATA 월 부재에서 죽지 않고 UNKNOWN 인가
#   D. 차단 실효 — 감시 로직을 "지연을 못 보는" 형태로 되돌리면 A 가 전부 통과해
#                  버리는 것을 이 케이스 집합이 실제로 구분하는가 (공허한 통과 방지)
#   E. 규약 일치 — 프론티어의 pair 술어가 P1 정본(.ic_pair_complete)과 같은 판정인가
#                  + 소비처 배선이 살아 있는가
#
# ★D 축의 주입 대상은 **정본 파일의 임시 사본**이다. 스크립트 최상위 on.exit() 는
#   발화하지 않으므로(r-portability 금칙 ②) 정본 파일을 제자리 변조하면 중단 시
#   복구가 안 된다. 사본을 변조하고, 정본은 md5 로 불변을 실증한다.
#
# 단독 실행: Rscript 08_Tests/factor_db/test_ic_frontier_check.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/data/ic_frontier_check.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)
PROJECT_ROOT <- PROJ            # ic_frontier_check.R 이 참조

SRC        <- "02_Infrastructure/data/ic_frontier_check.R"
GUARD_SRC  <- "02_Infrastructure/factor_db/ic_pair_completeness.R"
AUDIT_SRC  <- "02_Infrastructure/data/cache_freshness_audit.R"
BOOT_SRC   <- "02_Infrastructure/ops/bootstrap.sh"

SRC_MD5_BEFORE <- unname(tools::md5sum(SRC))

source(SRC)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

D <- function(s) as.Date(s)

# 합성 RAWDATA 거래일 — 월별 최종 거래일이 판정의 operand 이므로 월당 2일이면 충분.
# (실측 캘린더: 2026-03-31 / 04-30 / 05-29 / 06-30 / 07-31)
RAW <- D(c("2026-03-02", "2026-03-31", "2026-04-01", "2026-04-30",
           "2026-05-04", "2026-05-29", "2026-06-01", "2026-06-30",
           "2026-07-01", "2026-07-31"))

run <- function(ic, today, raw = RAW, ...) {
  tryCatch(ic_frontier_check(ic_max_date_override = ic, raw_dates = raw,
                             today = D(today), ...),
           error = function(e) list(status = paste0("ERROR:", conditionMessage(e)),
                                    severity = "ERROR"))
}

expect <- function(id, r, want_status, want_sev, note = "") {
  if (identical(r$severity, "ERROR")) { bad(id, sprintf("판정이 죽음 (%s)", r$status)); return(invisible()) }
  if (!identical(r$status, want_status) || !identical(r$severity, want_sev)) {
    bad(id, sprintf("status/severity = %s/%s 기대했으나 %s/%s %s",
                    want_status, want_sev, r$status, r$severity, note))
    return(invisible())
  }
  ok(id, sprintf("%s/%s lag=%s days=%s", r$status, r$severity,
                 r$lag_months %||% "n/a", r$days_since_computable %||% "n/a"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

#──────────────────────────────────────────────────────────────────────────────
cat("\n=== A. 위반 주입 — 프론티어 지연을 잡는가 ===\n")
# 기준: today=2026-08-05 → forward month F=2026-07(달력 종료), 기대 프론티어 E=2026-06,
#       산출가능 2026-08-01, 경과 4일 (> 유예 3일).

# ① 7-31 재빌드가 실패해 IC 가 2026-05 에 멈춤 = 1개월 미달 → 경보(WARN)
A1 <- list(ic = "2026-05-29", today = "2026-08-05")
expect("A1_rebuild_failed_1m_short", run(A1$ic, A1$today), "IC_FRONTIER_LAG", "WARN")

# ② IC 가 2개월 정지(6-30·7-31 두 번 실패) → CRITICAL
A2 <- list(ic = "2026-04-30", today = "2026-08-05")
expect("A2_two_month_stall_critical", run(A2$ic, A2$today), "IC_FRONTIER_LAG", "CRITICAL")

# ③ 여러 달 뒤처짐(5개월) → CRITICAL 이고 lag 수치가 실제 개월수와 일치해야 한다
A3 <- list(ic = "2026-01-30", today = "2026-08-05")
r <- run(A3$ic, A3$today)
expect("A3_multi_month_behind_critical", r, "IC_FRONTIER_LAG", "CRITICAL")
if (identical(r$lag_months, 5L)) ok("A3b_lag_months_value", "lag_months=5")  else
  bad("A3b_lag_months_value", sprintf("lag_months=5 기대, 실제 %s", r$lag_months))

# ④ 유예 경계 — 경과일 == grace 면 더 이상 유예가 아니다(경보)
A4 <- list(ic = "2026-05-29", today = "2026-08-04")   # 산출가능 08-01 → 경과 3일
expect("A4_grace_boundary_at_grace_days", run(A4$ic, A4$today), "IC_FRONTIER_LAG", "WARN")

# ⑤ IC 가 기대보다 앞섬 = 미완결 forward month 를 완결로 기록(guard 무력화 의심)
A5 <- list(ic = "2026-06-30", today = "2026-07-26")   # E=2026-05 인데 IC 는 2026-06
expect("A5_frontier_ahead_partial_pair", run(A5$ic, A5$today), "IC_FRONTIER_AHEAD", "WARN")

#──────────────────────────────────────────────────────────────────────────────
cat("\n=== B. 회귀 — 정상 상태를 경보로 오탐하지 않는가 ===\n")
# ① 2026-07-26 실측 상태 재현: IC max 2026-05-29, 기대 프론티어 2026-05 → OK
expect("B1_measured_state_20260726", run("2026-05-29", "2026-07-26"),
       "IC_FRONTIER_CURRENT", "OK")

# ② 당월 진행 중 전월 IC 가 최신인 일반형(다른 달) — 경보 아님
#    today=2026-06-15 → F=2026-05, E=2026-04 → IC 2026-04-30 이 정상
expect("B2_month_in_progress_generic", run("2026-04-30", "2026-06-15"),
       "IC_FRONTIER_CURRENT", "OK")

# ③ 재빌드가 정상 수행돼 프론티어 도달
expect("B3_frontier_reached", run("2026-06-30", "2026-08-05"),
       "IC_FRONTIER_CURRENT", "OK")

# ④ 유예 안 (월말 재빌드 진행 중) — 경보 아님
expect("B4_within_grace", run("2026-05-29", "2026-08-02"),
       "IC_FRONTIER_GRACE", "OK")
expect("B4b_grace_day0", run("2026-05-29", "2026-08-01"),
       "IC_FRONTIER_GRACE", "OK")

# ⑤ 규약 자기검증 — 기대 프론티어의 forward pair 는 P1 guard 를 통과해야 한다
r <- run("2026-05-29", "2026-07-26")
if (isTRUE(r$guard_agrees)) ok("B5_guard_agrees", "forward pair 가 guard 통과") else
  bad("B5_guard_agrees", sprintf("guard_agrees=%s — 프론티어 산정과 guard 규약이 갈렸다", r$guard_agrees))

# ⑥ 실파일 라이브 — 크래시 없이 well-formed. ★severity 값은 주장하지 않는다
#    (그건 데이터 상태이고, 보고 주체는 cache_freshness_audit 다. 여기서 주장하면
#     체인이 실제로 지연될 때 배터리가 데이터 사유로 붉어진다 = 검사 대상 혼동)
live <- tryCatch(ic_frontier_check(today = Sys.Date()),
                 error = function(e) list(status = paste0("ERROR:", conditionMessage(e))))
need <- c("path", "check", "status", "severity")
if (all(need %in% names(live)) && identical(live$check, "ic_month_frontier") &&
    live$severity %in% c("OK", "WARN", "CRITICAL")) {
  ok("B6_live_wellformed", sprintf("%s/%s ic_max=%s expected=%s",
                                   live$status, live$severity,
                                   live$ic_max_date %||% "n/a", live$expected_month %||% "n/a"))
} else {
  bad("B6_live_wellformed", sprintf("실파일 실행 결과가 계약 형태가 아님: %s",
                                    paste(names(live), collapse = ",")))
}
# 라이브 lag_months 를 독립 재계산과 대조 (산식 드리프트 검출 — 데이터 상태와 무관)
if (!is.null(live$ic_month) && !is.null(live$expected_month)) {
  mi <- function(m) { p <- as.integer(strsplit(m, "-")[[1]]); p[1] * 12L + p[2] }
  if (identical(as.integer(live$lag_months), mi(live$expected_month) - mi(live$ic_month))) {
    ok("B7_live_lag_recompute", sprintf("lag_months=%d 재계산 일치", live$lag_months))
  } else {
    bad("B7_live_lag_recompute", "lag_months 가 독립 재계산과 불일치")
  }
} else {
  bad("B7_live_lag_recompute", "라이브 판정이 월 필드를 못 채움 — 상류(IC/RAWDATA) 점검")
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n=== C. 크래시 축 — 부재/파손/0행/월 부재에서 안전한가 ===\n")
TD <- file.path(tempdir(), "icfc_test"); dir.create(TD, showWarnings = FALSE, recursive = TRUE)

chk_unknown <- function(id, expr, note = "", want_note = NULL) {
  r <- tryCatch(expr, error = function(e) list(status = paste0("ERROR:", conditionMessage(e)),
                                               severity = "ERROR"))
  if (identical(r$severity, "ERROR")) { bad(id, sprintf("크래시: %s %s", r$status, note)); return(invisible()) }
  if (!identical(r$status, "IC_FRONTIER_UNKNOWN") || !identical(r$severity, "WARN")) {
    bad(id, sprintf("UNKNOWN/WARN 기대, 실제 %s/%s", r$status, r$severity)); return(invisible())
  }
  # 사유가 뭉뚱그려지면 운영자가 "부재"와 "0행"을 구분하지 못한다(다른 고장·다른 조치)
  if (!is.null(want_note) && !grepl(want_note, r$note %||% "")) {
    bad(id, sprintf("note 에 '%s' 기대, 실제 '%s'", want_note, r$note %||% "")); return(invisible())
  }
  ok(id, r$note %||% "")
}

# ① IC 파일 부재
chk_unknown("C1_ic_file_missing",
            ic_frontier_check(ic_path = file.path(TD, "nope.parquet"),
                              raw_dates = RAW, today = D("2026-08-05")),
            want_note = "부재")
# ② 0바이트 파손 파일 (read_parquet 이 던진다)
zb <- file.path(TD, "zero.parquet"); if (!file.exists(zb)) invisible(file.create(zb))
chk_unknown("C2_ic_file_corrupt_zero_byte",
            ic_frontier_check(ic_path = zb, raw_dates = RAW, today = D("2026-08-05")),
            want_note = "read 실패")
# ③ 0행 parquet — read 는 성공하고 max(numeric(0)) = -Inf 가 흘러간다.
#    2026-07-26 실측: 여기서 "missing value where TRUE/FALSE needed" 로 abort 했다.
if (requireNamespace("arrow", quietly = TRUE)) {
  ep <- file.path(TD, "empty.parquet")
  arrow::write_parquet(data.frame(Date = as.Date(character(0))), ep)
  chk_unknown("C3_ic_parquet_zero_rows",
              ic_frontier_check(ic_path = ep, raw_dates = RAW, today = D("2026-08-05")),
              note = "(0행 → -Inf 전파)", want_note = "0행")
} else {
  bad("C3_ic_parquet_zero_rows", "arrow 미설치 — 0행 경로를 실증할 수 없음")
}
# ④ RAWDATA 거래일 전무
chk_unknown("C4_rawdata_empty",
            ic_frontier_check(ic_max_date_override = "2026-05-29",
                              raw_dates = as.Date(character(0)), today = D("2026-08-05")))
# ⑤ 완결월이 1개뿐 (E 를 잡을 수 없다)
chk_unknown("C5_only_one_complete_month",
            ic_frontier_check(ic_max_date_override = "2026-05-29",
                              raw_dates = D(c("2026-07-01", "2026-07-31")),
                              today = D("2026-08-05")))
# ⑥ RAWDATA 가 전부 미래 (달력 종료월 0개)
chk_unknown("C6_rawdata_all_future",
            ic_frontier_check(ic_max_date_override = "2026-05-29",
                              raw_dates = D(c("2027-01-04", "2027-02-01")),
                              today = D("2026-08-05")))
# ⑦ IC max 자체가 NA
chk_unknown("C7_ic_max_na",
            ic_frontier_check(ic_max_date_override = as.Date(NA),
                              raw_dates = RAW, today = D("2026-08-05")))

#──────────────────────────────────────────────────────────────────────────────
cat("\n=== D. 차단 실효 — 감시를 무력화하면 A 가 뚫리는가 ===\n")
# 무력화 형태 = "지연을 못 보는" 감시(lag 를 항상 0 으로 계산 → 전부 CURRENT/OK).
# 정본을 제자리 변조하지 않는다: 최상위 on.exit() 미발화(r-portability 금칙 ②)라
# 중단 시 복구가 보장되지 않는다. 사본을 변조하고 정본은 md5 로 불변을 실증한다.
STUB_OK <- FALSE
stub_env <- NULL
{
  src_txt <- readLines(SRC, warn = FALSE)
  needle  <- ".mi(exp_f$expected_month) - .mi(ic_month)"
  hits    <- sum(grepl(needle, src_txt, fixed = TRUE))
  if (hits != 1L) {
    bad("D0_stub_injectable", sprintf("주입 지점(lag 산식) %d곳 — 소스 구조가 바뀌었다. D축 공허", hits))
  } else {
    stub_path <- file.path(TD, "ic_frontier_check_STUB.R")
    writeLines(sub(needle, "0L", src_txt, fixed = TRUE), stub_path)
    e <- new.env(parent = globalenv())
    stub_env <- tryCatch({ sys.source(stub_path, envir = e); e }, error = function(err) NULL)
    if (is.null(stub_env)) bad("D0_stub_injectable", "무력화 사본 source 실패")
    else { STUB_OK <- TRUE; ok("D0_stub_injectable", "lag 산식 1곳을 0L 로 치환한 사본 적재") }
  }
}

if (STUB_OK) {
  cases <- list(list(id = "A1", ic = A1$ic, today = A1$today),
                list(id = "A2", ic = A2$ic, today = A2$today),
                list(id = "A3", ic = A3$ic, today = A3$today),
                list(id = "A4", ic = A4$ic, today = A4$today),
                list(id = "A5", ic = A5$ic, today = A5$today))
  disc <- character(0)
  for (cs in cases) {
    real <- run(cs$ic, cs$today)
    fake <- tryCatch(stub_env$ic_frontier_check(ic_max_date_override = cs$ic,
                                                raw_dates = RAW, today = D(cs$today)),
                     error = function(e) list(severity = "ERROR"))
    if (!identical(real$severity, "OK") && identical(fake$severity, "OK")) disc <- c(disc, cs$id)
  }
  if (identical(sort(disc), c("A1", "A2", "A3", "A4", "A5"))) {
    ok("D1_neutered_monitor_passes_all_A",
       "무력화판은 A1~A5 를 전부 OK 로 통과 — 이 케이스 집합이 감시 사망을 구분한다")
  } else {
    bad("D1_neutered_monitor_passes_all_A",
        sprintf("구분되는 케이스가 {%s} 뿐 — A 케이스 일부가 회귀를 못 잡는다(공허한 통과)",
                paste(disc, collapse = ",")))
  }
  # 무력화판이 B(정상)도 OK 로 낸다는 사실 = A 와 B 의 구분력이 A 에서만 나온다는 확인
  b_same <- identical(stub_env$ic_frontier_check(ic_max_date_override = "2026-05-29",
                                                 raw_dates = RAW, today = D("2026-07-26"))$severity, "OK")
  if (b_same) ok("D2_neutered_keeps_B_ok", "정상 케이스는 신·구 모두 OK (B 는 판별자가 아니다)")
  else bad("D2_neutered_keeps_B_ok", "무력화판이 정상 케이스를 OK 로 못 냄 — 주입이 의도와 다르게 걸렸다")
}

# 정본 불변 실증 (사본만 건드렸는지)
SRC_MD5_AFTER <- unname(tools::md5sum(SRC))
if (identical(SRC_MD5_BEFORE, SRC_MD5_AFTER)) {
  ok("D3_source_untouched_md5", sprintf("md5 %s 불변", substr(SRC_MD5_AFTER, 1, 12)))
} else {
  bad("D3_source_untouched_md5",
      sprintf("정본이 변조됨: %s → %s (즉시 git 복원 필요)", SRC_MD5_BEFORE, SRC_MD5_AFTER))
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n=== E. 규약 일치 — P1 정본 판정과 같은 답을 내는가 + 배선 ===\n")
# E1. 위임이 살아 있는가 (NULL 이면 미러 폴백 = 중복 구현이 조용히 가동 중)
if (!is.null(.ICFC_GUARD)) {
  ok("E1_delegation_live", "ic_pair_completeness.R 전용 env 위임 활성")
} else {
  bad("E1_delegation_live", ".ICFC_GUARD 가 NULL — 정본 위임 끊김(미러 폴백 가동)")
}

# E2. 그리드 대조: .icfc_pair_complete(프론티어) == .ic_pair_complete(P1 정본)$complete
canon_env <- new.env(parent = globalenv())
sys.source(GUARD_SRC, envir = canon_env)
grid <- list(
  # sig, today, 그달 RAWDATA 최종거래일
  list(D("2026-06-30"), D("2026-07-26"), D("2026-06-30")),   # 완결
  list(D("2026-07-24"), D("2026-07-31"), D("2026-07-31")),   # file_partial
  list(D("2026-07-24"), D("2026-08-05"), D("2026-07-31")),   # file_partial(달 넘김)
  list(D("2026-07-24"), D("2026-07-26"), D("2026-07-24")),   # calendar_not_ended
  list(D("2026-06-30"), D("2026-06-30"), D("2026-06-30")),   # 월말 당일 cron
  list(D("2026-06-30"), D("2026-06-29"), D("2026-06-30")),   # 하루 전
  list(D("2020-06-30"), D("2026-07-26"), D("2020-06-30")),   # 과거
  list(as.Date(NA),     D("2026-07-26"), D("2026-06-30"))    # 파손 sig (fail-closed)
)
mism <- integer(0)
for (i in seq_along(grid)) {
  g <- grid[[i]]
  # 프론티어 술어는 raw_dates 벡터를 받아 그달 최종거래일을 스스로 뽑는다 →
  # 같은 operand 가 되도록 그 달의 날짜 하나만 담은 벡터를 준다
  rawv <- if (is.na(g[[3]])) as.Date(character(0)) else g[[3]]
  a <- tryCatch(isTRUE(.icfc_pair_complete(g[[1]], rawv, today = g[[2]])),
                error = function(e) NA)
  b <- tryCatch(isTRUE(canon_env$.ic_pair_complete(g[[1]], today = g[[2]],
                                                   raw_month_last = g[[3]])$complete),
                error = function(e) NA)
  if (is.na(a) || is.na(b) || !identical(a, b)) mism <- c(mism, i)
}
if (length(mism) == 0L) {
  ok("E2_predicate_matches_canonical", sprintf("그리드 %d건 전부 정본과 동일 판정", length(grid)))
} else {
  bad("E2_predicate_matches_canonical",
      sprintf("불일치/크래시 케이스 #%s — 두 판정이 갈렸다(같은 '완결' 정의를 안 쓴다)",
              paste(mism, collapse = ",")))
}

# E3. 폴백 미러도 같은 답인가 (위임이 끊긴 순간 판정이 바뀌면 안 된다)
{
  keep <- .ICFC_GUARD
  .ICFC_GUARD <<- NULL
  mism2 <- integer(0)
  for (i in seq_along(grid)) {
    g <- grid[[i]]
    rawv <- if (is.na(g[[3]])) as.Date(character(0)) else g[[3]]
    a <- tryCatch(isTRUE(.icfc_pair_complete(g[[1]], rawv, today = g[[2]])), error = function(e) NA)
    b <- tryCatch(isTRUE(canon_env$.ic_pair_complete(g[[1]], today = g[[2]],
                                                     raw_month_last = g[[3]])$complete),
                  error = function(e) NA)
    if (is.na(a) || is.na(b) || !identical(a, b)) mism2 <- c(mism2, i)
  }
  .ICFC_GUARD <<- keep
  if (length(mism2) == 0L) ok("E3_fallback_mirror_matches", "폴백 미러도 정본과 동일 판정")
  else bad("E3_fallback_mirror_matches",
           sprintf("폴백 불일치/크래시 #%s — 위임이 끊기면 판정이 바뀐다",
                   paste(mism2, collapse = ",")))
}

# E4. 소비처 배선 — audit 이 source 하고 호출하고 결과를 results 에 담는가
if (!file.exists(AUDIT_SRC)) {
  bad("E4_audit_wiring", sprintf("%s 부재", AUDIT_SRC))
} else {
  atxt <- readLines(AUDIT_SRC, warn = FALSE); acode <- atxt[!grepl("^\\s*#", atxt)]
  has_src  <- any(grepl("ic_frontier_check\\.R", acode))
  has_call <- any(grepl("ic_frontier_check\\s*\\(", acode))
  has_use  <- any(grepl("results\\[\\[fr\\$path\\]\\]", acode))
  if (has_src && has_call && has_use) ok("E4_audit_wiring", "source + 호출 + results 적재 모두 존재")
  else bad("E4_audit_wiring", sprintf("source=%s call=%s use=%s", has_src, has_call, has_use))
}

# E5. 부팅 소비 — bootstrap 이 check=='ic_month_frontier' 결과를 읽는가
if (!file.exists(BOOT_SRC)) {
  bad("E5_bootstrap_reads_result", sprintf("%s 부재", BOOT_SRC))
} else if (any(grepl("ic_month_frontier", readLines(BOOT_SRC, warn = FALSE)))) {
  ok("E5_bootstrap_reads_result", "bootstrap.sh 가 ic_month_frontier 결과를 조회")
} else {
  bad("E5_bootstrap_reads_result", "부팅 경로가 프론티어 결과를 읽지 않는다 — 경보가 도달하지 않음")
}

#──────────────────────────────────────────────────────────────────────────────
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "ic_frontier_check", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
