#==============================================================================
# test_ic_completion_guard.R — IC month-pair 완결성 가드 상설 검사
#
# 대상: 02_Infrastructure/factor_db/ic_pair_completeness.R 의 .ic_pair_complete()
#       (compute_all_factor_ic_monthly() 이 이 함수로 pair 를 skip 한다)
#
# 왜 있나 (2026-07-26, R-ICGUARD):
#   가드는 2026-07-25 신설 → 07-26 2조건 강화됐지만, 판정이 빌더 안 인라인이라
#   아무 검사도 걸려 있지 않았다. 검사 없는 가드는 나중에 조용히 무력화돼도
#   신호가 없다("실패 0건"으로 보인다).
#
# 구조 4축:
#   A. 위반 주입 — 일부러 미완결인 pair 를 넣어 '미완결'로 잡히는지
#   B. 회귀     — 과거 완결 pair 가 계속 '완결'인지 (가드가 과잉 차단하지 않는지)
#   C. 크래시   — RAWDATA 에 그 달이 없어 max() 가 -Inf 인 경로에서 죽지 않는지
#   D. 차단 실효 — **구 guard(달력만)로 되돌리면 A①②가 통과해버리는 것**을
#                  이 케이스 집합이 실제로 구분하는지 (=케이스가 공허하지 않은지)
#   E. 배선     — 빌더가 실제로 이 함수를 호출하고 결과로 skip 하는지
#                 (함수만 남고 호출이 끊기면 판정은 100% 통과하면서 무력화된다)
#
# 단독 실행: Rscript 08_Tests/factor_db/test_ic_completion_guard.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/factor_db/ic_pair_completeness.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

GUARD_SRC   <- "02_Infrastructure/factor_db/ic_pair_completeness.R"
BUILDER_SRC <- "02_Infrastructure/factor_db/factor_db_builder.R"
source(GUARD_SRC)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

D <- function(s) as.Date(s)

# 판정 1건 실행 — 에러도 결과로 받는다(크래시 축에서 필요).
try_judge <- function(sig, today, raw_last) {
  tryCatch(.ic_pair_complete(sig, today = today, raw_month_last = raw_last),
           error = function(e) list(complete = NA, reason = paste0("ERROR:", conditionMessage(e)),
                                    detail = "", month = NA_character_))
}

expect_case <- function(id, sig, today, raw_last, want_complete, want_reason = NULL, note = "") {
  r <- try_judge(sig, today, raw_last)
  if (is.na(r$complete)) {
    bad(id, sprintf("판정이 죽음 (%s)", r$reason)); return(invisible(NULL))
  }
  if (!identical(isTRUE(r$complete), want_complete)) {
    bad(id, sprintf("complete=%s 기대했으나 %s (reason=%s) %s",
                    want_complete, r$complete, r$reason, note))
    return(invisible(NULL))
  }
  if (!is.null(want_reason) && !identical(r$reason, want_reason)) {
    bad(id, sprintf("reason='%s' 기대했으나 '%s'", want_reason, r$reason))
    return(invisible(NULL))
  }
  ok(id, sprintf("complete=%s reason=%s", r$complete, r$reason))
}

cat("\n=== A. 위반 주입 — 미완결 pair 를 잡는가 ===\n")
# ① 달력 종료일 당일 도래했지만 파일은 07-24 스냅샷, RAWDATA 는 07-31 까지 있다.
#    달력만 보는 구 guard 는 여기서 '완결'을 내준다(=07-24까지의 부분월 IC 를 기록).
A1 <- list(sig = D("2026-07-24"), today = D("2026-07-31"), raw = D("2026-07-31"))
expect_case("A1_month_end_arrived_file_stale", A1$sig, A1$today, A1$raw,
            want_complete = FALSE, want_reason = "file_partial")

# ② 달이 넘어갔는데(8/5) 7월 파일이 여전히 07-24 스냅샷 — 월말 재빌드 지연/실패.
#    7월 최종 거래일 = 07-31. 구 guard 는 달력이 끝났으므로 '완결' 처리.
A2 <- list(sig = D("2026-07-24"), today = D("2026-08-05"), raw = D("2026-07-31"))
expect_case("A2_next_month_file_never_rebuilt", A2$sig, A2$today, A2$raw,
            want_complete = FALSE, want_reason = "file_partial")

