#==============================================================================
# test_build_hash_provenance.R — factor DB build_hash provenance 상설 검사
#
# 대상: 02_Infrastructure/factor_db/factor_db_builder.R 의
#       .fdb_run_git() / .fdb_resolve_repo() / .fdb_code_digest() /
#       .fdb_init_code_rev() / .write_build_hash()
#       (소비: load_month_factors() 가 attr "factor_db_build_hash" 로 전파,
#        AST v1.1 STORED_SCORE provenance 의 store_build_hash 필드 기반)
#
# 왜 있나 (2026-07-26, P4):
#   2026-07-25 전기간 재빌드에서 440 write 중 415건이 "_unknown" 으로 기록됐다.
#   구 구현은 system(intern=TRUE, ignore.stderr=TRUE) 을 썼는데
#     ① 명령 실패는 R 이 *warning* 으로만 신호 → tryCatch(error=) 가 못 잡고
#     ② ignore.stderr=TRUE 가 원인 문자열을 버리고
#     ③ 그 경고마저 "There were 50 or more warnings" 로 집계돼 보이지 않았다.
#   즉 provenance 가 조용히 소실됐다. 이 검사의 본질은 해시 값 자체가 아니라
#   **실패가 침묵하지 않는지**다.
#
# 구조 5축:
#   A. 위반 주입 — 일부러 git 을 못 쓰게 만들고 'unknown' 침묵이 없는지
#   B. 회귀     — 정상 환경에서 git rev 가 실제로 나오는지 + 1행 계약
#   C. 차단 실효 — **구 구현으로 되돌리면 A 케이스가 침묵 unknown 을 내는지**
#                  (=A 의 PASS 가 공허하지 않은지)
#   D. 배선     — 빌더가 rev 를 source 시점 1회 확정하고 구 호출 잔재가 없는지
#   E. 소비자·현물 — 소비 측 n=1 계약 + 현행 canonical build_hash.txt 상태
#
# 단독 실행: Rscript 08_Tests/factor_db/test_build_hash_provenance.R
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/factor_db/factor_db_builder.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

BUILDER_SRC   <- "02_Infrastructure/factor_db/factor_db_builder.R"
CONNECTOR_SRC <- "02_Infrastructure/factor_db/factor_db_connector.R"
DISCOVERY_SRC <- "02_Infrastructure/discovery/discovery_loader.R"

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
# 제3상태 (2026-08-02): 전제 산출물이 이 트리에 없으면 **판정하지 않는다**.
#   실패로 계상하면 "계약 위반"과 "전제 부재"가 같은 빨강이 되고(worktree 오진단),
#   통과로 계상하면 "빈 결과 = 합격" 계통 재발이다. 사유와 없는 경로를 함께 남긴다.
skip <- function(n, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = n, reason = reason, missing = missing)
  cat(sprintf("  SKIP: %s — %s [missing: %s]\n", n, reason, missing))
}
# 전제 경로의 뿌리. 기본 = PROJ. 환경변수는 **주입 테스트 전용** —
# 빈 디렉터리를 가리켜 "전제 부재" 상태를 실제로 재현한다(가짜 skip 플래그가 아니라
# 경로 치환이므로, 전제가 실재하면 이 변수로도 skip 을 만들어낼 수 없다).
CACHE_ROOT <- Sys.getenv("QVEST_TEST_CACHE_ROOT", unset = PROJ)

# ── 해시 헬퍼 블록만 격리 평가 (빌더 전체 source = arrow/config 부작용 회피) ──
SRC <- readLines(BUILDER_SRC, warn = FALSE)
i0  <- grep("^\\.fdb_hash_env <- new\\.env", SRC)[1]
i1  <- grep("^# 코드 버전은 source 시점에 1회 확정", SRC)[1] - 1L
if (is.na(i0) || is.na(i1) || i1 <= i0)
  stop("build_hash 헬퍼 블록 경계를 찾지 못함 — 빌더 구조 변경 시 이 검사부터 갱신할 것")
BLOCK <- paste(SRC[i0:i1], collapse = "\n")

