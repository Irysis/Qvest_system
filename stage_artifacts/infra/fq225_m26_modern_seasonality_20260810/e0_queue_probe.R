suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(gsub("\\\\", "/", ROOT))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
cat("항목 수:", length(ids), "\n")
num <- suppressWarnings(as.integer(sub("^FQ-", "", ids)))
cat("FQ 번호 최대:", max(num, na.rm = TRUE), " · 비FQ id:", sum(is.na(num)), "\n")
cat("최근 5개 id:", paste(tail(ids[order(num)], 5), collapse = " "), "\n")
cat("--- 최신 항목 스키마 ---\n")
last <- Q$entries[[which.max(num)]]
cat(toJSON(last, auto_unbox = TRUE, pretty = 1, digits = NA), "\n")
cat("--- 형식 정본 여부:", frontier_queue_format_ok(), "---\n")
cat("--- M26 / FQ-223 언급 항목 ---\n")
for (i in seq_along(Q$entries)) {
  s <- toJSON(Q$entries[[i]], auto_unbox = TRUE, digits = NA)
  if (grepl("M26|FQ-223|rollover|롤오버", s)) cat(" ", ids[i], "|", substr(s, 1, 220), "\n")
}
