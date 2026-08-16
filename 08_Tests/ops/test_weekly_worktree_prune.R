# =============================================================================
# test_weekly_worktree_prune.R — weekly_cleaner_sweep [2c] 워크트리 자동 prune 위반 주입
#
# 신설 2026-08-16. 대상 = 02_Infrastructure/ops/weekly_cleaner_sweep.R [2c].
#
# ★이것은 **무인 삭제**다 — 토 09:00 Task Scheduler 가 사람 없이 실행한다. 판정이 한 칸만
#   틀려도 진행 중인 작업이 사라진다. 그래서 '지운다'보다 **'안 지운다'를 더 많이 시험**한다.
#
# ★삭제 안전성을 `git diff main` 으로 재면 안 된다(방향 미구분 — 실측 4,846건 중 대부분이
#   'main 이 더 새로움'이었다). 정본 = ahead 커밋 + 미커밋 편집을 **따로** 세는 것.
#
# ★churn 제외가 없으면 prune 대상이 사실상 0 이 된다 — 실측: 병합완료 31건 중 28건에서
#   qepm/observability/events.jsonl 이 유일한 차이였다(append-only 로그).
#
# 실행: Rscript -e 'source("08_Tests/ops/test_weekly_worktree_prune.R", encoding="UTF-8")'
# =============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- getwd()
ROOT  <- sub("/+$", "", gsub("\\\\", "/", ROOT))
SWEEP <- file.path(ROOT, "02_Infrastructure", "ops", "weekly_cleaner_sweep.R")
stopifnot(file.exists(SWEEP))

PASS <- 0L; FAIL <- 0L
ok  <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
bad <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s — %s\n", m, d)) }

g <- function(dir, ...) suppressWarnings(system2("git", c("-C", shQuote(dir), ...),
                                                 stdout = TRUE, stderr = FALSE))
age_it <- function(p, hours) {           # 무활동 시간 조작
  t <- Sys.time() - hours * 3600
  for (f in c(p, list.files(p, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)))
    try(Sys.setFileTime(f, t), silent = TRUE)
  try(Sys.setFileTime(p, t), silent = TRUE)
}

# ---- 픽스처: 실제 git 저장소 + 실제 워크트리 (판정 로직을 재구현하지 않는다) --------
build <- function() {
  fx <- gsub("\\\\", "/", file.path(tempdir(), paste0("wtfx_", as.integer(runif(1, 1e6, 9e6)))))
  dir.create(file.path(fx, "02_Infrastructure", "ops"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fx, ".cache"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fx, ".claude", "worktrees"), recursive = TRUE, showWarnings = FALSE)
  writeLines("base", file.path(fx, "base.txt"))
  g(fx, "init", "-q", ".")
  g(fx, "config", "user.email", "t@t"); g(fx, "config", "user.name", "t")
  g(fx, "config", "core.longpaths", "true")
  g(fx, "add", "-A"); g(fx, "commit", "-qm", "base")
  g(fx, "branch", "-M", "main")

  wt <- function(nm, br) g(fx, "worktree", "add", "-q", "-b", br,
                           file.path(fx, ".claude/worktrees", nm), "main")
  wp <- function(nm) file.path(fx, ".claude/worktrees", nm)

  wt("wt-prunable", "b-prunable");   age_it(wp("wt-prunable"), 48)
  wt("wt-active",   "b-active")      # mtime = now → 보호되어야
  wt("wt-ahead",    "b-ahead")
  writeLines("x", file.path(wp("wt-ahead"), "extra.txt"))
  g(wp("wt-ahead"), "add", "-A"); g(wp("wt-ahead"), "commit", "-qm", "ahead")
  age_it(wp("wt-ahead"), 48)
  wt("wt-unique",   "b-unique")
  writeLines("only here", file.path(wp("wt-unique"), "unique_note.md"))
  age_it(wp("wt-unique"), 48)
  wt("wt-churn",    "b-churn")
  dir.create(file.path(wp("wt-churn"), "qepm", "observability"), recursive = TRUE, showWarnings = FALSE)
  writeLines("{}", file.path(wp("wt-churn"), "qepm/observability/events.jsonl"))
  age_it(wp("wt-churn"), 48)
  dir.create(wp("shell-empty"), recursive = TRUE, showWarnings = FALSE)   # 미등록 + 파일 0
  fx
}

