## FQ-169 CLAIM + 인접 FQ-108d 정체 확인 (배정 규약 1조 준수)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[claim] ", fmt, "\n"), ...)); flush.console() }
suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
say("원장 %d 항목", length(ids))

## 1조: 착수 전 owner 확인
for (k in c("FQ-169","FQ-108d")) {
  i <- which(ids == k); if (!length(i)) { say("★%s 부재", k); next }
  e <- Q$entries[[i]]
  say("=== %s | status=%s ===", k, e$status)
  say("  owner: %s", substr(paste(e$owner, collapse=" "), 1, 190))
  say("  title: %s", substr(gsub("[\r\n]+"," ", e$title), 1, 150))
  for (f in c("hypothesis","ev_rationale","next_action","data_gate")) {
    v <- e[[f]]; if (!is.null(v)) say("  [%s] %s", f, substr(gsub("[\r\n]+"," ", paste(v, collapse=" ")), 1, 700))
  }
}

i <- which(ids == "FQ-169")
own <- paste(Q$entries[[i]]$owner, collapse = " ")
if (grepl("CLAIMED", own) && !grepl("UNCLAIMED", own)) {
  say("★이미 CLAIMED — 착수 금지 (배정 규약 1조)"); quit(status = 0)
}
Q$entries[[i]]$owner <- paste0("CLAIMED Q-Lead session WT-D20260809_003 계열 · 2026-08-09 13:1x — ",
  "vol/tail 계열 평균/순위 괴리 전수 스크린 착수. 완료 시 result_ref 기입 후 해제.")
Q$entries[[i]]$status <- "in_flight_20260809"
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("FQ-169 CLAIMED 표기 완료 — 재읽기 확인 %s",
    grepl("CLAIMED Q-Lead", paste(read_frontier_queue()$entries[[i]]$owner, collapse=" ")))
