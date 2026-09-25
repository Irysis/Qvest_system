#!/usr/bin/env Rscript
#==============================================================================
# test_mba_main_guard.R — measurement_basis_audit.R CLI 진입 가드 (2026-09-25 · QEPM 동결 잔여 수리 (5) · Q19 형제)
#
# 결함(샌드박스 실측): 구 가드 `if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0)` 은 "호출자 프로세스에
#   인자가 있는가"를 물었다. cert_backfill_audit.R 을 --dry-run/--auto 로 실행하면 .cba_load_resolver() 가 이 파일을 source 하고,
#   그 순간 본체가 돌아 args[1]("--dry-run")을 book_state 경로로 읽고 "Tier: BOOK_STATE_MISSING" 을 찍고 로그 파일을 덮어썼다
#   (운영이면 C: 루트의 measurement_coherence_health.log). 신판 = "Rscript 가 이 파일을 --file 로 실행했는가" ∧ 인자 ≥1.
#
# ★정본 무접촉: 정본 두 파일은 텍스트로 읽어 복제만 한다. 실행은 전부 tempdir 샌드박스(로그 경로도 샌드박스로 치환).
# ★"쓰기 0" 은 source 가 끝까지 돌았을 때만 증거다 — SOURCED_OK 표식 + exit 0 을 함께 단언한다.
#
# 축:
#   G1 호출자(인자 --auto)가 source            → 본체 미발화 · 로그 0 · source 완주
#   G2 호출자(인자 없음)가 source               → 미발화
#   I1 실 호출자 cert_backfill_audit.R --dry-run → 형제 본체 미발화('BOOK_STATE_MISSING' 0) · resolver 로드 성공
#   P1 양성 대조: 직접 실행 <book_state> <wt_root> → 본체 발화(배너·Tier) · 로그 기록
#   P2 직접 실행 인자 없음                       → 무동작(구판 동작 보존)
#   M1 위반 주입(구판 가드 `> 0`)                → G1·I1 술어 red(구 사고 재현)
#   M2 돌연변이(--file 정체 판정 제거)            → G1 술어 red
#
# 요약 규약: 마지막 줄 {"test":"mba_main_guard","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

.MBA <- "02_Infrastructure/portfolio/measurement_basis_audit.R"
.CBA <- "02_Infrastructure/ops/cert_backfill_audit.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE); m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return(""); dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MBA))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_mba_main_guard] PROJECT_ROOT 해석 실패 — 표지 부재")

PASS <- 0L; FAIL <- 0L
ok  <- function(n) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s  (%s)\n", n, d)) }

RSCRIPT <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
SRC_M <- readLines(file.path(PROJ, .MBA), warn = FALSE, encoding = "UTF-8")
SRC_C <- readLines(file.path(PROJ, .CBA), warn = FALSE, encoding = "UTF-8")
BANNER <- "=== Measurement Coherence Health ==="
MISFIRE <- "Tier: BOOK_STATE_MISSING"
# 로그 경로 줄은 정본에서 재도출(경로 리터럴을 검사에 복제하지 않는다 — r-portability 금칙 ③)
RX_MLOG <- '^  log_path <- "'
RX_CLOG <- '^LOG_PATH <- "'
# 가드 줄 = CLI 본체 첫 줄(args <- commandArgs(trailingOnly = TRUE)) 바로 위의 if 줄 — 문구가 아니라 위치로 찾는다
guard_idx <- function(src) {
  i <- which(src == "  args <- commandArgs(trailingOnly = TRUE)")
  if (length(i) == 1L && i > 1L && grepl("^if \\(.*\\) \\{", src[i - 1L])) i - 1L else integer(0)
}
GUARD_OLD <- "if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {"

BASE <- file.path(tempdir(), paste0("mba_guard_", Sys.getpid()))
unlink(BASE, recursive = TRUE); dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(BASE, recursive = TRUE)   # top-level on.exit 금지(금칙②)
fwd <- function(p) gsub("\\\\", "/", p)

