#!/usr/bin/env Rscript
#==============================================================================
# test_cert_backfill_main_guard.R — Q19 (QEPM 감사 2026-09-25 · 도훈 QEPM-IMMEDIATE-FIXES)
#
# 대상: 02_Infrastructure/ops/cert_backfill_audit.R 의 CLI 진입 가드.
#   구판 `if (!interactive() && length(commandArgs(trailingOnly = TRUE)) >= 0)` 은 **항상 참**이라
#   이 파일을 source 한 08_Tests/integration/test_execution_path_unified.R 이 배터리마다 --auto 본체를
#   돌렸다 → 운영 qepm/mailbox/governor/governance_log.json 에 RETROACTIVE_CERT_ISSUANCE append +
#   governance_log.json.bak.<ts> 생성(08-16~09-24 · 109개).
#   신판 = "Rscript 가 이 파일을 --file 로 실행했는가"(.cba_is_cli_main) + QVEST_CERT_BACKFILL_NO_MAIN=1.
#
# ★정본 무접촉: 정본 파일은 **텍스트로 읽어 복제만** 한다. 실행은 전부 tempdir 샌드박스 루트
#   (LOG_PATH 도 샌드박스로 치환 — 구판 /tmp 로그에 섞지 않는다). 운영 경로를 읽거나 쓰지 않는다.
# ★"쓰기 0" 은 **source 가 끝까지 돌았을 때만** 증거다 — 크래시도 쓰기 0 이다. 그래서 source 경로는
#   SOURCED_OK 표식 + exit 0 을 함께 단언한다(총계 0 = 성공이 아니라 계측 사망 부류 차단).
#
# 축:
#   G1 source(호출자 인자 없음)          → 본체 미발화 · governance_log 불변 · .bak 0 · 로그 0
#   G2 source(호출자 인자 --auto)        → 미발화 (`> 0` 만 고친 판을 잡는다)
#   G3 NO_MAIN=1 + 직접 실행 --auto      → 미발화
#   P1 양성 대조: 직접 실행 --dry-run    → 본체 발화(배너) · 쓰기 0
#   P2 양성 대조: 직접 실행 --auto       → 본체 발화 · 샌드박스 governance_log +1건 · .bak 1
#   P3 양성 대조: 직접 실행 인자 없음    → 본체 발화 (Usage 상 --auto 기본 보존)
#   M1 위반 주입(구판 가드 `>= 0`)       → G1 경로에서 쓰기 발생 = 구 사고 재현 (G1 술어 red)
#   M2 돌연변이(`> 0` 만)                → G2 경로에서 쓰기 발생 (G2 술어 red)
#   M3 돌연변이(--file 정체 판정 제거)   → G1 경로에서 쓰기 발생 (G1 술어 red)
#
# 요약 규약: 마지막 줄 {"test":"cert_backfill_main_guard","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

.MARKER <- "02_Infrastructure/ops/cert_backfill_audit.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_cert_backfill_main_guard] PROJECT_ROOT 해석 실패 — 표지 부재")

PASS <- 0L; FAIL <- 0L
ok  <- function(n) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s  (%s)\n", n, d)) }

RSCRIPT <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
SRC <- readLines(file.path(PROJ, .MARKER), warn = FALSE, encoding = "UTF-8")

GUARD_OLD <- "if (!interactive() && length(commandArgs(trailingOnly = TRUE)) >= 0) {"
GUARD_GT0 <- "if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {"
# LOG_PATH 줄은 정본에서 재도출한다(경로 리터럴을 검사에 복제하지 않는다 — r-portability 금칙 ③ · 정본 경로가 바뀌어도 샌드박스 치환은 산다)
LOG_RX    <- '^LOG_PATH <- "'
BANNER    <- "=== cert_backfill_audit.R Layer 2 ==="
ID_CHECK  <- 'length(f) >= 1L && identical(basename(gsub("\\\\\\\\", "/", f[1L])), "cert_backfill_audit.R")'

BASE <- file.path(tempdir(), paste0("cba_guard_", Sys.getpid()))
unlink(BASE, recursive = TRUE); dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(BASE, recursive = TRUE)   # top-level on.exit 금지(금칙②)

cat("=== test_cert_backfill_main_guard (Q19 · 샌드박스) ===\n")

