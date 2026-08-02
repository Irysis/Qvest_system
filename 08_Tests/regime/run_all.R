#==============================================================================
# Quant Module — Regime Infra Test Runner (Step 8)
# Author: Q-Lead (Session 70 — 2026-04-24)
#
# 책임:
#   - 08_Tests/regime/ 하위 모든 test_*.R 파일을 순차 실행
#   - 각 파일의 pass/fail 집계 + 종합 summary 출력
#
# 사용법 (러너는 자기가 실린 트리를 검사한다 — cd 는 어디서 하든 무방):
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
  #
  # [fix 2026-08-02] 후보 **순서** 교체: self(`--file=`) 를 1순위로.
  #   구판은 CLAUDE_PROJECT_DIR → QM_ROOT → self → cwd 였다. Bash 툴 환경에서
  #   CLAUDE_PROJECT_DIR 은 미설정(훅 안에서만 세워진다)이고 QM_ROOT 는 ~/.Renviron 이
  #   **main 트리**로 고정해 두므로, worktree 에서 이 러너를 돌리면 PROJECT_ROOT 가
  #   main 이 되고 :52 의 test_dir 도 따라간다 → **worktree 의 테스트가 아니라
  #   main 의 테스트를 실행**한다.
  #   실측(2026-08-02): worktree 에 test_*.R 6개 / main 5개인 상태에서 worktree 에서
  #   실행 → "Test files found: 5" (main 것을 찾음). 신설 테스트는 실행조차 안 된다.
  #   ★표지 검증은 이 갈림을 **판별하지 못한다** — 두 트리 다 config.R 을 갖는다.
  #     가르는 것은 오직 후보 **순서**뿐이다. 테스트 러너는 *자기가 실린 트리*를 재야 한다.
  #   ★shell 에서 `QM_ROOT=... Rscript` 로 덮어써도 R 은 ~/.Renviron 을 나중에 적용해
  #     Sys.getenv("QM_ROOT") 가 안 바뀐다 — 이 결함은 env 덮어쓰기로 재현/회피 불가.
  #   ★공유 resolver(`02_Infrastructure/{hooks,ops}/resolve_project.sh`)는 무변경 —
  #     소비자 계층이 다르다(2026-08-01 도훈 결정, test_resolve_project_marker.sh 축 G).
  .qv_marker <- "02_Infrastructure/config.R"
  # ★앵커 순서 정본 = 이 한 줄. 위반 주입 테스트가 이 줄을 갈아끼워 검출력을 실증한다
  #   (08_Tests/hooks/test_runner_anchor_selffirst.sh).
  .qv_order <- c("self", "CLAUDE_PROJECT_DIR", "QM_ROOT", "cwd")
  .qv_norm <- function(p) {
    if (!nzchar(p)) return("")
    normalizePath(gsub("\\\\", "/", p), winslash = "/", mustWork = FALSE)
  }
  .qv_argv <- commandArgs(trailingOnly = FALSE)
  .qv_f <- grep("^--file=", .qv_argv, value = TRUE)
  .qv_sd <- if (length(.qv_f)) dirname(sub("^--file=", "", .qv_f[1])) else ""
  .qv_self <- if (nzchar(.qv_sd)) .qv_norm(file.path(.qv_sd, "..", "..")) else ""
  .qv_val <- c(self               = .qv_self,
               CLAUDE_PROJECT_DIR = .qv_norm(Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")),
               QM_ROOT            = .qv_norm(Sys.getenv("QM_ROOT", unset = "")),
               cwd                = .qv_norm(getwd()))
  .qv_src <- ""
  for (.qv_s in .qv_order) {
    .qv_c <- .qv_val[[.qv_s]]
    # 표지 검증은 **모든 tier** 에 건다 — self 도 예외 아님(표지 없는 위치의 사본은 기각).
    if (nzchar(.qv_c) && file.exists(file.path(.qv_c, .qv_marker))) {
      PROJECT_ROOT <- .qv_c
      .qv_src <- .qv_s
      break
    }
  }
  if (!exists("PROJECT_ROOT")) {
    stop(sprintf(paste0("[regime] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음.\n",
                        "  self='%s' / cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
                 .qv_marker, .qv_self, getwd(),
                 Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = "")))
  }
  # 앵커가 자기 트리와 갈리면 **보이게** 한다. 낙하 자체는 정당할 수 있으나(표지 없는
  # 위치의 사본 등) 침묵하면 "어느 트리를 쟀는지"가 로그에 안 남는다 — 침묵 낙하가
  # 이 계통의 재발 기전이다.
  if (nzchar(.qv_self) && !identical(PROJECT_ROOT, .qv_self)) {
    message(sprintf("⚠ ANCHOR OVERRIDE: 러너 자신의 트리 '%s' 가 아니라 %s='%s' 를 검사합니다.",
                    .qv_self, .qv_src, PROJECT_ROOT))
  }
  rm(list = intersect(ls(), c(".qv_marker", ".qv_order", ".qv_norm", ".qv_argv", ".qv_f",
                              ".qv_sd", ".qv_self", ".qv_val", ".qv_src", ".qv_s", ".qv_c")))
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
