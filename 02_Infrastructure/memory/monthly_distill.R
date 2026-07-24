# Monthly Memory Distillation — 매월 1일 06:00 (Qvest_MonthlyDistill.bat → monthly_distill.sh 경유)
# 2026-07-25 분리: 구 monthly_distill.sh 인라인 `Rscript -e '<한글 포함>'`이 Windows에서
#   세그폴트(exit 139, 무출력)로 매회 죽는데 셸은 exit 0 "Done." — 침묵 no-op.
#   (근본원인 = reference-rscript-e-korean-segfault, 수리 패턴 = 외부 .R + source() 경유)
# 동반 수리 2건:
#   ① 구 §4 mem_path가 구 WSL 경로(/home/quant/...) 하드코딩 → Windows에서 항상 부재.
#      update_memory_summary()가 동일 L-code 합산을 현행 MEMORY_DIR에서 이미 수행 — 반환값 사용.
#   ② 구 §7 tg 블록이 미정의 변수(active, l_codes) 참조 → 매월 silent fail. 명시 정의로 교체.

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
#    (cond_ic는 daily_refresh.sh [6c] 주간 배선과 중복이나 무해 — 2026-07-25 handoff)
gap <- NULL
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

# 3. Axiom monthly review (활성 axiom apply=FALSE 재검증 + candidate 5-axis dry-scan)
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/review.R"))
  review_all_active_axioms(apply = FALSE)
  source(file.path(PROJECT_ROOT, "02_Infrastructure/axiom/promote.R"))
  cand_dir <- file.path(PROJECT_ROOT, "qepm/memory/axioms/candidates")
  cands <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  cat(sprintf("[axiom] %d candidates found\n", length(cands)))
  for (cp in cands) {
    r <- tryCatch(promote_to_axiom(cp, threshold = 0.80, auto_inject = FALSE),
                  error = function(e) NULL)
    if (!is.null(r)) cat(sprintf("[axiom]   %s weighted=%.3f %s\n",
        r$candidate_id, r$weighted_score,
        if (isTRUE(r$passed)) "PROMOTE-READY" else "below"))
  }
}, error = function(e) cat("[axiom] Review failed:", conditionMessage(e), "\n"))

# 4+5. methodology 통계 + MEMORY.md 전면 갱신
#      (update_memory_summary가 active/archive/experiment_log L-code 합산 스캔 겸함)
mem_stat <- tryCatch(update_memory_summary(), error = function(e) {
  cat("[memory] Summary failed:", conditionMessage(e), "\n")
  list(max_l = 0L, count = 0L)
})
cat(sprintf("L-codes: %d total (max L-%d)\n", mem_stat$count, mem_stat$max_l))

# 6. Stage Gate 현황
db <- tryCatch(sg_get_dashboard(), error = function(e) {
  cat("[dashboard] Failed:", conditionMessage(e), "\n")
  data.frame()
})

# 7. 텔레그램 월간 리포트 (ops 내부 자동알림 관례 = tg_send, freshness_audit.R 등과 동일)
tryCatch({
  active_ax <- list.files(file.path(PROJECT_ROOT, "qepm/memory/axioms/active"),
                          pattern = "^AX-\\d+\\.json$")
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_send(sprintf("[Q-Lead] Monthly Audit %s\nL-codes: %d\nActive Axioms: %d\nTracked: %d\nGap: SR %.3f",
    format(Sys.Date(), "%Y-%m"),
    mem_stat$count, length(active_ax), nrow(db),
    if (!is.null(gap)) gap$gap_vector$sharpe_gap else 0))
}, error = function(e) cat("[telegram] Failed:", conditionMessage(e), "\n"))
