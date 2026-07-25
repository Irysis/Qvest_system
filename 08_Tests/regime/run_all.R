#==============================================================================
# Quant Module — Regime Infra Test Runner (Step 8)
# Author: Q-Lead (Session 70 — 2026-04-24)
#
# 책임:
#   - 08_Tests/regime/ 하위 모든 test_*.R 파일을 순차 실행
#   - 각 파일의 pass/fail 집계 + 종합 summary 출력
#
# 사용법:
#   cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
#   Rscript 08_Tests/regime/run_all.R
#
# 개별 실행:
#   Rscript 08_Tests/regime/test_ktri_v3_builder.R
#==============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("testthat", quietly = TRUE)) {
    stop("testthat package required. install.packages('testthat')")
  }
})

if (!exists("PROJECT_ROOT")) {
  # [fix 2026-07-25] 구 하드코딩 WSL 폴백 제거. 이 가드는 환경변수를 보지 않아
  # 단독 실행 시 무조건 없는 경로로 가 source(config.R) 가 죽었고,
  # 그 결과 러너가 "0 passed / 0 failed (of 0 total)" 을 성공처럼 냈다.
  # 후보를 **표지 파일 검증**으로 확인한다 — 존재검사로 정체성검사를 대체하지 않는다.
  .qv_marker <- "02_Infrastructure/config.R"
  .qv_argv <- commandArgs(trailingOnly = FALSE)
  .qv_f <- grep("^--file=", .qv_argv, value = TRUE)
  .qv_sd <- if (length(.qv_f)) dirname(sub("^--file=", "", .qv_f[1])) else ""
  for (.qv_c in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                  Sys.getenv("QM_ROOT", unset = ""),
                  if (nzchar(.qv_sd)) file.path(.qv_sd, "..", "..") else "",
                  getwd())) {
    if (nzchar(.qv_c) && file.exists(file.path(.qv_c, .qv_marker))) {
      PROJECT_ROOT <- .qv_c
      break
    }
  }
  if (!exists("PROJECT_ROOT")) {
    stop(sprintf(paste0("[regime] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음.\n",
                        "  cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
                 .qv_marker, getwd(),
                 Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = "")))
  }
  rm(list = intersect(ls(), c(".qv_marker", ".qv_argv", ".qv_f", ".qv_sd", ".qv_c")))
}
setwd(PROJECT_ROOT)

test_dir <- file.path(PROJECT_ROOT, "08_Tests/regime")
test_files <- list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE)

cat("\n=============================================================\n")
cat(" Regime Infra Test Runner — Session 70 Step 8\n")
cat(" Test files found:", length(test_files), "\n")
cat("=============================================================\n")

results <- list()
pass_files <- 0L
fail_files <- 0L

for (f in test_files) {
  cat(sprintf("\n── %s ──\n", basename(f)))
  t0 <- Sys.time()
  status <- tryCatch({
    env <- new.env()
    sys.source(f, envir = env, keep.source = FALSE)
    "PASS"
  },
  error = function(e) {
    cat(sprintf("FAIL: %s\n", conditionMessage(e)))
    "FAIL"
  })
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  results[[basename(f)]] <- list(status = status, elapsed = elapsed)
  if (status == "PASS") pass_files <- pass_files + 1L
  else fail_files <- fail_files + 1L
  cat(sprintf("  [%s] %s (%.2fs)\n", status, basename(f), elapsed))
}

cat("\n=============================================================\n")
cat(sprintf(" Summary: %d passed / %d failed (of %d total)\n",
            pass_files, fail_files, length(test_files)))
cat("=============================================================\n\n")

for (name in names(results)) {
  r <- results[[name]]
  cat(sprintf("  %-40s  %s  (%.2fs)\n", name, r$status, r$elapsed))
}
cat("\n")

if (fail_files > 0) {
  cat("NOTE: one or more test files failed — see individual output above.\n")
  # Don't quit with non-zero for interactive use; harness can check summary
}

invisible(results)