cat("=== test_mba_main_guard (샌드박스) ===\n")

mk_sandbox <- function(tag, mutate = NULL) {
  sb <- file.path(BASE, tag)
  for (d in c("02_Infrastructure/portfolio", "02_Infrastructure/ops", "qepm/mailbox/governor", "qepm/mailbox/worktask"))
    dir.create(file.path(sb, d), recursive = TRUE, showWarnings = FALSE)
  m <- SRC_M; c2 <- SRC_C
  im <- grep(RX_MLOG, m); ic <- grep(RX_CLOG, c2); ig <- guard_idx(m)
  if (length(im) != 1L || length(ic) != 1L || length(ig) != 1L) return(NULL)
  m[im]  <- sprintf('  log_path <- "%s"', fwd(file.path(sb, "mba.log")))
  c2[ic] <- sprintf('LOG_PATH <- "%s"', fwd(file.path(sb, "cba.log")))
  if (!is.null(mutate)) { m <- mutate(m, ig); if (is.null(m)) return(NULL) }
  writeLines(m, file.path(sb, .MBA), useBytes = TRUE)
  writeLines(c2, file.path(sb, .CBA), useBytes = TRUE)
  writeLines('{"admitted_ids": ["STR_QA_GUARD"]}', file.path(sb, "qepm/mailbox/governor/book_state.json"))
  writeLines('{"retroactive_cert_issuances": [], "events": []}', file.path(sb, "qepm/mailbox/governor/governance_log.json"))
  writeLines(c(sprintf('source("%s")', .MBA), 'cat(if (exists(".lineage_related")) "RESOLVER_OK\\n" else "RESOLVER_MISSING\\n")',
               'cat("SOURCED_OK\\n")'), file.path(sb, "driver_source.R"))
  sb
}

