#!/usr/bin/env Rscript
#==============================================================================
# test_dr_register_concurrency.R — 결정 레지스터 공용 claim + CAS 경합 시뮬레이션 (O0a · 설계 §3.1.1 "두 프로세스 동시 쓰기 → 유실 0")
#
#   K1 [양성] 프로세스 3개가 동시에 dr_open(사람 writer) · dr_record_machine(기계 writer)을 섞어 쓴다. 쓰기 창을 넓히려고 적재와 쓰기
#      사이에 지연(.pre_write_hook)을 넣는다 → 모든 id 가 남는다(유실 0) · 중복 0 · dr_load 성공 · 권한 결정 항목 불변.
#   K2 [돌연변이] 같은 부하에서 .dr_txn 을 잠금·CAS 없는 구판 모양(적재 → 수정 → 쓰기)으로 바꾼다 → 유실 > 0 이어야 한다
#      (= K1 의 '유실 0' 단정이 잠금을 실제로 재고 있다는 증거 · 발화 실증).
# 격리: 임시 root · 자식 Rscript 는 R_ENVIRON_USER=빈 파일 · QM_ROOT = 코드 루트(이 검사를 부른 루트) · 운영 레지스터 md5 불변.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
REAL <- file.path(ROOT, "06_Registry/decision_register.json")
real_md5 <- if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_
Sys.unsetenv(c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE", "QVEST_DR_CLAIM"))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
TMP <- normalizePath(tempdir(), winslash = "/")
EMPTY <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY)
RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
N_EACH <- 5L; N_PROC <- 3L; DELAY <- 0.25   # 경합 창을 넓히는 지연(초) — 구판 모양이면 창이 겹쳐 유실이 드러난다

mk_root <- function(tag) { d <- file.path(TMP, sprintf("drc_%s_%d", tag, Sys.getpid())); unlink(d, recursive = TRUE, force = TRUE)
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE); normalizePath(d, winslash = "/") }
seed <- function(R) {
  dr_open("REINFORCE-ORGANIC-AUTONOMY", "자율", c("승인"), "승인", "보류", character(0), source = "test", root = R)
  dr_resolve("REINFORCE-ORGANIC-AUTONOMY", "승인", decided_by = "dohoon", root = R, recorded_by = "Q(세션)", evidence = "픽스처")
}
# 자식 스크립트 — 결과(기록한 기계 id)와 완료 표식은 **자기 결과 파일**에 마지막에 쓴다(Windows 에서 stdout 리다이렉트 파일은 자식이 잡고 있다)
worker_src <- function(R, tag, mutant, res) c(
  'suppressPackageStartupMessages(library(jsonlite))',
  sprintf('invisible(capture.output(suppressMessages(source(%s))))', deparse(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))),
  if (mutant) c('.dr_txn <- function(root, what, mutate, create = FALSE, .pre_write_hook = NULL) {',
                '  orig <- dr_load(root, create = create); res <- mutate(orig); if (is.null(res)) return(invisible(NULL))',
                '  if (is.function(.pre_write_hook)) .pre_write_hook(dr_path(root)); .dr_write(res$obj, root); invisible(res$item) }') else character(0),
  sprintf('R <- %s; tag <- %s; hook <- function(p) Sys.sleep(%s); ids <- character(0)', deparse(R), deparse(tag), DELAY),
  sprintf('for (i in seq_len(%dL)) {', N_EACH),
  '  if (i %% 2L == 1L) dr_open(sprintf("P-%s-%02d", tag, i), "경합", "가", "", "현행", character(0), source = "race", root = R, .pre_write_hook = hook)',
  '  else { r <- dr_record_machine("organic_rollback", sprintf("race %s %02d", tag, i), sprintf("ptr#%s-%02d", tag, i), "u", root = R, .pre_write_hook = hook)',
  '         ids <- c(ids, paste("MACHINE", r$id)) }',
  '}',
  sprintf('writeLines(c(ids, "WORKER_DONE"), %s)', deparse(res)))