# 샌드박스 루트 1벌 — src 변형(가드 교체)을 받아 복제본을 쓴다. 표지 줄이 없으면 NULL(= 픽스처 불가 · FAIL 로 드러냄)
mk_sandbox <- function(tag, mutate = NULL) {
  sb <- file.path(BASE, tag)
  for (d in c("02_Infrastructure/ops", "qepm/mailbox/governor", "qepm/mailbox/worktask"))
    dir.create(file.path(sb, d), recursive = TRUE, showWarnings = FALSE)
  src <- SRC
  # 가드 줄 = CLI 본체 첫 줄(args <- commandArgs(trailingOnly = TRUE)) 바로 위의 if 줄 — 가드 **문구**가 아니라
  #   위치로 찾는다(문구로 찾으면 가드를 바꾼 판은 행동 검사 전에 픽스처에서 멈춘다).
  i_body <- which(src == "  args <- commandArgs(trailingOnly = TRUE)")
  i_g <- if (length(i_body) == 1L && i_body > 1L && grepl("^if \\(.*\\) \\{", src[i_body - 1L])) i_body - 1L else integer(0)
  i_log <- grep(LOG_RX, src)
  if (length(i_log) != 1L || length(i_g) != 1L) return(NULL)
  src[i_log] <- sprintf('LOG_PATH <- "%s"', gsub("\\\\", "/", file.path(sb, "cba.log")))
  if (!is.null(mutate)) { src <- mutate(src, i_g); if (is.null(src)) return(NULL) }
  writeLines(src, file.path(sb, .MARKER), useBytes = TRUE)
  writeLines('{"admitted_ids": []}', file.path(sb, "qepm/mailbox/governor/book_state.json"))
  writeLines('{"retroactive_cert_issuances": [], "events": []}',
             file.path(sb, "qepm/mailbox/governor/governance_log.json"))
  writeLines(c(sprintf('source("%s")', .MARKER), 'cat("SOURCED_OK\\n")'), file.path(sb, "driver_source.R"))
  sb
}

