#==============================================================================
# test_lookahead_unscanned.R — PIT lookahead 검출기의 "미스캔 ≠ 통과" 계약 검사기
#
# 배경 (2026-08-02): detect_lookahead() 가 파일 부재 시 clean=TRUE 를 반환했다.
#   즉 **스캔을 0회 한 사실이 'PIT 위반 없음' 판정**이 됐다. 같은 형태가 3곳:
#     ① detect_lookahead        — 파일 부재 → clean=TRUE
#     ② detect_lookahead_dir    — 대상 파일 0개 → "ALL CLEAN: 0 files scanned"
#     ③ detect_gate15_infra_pit — 대상 0개 → "INFRA_PIT_SCAN PASS: 0 files"
#   소비부(10개 alpha_search 러너 + hook_batch_runner + backfill)는 전부
#   isTRUE(pit$clean) 을 쓰므로, 검출기가 NA 를 내면 자동으로 not-clean 이 된다.
#
# ★이 검사기는 "정상 파일에서 위반을 잡는가"만 보지 않는다. 그건 구 구현도 통과했다.
#   스캔이 **수행되지 않은** 상황을 실제로 만들어 그것이 PASS 로 새지 않는지 본다.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj(); setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

invisible(capture.output(source(file.path(PROJ, "02_Infrastructure/validation/lookahead_detector.R"))))
cat("=== lookahead: 미스캔 ≠ 통과 계약 ===\n")

# ─── 1) 위반 주입 A: 존재하지 않는 파일 ──────────────────────────────────────
r <- suppressWarnings(detect_lookahead(file.path(tempdir(), "no_such_file_xyz.R"), verbose = FALSE))
if (isTRUE(r$clean)) {
  bad("missing_file_not_pass", "파일 부재인데 clean=TRUE — 스캔 0회가 PIT 통과로 샘(구 결함)")
} else if (is.na(r$clean) && identical(r$scanned, FALSE)) {
  ok("missing_file_not_pass", "clean=NA · scanned=FALSE")
} else {
  bad("missing_file_not_pass", sprintf("예상 밖: clean=%s scanned=%s", r$clean, r$scanned))
}
if (!is.null(r$error) && nzchar(r$error)) {
  ok("missing_file_error_label", r$error)
} else {
  bad("missing_file_error_label", "미스캔 사유 라벨 없음")
}

# ─── 2) 회귀: 정상 파일은 여전히 정상 판정 ───────────────────────────────────
mk <- function(lines) { p <- tempfile(fileext = ".R"); writeLines(lines, p); p }
clean_f <- mk(c("x <- 1", "y <- x + 1", "print(y)"))
rc <- suppressWarnings(detect_lookahead(clean_f, verbose = FALSE))
if (isTRUE(rc$clean) && isTRUE(rc$scanned)) {
  ok("clean_file_still_passes", "clean=TRUE · scanned=TRUE")
} else {
  bad("clean_file_still_passes", sprintf("정상 파일인데 clean=%s", rc$clean))
}

# ─── 3) 회귀: 실제 위반은 여전히 검출 ────────────────────────────────────────
viol_f <- mk(c("best_combination <- expand.grid(a=1:3, b=1:3)",
               "pick <- which.max(res$sharpe)"))
rv <- suppressWarnings(detect_lookahead(viol_f, verbose = FALSE))
if (identical(rv$clean, FALSE) && rv$n_violations > 0L) {
  ok("real_violation_detected", sprintf("%d violation(s)", rv$n_violations))
} else {
  bad("real_violation_detected", sprintf("위반 파일인데 clean=%s n=%s", rv$clean, rv$n_violations))
}