# ③ 진행 중인 달 — 파일은 최신(07-24 = 현재까지의 최종 거래일)이지만 달이 안 끝났다.
A3 <- list(sig = D("2026-07-24"), today = D("2026-07-26"), raw = D("2026-07-24"))
expect_case("A3_month_in_progress", A3$sig, A3$today, A3$raw,
            want_complete = FALSE, want_reason = "calendar_not_ended")

cat("\n=== B. 회귀 — 과거 완결 pair 는 통과해야 한다 ===\n")
expect_case("B1_2026-06", D("2026-06-30"), D("2026-07-26"), D("2026-06-30"), TRUE, "complete")
expect_case("B2_2026-05", D("2026-05-29"), D("2026-07-26"), D("2026-05-29"), TRUE, "complete")
expect_case("B3_2020-06", D("2020-06-30"), D("2026-07-26"), D("2020-06-30"), TRUE, "complete")
# 월말 cron 이 달력 마지막 날 당일 도는 경우 = 통과여야 함(가드 도입 시 명시 계약)
expect_case("B4_month_end_cron_same_day", D("2026-06-30"), D("2026-06-30"), D("2026-06-30"),
            TRUE, "complete")
# 하루 전이면 아직 달력이 안 끝났다
expect_case("B5_one_day_before_cal_end", D("2026-06-30"), D("2026-06-29"), D("2026-06-30"),
            FALSE, "calendar_not_ended")
# 입력 타입 견고성: 문자·POSIXct 로 들어와도 같은 판정
expect_case("B6_character_input", "2026-06-30", D("2026-07-26"), "2026-06-30", TRUE, "complete")
expect_case("B7_posixct_input", as.POSIXct("2026-06-30 09:00:00", tz = "UTC"),
            D("2026-07-26"), as.POSIXct("2026-06-30 15:30:00", tz = "UTC"), TRUE, "complete")

cat("\n=== C. 크래시 축 — RAWDATA 그 달 부재/파손 입력 ===\n")
# max(빈 Date) = -Inf (그 달 데이터가 통째로 없을 때 실제로 나오는 값)
neg_inf_date <- suppressWarnings(max(as.Date(character(0))))
expect_case("C1_raw_month_missing_neg_inf", D("2026-06-30"), D("2026-07-26"), neg_inf_date,
            TRUE, "complete_calendar_only", note = "(-Inf 에서 죽지 않고 달력-only 후퇴)")
expect_case("C2_raw_month_NA", D("2026-06-30"), D("2026-07-26"), as.Date(NA),
            TRUE, "complete_calendar_only")
expect_case("C3_raw_month_NULL", D("2026-06-30"), D("2026-07-26"), NULL,
            TRUE, "complete_calendar_only")
# 실제 빌더의 조회 형태: 이름 없는 키 조회 → 이름 NA 인 Date NA
miss_key <- setNames(as.Date(c("2020-01-31")), "2020-01")["1999-13"]
expect_case("C4_map_lookup_miss", D("2026-06-30"), D("2026-07-26"), miss_key,
            TRUE, "complete_calendar_only")
# sig 자체가 파손 → fail-closed(완결로 밀어주지 않는다)
expect_case("C5_sig_NA_fail_closed", as.Date(NA), D("2026-07-26"), D("2026-06-30"),
            FALSE, "sig_date_invalid")
expect_case("C6_sig_empty_fail_closed", as.Date(character(0)), D("2026-07-26"), D("2026-06-30"),
            FALSE, "sig_date_invalid")
# -Inf 인데 달력도 안 끝났으면 여전히 미완결 (두 축이 독립인지)
expect_case("C7_neg_inf_but_month_open", D("2026-07-24"), D("2026-07-26"), neg_inf_date,
            FALSE, "calendar_not_ended")