probe <- function(sb, script, args = character(0)) {
  lg <- file.path(sb, "mba.log"); if (file.exists(lg)) unlink(lg)
  owd <- setwd(sb); on.exit(setwd(owd), add = TRUE)
  keys <- c("CLAUDE_PROJECT_DIR", "QM_ROOT"); old <- Sys.getenv(keys, unset = NA)
  Sys.setenv(CLAUDE_PROJECT_DIR = fwd(sb), QM_ROOT = fwd(sb))   # 형제 탐색 폴백도 샌드박스로
  on.exit(for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)), add = TRUE)
  out <- suppressWarnings(system2(RSCRIPT, c(script, args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); st <- if (is.null(st)) 0L else as.integer(st)
  list(status = st, out = out, banner = any(grepl(BANNER, out, fixed = TRUE)),
       misfire = any(grepl(MISFIRE, out, fixed = TRUE)), tier = any(grepl("^Tier: ", out)),
       sourced_ok = any(grepl("SOURCED_OK", out, fixed = TRUE)), resolver_ok = any(grepl("RESOLVER_OK", out, fixed = TRUE)),
       log_written = file.exists(lg))
}
tail2 <- function(r) paste(utils::tail(r$out, 2), collapse = " | ")
g1_clean <- function(r) r$status == 0L && r$sourced_ok && r$resolver_ok && !r$banner && !r$log_written
i1_clean <- function(r) r$status == 0L && !r$misfire && !any(grepl("lineage resolver 로드 실패", r$out, fixed = TRUE))

sb <- mk_sandbox("new")
if (is.null(sb)) {
  bad("F0 픽스처", "정본에 로그 경로 줄 또는 CLI 본체 위 가드 줄이 정확히 1개가 아니다 — 구조가 바뀌었으면 이 검사도 옮겨라")
} else {
  ok("F0 픽스처 — 로그 경로·CLI 가드 표지 각 1줄(두 정본)")
  r <- probe(sb, "driver_source.R", "--auto")
  if (g1_clean(r)) ok("G1 호출자(인자 --auto)가 source → 본체 미발화 · 로그 0 · resolver 로드 · source 완주")
  else bad("G1 호출자 인자 --auto", sprintf("status=%d banner=%s log=%s resolver=%s · %s", r$status, r$banner, r$log_written, r$resolver_ok, tail2(r)))
  r <- probe(sb, "driver_source.R")
  if (g1_clean(r)) ok("G2 호출자(인자 없음)가 source → 미발화") else bad("G2 호출자 인자 없음", tail2(r))
  r <- probe(sb, .CBA, "--dry-run")
  if (i1_clean(r)) ok("I1 실 호출자 cert_backfill_audit.R --dry-run → 형제 본체 미발화(BOOK_STATE_MISSING 0) · resolver 폴백 경고 0")
  else bad("I1 cert_backfill --dry-run", sprintf("status=%d misfire=%s · %s", r$status, r$misfire, tail2(r)))
  r <- probe(sb, .MBA, c("qepm/mailbox/governor/book_state.json", "qepm/mailbox/worktask"))
  if (r$status == 0L && r$banner && r$tier && !r$misfire && r$log_written) ok("P1 직접 실행 <book_state> <wt_root> → 본체 발화 · Tier · 로그 기록(CLI 경로 생존)")
  else bad("P1 직접 실행", sprintf("status=%d banner=%s tier=%s log=%s · %s", r$status, r$banner, r$tier, r$log_written, tail2(r)))
  r <- probe(sb, .MBA)
  if (r$status == 0L && !r$banner && !r$log_written) ok("P2 직접 실행 인자 없음 → 무동작(구판 동작 보존)")
  else bad("P2 직접 실행 인자 없음", sprintf("status=%d banner=%s · %s", r$status, r$banner, tail2(r)))
}

# M1 — 위반 주입: 구판 가드(`> 0`) → 인자를 받은 호출자의 source 로 본체 발화 + 실 호출자에서 BOOK_STATE_MISSING 재현
sb1 <- mk_sandbox("m1_old", function(src, i) { src[i] <- GUARD_OLD; src })
if (is.null(sb1)) bad("M1 픽스처", "구판 가드 주입 실패") else {
  r <- probe(sb1, "driver_source.R", "--auto"); r2 <- probe(sb1, .CBA, "--dry-run")
  if (!g1_clean(r) && r$banner && r$log_written && !i1_clean(r2) && r2$misfire)
    ok("M1 구판 가드 주입 → G1 red(배너·로그) + I1 red('Tier: BOOK_STATE_MISSING') — 구 결함 재현")
  else bad("M1 구판 가드 주입", sprintf("재현 실패 — G1 banner=%s log=%s · I1 misfire=%s", r$banner, r$log_written, r2$misfire))
}
# M2 — 돌연변이: --file 정체 판정 제거(--file 이 있기만 하면 참) → 호출자 source 시 발화
ID_RX <- 'identical\\(basename\\(gsub\\(.*"measurement_basis_audit\\.R"\\)'
sb2 <- mk_sandbox("m2_noid", function(src, i) {
  j <- grep(ID_RX, src)
  if (length(j) != 1L) return(NULL)
  src[j] <- sub(" && identical\\(basename\\(.*$", "", src[j]); src })
if (is.null(sb2)) bad("M2 픽스처", "--file 정체 판정 줄을 찾지 못함 — 신판 판정식이 바뀌었으면 이 검사도 옮겨라") else {
  r <- probe(sb2, "driver_source.R", "--auto")
  if (!g1_clean(r) && r$banner) ok("M2 --file 정체 판정 제거 → 호출자 source 시 발화 (G1 술어 red)")
  else bad("M2 --file 정체 판정 제거", sprintf("발화 안 함 — G1 이 판별력 없음 · banner=%s · %s", r$banner, tail2(r)))
}

.cleanup()
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"mba_main_guard","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
