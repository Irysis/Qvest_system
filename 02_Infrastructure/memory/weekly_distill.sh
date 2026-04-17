#!/bin/bash
# Weekly Memory Distillation — 매주 일요일 12:00
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

echo "[weekly_distill] $(date '+%Y-%m-%d %H:%M') Starting..."

Rscript --no-save -e '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/stage_gate_engine.R")
  source("02_Infrastructure/memory_logger.R")
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

# 3. Axiom candidate scan
tryCatch({
  source(file.path(PROJECT_ROOT, "qepm/R/memory/r7_axiom.R"))
  candidates <- scan_axiom_candidates()
  cat(sprintf("Axiom candidates: %d\n", length(candidates)))
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
