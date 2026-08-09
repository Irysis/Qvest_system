## FQ-229 e0 — 큐 실측 (쓰기 전 read. 번호 하드코딩 금지)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(gsub("\\\\","/",ROOT))
source("02_Infrastructure/ops/frontier_queue_io.R")
say <- function(fmt, ...) cat(sprintf(paste0("[e0] ", fmt, "\n"), ...))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
say("항목 %d · 형식 정본 여부 %s", length(ids), frontier_queue_format_ok())
num <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
say("FQ 번호 max = %d ⇒ 다음 번호 = FQ-%03d", max(num, na.rm = TRUE), max(num, na.rm = TRUE) + 1L)
for (tgt in c("FQ-225","FQ-226","FQ-229","FQ-223","FQ-161")) {
  i <- which(ids == tgt)
  if (!length(i)) { say("%s: 원장에 없음", tgt); next }
  e <- Q$entries[[i]]
  say("%s status=%s · title=%s", tgt, as.character(e$status)[1], substr(as.character(e$title)[1], 1, 70))
}
say("--- status 자유문자열 census (상위) ---")
st <- table(vapply(Q$entries, function(e) as.character(e$status)[1] %||% "NA", character(1)))
`%||%` <- function(a,b) if (is.null(a)) b else a
print(head(sort(st, decreasing = TRUE), 12))
say("--- 필드 키 (첫 항목) ---")
say("%s", paste(names(Q$entries[[1]]), collapse = " · "))
