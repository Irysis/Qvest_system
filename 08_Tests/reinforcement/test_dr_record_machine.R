#!/usr/bin/env Rscript
#==============================================================================
# test_dr_record_machine.R — 결정 레지스터 G7 재설계 (O0a · 2026-09-25 · 설계 organic_design_final §3.1.1)
#
# 계약(reinforce_ledger.R):
#   M  dr_record_machine — 포인터 행 1개(status resolved · owner/decided_by/recorded_by = machine:organic · record_class machine ·
#      M-ORG- id) · scope 허용목록 밖 거부 · 헌법 경계 대상(tier_graduation·fixed_axes·pit·book·a_eligibility·D-*) 거부 ·
#      권한 결정(REINFORCE-ORGANIC-AUTONOMY) 미충족 거부 · 주간 상한(상한 도달 = overflow 1행 · 그 뒤 0행) · dr_load 성공 ·
#      부팅 Director 판독(open 수) 불변(기계 행은 resolved)
#   N  네임스페이스 — dr_open 이 M-ORG- 접두·machine: owner 거부 · 기계 id 중복 주입 → 쓰기 전 거부(레지스터 불변)
#   C  문맥 봉쇄 — QVEST_ORGANIC_CTX=1 · QVEST_UNATTENDED_LANE=1 에서 dr_open/dr_resolve stop(decided_by="dohoon" 이어도) ·
#      dr_resolve(recorded_by="machine:x") 거부
#   E  증거 규칙(dr_evidence_ok) — 운영 레지스터 사본: 경계 = evidence 필드가 처음 나타난 항목(기계 행 제외)의 registered_at 재도출 ·
#      09-23 일괄 결정(evidence 필드 없음 · note 있음) = legacy 통과 · 경계 뒤 evidence 없는 항목 = 거부 · 기계 행·recorded_by machine:·
#      owner≠dohoon · open = 거부 · 사본 무수정(md5)
#   P  전후 대조·CAS — 쓰기 중 외부 writer 주입(.pre_write_hook) → CAS 재시도 후 반영 · 끝까지 바뀌면 거부 · 쓰기 뒤 대상 밖 항목 변조
#      주입 → 원본 복원 + stop · 돌연변이(전후 대조 제거 / CAS 제거 / 문맥 봉쇄 제거 / M-ORG 거부 제거) → 해당 단정 red
# 격리: 임시 root 만 쓴다 · 운영 decision_register.json md5 전후 동일.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
REAL <- file.path(ROOT, "06_Registry/decision_register.json")
real_md5 <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
Sys.unsetenv(c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE", "QVEST_DR_CLAIM"))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
mk_root <- function(tag) { d <- file.path(tempdir(), sprintf("drm_%s_%d_%d", tag, Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE); normalizePath(d, winslash = "/") }
seed_auth <- function(R, evidence = "도훈 채팅 응답(픽스처)") {
  dr_open("REINFORCE-ORGANIC-AUTONOMY", "자율", c("승인", "보류"), "승인", "보류", character(0), source = "test", root = R)
  dr_resolve("REINFORCE-ORGANIC-AUTONOMY", "승인", decided_by = "dohoon", root = R, recorded_by = "Q(세션)", evidence = evidence)
}
nitems <- function(R) length(dr_load(R)$items)
n_open <- function(R) sum(vapply(dr_load(R)$items, function(x) identical(x$status, "open"), logical(1)))

cat("=== M dr_record_machine ===\n")
R1 <- mk_root("m"); seed_auth(R1)
dr_open("DR-OPEN-1", "대기 1", "가", "가", "현행", character(0), source = "test", root = R1)
open0 <- n_open(R1); n0 <- nitems(R1)
r <- dr_record_machine("organic_policy_transition", "π_dorm shadow→live(픽스처)", "06_Registry/organic/decisions.jsonl#d1",
                       "Rscript 02_Infrastructure/ops/rf_organic_cmd.R rollback d1", root = R1, targets = c("space:B2"))
L <- dr_load(R1); it <- L$items[[length(L$items)]]
chk(isTRUE(r$written) && nitems(R1) == n0 + 1L && startsWith(it$id, "M-ORG-") && identical(it$status, "resolved") &&
      identical(it$owner, "machine:organic") && identical(it$decided_by, "machine:organic") && identical(it$recorded_by, "machine:organic") &&
      identical(it$record_class, "machine") && identical(it$evidence, "06_Registry/organic/decisions.jsonl#d1"),
    "M1 포인터 행 1개 · M-ORG- id · resolved · owner/decided_by/recorded_by = machine:organic · evidence = 포인터", it$id %||% "")
chk(grepl("^M-ORG-[0-9]{8}T[0-9]{9}-[0-9]+-[0-9a-f]{6}$", it$id), "M2 id 형식 M-ORG-<yyyymmddTHHMMSSmmm>-<순번>-<해시6>", it$id)
chk(n_open(R1) == open0, "M3 부팅 Director 판독(open 수) 불변 — 기계 행은 대기 결정이 아니다", sprintf("%d→%d", open0, n_open(R1)))
chk(is.list(dr_load(R1)), "M4 dr_load 성공(DR_STATUS_ENUM 안 · 중복 id 없음)")
for (bad in c("organic_budget_raise", "tier_graduation"))
  { m <- err_of(dr_record_machine(bad, "x", "p", "u", root = R1)); chk(!is.na(m) && grepl("scope 밖", m), sprintf("M5 scope 밖 kind=%s 거부", bad), m) }
for (tg in c("tier_graduation", "fixed_axes.n_max", "pit_quarantine", "book:BOOK_0001", "a_eligibility_gate", "D-E"))
  { m <- err_of(dr_record_machine("organic_structure_change", "x", "p", "u", root = R1, targets = tg))
    chk(!is.na(m) && grepl("금지 대상", m), sprintf("M6 헌법 경계 대상 %s 거부", tg), m) }
chk(nitems(R1) == n0 + 1L, "M7 거부 경로는 레지스터 불변")
R2 <- mk_root("m2")
dr_open("REINFORCE-ORGANIC-AUTONOMY", "자율", c("승인"), "승인", "보류", character(0), source = "test", root = R2)
m <- err_of(dr_record_machine("organic_kill", "K1", "p", "u", root = R2))
chk(!is.na(m) && grepl("권한", m) && grepl("not_resolved", m), "M8 권한 결정 open → 거부", m)
R2b <- mk_root("m2b"); seed_auth(R2b, evidence = NULL)
m <- err_of(dr_record_machine("organic_kill", "K1", "p", "u", root = R2b))
chk(!is.na(m) && grepl("evidence_empty", m), "M9 권한 결정 evidence 없음(경계 뒤 · 레거시 아님) → 거부", m)
R3 <- mk_root("m3"); seed_auth(R3)
w <- lapply(1:4, function(i) dr_record_machine("organic_rollback", sprintf("rb %d", i), sprintf("ptr#%d", i), "u", root = R3, max_rows_week = 2L))
mach <- Filter(function(x) identical(x$record_class, "machine"), dr_load(R3)$items)
chk(identical(vapply(w, function(z) isTRUE(z$written), logical(1)), c(TRUE, TRUE, TRUE, FALSE)) && length(mach) == 3L &&
      isTRUE(mach[[3]]$overflow) && !isTRUE(mach[[1]]$overflow) && isTRUE(w[[4]]$overflow),
    "M10 주간 상한 2 → 정상 2행 + '외 n건' overflow 1행 · 그 뒤 0행(jsonl 이 정본)", sprintf("written=%s n=%d", paste(vapply(w, function(z) isTRUE(z$written), logical(1)), collapse = ","), length(mach)))

cat("\n=== N 네임스페이스 · 중복 id ===\n")
m <- err_of(dr_open("M-ORG-20260925T000000000-1-abcdef", "t", "가", "", "현행", character(0), source = "test", root = R1))
chk(!is.na(m) && grepl("네임스페이스", m), "N1 dr_open 이 M-ORG- 접두 거부", m)
m <- err_of(dr_open("DR-X", "t", "가", "", "현행", character(0), owner = "machine:organic", source = "test", root = R1))
chk(!is.na(m) && grepl("machine", m), "N2 dr_open 이 owner=machine:* 거부", m)
md5b <- unname(tools::md5sum(dr_path(R1)))
real_uid <- .rf_uid; mid_dup <- dr_load(R1)$items[[length(dr_load(R1)$items)]]$id
.rf_uid <- function(prefix, payload = "") if (identical(prefix, DR_MACHINE_PREFIX)) mid_dup else real_uid(prefix, payload)
m <- err_of(dr_record_machine("organic_kill", "dup", "p", "u", root = R1))
.rf_uid <- real_uid
chk(!is.na(m) && grepl("충돌", m) && identical(unname(tools::md5sum(dr_path(R1))), md5b), "N3 기계 id 중복 주입 → 쓰기 전 거부 · 레지스터 불변(dr_load 동반 사망 방지)", m)
ids500 <- replicate(500, .rf_uid(DR_MACHINE_PREFIX, "same"))
chk(!anyDuplicated(ids500), "N4 같은 payload 500연속 id 유일(밀리초+순번+해시)")

cat("\n=== C 문맥 봉쇄 ===\n")
dr_open("DR-C", "t", "가", "", "현행", character(0), source = "test", root = R1)
for (v in c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE")) {
  do.call(Sys.setenv, stats::setNames(list("1"), v))
  m1 <- err_of(dr_resolve("DR-C", "가", decided_by = "dohoon", root = R1))
  m2 <- err_of(dr_open("DR-C2", "t", "가", "", "현행", character(0), source = "test", root = R1))
  Sys.unsetenv(v)
  chk(!is.na(m1) && grepl(v, m1) && !is.na(m2) && grepl(v, m2), sprintf("C1 %s=1 → dr_resolve(decided_by=dohoon)·dr_open stop", v), paste(m1, m2))
}
chk(identical(dr_load(R1)$items[[which(vapply(dr_load(R1)$items, function(x) x$id, character(1)) == "DR-C")]]$status, "open"),
    "C2 문맥 봉쇄 뒤 DR-C 는 여전히 open(쓰기 0)")
m <- err_of(dr_resolve("DR-C", "가", decided_by = "dohoon", root = R1, recorded_by = "machine:organic"))
chk(!is.na(m) && grepl("machine", m), "C3 dr_resolve(recorded_by=machine:*) 거부", m)
dr_resolve("DR-C", "가", decided_by = "dohoon", root = R1, recorded_by = "Q(세션)", evidence = "도훈 채팅")
chk(isTRUE(dr_evidence_ok("DR-C", R1)$ok), "C4 [양성] 일반 문맥 dr_resolve 는 그대로 동작 · 증거 규칙 통과")

cat("\n=== E 증거 규칙 (운영 레지스터 사본) ===\n")
if (!file.exists(REAL)) ng("E 운영 레지스터 사본 부재", REAL) else {
  R4 <- mk_root("e"); file.copy(REAL, dr_path(R4)); md5_c <- unname(tools::md5sum(dr_path(R4)))
  Lr <- dr_load(R4)
  ts <- function(s) as.POSIXct(as.character(s %||% ""), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  hum <- Filter(function(x) !identical(x$record_class %||% "", "machine") && "evidence" %in% names(x), Lr$items)
  first_ev <- hum[[which.min(vapply(hum, function(x) as.numeric(ts(x$registered_at)), numeric(1)))]]
  e0 <- dr_evidence_ok(first_ev$id, R4)
  chk(isTRUE(e0$ok) && identical(e0$boundary, format(ts(first_ev$registered_at), "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")),
      sprintf("E1 경계 재도출 = evidence 필드 첫 항목 %s 의 registered_at(%s)", first_ev$id, first_ev$registered_at %||% ""), e0$boundary)
  legacy <- Filter(function(x) identical(x$status, "resolved") && identical(x$owner, "dohoon") && identical(x$decided_by, "dohoon") &&
                     !("evidence" %in% names(x)) && nzchar(x$note %||% "") && isTRUE(ts(x$registered_at) < ts(first_ev$registered_at)), Lr$items)
  lg_ok <- vapply(legacy, function(x) { z <- dr_evidence_ok(x$id, R4); isTRUE(z$ok) && isTRUE(z$legacy) }, logical(1))
  de <- Filter(function(x) grepl("^D-[A-M]$", x$id), legacy)
  chk(length(legacy) >= 1L && all(lg_ok) && length(de) >= 1L,
      sprintf("E2 09-23 일괄 결정(evidence 필드 없음 · note 있음 · 경계 이전) %d건 전부 legacy 통과 · D-A~D-M %d건 포함", length(legacy), length(de)),
      paste(vapply(legacy[!lg_ok], function(x) x$id, character(1)), collapse = ","))
  for (did in c("REINFORCE-ORGANIC-AUTONOMY", "ORGANIC-DE", "B3-STRUCTURAL-TRIM"))
    if (did %in% vapply(Lr$items, function(x) x$id, character(1))) {
      z <- dr_evidence_ok(did, R4); chk(isTRUE(z$ok) && !isTRUE(z$legacy), sprintf("E3 %s — evidence 필드로 통과(레거시 아님)", did), z$why) }
  # 위반 주입(사본): 경계 뒤 evidence 없는 도훈 항목 · recorded_by machine · owner 위조 · open
  L2 <- Lr; now <- format(Sys.time() + 60, "%Y-%m-%dT%H:%M:%S%z")
  add <- function(id, ...) { x <- list(id = id, title = "inj", status = "resolved", opened_at = now, options = list("가"), recommendation = "",
                                       default_until_decided = "", blocks = list(), owner = "dohoon", source = "inj", decision = "가",
                                       decided_by = "dohoon", decided_at = now, note = "노트만", registered_at = now)
    a <- list(...); for (k in names(a)) x[[k]] <- a[[k]]; x }
  L2$items <- c(L2$items, list(add("INJ-NOEV"), add("INJ-RBM", recorded_by = "machine:organic", evidence = "x"),
                               add("INJ-OWN", owner = "q", decided_by = "q", evidence = "x"), add("INJ-OPEN", status = "open", evidence = "x"),
                               add("INJ-MROW", record_class = "machine", evidence = "x")))
  writeLines(toJSON(L2, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), dr_path(R4))
  why <- vapply(c("INJ-NOEV", "INJ-RBM", "INJ-OWN", "INJ-OPEN", "INJ-MROW"), function(i) { z <- dr_evidence_ok(i, R4); if (isTRUE(z$ok)) "PASS" else z$why }, character(1))
  chk(identical(unname(why), c("evidence_empty", "recorded_by_machine", "owner:q", "not_resolved", "machine_row")),
      "E4 위반 주입 5종(경계 뒤 note 만 · recorded_by machine · owner 위조 · open · 기계 행) 전부 거부", paste(names(why), why, sep = "=", collapse = " "))
  chk(!isTRUE(dr_evidence_ok("M-ORG-20260925T000000000-1-abcdef", R4)$ok), "E5 M-ORG- id 는 참조 결정이 될 수 없다")
}

cat("\n=== P 전후 대조 · CAS ===\n")
R5 <- mk_root("p"); seed_auth(R5)
dr_open("DR-P1", "t", "가", "", "현행", character(0), source = "test", root = R5)
fired <- 0L
hook1 <- function(p) { if (fired == 0L) { fired <<- 1L; j <- fromJSON(p, simplifyVector = FALSE); j$note <- paste0(j$note, " (외부 writer)")
  writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), p) } }
r5 <- dr_record_machine("organic_kill", "K1 드릴", "ptr#k1", "u", root = R5, .pre_write_hook = hook1)
L5 <- dr_load(R5)
chk(isTRUE(r5$written) && grepl("외부 writer", L5$note) && identical(L5$items[[length(L5$items)]]$id, r5$id),
    "P1 쓰기 직전 외부 writer 주입 → CAS 가 감지 · 재적재 후 반영(외부 변경 보존 · 유실 0)", r5$id %||% "")
hook_always <- function(p) { j <- fromJSON(p, simplifyVector = FALSE); j$note <- paste0(j$note, "+"); writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), p) }
n5 <- nitems(R5)
m <- err_of(dr_record_machine("organic_kill", "K1 드릴2", "ptr#k2", "u", root = R5, .pre_write_hook = hook_always))
chk(!is.na(m) && grepl("CAS", m) && nitems(R5) == n5, "P2 CAS 매번 실패(DR_CAS_TRIES) → 거부 · 기계 행 0 추가", m)
# 쓰기 뒤 대상 밖 항목 변조 — qvest_atomic_write_json 을 감싸 다른 항목을 바꿔 쓰게 한다(쓰기 경로 결함 주입)
R6 <- mk_root("p6"); seed_auth(R6); dr_open("DR-P6", "원문 제목", "가", "", "현행", character(0), source = "test", root = R6)
raw6 <- readBin(dr_path(R6), "raw", file.info(dr_path(R6))$size)
real_aw <- qvest_atomic_write_json
qvest_atomic_write_json <- function(obj, path, ...) { for (k in seq_along(obj$items)) if (identical(obj$items[[k]]$id, "DR-P6")) obj$items[[k]]$title <- "변조"; real_aw(obj, path, ...) }
m <- tryCatch({ dr_record_machine("organic_rollback", "rb", "ptr#r", "u", root = R6); NA_character_ }, dr_postcheck_failed = function(e) conditionMessage(e), error = function(e) paste("다른 오류:", conditionMessage(e)))
qvest_atomic_write_json <- real_aw
chk(!is.na(m) && grepl("전후 대조", m) && identical(readBin(dr_path(R6), "raw", file.info(dr_path(R6))$size), raw6),
    "P3 쓰기 뒤 대상 밖 항목 변조 → dr_postcheck_failed · 원본 바이트 복원", m)
