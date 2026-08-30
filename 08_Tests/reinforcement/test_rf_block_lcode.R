#==============================================================================
# test_rf_block_lcode.R — 블록 L-code 무인 발행 검사 (2026-08-30)
#
# 왜: SKILL §0 이 "블록당 L-code 1건" 을 규정했는데 러너에 소비자가 없어서(emit_lcode 0건)
#   세션이 안 오면 학습이 증발했다. 그리고 구 L-code 다수가 record_type="process" 로
#   적립돼 **등급 기반 집계에서 성과로 안 잡혔다**. 둘 다 조용한 실패라 검사로 박아둔다.
# 부작용 없음: dry_run 으로만 발행한다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

led <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) {
  writeLines("  SKIP  active entry 없음 — 발행 경로를 실측할 대상이 없다")
} else {
  E <- act[[1]]; used <- as.integer(E$attempts_used %||% 0L)
  nb <- (used %/% 5L) * 5L
  if (nb < 5L) {
    writeLines("  SKIP  완료된 블록 없음")
  } else {
    r <- rf_emit_block_lcode(E$base_id, nb, root = ROOT, dry_run = TRUE)
    if (!is.null(r)) ok(sprintf("블록 n=%d dry_run 발행", nb)) else ng("dry_run 발행 실패")
    # 실제 적립분에서 계약 2종을 재도출한다 — 진술이 아니라 파일에서
    f <- file.path(ROOT, "stage_artifacts/l_code/reinforcement",
                   sprintf("l_code_%s_B%d.json", E$base_id, nb %/% 5L))
    if (file.exists(f)) {
      d <- jsonlite::fromJSON(f, simplifyVector = TRUE)
      if (identical(d$record_type, "performance")) ok("record_type=performance (등급 집계에 잡힌다)")
      else ng("record_type", paste(d$record_type, "— 성과 기록으로 안 잡힌다"))
      np <- unlist(strsplit(paste(d$next_probe, collapse = " | "), " | ", fixed = TRUE))
      np <- np[nzchar(trimws(np))]
      if (length(np) >= 2L) ok(sprintf("next_probe %d건 (C/F 연속성 계약 >=2)", length(np)))
      else ng("next_probe", sprintf("%d건 — 연속성 계약 미달", length(np)))
      if (!is.null(d$source_paper) && nzchar(as.character(d$source_paper)))
        ok("source_paper 기록(근거 논문 의무)") else ng("source_paper 부재")
    } else ng("적립 파일 부재", f)
  }
}

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