mk_env <- function(self_dir = file.path(PROJ, "02_Infrastructure", "factor_db")) {
  e <- new.env()
  e$COMPUTE_MOD_DIR <- file.path(PROJ, "02_Infrastructure", "factor_db")
  e$FACTOR_REG_PATH <- file.path(e$COMPUTE_MOD_DIR, "factor_registry.json")
  e$FACTOR_DB_DIR   <- tempfile("fdb_test_"); dir.create(e$FACTOR_DB_DIR)
  e$.self_dir       <- self_dir
  eval(parse(text = BLOCK), envir = e)
  e
}

# rev 확정 + 파일 기록을 한 번에 실행하고 경고를 수집한다.
run_env <- function(e) {
  warns <- character(0)
  h <- function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }
  cr <- withCallingHandlers(e$.fdb_init_code_rev(force = TRUE, quiet = TRUE), warning = h)
  invisible(withCallingHandlers(e$.write_build_hash(), warning = h))
  hp <- file.path(e$FACTOR_DB_DIR, "build_hash.txt")
  list(rev = cr$rev, source = cr$source, reason = cr$reason,
       warns = warns, lines = readLines(hp, warn = FALSE),
       first = readLines(hp, n = 1L))
}

# PATH 에서 git 을 제거한 채 실행 (위반 주입 ①)
without_git <- function(fn) {
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)   # 함수 내부 on.exit — 정상 발화
  parts <- strsplit(old, ";", fixed = TRUE)[[1]]
  Sys.setenv(PATH = paste(parts[!grepl("git", parts, ignore.case = TRUE)], collapse = ";"))
  fn()
}
# 저장소가 아닌 곳에서 실행 (위반 주입 ②)
in_nonrepo <- function(fn) {
  oc <- Sys.getenv("CLAUDE_PROJECT_DIR"); oq <- Sys.getenv("QM_ROOT"); ow <- getwd()
  on.exit({ Sys.setenv(CLAUDE_PROJECT_DIR = oc, QM_ROOT = oq); setwd(ow) }, add = TRUE)
  tmp <- tempfile("notarepo_"); dir.create(tmp)
  Sys.setenv(CLAUDE_PROJECT_DIR = tmp, QM_ROOT = tmp); setwd(tmp)
  fn(tmp)
}
# git 은 있고 저장소도 맞지만 HEAD 가 없음 = rev-parse status 128 (위반 주입 ③,
#   2026-07-25 실사고와 같은 실패 클래스)
in_headless_repo <- function(fn) {
  oc <- Sys.getenv("CLAUDE_PROJECT_DIR"); oq <- Sys.getenv("QM_ROOT"); ow <- getwd()
  on.exit({ Sys.setenv(CLAUDE_PROJECT_DIR = oc, QM_ROOT = oq); setwd(ow) }, add = TRUE)
  repo <- tempfile("emptyrepo_"); dir.create(repo)
  system2("git", c("-C", repo, "init", "-q"), stdout = NULL, stderr = NULL)
  Sys.setenv(CLAUDE_PROJECT_DIR = repo, QM_ROOT = repo); setwd(repo)
  fn(repo)
}

check_injection <- function(id, r) {
  if (grepl("_unknown$", r$first) || identical(r$rev, "unknown")) {
    bad(id, sprintf("침묵 unknown 재현 — rev='%s'", r$rev)); return(invisible(NULL))
  }
  if (length(r$warns) < 1L) {
    bad(id, sprintf("경고가 남지 않음 (rev='%s') — 침묵 실패", r$rev)); return(invisible(NULL))
  }
  if (length(r$lines) < 2L || !grepl("^# rev_source=", r$lines[2])) {
    bad(id, "진단 2행이 파일에 남지 않음"); return(invisible(NULL))
  }
  if (!nzchar(r$reason)) { bad(id, "실패 사유 문자열이 비어 있음"); return(invisible(NULL)) }
  ok(id, sprintf("rev='%s' source=%s warn=%d reason='%s'",
                 r$rev, r$source, length(r$warns), substr(r$reason, 1, 90)))
}