# ─── 4) 위반 주입 B: 대상 파일 0개인 디렉토리 ────────────────────────────────
empty_dir_case <- function(fn, label) {
  d <- file.path(tempfile("emptydir_")); dir.create(d, recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  suppressWarnings(fn(d, verbose = FALSE))
}
rd <- empty_dir_case(detect_lookahead_dir, "dir")
if (isTRUE(rd$clean)) {
  bad("empty_dir_not_pass", "대상 0개인데 clean=TRUE — 'ALL CLEAN: 0 files scanned'(구 결함)")
} else if (is.na(rd$clean)) {
  ok("empty_dir_not_pass", sprintf("clean=NA (n_files=%d)", rd$n_files))
} else {
  bad("empty_dir_not_pass", sprintf("예상 밖: clean=%s", rd$clean))
}
rg <- empty_dir_case(detect_gate15_infra_pit, "gate15")
if (isTRUE(rg$clean)) {
  bad("gate15_empty_not_pass", "대상 0개인데 clean=TRUE — 'INFRA_PIT_SCAN PASS: 0 files'(구 결함)")
} else if (is.na(rg$clean)) {
  ok("gate15_empty_not_pass", "clean=NA")
} else {
  bad("gate15_empty_not_pass", sprintf("예상 밖: clean=%s", rg$clean))
}

# ─── 5) 회귀: 정상 파일이 든 디렉토리는 통과 ─────────────────────────────────
good_dir <- file.path(tempfile("gooddir_")); dir.create(good_dir, recursive = TRUE)
writeLines(c("x <- 1", "print(x)"), file.path(good_dir, "run_all.R"))
rd2 <- suppressWarnings(detect_lookahead_dir(good_dir, verbose = FALSE))
if (isTRUE(rd2$clean) && rd2$n_scanned == 1L) {
  ok("good_dir_passes", "clean=TRUE · n_scanned=1")
} else {
  bad("good_dir_passes", sprintf("clean=%s n_scanned=%s", rd2$clean, rd2$n_scanned))
}
unlink(good_dir, recursive = TRUE)

# ─── 6) 소비부 계약: 전부 isTRUE() 로 받는가 (NA 가 PASS 로 새지 않도록) ─────
consumers <- list.files(file.path(PROJ, "02_Infrastructure"), pattern = "\\.R$",
                        recursive = TRUE, full.names = TRUE)
bare <- character(0)
for (f in consumers) {
  L <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
  L <- L[!grepl("^\\s*#", L)]
  # `!x$clean` / `if (x$clean)` 처럼 isTRUE 없이 3값을 논리로 쓰는 지점
  if (any(grepl("(!|\\(|&&|\\|\\|)\\s*[A-Za-z._][A-Za-z0-9._]*\\$clean\\b", L) &
          !grepl("isTRUE\\s*\\(|identical\\s*\\(|is\\.na\\s*\\(", L)))
    bare <- c(bare, sub(paste0("^", PROJ, "/"), "", gsub("\\\\", "/", f)))
}
if (length(bare) == 0L) {
  ok("consumers_use_isTRUE", "$clean 을 isTRUE/identical 없이 논리로 쓰는 지점 0")
} else {
  bad("consumers_use_isTRUE",
      sprintf("NA 가 오류/통과로 샐 수 있는 지점: %s", paste(utils::head(bare, 4), collapse = ", ")))
}

# ─── 7) 래퍼 관통: pit_engine_v3 가 미측정을 다시 PASS 로 바꾸지 않는가 ──────
#  구 구현은 세 갈래(검출기 미로드 / run_all.R 0개 / 스캔 예외)를 모두 clean=TRUE 로
#  바꿔 **lookahead_detector 의 NA 수리를 덮어썼다**. 검출기만 고치면 무력화되는 자리.
invisible(capture.output(source(file.path(PROJ, "02_Infrastructure/validation/pit_engine_v3.R"))))
empty_strategy <- file.path(tempfile("strat_")); dir.create(empty_strategy, recursive = TRUE)
ss <- suppressWarnings(pit_engine_v3$scan_static(empty_strategy, verbose = FALSE))
if (isTRUE(ss$clean)) {
  bad("engine_static_empty_not_pass",
      "run_all.R 0개인데 clean=TRUE — 래퍼가 미측정을 PASS 로 되돌림(구 결함)")
} else if (is.na(ss$clean) && identical(ss$scanned, FALSE)) {
  ok("engine_static_empty_not_pass", "clean=NA · scanned=FALSE")
} else {
  bad("engine_static_empty_not_pass", sprintf("예상 밖: clean=%s", ss$clean))
}
unlink(empty_strategy, recursive = TRUE)

# ─── 8) scan_runtime: 실데이터 PIT(D000) 의 미스캔 3갈래 ─────────────────────
#  1차 수리에서 놓쳤던 지점 — "조기 return(clean=TRUE)" 형태라 스크린 정규식의 사각이었다.
rt_cases <- list(
  list(nm = "no_input",        f = list(NULL, NULL)),
  list(nm = "no_FACTORS_Date", f = list(data.frame(x = 1), data.frame(Exec_Date = Sys.Date()))),
  list(nm = "no_PLOG_ExecDate",f = list(data.frame(Date = Sys.Date()), data.frame(y = 1)))
)
for (cs in rt_cases) {
  r <- suppressWarnings(tryCatch(pit_engine_v3$scan_runtime(cs$f[[1]], cs$f[[2]]),
                                 error = function(e) list(clean = paste("ERR:", conditionMessage(e)))))
  if (isTRUE(r$clean)) {
    bad(sprintf("runtime_%s_not_pass", cs$nm), "검사 불가인데 clean=TRUE (구 결함)")
  } else if (is.na(r$clean) && identical(r$scanned, FALSE)) {
    ok(sprintf("runtime_%s_not_pass", cs$nm), "clean=NA · scanned=FALSE")
  } else {
    bad(sprintf("runtime_%s_not_pass", cs$nm), sprintf("예상 밖: clean=%s", r$clean))
  }
}

cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "lookahead_unscanned", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
