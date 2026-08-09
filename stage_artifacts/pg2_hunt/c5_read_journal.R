## c5 — 워크플로 journal 에서 완료 샤드 결과 읽기 (캐시가 비었는지 확인 포함)
suppressPackageStartupMessages(library(jsonlite))
p <- file.path("C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot",
               "832fa2fc-c147-4788-b363-4b17e97ed23e/subagents/workflows/wf_8c401997-47a/journal.jsonl")
say <- function(fmt, ...) { cat(sprintf(paste0("[c5] ", fmt, "\n"), ...)); flush.console() }
if (!file.exists(p)) { say("journal 부재"); quit(status=0) }
L <- readLines(p, warn = FALSE)
say("journal %d줄", length(L))
tt <- character(0)
done <- 0L
for (l in L) {
  j <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) next
  ty <- as.character(j$type %||% "?")[1]
  tt <- c(tt, ty)
  if (ty %in% c("completed","result","finished")) {
    done <- done + 1L
    r <- j$result
    if (is.list(r)) {
      say("--- 완료 #%d ---", done)
      say("  측정 %s · 실패 %s · 생존 %s",
          as.character(r$n_measured %||% "?"), as.character(r$n_failed %||% "?"),
          if (is.null(r$survivors)) "?" else as.character(length(r$survivors)))
      if (!is.null(r$distribution_note))
        say("  분포: %s", substr(as.character(r$distribution_note)[1], 1, 300))
      if (!is.null(r$top5_closest))
        say("  근접5: %s", substr(as.character(r$top5_closest)[1], 1, 300))
      if (!is.null(r$survivors) && length(r$survivors)) {
        for (s in r$survivors) say("  ★생존: %s [%s] ΔIR %s · 상관 %s · IR %s",
          as.character(s$factor %||% "?"), as.character(s$arm %||% "?"),
          as.character(s$best_delta_ir %||% "?"), as.character(s$cor_incumbent %||% "?"),
          as.character(s$sleeve_ir %||% "?"))
      }
      if (!is.null(r$failure_reason)) say("  실패사유: %s", substr(as.character(r$failure_reason)[1],1,200))
    }
  }
}
`%||%` <- function(a,b) if (is.null(a)) b else a
say("=== 이벤트 유형 ===")
print(table(tt))
say("완료 샤드 %d / 8", done)
