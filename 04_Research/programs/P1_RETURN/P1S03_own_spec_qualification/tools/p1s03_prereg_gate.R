## P1S03 등록 직전 확인(DESIGN §8 · 변경분 점검 v3 M-1 (b)) — 판 표식 계약 판독 · P1R04 평가 산출 없음 · 핀 불일치 0 · 초안 = 마지막 점검본
##   종료 0 = 모두 충족 · 1 = 하나라도 미충족(이유 출력)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
suppressMessages(source("02_Infrastructure/contracts/factor_db_vintage.R"))
rd <- "04_Research/programs/P1_RETURN/P1S03_own_spec_qualification"
bad <- character(0)
L <- tryCatch(fdv_ledger(), error = function(e) { bad <<- c(bad, paste("fdv_ledger 판독 실패:", conditionMessage(e))); NULL })
if (!is.null(L)) {
  S <- fdv_stamp(); E <- L$entries; last <- E[[length(E)]]
  if (length(S$in_progress)) bad <- c(bad, paste("진행 중 판 표식 줄:", paste(unlist(S$in_progress), collapse = ", ")))
  if (is.null(last$completed_at) || !nzchar(as.character(last$completed_at))) bad <- c(bad, paste("마지막 줄 미완료:", last$id))
  cat(sprintf("판 표식 마지막 줄 %s · completed_at %s · valid_from %s\n", last$id, last$completed_at %||% "null", as.character(S$valid_from)))
  pre <- rc_json_read(file.path(rd, "prereg_draft.json"))
  ## 변경분 점검 v4 R-1: 원장 마지막 줄 id = 사양 결론의 측정 자료 판 id('마지막 줄 <id> 완료 뒤') — 다르면 생성기 · 새 초안 · 변경분 점검
  if (!any(grepl(paste0("마지막 줄 ", last$id, " 완료"), unlist(pre$spec$conclusion_scope), fixed = TRUE))) bad <- c(bad, paste("사양 결론의 측정 자료 판 id ≠ 원장 마지막 줄:", last$id, "— 새 초안"))
}
if (file.exists("04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/results/evaluation_visible.json")) bad <- c(bad, "P1R04 평가 산출 있음")
pre <- rc_json_read(file.path(rd, "prereg_draft.json")); mm <- rc_pins_mismatches(pre$pins, rc_root())
if (length(mm)) bad <- c(bad, paste("핀 불일치:", paste(mm, collapse = " | ")))
D <- rc_json_read(file.path(rd, "drafts.json")); lv <- D$versions[[length(D$versions)]]
if (!identical(rc_md5(file.path(rd, "prereg_draft.json")), lv$md5)) bad <- c(bad, "디스크 초안 ≠ 마지막 초안 기록")
if (is.null(lv$review) || !identical(lv$review$verdict, "ok")) bad <- c(bad, sprintf("마지막 초안 v%s 점검 = %s", lv$version, if (is.null(lv$review)) "없음" else lv$review$verdict))
cat(sprintf("핀 %d · 불일치 %d · 마지막 초안 v%s · P1R04 results 파일 %d\n", length(pre$pins$files), length(mm), lv$version,
            length(list.files("04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/results"))))
if (length(bad)) { cat("미충족:\n", paste0(" - ", bad, collapse = "\n"), "\n"); quit(status = 1) }
cat("등록 직전 확인 통과\n")
