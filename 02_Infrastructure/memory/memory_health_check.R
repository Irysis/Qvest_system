## ══════════════════════════════════════════════════════════════════════════════
## memory_health_check.R — 장기기억 자동 갱신 스크립트
## 용도: 세션 시작 시 자동 실행. 현재 프로젝트 상태를 수집하여
##       메모리 파일의 staleness를 진단하고, 핵심 수치를 갱신한다.
## ══════════════════════════════════════════════════════════════════════════════
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })

# 2026-07-25 수리: ① memory/는 root 2단계 아래인데 dirname 1회만 올라가 PROJECT_ROOT가
# 항상 "02_Infrastructure"였음(전략 폴더 0개의 원인). ② 중첩 source(monthly_distill.R 경유)
# 시 sys.frame(1)$ofile이 바깥 스크립트 경로 → 전역 PROJECT_ROOT 오염 실측.
# 실존 검증 실패 시 env 루트 폴백.
PROJECT_ROOT <- dirname(dirname(SCRIPT_DIR))
if (!dir.exists(file.path(PROJECT_ROOT, "02_Infrastructure"))) {
  PROJECT_ROOT <- Sys.getenv("QM_ROOT", unset = Sys.getenv("CLAUDE_PROJECT_DIR",
                  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
}
MEMORY_DIR   <- local({ .c <- c("C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory", "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory"); .e <- .c[dir.exists(.c)]; if (length(.e)) .e[1] else .c[1] })  # 2026-06-10 현 경로 1순위
STRAT_DIR    <- file.path(PROJECT_ROOT, "04_Research", "strategies")

cat("══════════════════════════════════════\n")
cat("[Memory Health Check] Starting...\n")
cat("══════════════════════════════════════\n\n")

## ── 1. 전략 현황 수집 ──────────────────────────────────────────────────────
hurdle_files <- list.files(STRAT_DIR, pattern = "hurdle_result\\.json$",
                           recursive = TRUE, full.names = TRUE)
n_folders <- length(list.dirs(STRAT_DIR, recursive = FALSE))
n_hurdle  <- length(hurdle_files)

grade_counts <- list(A = 0L, B = 0L, C = 0L, F = 0L)
top_strategies <- list()

for (f in hurdle_files) {
  tryCatch({
    j <- fromJSON(f, simplifyVector = FALSE)
    g <- j$grade
    if (!is.null(g) && g %in% names(grade_counts)) {
      grade_counts[[g]] <- grade_counts[[g]] + 1L
    }
    if (!is.null(g) && g == "A" && !is.null(j$total_score)) {
      top_strategies[[length(top_strategies) + 1]] <- list(
        strategy = j$strategy,
        score = j$total_score,
        file = f
      )
    }
  }, error = function(e) NULL)
}

## Top 5 정렬
if (length(top_strategies) > 0) {
  scores <- sapply(top_strategies, function(x) x$score)
  top_idx <- order(scores, decreasing = TRUE)[1:min(5, length(scores))]
  top5 <- top_strategies[top_idx]
}

## ── 2. MEMORY.md staleness 체크 ────────────────────────────────────────────
# 2026-07-25: evolution_roadmap.md / infrastructure_state.md 체크 제거 — 두 파일은
# 의도적 제거 확인된 legacy(CLAUDE.md 2026-07-18 정정). 부재 파일의 days_stale=NULL이
# §5 if(NA) 크래시("missing value where TRUE/FALSE needed")의 원인이기도 했음.
memory_file <- file.path(MEMORY_DIR, "MEMORY.md")

check_staleness <- function(filepath) {
  if (!file.exists(filepath)) return(list(exists = FALSE))
  lines <- readLines(filepath, warn = FALSE)
  # 업데이트 날짜 추출
  date_line <- grep("최종 업데이트", lines, value = TRUE)
  if (length(date_line) > 0) {
    date_match <- regmatches(date_line[1], regexpr("\\d{4}-\\d{2}-\\d{2}", date_line[1]))
    if (length(date_match) > 0) {
      last_update <- as.Date(date_match)
      days_stale <- as.integer(Sys.Date() - last_update)
      return(list(exists = TRUE, last_update = as.character(last_update),
                  days_stale = days_stale, n_lines = length(lines)))
    }
  }
  list(exists = TRUE, last_update = "unknown", days_stale = NA, n_lines = length(lines))
}

mem_status  <- check_staleness(memory_file)

## ── 3. MEMORY.md에 기록된 수치 vs 실제 수치 비교 ──────────────────────────
mem_lines <- if (file.exists(memory_file)) readLines(memory_file, warn = FALSE) else character(0)
mem_grade_a <- NA
grade_a_line <- grep("Grade A.*\\d+개", mem_lines, value = TRUE)
if (length(grade_a_line) > 0) {
  mem_grade_a <- as.integer(regmatches(grade_a_line[1],
    regexpr("\\d+(?=개)", grade_a_line[1], perl = TRUE)))
}

## ── 4. 결과 출력 ──────────────────────────────────────────────────────────
cat("[현재 프로젝트 상태]\n")
cat(sprintf("  전략 폴더: %d개\n", n_folders))
cat(sprintf("  Hurdle 완료: %d개\n", n_hurdle))
cat(sprintf("  Grade A: %d | B: %d | C: %d | F: %d\n",
            grade_counts$A, grade_counts$B, grade_counts$C, grade_counts$F))
cat(sprintf("  미완료: %d개\n", n_folders - n_hurdle))

if (length(top_strategies) > 0) {
  cat("\n[Top 5 Grade A]\n")
  for (i in seq_along(top5)) {
    s <- top5[[i]]
    cat(sprintf("  %d. %s (Score %.1f)\n", i, s$strategy, s$score))
  }
}

cat("\n[메모리 파일 상태]\n")
print_status <- function(name, status) {
  if (!status$exists) {
    cat(sprintf("  %s: 파일 없음!\n", name))
  } else if (is.na(status$days_stale)) {
    cat(sprintf("  %s: 날짜 파싱 불가 (%d줄)\n", name, status$n_lines))
  } else {
    stale_flag <- if (status$days_stale > 3) " *** STALE ***" else " OK"
    cat(sprintf("  %s: %s (%d일 전, %d줄)%s\n",
                name, status$last_update, status$days_stale, status$n_lines, stale_flag))
  }
}
print_status("MEMORY.md", mem_status)

## ── 5. 수치 괴리 진단 ────────────────────────────────────────────────────
cat("\n[수치 괴리 진단]\n")
drift_detected <- FALSE

if (length(mem_grade_a) == 1 && !is.na(mem_grade_a)) {
  diff <- grade_counts$A - mem_grade_a
  if (abs(diff) > 5) {
    cat(sprintf("  !! Grade A: MEMORY.md=%d vs 실제=%d (차이 %+d) → 갱신 필요\n",
                mem_grade_a, grade_counts$A, diff))
    drift_detected <- TRUE
  } else {
    cat(sprintf("  Grade A: MEMORY.md=%d vs 실제=%d → OK\n", mem_grade_a, grade_counts$A))
  }
}

if (mem_status$exists && !is.na(mem_status$n_lines) && mem_status$n_lines > 200) {
  cat(sprintf("  !! MEMORY.md %d줄 > 200줄 제한 → 압축 필요\n", mem_status$n_lines))
  drift_detected <- TRUE
}

stale_files <- c()
if (length(mem_status$days_stale) == 1 && !is.na(mem_status$days_stale) &&
    mem_status$days_stale > 3) stale_files <- c(stale_files, "MEMORY.md")

if (length(stale_files) > 0) {
  cat(sprintf("  !! Stale files (3일+): %s\n", paste(stale_files, collapse = ", ")))
  drift_detected <- TRUE
}

## ── 6. 최종 판정 ─────────────────────────────────────────────────────────
cat("\n══════════════════════════════════════\n")
if (drift_detected) {
  cat("[VERDICT] MEMORY DRIFT DETECTED — 갱신 필요\n")
  cat("  → MEMORY.md의 전략 수치를 현재 값으로 업데이트하세요\n")
  cat("  → stale 파일의 '최종 업데이트' 날짜를 확인하세요\n")
} else {
  cat("[VERDICT] MEMORY UP-TO-DATE — 정상\n")
}
cat("══════════════════════════════════════\n")

## ── 7. 갱신용 데이터 snapshot 저장 ────────────────────────────────────────
snapshot <- list(
  timestamp = as.character(Sys.time()),
  date = as.character(Sys.Date()),
  n_folders = n_folders,
  n_hurdle = n_hurdle,
  grade_a = grade_counts$A,
  grade_b = grade_counts$B,
  grade_c = grade_counts$C,
  grade_f = grade_counts$F,
  top5 = if (length(top_strategies) > 0)
    lapply(top5, function(x) list(strategy = x$strategy, score = x$score)) else list(),
  drift_detected = drift_detected,
  stale_files = stale_files
)

snapshot_path <- file.path(MEMORY_DIR, ".memory_snapshot.json")
write(toJSON(snapshot, auto_unbox = TRUE, pretty = TRUE), snapshot_path)
cat(sprintf("\n[Snapshot] Saved to %s\n", snapshot_path))

# --- Loop Integrator Session Briefing ---
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "memory", "loop_integrator.R"))
  loop_session_brief()
}, error = function(e) {
  cat(sprintf("[Loop Integrator] Briefing skipped: %s\n", conditionMessage(e)))
})
