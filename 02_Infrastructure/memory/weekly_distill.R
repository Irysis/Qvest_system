# Weekly Memory Distillation — 매주 일요일 12:00 (Qvest_WeeklyDistill.bat → weekly_distill.sh 경유)
# 2026-07-25 분리: monthly_distill과 동일한 인라인 `Rscript -e '<한글 포함>'` 세그폴트
#   (exit 139 침묵 no-op) 수리 — 본 파일로 분리, source() 경유. 마지막 정상 로그 2026-06-08.
# 동반 수리: §5 tg 블록이 §2 미실행 시 미정의 변수(n_recent) 참조 → 상단 기본값 정의.

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/stage_gate_engine.R")
  source("02_Infrastructure/memory/memory_logger.R")
})

cat("=== Weekly Distillation ===\n")

# 1. Stage Gate 현황
db <- tryCatch(sg_get_dashboard(), error = function(e) {
  cat("[dashboard] Failed:", conditionMessage(e), "\n")
  data.frame(current_stage = character())
})
stage_dist <- table(gsub("_.*", "", db$current_stage))
cat("Stage distribution:\n"); print(stage_dist)

# 2. 주간 실험 요약 (experiments.json에서 최근 7일)
n_recent <- 0L
reg_path <- file.path(PROJECT_ROOT, "qepm/registry/experiments.json")
if (file.exists(reg_path)) {
  exps <- jsonlite::fromJSON(reg_path, simplifyVector = FALSE)
  week_ago <- format(Sys.Date() - 7, "%Y-%m-%d")
  recent <- Filter(function(e) (e$registered_at %||% "") >= week_ago, exps)
  n_recent <- length(recent)
  grades <- sapply(recent, function(e) e$grade %||% "?")
  cat(sprintf("This week: %d experiments (A:%d B:%d C:%d F:%d)\n",
      n_recent, sum(grades == "A"), sum(grades == "B"),
      sum(grades == "C"), sum(grades == "F")))
}

# 3. Axiom candidate scan (promote.R dry-scan, auto_inject=FALSE)
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/promote.R"))
  cand_dir <- file.path(PROJECT_ROOT, "qepm/memory/axioms/candidates")
  cands <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  cat(sprintf("Axiom candidates: %d\n", length(cands)))
  for (cp in cands) {
    r <- tryCatch(promote_to_axiom(cp, threshold = 0.80, auto_inject = FALSE),
                  error = function(e) NULL)
    if (!is.null(r)) cat(sprintf("  %s weighted=%.3f (thr 0.80) %s\n",
        r$candidate_id, r$weighted_score,
        if (isTRUE(r$passed)) "PROMOTE-READY" else "below"))
  }
}, error = function(e) cat("[axiom] Scan skipped:", conditionMessage(e), "\n"))

# 4. MEMORY.md 통계 갱신
tryCatch(update_memory_summary(), error = function(e)
  cat("[memory] Summary failed:", conditionMessage(e), "\n"))

# 5. 텔레그램 주간 브리핑 (ops 내부 자동알림 관례 = tg_send)
tryCatch({
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_send(sprintf("🧠 [Q-Lead] Weekly Distill %s\nTracked: %d strategies\n%s\nThis week: %d experiments",
    format(Sys.Date(), "%m/%d"),
    nrow(db),
    paste(names(stage_dist), stage_dist, sep = ":", collapse = " "),
    n_recent))
}, error = function(e) cat("[telegram] Failed:", conditionMessage(e), "\n"))
