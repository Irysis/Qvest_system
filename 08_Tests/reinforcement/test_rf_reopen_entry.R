#!/usr/bin/env Rscript
#==============================================================================
# test_rf_reopen_entry.R — 소진 entry 되살리기(사람 호출 writer) 단위 검사 (O0a · 2026-09-25 · 설계 §3 G6 · §3.3 · 헌M10)
#
#   R1 [양성] exhausted → active · reopened{at,reason,decision_id,from_status,exhausted_at,attempts_used,handed_off,promoted_to} ·
#      status·reopened **밖 필드 비트 불변**(다른 entry 포함) · handed_off·promoted_to 보존(재승격·재요약 방지)
#   R2 멱등 — 같은 decision_id 두 번째 호출은 쓰지 않는다(md5 불변 · status already)
#   R3 거부 — 다른 결정으로 active entry · graduated · parked · 없는 entry → stop · 원장 불변
#   R4 문맥 봉쇄 — QVEST_ORGANIC_CTX=1 · QVEST_UNATTENDED_LANE=1 → stop · 원장 불변(유기체는 원장을 쓰지 않는다)
#   R5 입력 — 사유 공백 · decision_id 형식 위반 → stop
#   R6 CAS — 적재 뒤 외부 writer(.pre_write_hook) → 덮어쓰지 않는다(외부 변경 보존)
#   R7 claim — 러너 claim(QVEST_RF_CLAIM) 경로를 잡았다 놓는다(잔재 없음)
#   X  돌연변이 — 멱등 분기 제거 → R2 red · 상태 검사 제거(graduated 되살림) → R3 red · 문맥 봉쇄 제거 → R4 red
#   (러너 종단 — 잘렸던 칸을 다음 tick 이 배치하는가 — 는 test_rf_trial_log_producers.R 의 P9 가 샌드박스 러너로 잰다)
# 격리: 임시 root · 운영 원장 md5 불변.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
REAL <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")
real_md5 <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
Sys.unsetenv(c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE"))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
TMP <- normalizePath(tempdir(), winslash = "/")
mk_root <- function(tag) {
  d <- file.path(TMP, sprintf("rre_%s_%d_%d", tag, Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
  writeLines("# marker", file.path(d, "02_Infrastructure/config.R"))
  ent <- function(bid, st, ...) c(list(base_id = bid, status = st, base_grade = "C", attempts_used = 3L, max_attempts = 35L,
    attempts = lapply(1:3, function(n) list(n = n, cell_code = sprintf("B1_%d", n), grade = "C", essence = list(port_t = 1 + n / 10, calmar = 0.3)))), list(...))
  L <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L,
            entries = list(ent("RP_EX", "exhausted", exhausted_at = "2026-09-25T10:00:00+0900", handed_off = TRUE, promoted_to = "RP_EX_promo1",
                               summarized_at = "2026-09-25T10:00:01+0900"),
                           ent("RP_ACT", "active"), ent("RP_GRAD", "graduated"), ent("RP_PARK", "parked", parked_reason = "도훈"),
                           ent("RP_EX_promo1", "active", parent = list(base_id = "RP_EX", depth = 1L))),
            combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = "")
  writeLines(toJSON(L, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(d, "06_Registry/reinforce_ledger_l1.json"))
  normalizePath(d, winslash = "/")
}
lp <- function(R) file.path(R, "06_Registry/reinforce_ledger_l1.json")
md5 <- function(R) unname(tools::md5sum(lp(R)))
ld <- function(R) fromJSON(lp(R), simplifyVector = FALSE)
en <- function(L, bid) Filter(function(e) identical(e$base_id, bid), L$entries)[[1]]
strip <- function(L, bid) { L$last_updated <- NULL; for (i in seq_along(L$entries)) if (identical(L$entries[[i]]$base_id, bid)) {
  L$entries[[i]]$status <- NULL; L$entries[[i]]$reopened <- NULL }; L }
q <- function(expr) invisible(capture.output(r <- force(expr)))
Sys.setenv(QVEST_RF_CLAIM = file.path(TMP, "rre_claim"))

cat("=== R1 [양성] ===\n")
R <- mk_root("r1"); L0 <- ld(R)
invisible(capture.output(r1 <- rf_reopen_entry(1L, "RP_EX", "유기체 절단 롤백(픽스처) — 잘린 칸을 되살린다", "M-ORG-20260925T120000000-1-abcdef", root = R)))
L1 <- ld(R); e1 <- en(L1, "RP_EX"); h <- e1$reopened[[1]]
chk(isTRUE(r1$written) && identical(e1$status, "active") && length(e1$reopened) == 1L && identical(h$decision_id, "M-ORG-20260925T120000000-1-abcdef") &&
      identical(h$from_status, "exhausted") && identical(h$exhausted_at, "2026-09-25T10:00:00+0900") && identical(as.integer(h$attempts_used), 3L) &&
      isTRUE(h$handed_off) && identical(h$promoted_to, "RP_EX_promo1"),
    "R1a exhausted → active · reopened 이력(결정 id · 이전 상태 · 소진 시각 · used · handed_off · promoted_to)")
chk(identical(strip(L1, "RP_EX"), strip(L0, "RP_EX")), "R1b status·reopened 밖 필드(다른 entry 포함) 비트 불변")
chk(isTRUE(e1$handed_off) && identical(e1$promoted_to, "RP_EX_promo1") && nzchar(e1$summarized_at %||% ""),
    "R1c handed_off·promoted_to·summarized_at 보존 — 다시 소진돼도 재승격·재요약 없음(이미 개시된 자식은 별개의 사실)")
chk(!dir.exists(file.path(TMP, "rre_claim")) || file.exists(file.path(TMP, "rre_claim/released.json")), "R7 러너 claim 을 잡았다 놓았다(잔재 없음)")

cat("\n=== R2 멱등 ===\n")
m0 <- md5(R)
invisible(capture.output(r2 <- rf_reopen_entry(1L, "RP_EX", "두 번째 호출", "M-ORG-20260925T120000000-1-abcdef", root = R)))
chk(!isTRUE(r2$written) && identical(r2$status, "already") && identical(md5(R), m0), "R2 같은 결정 두 번째 호출 → 쓰기 0(md5 불변 · already)")

cat("\n=== R3 거부 ===\n")
m1 <- md5(R)
e <- c(err_of(capture.output(rf_reopen_entry(1L, "RP_EX", "다른 결정", "DOHOON-X", root = R))),
       err_of(capture.output(rf_reopen_entry(1L, "RP_GRAD", "x", "D1", root = R))),
       err_of(capture.output(rf_reopen_entry(1L, "RP_PARK", "x", "D1", root = R))),
       err_of(capture.output(rf_reopen_entry(1L, "RP_NONE", "x", "D1", root = R))))
chk(all(!is.na(e)) && grepl("이미 active", e[1]) && grepl("graduated", e[2]) && grepl("parked", e[3]) && grepl("부재", e[4]) && identical(md5(R), m1),
    "R3 다른 결정의 active · graduated · parked · 없는 entry → 거부 · 원장 불변", paste(substr(e, 1, 50), collapse = " | "))

cat("\n=== R4 문맥 봉쇄 · R5 입력 ===\n")
Rb <- mk_root("r4"); mb <- md5(Rb)
for (v in c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE")) {
  do.call(Sys.setenv, stats::setNames(list("1"), v))
  m <- err_of(capture.output(rf_reopen_entry(1L, "RP_EX", "x", "D1", root = Rb)))
  Sys.unsetenv(v)
  chk(!is.na(m) && grepl(v, m) && identical(md5(Rb), mb), sprintf("R4 %s=1 → stop · 원장 불변", v), m)
}
e <- c(err_of(capture.output(rf_reopen_entry(1L, "RP_EX", "", "D1", root = Rb))),
       err_of(capture.output(rf_reopen_entry(1L, "RP_EX", "x", "bad id!", root = Rb))))
chk(all(!is.na(e)) && grepl("사유", e[1]) && grepl("형식", e[2]) && identical(md5(Rb), mb), "R5 사유 공백 · decision_id 형식 위반 → 거부")

cat("\n=== R6 CAS ===\n")
Rc <- mk_root("r6")
hook <- function(p) { j <- fromJSON(p, simplifyVector = FALSE); j$note_ext <- "외부 writer"; writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), p) }
m <- err_of(capture.output(rf_reopen_entry(1L, "RP_EX", "x", "D1", root = Rc, .pre_write_hook = hook)))
Lc <- ld(Rc)
chk(!is.na(m) && grepl("claim 밖", m) && identical(Lc$note_ext, "외부 writer") && identical(en(Lc, "RP_EX")$status, "exhausted"),
    "R6 적재 뒤 외부 writer → 덮어쓰지 않는다(외부 변경 보존 · entry 그대로 exhausted)", m)

cat("\n=== X 돌연변이 ===\n")
mut_fn <- function(f, from, to) { src <- deparse(f, width.cutoff = 500L); mut <- sub(from, to, src, fixed = TRUE)
  if (sum(src != mut) != 1L) return(NULL); g <- eval(parse(text = mut)); environment(g) <- environment(f); g }
g <- mut_fn(rf_reopen_entry, "if (!is.null(last) && identical(.rf_s1(last$decision_id), did)) {", "if (FALSE) {")
if (is.null(g)) ng("X1 돌연변이 주입 실패(멱등 줄)") else {
  Rx <- mk_root("x1"); invisible(capture.output(rf_reopen_entry(1L, "RP_EX", "x", "D1", root = Rx)))
  m <- err_of(capture.output(g(1L, "RP_EX", "x", "D1", root = Rx)))
  chk(!is.na(m) && grepl("이미 active", m), "X1 [돌연변이] 멱등 분기 제거 → 같은 결정 재호출이 오류 = R2 가 이 결함을 잡는다", m)
}
g <- mut_fn(rf_reopen_entry, 'if (!identical(st, "exhausted"))', "if (FALSE)")
if (is.null(g)) ng("X2 돌연변이 주입 실패(상태 검사 줄)") else {
  Rx2 <- mk_root("x2"); invisible(capture.output(m <- err_of(g(1L, "RP_GRAD", "x", "D1", root = Rx2))))
  chk(is.na(m) && identical(en(ld(Rx2), "RP_GRAD")$status, "active"), "X2 [돌연변이] 상태 검사 제거 → graduated 가 되살아난다 = R3 가 이 결함을 잡는다")
}
g <- mut_fn(rf_reopen_entry, "if (nzchar(v))", "if (FALSE)")
if (is.null(g)) ng("X3 돌연변이 주입 실패(문맥 줄)") else {
  Rx3 <- mk_root("x3"); Sys.setenv(QVEST_ORGANIC_CTX = "1")
  m <- err_of(capture.output(g(1L, "RP_EX", "x", "D1", root = Rx3))); Sys.unsetenv("QVEST_ORGANIC_CTX")
  chk(is.na(m) && identical(en(ld(Rx3), "RP_EX")$status, "active"), "X3 [돌연변이] 문맥 봉쇄 제거 → 유기체 문맥이 원장을 쓴다 = R4 가 이 결함을 잡는다")
}
Sys.unsetenv("QVEST_RF_CLAIM")
chk(identical(if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_, real_md5), "Z1 운영 원장 md5 전후 동일")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_reopen_entry","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
