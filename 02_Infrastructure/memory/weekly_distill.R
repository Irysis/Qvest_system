# Weekly Memory Distillation — 매주 일요일 12:00 (Qvest_WeeklyDistill.bat → weekly_distill.sh 경유)
# 2026-07-25 분리: monthly_distill과 동일한 인라인 `Rscript -e '<한글 포함>'` 세그폴트
#   (exit 139 침묵 no-op) 수리 — 본 파일로 분리, source() 경유. 마지막 정상 로그 2026-06-08.
# 2026-07-25 소스 재배선(도훈 지시 "수리 필요한 부분도 fix"):
#   ① 주간 실험 요약이 참조하던 `qepm/registry/experiments.json` = 파일 부재(항상 0건)
#      → 현행 Ledger `06_Registry/hypothesis_index.json`(965 entries) 기반 판정 요약으로 교체.
#   ② `update_memory_summary()` = 구 경로(methodology_active.md) 부재로 no-op이자
#      MEMORY.md를 정규식 덮어쓰는 함수 → 무인 루틴에서 호출 제거, knowledge_index 카운트 보고로 교체.
#   상세: 02_Infrastructure/memory/distill_stats.R 헤더.

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/stage_gate_engine.R")
  source("02_Infrastructure/memory/distill_stats.R")
})

cat("=== Weekly Distillation ===\n")

# 1. Stage Gate 현황
db <- tryCatch(sg_get_dashboard(), error = function(e) {
  cat("[dashboard] Failed:", conditionMessage(e), "\n")
  data.frame(current_stage = character())
})
stage_dist <- table(gsub("_.*", "", db$current_stage))
cat("Stage distribution:\n"); print(stage_dist)

# 2. 주간 리서치 판정 요약 (hypothesis_index Ledger, 최근 7일)
rr <- tryCatch(qv_recent_research(days = 7L), error = function(e) {
  cat("[research] Failed:", conditionMessage(e), "\n")
  list(n = 0L, verdicts = integer(0), since = NA, source = "error")
})
cat(sprintf("This week (since %s): %d entries [%s] (src=%s)\n",
            rr$since, rr$n, qv_verdict_line(rr), rr$source))

# 3. 지식 Ledger 카운트 (knowledge_index)
ls_ <- tryCatch(qv_ledger_stats(), error = function(e) {
  cat("[ledger] Failed:", conditionMessage(e), "\n")
  list(law = NA, distilled = NA, lcode = NA, archived = NA, source = "error")
})
cat(sprintf("Ledger: Law %s · Distilled %s · L-code %s · archived %s (src=%s)\n",
            ls_$law, ls_$distilled, ls_$lcode, ls_$archived, ls_$source))

# 4. Axiom candidate scan (promote.R dry-scan, auto_inject=FALSE)
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/promote.R"))
  cand_dir <- file.path(PROJECT_ROOT, "qepm/memory/axioms/candidates")
  cands <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  cat(sprintf("Axiom candidates: %d\n", length(cands)))
  n_ready <- 0L
  for (cp in cands) {
    r <- tryCatch(promote_to_axiom(cp, threshold = 0.80, auto_inject = FALSE),
                  error = function(e) NULL)
    if (!is.null(r)) {
      if (isTRUE(r$passed)) n_ready <- n_ready + 1L
      cat(sprintf("  %s weighted=%.3f (thr 0.80) %s\n",
          r$candidate_id, r$weighted_score,
          if (isTRUE(r$passed)) "PROMOTE-READY" else "below"))
    }
  }
  cat(sprintf("Axiom PROMOTE-READY: %d / %d\n", n_ready, length(cands)))
}, error = function(e) cat("[axiom] Scan skipped:", conditionMessage(e), "\n"))

# 5. 텔레그램 주간 브리핑 (ops 내부 자동알림 관례 = tg_send)
tryCatch({
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_send(sprintf(paste0("🧠 [Q-Lead] Weekly Distill %s\n",
                         "Tracked: %d strategies\n%s\n",
                         "This week: %d entries (%s)\n",
                         "Ledger: Law %s / Distilled %s / L-code %s"),
    format(Sys.Date(), "%m/%d"),
    nrow(db),
    paste(names(stage_dist), stage_dist, sep = ":", collapse = " "),
    rr$n, qv_verdict_line(rr, k = 3L),
    ls_$law, ls_$distilled, ls_$lcode))
}, error = function(e) cat("[telegram] Failed:", conditionMessage(e), "\n"))