cat("\n=== A. 위반 주입 — 해시 산출이 실패할 때 침묵하지 않는가 ===\n")
rA1 <- without_git(function() run_env(mk_env()))
check_injection("A1_git_absent", rA1)

rA2 <- in_nonrepo(function(tmp) run_env(mk_env(self_dir = file.path(tmp, "02_Infrastructure", "factor_db"))))
check_injection("A2_not_a_repository", rA2)

rA3 <- in_headless_repo(function(repo) run_env(mk_env(self_dir = file.path(repo, "02_Infrastructure", "factor_db"))))
check_injection("A3_rev_parse_status128", rA3)
if (grepl("status=128", rA3$reason) && grepl("fatal", rA3$reason)) {
  ok("A3b_stderr_preserved", sprintf("종료코드+stderr 보존: %s", substr(rA3$reason, 1, 80)))
} else {
  bad("A3b_stderr_preserved",
      sprintf("실패 원인(status/stderr)이 버려짐 — reason='%s'", rA3$reason))
}
# 대체 식별자는 코드 버전을 실제로 구분해야 한다(상수 토큰이면 unknown 과 다를 게 없다)
if (grepl("^nogit[0-9a-f]{8}$", rA1$rev)) {
  ok("A4_fallback_is_code_derived", sprintf("코드 다이제스트 식별자 '%s'", rA1$rev))
} else {
  bad("A4_fallback_is_code_derived", sprintf("대체 식별자가 코드 파생이 아님: '%s'", rA1$rev))
}

cat("\n=== B. 회귀 — 정상 환경 ===\n")
rB <- run_env(mk_env())
if (identical(rB$source, "git") && grepl("^[0-9a-f]{7,}(-dirty)?$", rB$rev)) {
  ok("B1_git_rev_resolved", sprintf("rev='%s'", rB$rev))
} else {
  bad("B1_git_rev_resolved", sprintf("rev='%s' source=%s reason=%s", rB$rev, rB$source, rB$reason))
}
if (grepl("^[0-9]{14}_", rB$first)) {
  ok("B2_line1_format", rB$first)
} else {
  bad("B2_line1_format", sprintf("1행 형식 위반: '%s'", rB$first))
}
if (length(rB$lines) == 1L) {
  ok("B3_no_diag_line_when_clean", "정상일 때 2행 미부착")
} else {
  bad("B3_no_diag_line_when_clean", sprintf("불필요한 2행: '%s'", rB$lines[2]))
}
# cwd 가 저장소 밖이어도 rev 가 나와야 한다(구 구현은 cwd 의존)
rB4 <- local({ ow <- getwd(); on.exit(setwd(ow), add = TRUE); setwd(tempdir()); run_env(mk_env()) })
if (identical(rB4$source, "git")) {
  ok("B4_cwd_independent", sprintf("tempdir 에서도 rev='%s'", rB4$rev))
} else {
  bad("B4_cwd_independent", sprintf("cwd 의존 잔존 — source=%s reason=%s", rB4$source, rB4$reason))
}

cat("\n=== C. 차단 실효 — 구 구현으로 되돌리면 A 가 뚫리는가 ===\n")
old_impl_rev <- function(dir) {
  ow <- getwd(); on.exit(setwd(ow), add = TRUE); setwd(dir)
  gr <- tryCatch(suppressWarnings(system("git rev-parse --short HEAD",
                                         intern = TRUE, ignore.stderr = TRUE)),
                 error = function(e) "unknown")
  if (length(gr) == 0 || nchar(gr[1]) == 0) "unknown" else gr[1]
}
silent_cases <- character(0)
if (identical(without_git(function() old_impl_rev(PROJ)), "unknown")) silent_cases <- c(silent_cases, "A1")
if (in_nonrepo(function(tmp) identical(old_impl_rev(tmp), "unknown"))) silent_cases <- c(silent_cases, "A2")
if (in_headless_repo(function(repo) identical(old_impl_rev(repo), "unknown"))) silent_cases <- c(silent_cases, "A3")
if (length(silent_cases) >= 2L) {
  ok("C1_old_impl_would_go_silent",
     sprintf("구 구현이 침묵 unknown 을 내는 케이스 %d건: %s (신 구현은 전부 식별자+경고)",
             length(silent_cases), paste(silent_cases, collapse = ",")))
} else {
  bad("C1_old_impl_would_go_silent",
      sprintf("구·신이 갈리는 케이스가 %d건뿐 — A 케이스가 회귀를 못 잡는다(공허한 통과)",
              length(silent_cases)))
}