run_load <- function(R, mutant) {
  tg <- if (mutant) "m" else "p"; res <- character(0); lgs <- character(0)
  for (k in seq_len(N_PROC)) {
    f <- file.path(TMP, sprintf("drc_w_%s_%d.R", tg, k))
    o <- file.path(TMP, sprintf("drc_w_%s_%d.res", tg, k)); unlink(o); res <- c(res, o)
    lg <- file.path(TMP, sprintf("drc_w_%s_%d.log", tg, k)); lgs <- c(lgs, lg)
    writeLines(worker_src(R, sprintf("w%d", k), mutant, o), f, useBytes = TRUE)
    old <- Sys.getenv(c("R_ENVIRON_USER", "QM_ROOT"), unset = NA)
    Sys.setenv(R_ENVIRON_USER = EMPTY, QM_ROOT = ROOT)
    system2(RS, c("--no-environ", shQuote(f)), wait = FALSE, stdout = lg, stderr = lg)
    for (nm in names(old)) if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, as.list(old[nm]))
  }
  rd <- function(p) tryCatch(readLines(p, warn = FALSE), error = function(e) character(0))
  t0 <- Sys.time()
  repeat {
    done <- vapply(res, function(o) any(rd(o) == "WORKER_DONE"), logical(1))
    dead <- vapply(lgs, function(l) any(grepl("^Error|Execution halted", rd(l))), logical(1))
    if (all(done | dead) || as.numeric(difftime(Sys.time(), t0, units = "secs")) > 600) break
    Sys.sleep(1)
  }
  Sys.sleep(2)   # 자식 로그 핸들 해제 대기(Windows)
  list(done = done, txt = unlist(lapply(res, rd)), logs = unlist(lapply(lgs, rd)))
}
expected_ids <- function(txt) {
  opened <- unlist(lapply(seq_len(N_PROC), function(k) sprintf("P-w%d-%02d", k, seq(1L, N_EACH, by = 2L))))
  c(opened, sub("^MACHINE ", "", grep("^MACHINE ", txt, value = TRUE)))
}

cat("=== K1 [양성] 잠금 + CAS — 동시 쓰기 3프로세스 ===\n")
RA <- mk_root("pos"); seed(RA); auth0 <- dr_load(RA)$items[[1]]
ra <- run_load(RA, mutant = FALSE)
chk(all(ra$done) && !any(grepl("^Error", ra$logs)), "K1a 자식 3개 정상 종료(오류 0)",
    paste(utils::head(grep("Error|halted", ra$logs, value = TRUE), 3), collapse = " | "))
LA <- tryCatch(dr_load(RA), error = function(e) NULL)
exp_a <- expected_ids(ra$txt); got_a <- vapply((LA %||% list(items = list()))$items, function(x) x$id, character(1))
chk(!is.null(LA), "K1b dr_load 성공(파손·중복 id 없음)")
chk(length(exp_a) == N_PROC * N_EACH && all(exp_a %in% got_a),
    sprintf("K1c 유실 0 — 기대 %d건 전부 존재(사람 %d · 기계 %d)", N_PROC * N_EACH, N_PROC * ceiling(N_EACH / 2), N_PROC * floor(N_EACH / 2)),
    sprintf("기대 %d · 부재 %s", length(exp_a), paste(setdiff(exp_a, got_a), collapse = ",")))
chk(!anyDuplicated(got_a) && length(got_a) == 1L + length(exp_a), "K1d 중복 0 · 총 항목 = 권한 1 + 기대", sprintf("n=%d", length(got_a)))
chk(!is.null(LA) && identical(LA$items[[1]], auth0), "K1e 기존 항목(권한 결정) 비트 불변")
chk(!dir.exists(file.path(RA, ".cache/decision_register.claim")) || file.exists(file.path(RA, ".cache/decision_register.claim/released.json")),
    "K1f claim 해제(잔재 없음 또는 해제 표식)")

cat("\n=== K2 [돌연변이] 잠금·CAS 제거 — 같은 부하 ===\n")
RB <- mk_root("mut"); seed(RB)
rb <- run_load(RB, mutant = TRUE)
LB <- tryCatch(dr_load(RB), error = function(e) NULL)
got_b <- vapply((LB %||% list(items = list()))$items, function(x) x$id, character(1))
lost <- setdiff(expected_ids(rb$txt), got_b)
chk(length(lost) > 0L || is.null(LB),
    sprintf("K2 [돌연변이] 잠금·CAS 제거판 → 유실 %d건(또는 파손) = K1c 가 이 결함을 잡는다", length(lost)),
    "돌연변이인데 유실 0 — 부하가 경합을 못 만들었다(검사 무력)")

chk(identical(if (file.exists(REAL)) unname(tools::md5sum(REAL)) else NA_character_, real_md5), "Z1 운영 decision_register.json md5 전후 동일")
unlink(c(RA, RB), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"dr_register_concurrency","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
