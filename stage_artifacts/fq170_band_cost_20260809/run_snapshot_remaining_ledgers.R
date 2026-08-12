## 남은 사건 원장 2종 보존 — continuity_blocks(77) + failure_revival_history(42)
## round_closures 는 이미 보존(06_Registry/round_closures_snapshot_20260809.jsonl).
## ★보존이지 수리가 아니다. 항구 수리 = 칩 task_7ee7a072.
## ⚠원본을 수정하지 않는다. 읽고 복사 + 재읽기 바이트 일치 검증만.
suppressPackageStartupMessages({ library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
D <- file.path(CODE_ROOT, "06_Registry"); dir.create(D, showWarnings=FALSE, recursive=TRUE)

jobs <- list(
  list(src=".cache/continuity_blocks.jsonl",
       dst="continuity_blocks_snapshot_20260809.jsonl",
       what="Continuity Firewall 이 턴을 강제 속행시킨 block 발화 이력"),
  list(src=".cache/failure_revival_history.jsonl",
       dst="failure_revival_history_snapshot_20260809.jsonl",
       what="INV-7 부활 신호 발화 이력 (06_Registry/revival_signals.json 은 현재 신호이지 이력 아님)"))

ok <- TRUE
for (j in jobs) {
  if (!file.exists(j$src)) { cat(sprintf("SKIP %s (부재)\n", j$src)); ok <- FALSE; next }
  ln <- readLines(j$src, warn=FALSE)
  out <- file.path(D, j$dst)
  writeLines(ln, out, useBytes=TRUE)
  back <- readLines(out, warn=FALSE)
  same <- identical(back, ln)
  ig <- system2("git", c("-C", shQuote(CODE_ROOT), "check-ignore", "-q", shQuote(file.path("06_Registry", j$dst))))
  cat(sprintf("%-42s %3d줄 → %s · 재읽기 일치 %s · ignored %s\n",
              basename(j$src), length(ln), j$dst, same, if (ig == 0L) "Y" else "N"))
  if (!same) { ok <- FALSE; cat("  ⚠내용 불일치\n") }
}
note <- file.path(D, "cache_only_ledgers_snapshot_20260809_README.md")
writeLines(c(
  "# `.cache` 전용 사건 원장 스냅샷 (2026-08-09)",
  "",
  "**라이브가 아니다.** 세 원장 모두 여전히 `.cache/` 에만 append 되며 `.gitignore:5` 로 추적되지 않는다.",
  "이 폴더의 `*_snapshot_20260809.*` 는 그 시점 사본일 뿐이다.",
  "",
  "| 원장 | 레코드 | writer |",
  "|---|---|---|",
  "| `.cache/round_closures.jsonl` | 368 | `02_Infrastructure/contracts/close_round.R:126` |",
  "| `.cache/continuity_blocks.jsonl` | 77 | `02_Infrastructure/hooks/research_continuity_guard.sh` |",
  "| `.cache/failure_revival_history.jsonl` | 42 | `02_Infrastructure/ops/failure_revival_monitor.R` |",
  "",
  "## 정답 패턴 (항구 수리는 이걸 복제할 것)",
  "`02_Infrastructure/validation/benchmark_source_parity.R:255-265` — 현재 상태는",
  "`.cache/benchmark_parity_latest.json`(재생성 가능), **사건 이력은**",
  "`06_Registry/benchmark_parity_history.jsonl`(추적).",
  "",
  "## 한정",
  "- census 로 찾은 3건은 **하한**이다. 스캐너가 줄 단위라 오탐 1건, 변수 경로라 누락 최소 1건이 실증됐다.",
  "- 항구 수리는 별도 태스크. 이 파일들은 보존일 뿐이다."), note, useBytes=TRUE)
cat(sprintf("README: %s\n전체 성공: %s\n", basename(note), ok))