chk(!length(list.files(file.path(R6, ".cache"), recursive = TRUE, all.files = TRUE)) || !dir.exists(file.path(R6, ".cache/decision_register.claim")),
    "P4 claim 해제(잔재 디렉터리 없음)")

cat("\n=== X 돌연변이 — 장치 제거판에서 위 단정이 red 가 되는가 ===\n")
mut_fn <- function(f, from, to) { src <- deparse(f, width.cutoff = 500L); mut <- sub(from, to, src, fixed = TRUE)
  if (sum(src != mut) != 1L) return(NULL); g <- eval(parse(text = mut)); environment(g) <- environment(f); g }
# X1 전후 대조 제거 → P3 가 통과되지 않아야(변조가 남는다)
g <- mut_fn(.dr_txn, "if (!ok) {", "if (FALSE) {")
if (is.null(g)) ng("X1 돌연변이 주입 실패(전후 대조 줄)") else {
  R7 <- mk_root("x1"); seed_auth(R7); dr_open("DR-P6", "원문 제목", "가", "", "현행", character(0), source = "test", root = R7)
  keep <- .dr_txn; .dr_txn <- g
  qvest_atomic_write_json <- function(obj, path, ...) { for (k in seq_along(obj$items)) if (identical(obj$items[[k]]$id, "DR-P6")) obj$items[[k]]$title <- "변조"; real_aw(obj, path, ...) }
  m <- err_of(dr_record_machine("organic_rollback", "rb", "ptr#r", "u", root = R7))
  qvest_atomic_write_json <- real_aw; .dr_txn <- keep
  t7 <- Filter(function(x) identical(x$id, "DR-P6"), dr_load(R7)$items)[[1]]$title
  chk(is.na(m) && identical(t7, "변조"), "X1 [돌연변이] 전후 대조 제거 → 대상 밖 변조가 남는다 = P3 가 이 결함을 잡는다", t7)
}
# X2 CAS 제거 → 외부 writer 변경이 덮여 사라진다(P1 red)
g <- mut_fn(.dr_txn, "if (!identical(md5_a, md5_b)) {", "if (FALSE) {")
if (is.null(g)) ng("X2 돌연변이 주입 실패(CAS 줄)") else {
  R8 <- mk_root("x2"); seed_auth(R8); fired <- 0L
  keep <- .dr_txn; .dr_txn <- g
  dr_record_machine("organic_kill", "K1", "ptr#k1", "u", root = R8, .pre_write_hook = hook1)
  .dr_txn <- keep
  chk(!grepl("외부 writer", dr_load(R8)$note %||% ""), "X2 [돌연변이] CAS 제거 → 외부 writer 변경 유실 = P1 이 이 결함을 잡는다")
}
# X3 문맥 봉쇄 제거 → 무인 문맥 dr_resolve 가 통과(C1 red)
g <- mut_fn(.dr_ctx_guard, "if (nzchar(v))", "if (FALSE)")
if (is.null(g)) ng("X3 돌연변이 주입 실패(봉쇄 줄)") else {
  R9 <- mk_root("x3"); dr_open("DR-C", "t", "가", "", "현행", character(0), source = "test", root = R9)
  keep <- .dr_ctx_guard; .dr_ctx_guard <- g; Sys.setenv(QVEST_UNATTENDED_LANE = "1")
  m <- err_of(dr_resolve("DR-C", "가", decided_by = "dohoon", root = R9))
  Sys.unsetenv("QVEST_UNATTENDED_LANE"); .dr_ctx_guard <- keep
  chk(is.na(m), "X3 [돌연변이] 문맥 봉쇄 제거 → 무인 레인이 도훈 결정을 대신 적는다 = C1 이 이 결함을 잡는다", m)
}
# X4 M-ORG 거부 제거 → dr_open 이 기계 네임스페이스로 쓴다(N1 red)
g <- mut_fn(dr_open, "if (startsWith(id, DR_MACHINE_PREFIX))", "if (FALSE)")
if (is.null(g)) ng("X4 돌연변이 주입 실패(네임스페이스 줄)") else {
  R10 <- mk_root("x4")
  m <- err_of(g("M-ORG-20260925T000000000-1-abcdef", "t", "가", "", "현행", character(0), source = "test", root = R10))
  chk(is.na(m), "X4 [돌연변이] M-ORG- 거부 제거 → 사람 writer 가 기계 id 로 쓴다 = N1 이 이 결함을 잡는다", m)
}

cat("\n=== Z 운영 무접촉 ===\n")
chk(identical(if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_, real_md5), "Z1 운영 decision_register.json md5 전후 동일")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"dr_record_machine","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
