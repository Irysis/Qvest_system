#!/bin/bash
# Weekly Memory Distillation — 매주 일요일 12:00
# PATCH 2026-04-29 (L-247 trigger): resolve_project.sh path + memory_logger.R path 정정
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
cd "$PROJECT"

echo "[weekly_distill] $(date '+%Y-%m-%d %H:%M') Starting..."

Rscript --no-save -e '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/stage_gate_engine.R")
  source("02_Infrastructure/memory/memory_logger.R")
})

cat("=== Weekly Distillation ===\n")

# 1. Stage Gate 현황
db <- sg_get_dashboard()
stage_dist <- table(gsub("_.*", "", db$current_stage))
cat("Stage distribution:\n"); print(stage_dist)

# 2. 주간 실험 요약 (experiments.json에서 최근 7일)
reg_path <- file.path(PROJECT_ROOT, "qepm/registry/experiments.json")
if (file.exists(reg_path)) {
  exps <- jsonlite::fromJSON(reg_path, simplifyVector=FALSE)
  week_ago <- format(Sys.Date() - 7, "%Y-%m-%d")
  recent <- Filter(function(e) (e$registered_at %||% "") >= week_ago, exps)
  n_recent <- length(recent)
  grades <- sapply(recent, function(e) e$grade %||% "?")
  cat(sprintf("This week: %d experiments (A:%d B:%d C:%d F:%d)\n",
      n_recent, sum(grades=="A"), sum(grades=="B"), sum(grades=="C"), sum(grades=="F")))
}

# 3. Axiom candidate scan (v8.0 fix: 부재 qepm/R/memory/r7_axiom.R → 실제 promote.R dry-scan.
#    구 블록은 source 실패로 매주 "Scan skipped" silent no-op였음 — 자동화 사멸 엣지 복구.)
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/promote.R"))
  cand_dir <- file.path(PROJECT_ROOT, "qepm/memory/axioms/candidates")
  cands <- list.files(cand_dir, pattern="^CAND_.*\\.json$", full.names=TRUE)
  cat(sprintf("Axiom candidates: %d\n", length(cands)))
  for (cp in cands) {
    r <- tryCatch(promote_to_axiom(cp, threshold=0.80, auto_inject=FALSE),
                  error=function(e) NULL)
    if (!is.null(r)) cat(sprintf("  %s weighted=%.3f (thr 0.80) %s\n",
        r$candidate_id, r$weighted_score,
        if (isTRUE(r$passed)) "PROMOTE-READY" else "below"))
  }
}, error = function(e) cat("[axiom] Scan skipped:", conditionMessage(e), "\n"))

# 4. MEMORY.md 통계 갱신
update_memory_summary()

# 5. 텔레그램 주간 브리핑
tryCatch({
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_send(sprintf("[Q-Lead] Weekly Distill %s\nTracked: %d strategies\n%s\nThis week: %d experiments",
    format(Sys.Date(), "%m/%d"),
    nrow(db),
    paste(names(stage_dist), stage_dist, sep=":", collapse=" "),
    n_recent %||% 0))
}, error = function(e) NULL)
' 2>&1

echo "[weekly_distill] Done."