run_sweep <- function(fx) {
  code <- sprintf(paste0('Sys.setenv(QM_ROOT="%s", QVEST_CLEANER_DRY="1", QVEST_CLEANER_NO_TG="1");',
                         ' source("%s", encoding="UTF-8")'), fx, SWEEP)
  out <- try(system2("Rscript", c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE), silent = TRUE)
  rp <- file.path(fx, ".cache", "cleaner_pending_dryrun.json")
  if (!file.exists(rp)) stop("cleaner_pending_dryrun.json 미생성 — ", substr(paste(out, collapse=" "), 1, 300))
  j <- fromJSON(rp, simplifyVector = FALSE)
  # ★가드: 픽스처가 아니라 실제 저장소를 쓸었으면 즉시 중단(env 주입 실패 시 조용히 통과 방지)
  if (!grepl(basename(fx), paste(out, collapse = " "), fixed = TRUE))
    stop("sweep 이 픽스처 루트를 못 받음 — env 주입 경로 점검")
  j$worktree_prune
}

cat("=== weekly_cleaner_sweep [2c] 워크트리 prune — 위반 주입 ===\n")
fx <- build()
w  <- run_sweep(fx)
pr <- unlist(w$pruned); kp <- names(w$kept)

chk <- function(nm, want_prune, label) {
  got <- nm %in% pr
  if (got == want_prune) ok(sprintf("%s — %s", label, if (want_prune) "PRUNE" else "KEEP"))
  else bad(label, sprintf("기대=%s 실제=%s 사유=%s", if (want_prune) "prune" else "keep",
                          if (got) "prune" else "keep", w$kept[[nm]] %||% "(없음)"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# 지워야 하는 것
chk("wt-prunable", TRUE,  "T1 병합완료·clean·48h 무활동")
chk("wt-churn",    TRUE,  "T2 churn(events.jsonl)만 dirty — churn 제외가 동작")
chk("shell-empty", TRUE,  "T3 미등록 빈 껍데기")

# ★지우면 안 되는 것 (이쪽이 본체)
chk("wt-active",   FALSE, "T4 활동 중(무활동 0h) — 진행 중 세션 보호")
chk("wt-ahead",    FALSE, "T5 미병합 커밋 보유")
chk("wt-unique",   FALSE, "T6 main 에 없는 미커밋 내용 보유")

# 보존 사유가 실제로 기록되는가 (조용한 누락 금지 — '대상 0' 과 '판정 실패' 구분)
if (all(c("wt-active", "wt-ahead", "wt-unique") %in% kp) &&
    all(nzchar(unlist(w$kept[c("wt-active", "wt-ahead", "wt-unique")])))) {
  ok("T7 보존 3건 전부 사유와 함께 기록됨")
} else bad("T7 보존 사유 누락", paste(kp, collapse = ","))

# DRY 는 실제로 지우지 않아야 한다 (dry 가 파괴적이면 이 테스트 자체가 위험)
if (dir.exists(file.path(fx, ".claude/worktrees", "wt-prunable"))) {
  ok("T8 DRY — prune 대상이 디스크에 그대로 (실삭제 없음)")
} else bad("T8 DRY 인데 실제 삭제됨", "무인 dry-run 이 파괴적")

# 브랜치 보존: prune 되어도 커밋은 ref 로 남는다 (설계의 안전 근거)
brs <- unlist(g(fx, "branch", "--list"))
if (any(grepl("b-prunable", brs))) {
  ok("T9 prune 대상 브랜치가 ref 로 보존됨")
} else bad("T9 브랜치 소실", paste(brs, collapse = ","))

unlink(fx, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
