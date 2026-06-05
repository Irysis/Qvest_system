#!/bin/bash
# Monthly Memory Distillation — 매월 1일 06:00
# PATCH 2026-04-29 (L-247 trigger): resolve_project.sh + memory_logger.R path 정정
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
cd "$PROJECT"

echo "[monthly_distill] $(date '+%Y-%m-%d %H:%M') Starting..."

Rscript --no-save -e '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/stage_gate_engine.R")
  source("02_Infrastructure/memory/memory_logger.R")
})

cat("=== Monthly Audit ===\n")

# 1. Full memory health audit
tryCatch(source("02_Infrastructure/memory/memory_health_check.R"), error = function(e)
  cat("[health] Check failed:", conditionMessage(e), "\n"))

# 2. Gap vector + Conditional IC 재계산
tryCatch({
  gap <- sg_compute_gap_vector()
  cat(sprintf("Gap: SR=%.3f, CAGR=%.4f, sleeve=%s\n",
      gap$gap_vector$sharpe_gap, gap$gap_vector$return_gap,
      paste(gap$sleeve_needs, collapse="+")))
}, error = function(e) cat("[gap] Failed:", conditionMessage(e), "\n"))

tryCatch({
  cond <- sg_compute_conditional_ic()
  cat(sprintf("Conditional IC: %d factors updated\n", nrow(cond)))
}, error = function(e) cat("[cond_ic] Failed:", conditionMessage(e), "\n"))

# 3. Axiom quarterly review (v8.0 fix: 부재 qepm/R/memory/r7_axiom.R → review.R + promote.R.
#    구 블록은 source 실패로 매월 "Review failed" silent no-op였음 — 자동화 사멸 엣지 복구.)
tryCatch({
  # 활성 axiom dry-run 재검증 (deprecation/유지 판정 보고만, apply=FALSE)
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/review.R"))
  review_all_active_axioms(apply = FALSE)
  # candidate dry-scan (promote.R 5-axis 점수)
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/promote.R"))
  cand_dir <- file.path(PROJECT_ROOT, "qepm/memory/axioms/candidates")
  cands <- list.files(cand_dir, pattern="^CAND_.*\\.json$", full.names=TRUE)
  cat(sprintf("[axiom] %d candidates found\n", length(cands)))
  for (cp in cands) {
    r <- tryCatch(promote_to_axiom(cp, threshold=0.80, auto_inject=FALSE),
                  error=function(e) NULL)
    if (!is.null(r)) cat(sprintf("[axiom]   %s weighted=%.3f %s\n",
        r$candidate_id, r$weighted_score,
        if (isTRUE(r$passed)) "PROMOTE-READY" else "below"))
  }
}, error = function(e) cat("[axiom] Review failed:", conditionMessage(e), "\n"))

# 4. methodology_memory 통계
mem_path <- "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_memory.md"
if (file.exists(mem_path)) {
  mem <- readLines(mem_path, warn=FALSE)
  l_codes <- unique(unlist(regmatches(mem, gregexpr("L-\\d+", mem))))
  cat(sprintf("L-codes: %d total\n", length(l_codes)))
}

# 5. MEMORY.md 전면 갱신
update_memory_summary()

# 6. Stage Gate 현황
db <- sg_get_dashboard()

# 7. 텔레그램 월간 리포트
tryCatch({
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_send(sprintf("[Q-Lead] Monthly Audit %s\nL-codes: %d\nActive Axioms: %d\nTracked: %d\nGap: SR %.3f",
    format(Sys.Date(), "%Y-%m"),
    length(l_codes %||% character()), length(active %||% list()),
    nrow(db), gap$gap_vector$sharpe_gap %||% 0))
}, error = function(e) NULL)
' 2>&1

echo "[monthly_distill] Done."