cat("\n=== D. 배선 — 빌더 코드 계약 ===\n")
code <- SRC[!grepl("^\\s*#", SRC)]
if (any(grepl("system\\(\\s*[\"']git rev-parse", code))) {
  bad("D1_no_legacy_system_call", "구 system('git rev-parse', intern=TRUE) 잔재 존재")
} else ok("D1_no_legacy_system_call", "구 호출 잔재 없음")
if (any(grepl("ignore\\.stderr\\s*=\\s*TRUE", code))) {
  bad("D2_stderr_not_discarded", "ignore.stderr=TRUE 로 실패 원인을 버리는 경로 존재")
} else ok("D2_stderr_not_discarded", "stderr 폐기 경로 없음")
if (length(grep("^\\.fdb_init_code_rev\\(\\)\\s*$", SRC)) >= 1L) {
  ok("D3_rev_pinned_at_source_time", "module-level .fdb_init_code_rev() — 빌드 중 HEAD 이동 무관")
} else {
  bad("D3_rev_pinned_at_source_time",
      "source 시점 1회 확정 배선 없음 — 빌드 도중 auto-commit 이 rev 를 바꾼다(07-25 실측)")
}
wb <- grep("\\.write_build_hash\\(\\)", code)
if (length(wb) >= 3L) {
  ok("D4_writer_called", sprintf("저장 경로 호출 %d곳", length(wb)))
} else {
  bad("D4_writer_called", sprintf(".write_build_hash() 호출이 %d곳뿐 — 저장 경로 배선 확인", length(wb)))
}

cat("\n=== E. 소비자 계약 + 현행 canonical 상태 ===\n")
for (f in c(CONNECTOR_SRC, DISCOVERY_SRC)) {
  if (!file.exists(f)) { bad(paste0("E_", basename(f)), "파일 부재"); next }
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  if (grepl("build_hash", txt) && grepl("readLines\\([^)]*n\\s*=\\s*1L?", txt))
    ok(paste0("E1_n1_contract_", basename(f)), "n=1 읽기 — 진단 2행 추가가 안전")
  else
    bad(paste0("E1_n1_contract_", basename(f)), "build_hash 를 n=1 로 읽지 않음 — 2행 추가가 소비를 깨뜨림")
}
HP <- file.path(CACHE_ROOT, ".cache", "factor_db", "build_hash.txt")
if (!file.exists(HP)) {
  # ★이 축만 **현물**(빌드 산출물)을 본다 — A~E1 은 전부 코드/합성 픽스처라 트리 무관.
  #  build_hash.txt 는 gitignore 대상이라 worktree/새 체크아웃엔 없다. 그 부재는
  #  provenance 계약 위반이 아니라 "이 트리에서 팩터 DB 를 빌드한 적 없음"이다.
  skip("E2_canonical_state",
       "canonical build_hash.txt 부재 — 이 트리에서 팩터 DB 빌드 이력 없음(계약 위반 아님)",
       HP)
} else {
  h1 <- readLines(HP, n = 1L)
  if (grepl("_unknown$", h1)) bad("E2_canonical_state", sprintf("현행 build_hash 가 unknown: '%s'", h1))
  else ok("E2_canonical_state", sprintf("현행 build_hash='%s'", h1))
}

cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, length(SKIPS)))
cat(toJSON(list(test = "build_hash_provenance", pass = PASS, fail = FAIL,
                skipped = length(SKIPS), total = PASS + FAIL,
                skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