cat("\n=== D. 차단 실효 — 구 guard(달력만)로 되돌리면 A가 뚫리는가 ===\n")
# 여기서 '구 guard' 를 주입한다. 이 케이스 집합이 신·구를 실제로 구분하지 못하면
# A 의 PASS 는 회귀를 못 잡는 공허한 통과다(검사가 잘못된 것을 재는 반복 부류).
.ic_pair_complete_calendar_only <- function(sig_d_t1, today, raw_month_last = NULL) {
  cal_end <- .ic_month_cal_end(as.Date(sig_d_t1))
  list(complete = !(cal_end > as.Date(today)), reason = "calendar_only")
}
disc <- character(0)
for (cs in list(list(id = "A1", v = A1), list(id = "A2", v = A2), list(id = "A3", v = A3))) {
  old <- .ic_pair_complete_calendar_only(cs$v$sig, cs$v$today)
  new <- .ic_pair_complete(cs$v$sig, today = cs$v$today, raw_month_last = cs$v$raw)
  if (isTRUE(old$complete) && !isTRUE(new$complete)) disc <- c(disc, cs$id)
}
if (length(disc) >= 2L) {
  ok("D1_old_guard_would_pass_these",
     sprintf("구 guard 가 통과시키는 케이스 %d건 검출: %s (신 guard 는 전부 차단)",
             length(disc), paste(disc, collapse = ",")))
} else {
  bad("D1_old_guard_would_pass_these",
      sprintf("구 guard 와 갈리는 케이스가 %d건뿐 — A 케이스가 회귀를 못 잡는다(공허한 통과)",
              length(disc)))
}
if (identical(sort(disc), c("A1", "A2"))) {
  ok("D2_discriminating_set_identity", "갈리는 케이스가 정확히 A1·A2 (파일-도달 조건 전담분)")
} else {
  bad("D2_discriminating_set_identity",
      sprintf("A1·A2 기대했으나 {%s} — 케이스 의미가 바뀌었다", paste(disc, collapse = ",")))
}

cat("\n=== E. 배선 — 빌더가 실제로 이 판정을 쓰는가 ===\n")
if (!file.exists(BUILDER_SRC)) {
  bad("E0_builder_present", sprintf("%s 부재", BUILDER_SRC))
} else {
  btxt <- readLines(BUILDER_SRC, warn = FALSE)
  code <- btxt[!grepl("^\\s*#", btxt)]

  if (any(grepl("ic_pair_completeness\\.R", code, fixed = FALSE))) {
    ok("E1_builder_sources_guard", "ic_pair_completeness.R source 배선 존재")
  } else {
    bad("E1_builder_sources_guard", "빌더가 판정 파일을 source 하지 않는다")
  }

  call_lines <- grep("\\.ic_pair_complete\\s*\\(", code)
  if (length(call_lines) >= 1L) {
    ok("E2_builder_calls_guard", sprintf("호출 %d곳", length(call_lines)))
  } else {
    bad("E2_builder_calls_guard", "빌더에 .ic_pair_complete() 호출 없음 — 가드 단절")
  }

  # 호출 결과로 실제 skip 하는가 (호출만 하고 결과를 버리면 무력화와 같다)
  used <- FALSE
  for (ln in call_lines) {
    win <- code[ln:min(length(code), ln + 8L)]
    if (any(grepl("\\$complete", win)) && any(grepl("^\\s*next\\s*$", win))) used <- TRUE
  }
  if (used) {
    ok("E3_result_gates_the_loop", "$complete 검사 후 next 로 pair skip")
  } else {
    bad("E3_result_gates_the_loop", "판정 결과가 skip 으로 이어지지 않는다 — 호출만 하고 버림")
  }

  # 인라인 판정 잔재가 남아 있으면 두 판정이 갈라진다(둘 중 하나만 고쳐지는 사고)
  if (any(grepl("cal_end_t1|\\.file_partial", code))) {
    bad("E4_no_inline_duplicate", "빌더에 구 인라인 판정 잔재(cal_end_t1/.file_partial) 존재")
  } else {
    ok("E4_no_inline_duplicate", "인라인 중복 판정 없음")
  }
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "ic_completion_guard", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