# 1회 실행 + 부작용 측정(★이 실행의 **증분**만 — 앞 축의 잔재가 뒤 축 판정에 실리지 않게).
#   script = 샌드박스 상대경로. env = 이 실행에만 켜는 환경변수.
probe <- function(sb, script, args = character(0), env = character(0)) {
  gl <- file.path(sb, "qepm/mailbox/governor/governance_log.json")
  lg <- file.path(sb, "cba.log")
  n_bak_f <- function() length(list.files(file.path(sb, "qepm/mailbox/governor"), pattern = "^governance_log\\.json\\.bak\\."))
  n_retro_f <- function() tryCatch(length(fromJSON(gl, simplifyVector = FALSE)$retroactive_cert_issuances),
                                   error = function(e) NA_integer_)
  lg_sz <- function() if (file.exists(lg)) file.size(lg) else -1
  md0 <- unname(tools::md5sum(gl)); b0 <- n_bak_f(); r0 <- n_retro_f(); l0 <- lg_sz()
  owd <- setwd(sb); on.exit(setwd(owd), add = TRUE)
  if (length(env)) { do.call(Sys.setenv, as.list(env)); on.exit(Sys.unsetenv(names(env)), add = TRUE) }
  out <- suppressWarnings(system2(RSCRIPT, c(script, args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); st <- if (is.null(st)) 0L else as.integer(st)
  list(status = st, out = out,
       banner = any(grepl(BANNER, out, fixed = TRUE)),
       sourced_ok = any(grepl("SOURCED_OK", out, fixed = TRUE)),
       gl_changed = !identical(unname(tools::md5sum(gl)), md0),
       n_bak = n_bak_f() - b0, n_retro = as.integer(n_retro_f() - r0),
       log_written = !identical(lg_sz(), l0))
}
wrote <- function(r) isTRUE(r$gl_changed) || r$n_bak > 0L || isTRUE(r$log_written) || isTRUE(r$banner)
tail2 <- function(r) paste(utils::tail(r$out, 2), collapse = " | ")

sb_new <- mk_sandbox("new")
if (is.null(sb_new)) {
  bad("F0 픽스처", "정본에 LOG_PATH 줄 또는 CLI 본체 위 가드 줄이 정확히 1개가 아니다 — 구조가 바뀌었으면 이 검사도 옮겨라")
} else {
  ok("F0 픽스처 — CLI 가드·LOG_PATH 표지 각 1줄")

  # G1 — source(인자 없음)
  r <- probe(sb_new, "driver_source.R")
  if (r$status == 0L && r$sourced_ok && !wrote(r)) ok("G1 source(인자 없음) → 본체 미발화 · 쓰기 0 · source 완주")
  else bad("G1 source(인자 없음)", sprintf("status=%d sourced=%s banner=%s gl_changed=%s bak=%d log=%s · %s",
            r$status, r$sourced_ok, r$banner, r$gl_changed, r$n_bak, r$log_written, tail2(r)))

  # G2 — source(호출자에 인자 --auto)
  r <- probe(sb_new, "driver_source.R", "--auto")
  if (r$status == 0L && r$sourced_ok && !wrote(r)) ok("G2 source(호출자 인자 --auto) → 미발화")
  else bad("G2 source(호출자 인자 --auto)", sprintf("status=%d banner=%s gl_changed=%s bak=%d · %s",
            r$status, r$banner, r$gl_changed, r$n_bak, tail2(r)))

  # G3 — NO_MAIN=1 + 직접 실행 --auto
  r <- probe(sb_new, .MARKER, "--auto", env = c(QVEST_CERT_BACKFILL_NO_MAIN = "1"))
  if (r$status == 0L && !wrote(r)) ok("G3 NO_MAIN=1 직접 실행 --auto → 미발화")
  else bad("G3 NO_MAIN=1", sprintf("status=%d banner=%s gl_changed=%s bak=%d · %s",
            r$status, r$banner, r$gl_changed, r$n_bak, tail2(r)))

  # P1 — 직접 실행 --dry-run: 발화하되 governance_log 불변
  r <- probe(sb_new, .MARKER, "--dry-run")
  if (r$status == 0L && r$banner && !r$gl_changed && r$n_bak == 0L) ok("P1 직접 실행 --dry-run → 본체 발화 · governance_log 불변")
  else bad("P1 직접 실행 --dry-run", sprintf("status=%d banner=%s gl_changed=%s bak=%d · %s",
            r$status, r$banner, r$gl_changed, r$n_bak, tail2(r)))

  # P2 — 직접 실행 --auto: 샌드박스 governance_log 에 1건 + .bak 1 (CLI 경로 생존 · 쓰기 대상 = 지시된 루트)
  r <- probe(sb_new, .MARKER, "--auto")
  if (r$status == 0L && r$banner && r$gl_changed && identical(r$n_retro, 1L) && r$n_bak == 1L)
    ok("P2 직접 실행 --auto → 발화 · 샌드박스 governance_log +1 · .bak 1")
  else bad("P2 직접 실행 --auto", sprintf("status=%d banner=%s n_retro=%s bak=%d · %s",
            r$status, r$banner, r$n_retro, r$n_bak, tail2(r)))
}

# P3 — 직접 실행 인자 없음(Usage: --auto 기본) — 새 샌드박스(P2 의 .bak 과 섞지 않는다)
sb_p3 <- mk_sandbox("noarg")
if (!is.null(sb_p3)) {
  r <- probe(sb_p3, .MARKER)
  if (r$status == 0L && r$banner && identical(r$n_retro, 1L)) ok("P3 직접 실행 인자 없음 → 발화(--auto 기본 보존)")
  else bad("P3 직접 실행 인자 없음", sprintf("status=%d banner=%s n_retro=%s · %s", r$status, r$banner, r$n_retro, tail2(r)))
}

# M1 — 위반 주입: 구판 가드(>= 0) → source 만으로 본체가 돌아 쓰기 발생(구 사고 재현)
sb_m1 <- mk_sandbox("m1_old", function(src, i) { src[i] <- GUARD_OLD; src })
if (is.null(sb_m1)) bad("M1 픽스처", "구판 가드 주입 실패") else {
  r <- probe(sb_m1, "driver_source.R")
  if (r$banner && r$gl_changed && r$n_bak >= 1L)
    ok(sprintf("M1 구판 가드 주입 → source 만으로 governance_log 변경 + .bak %d (G1 술어 red · 구 사고 재현)", r$n_bak))
  else bad("M1 구판 가드 주입", sprintf("재현 실패 — banner=%s gl_changed=%s bak=%d · %s", r$banner, r$gl_changed, r$n_bak, tail2(r)))
}

# M2 — 돌연변이: `> 0` 만 고친 판 → 인자를 받은 호출자가 source 하면 발화
sb_m2 <- mk_sandbox("m2_gt0", function(src, i) { src[i] <- GUARD_GT0; src })
if (is.null(sb_m2)) bad("M2 픽스처", "`> 0` 가드 주입 실패") else {
  r <- probe(sb_m2, "driver_source.R", "--auto")
  if (r$banner && r$gl_changed) ok("M2 `> 0` 돌연변이 → 호출자 인자 --auto 로 source 시 발화 (G2 술어 red)")
  else bad("M2 `> 0` 돌연변이", sprintf("발화 안 함 — G2 가 판별력 없음 · banner=%s gl_changed=%s", r$banner, r$gl_changed))
}

# M3 — 돌연변이: --file 정체 판정 제거(--file 이 있기만 하면 참) → source 시 발화
sb_m3 <- mk_sandbox("m3_noid", function(src, i) {
  j <- which(trimws(src) == ID_CHECK)
  if (length(j) != 1L) return(NULL)
  src[j] <- sub(ID_CHECK, "length(f) >= 1L", src[j], fixed = TRUE); src })
if (is.null(sb_m3)) bad("M3 픽스처", "--file 정체 판정 줄을 찾지 못함 — 신판 판정식이 바뀌었으면 이 검사도 옮겨라") else {
  r <- probe(sb_m3, "driver_source.R")
  if (r$banner && r$gl_changed) ok("M3 --file 정체 판정 제거 → source 시 발화 (G1 술어 red)")
  else bad("M3 --file 정체 판정 제거", sprintf("발화 안 함 — banner=%s gl_changed=%s", r$banner, r$gl_changed))
}

.cleanup()
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"cert_backfill_main_guard","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
